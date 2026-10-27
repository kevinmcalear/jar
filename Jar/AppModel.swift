import CloudKit
import CryptoKit
import Foundation
import Observation

struct ShoveShow: Identifiable, Equatable {
    var id: String { dates.joined(separator: ",") }
    var plan: ShovePlan
    var dates: [String]
}

struct SheetToken: Identifiable {
    let id = UUID()
}

@Observable
final class AppModel {
    var snapshot = Snapshot()
    var booted = false
    var unlocked = false
    var loadError: String?
    var shareError: String?
    var morningNote: String?
    var shove: ShoveShow?
    var addToken: SheetToken?
    var outsideToken: SheetToken?
    var settingsToken: SheetToken?
    var shareToken: SheetToken?
    var yesterdayToken: SheetToken?
    var editEntryID: String?
    var key: SymmetricKey?
    var waiting: [CKRecord] = []
    let sync = HouseholdSync()
    var store: Store?

    var timeZone: TimeZone {
        TimeZone(identifier: snapshot.settings?.timezone ?? "") ?? .current
    }

    var openDate: String {
        guard let settings = snapshot.settings else { return formatDay(Date(), timeZone: timeZone) }
        return openDay(now: Date(), timeZone: timeZone, closeHour: settings.closeHour)
    }

    var holder: Person? {
        snapshot.people.first { $0.id == snapshot.settings?.holderID }
    }

    var settledScore: (jar: Int, debt: Int) {
        replay(settledDays().map { (cap: $0.cap, spent: jarSpent($0.date)) })
    }

    var todayCap: Int {
        snapshot.days.first { $0.date == openDate }?.cap ?? snapshot.settings?.usualCap ?? 5000
    }

    var todaySpent: Int { jarSpent(openDate) }

    var picture: Picture {
        let settings = snapshot.settings
        let cap = todayCap
        let spent = todaySpent
        let settled = settledScore
        let projected = project(jar: settled.jar, debt: settled.debt, cap: cap, spent: spent)
        let remainder = cap - spent
        let usual = settings?.usualCap ?? 5000
        if projected.debt > 5000 {
            return .climb(debt: projected.debt, days: quietDayCount(debt: projected.debt, usualCap: usual), usualCap: usual, remainder: remainder)
        }
        if projected.debt > 0 {
            return .hole(debt: projected.debt, remainder: remainder)
        }
        if spent == 0, settled.jar == 0, settled.debt == 0 {
            return .quiet(cap: cap)
        }
        if projected.jar > settled.jar {
            return .growing(remainder: remainder, shove: projected.jar - settled.jar, cap: cap)
        }
        if projected.jar < settled.jar {
            return .borrowing(amount: settled.jar - projected.jar)
        }
        return .exact(cap: cap)
    }

    var coversTabs: Bool {
        shove != nil || picture.climbs
    }

    var todaySubtitle: String {
        let day = date(from: openDate, timeZone: timeZone) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        let hour = snapshot.settings?.closeHour ?? 4
        return "\(formatter.string(from: day)) · Ends at \(closeClock(hour))"
    }

    func boot() {
        guard store == nil else { return }
        do {
            let store = try Store()
            self.store = store
            snapshot = try store.load()
            sync.model = self
            sync.directory = store.directory
        } catch {
            loadError = error.localizedDescription
        }
        booted = true
    }

    func wake() async {
        guard booted, snapshot.settings != nil else { return }
        if key == nil {
            _ = await evaluateUnlock()
            key = readHouseholdKey()
        }
        unlocked = key != nil
        guard unlocked else { return }
        sync.start()
        drainWaiting()
        catchUp()
        await sync.fetch()
    }

    func lock() {
        guard snapshot.settings != nil, deviceCanUnlock() else { return }
        key = nil
        unlocked = false
    }

    func unlock(passphrase: String) -> Bool {
        guard let salt = snapshot.settings?.kdfSalt, let verifier = snapshot.settings?.verifier else { return false }
        let derived = deriveHouseholdKey(passphrase: passphrase, salt: salt, iterations: snapshot.settings?.kdfIterations ?? 600_000)
        guard (try? openField(verifier, record: "settings", field: "verifier", key: derived)) == householdVerifier else { return false }
        key = derived
        try? saveHouseholdKey(derived)
        unlocked = true
        sync.start()
        drainWaiting()
        catchUp()
        Task { await sync.fetch() }
        return true
    }

    func start(kevin: String, bridget: String, holderSticker: String, timezone: String, closeHour: Int, cap: Int, goal: Int?, passphrase: String) {
        guard let store, cap >= 0 else { return }
        let trimmedKevin = kevin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBridget = bridget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKevin.isEmpty, !trimmedBridget.isEmpty, !passphrase.isEmpty else { return }
        let salt = randomSalt()
        let derived = deriveHouseholdKey(passphrase: passphrase, salt: salt)
        guard let verifier = try? sealField(householdVerifier, record: "settings", field: "verifier", key: derived) else { return }
        let kevinID = UUID().uuidString
        let bridgetID = UUID().uuidString
        let now = stamp()
        let settings = HouseholdSettings(
            timezone: timezone, closeHour: min(23, max(0, closeHour)), usualCap: cap, usualCapChangedAt: now,
            usualCapSetBy: holderSticker == "bridget" ? bridgetID : kevinID, savingsGoal: goal,
            kdfSalt: salt, kdfIterations: 600_000, verifier: verifier,
            holderID: holderSticker == "bridget" ? bridgetID : kevinID, isOwner: true, zoneOwner: nil
        )
        try? store.insertSettings(settings)
        try? store.insertPerson(Person(id: kevinID, displayName: trimmedKevin, sticker: "kevin"))
        try? store.insertPerson(Person(id: bridgetID, displayName: trimmedBridget, sticker: "bridget"))
        for (index, item) in builtInCategories.enumerated() {
            try? store.insertCategory(JarCategory(id: UUID().uuidString, name: item.name, enabled: true, builtIn: item.key, sort: index, updatedAt: now))
        }
        try? saveHouseholdKey(derived)
        key = derived
        reload()
        let today = openDate
        try? store.insertDay(DayRow(date: today, cap: cap, settled: false))
        reload()
        unlocked = true
        sync.start()
        publishEverything()
    }

    func catchUp() {
        guard let store, snapshot.settings != nil else { return }
        let open = openDate
        if !snapshot.days.contains(where: { $0.date == open }) {
            try? store.insertDay(DayRow(date: open, cap: snapshot.settings?.usualCap ?? 5000, settled: false))
            reload()
            sync.enqueueSave(open)
        }
        if let latest = snapshot.days.filter(\.settled).map(\.date).max() {
            for day in daysFrom(addDays(latest, 1, timeZone: timeZone), until: open, timeZone: timeZone) {
                if !snapshot.days.contains(where: { $0.date == day }) {
                    try? store.insertDay(DayRow(date: day, cap: snapshot.settings?.usualCap ?? 5000, settled: false))
                    sync.enqueueSave(day)
                }
                try? store.setSettled(day, true)
            }
            reload()
        }
        let unseen = snapshot.days.filter { $0.settled && !snapshot.pourSeen.contains($0.date) }.sorted { $0.date < $1.date }
        let before = replay(snapshot.days.filter { $0.settled && snapshot.pourSeen.contains($0.date) }.sorted { $0.date < $1.date }.map { (cap: $0.cap, spent: jarSpent($0.date)) })
        let after = settledScore
        try? store.saveScore(jar: after.jar, debt: after.debt)
        guard !unseen.isEmpty else { return }
        if shove?.dates == unseen.map(\.date) { return }
        let plan = shovePlan(beforeJar: before.jar, beforeDebt: before.debt, afterJar: after.jar, afterDebt: after.debt, days: unseen.map { (cap: $0.cap, spent: jarSpent($0.date)) })
        if plan.plays {
            shove = ShoveShow(plan: plan, dates: unseen.map(\.date))
        } else {
            try? store.markPourSeen(unseen.map(\.date))
            reload()
            if !plan.text.isEmpty { morningNote = plan.text }
        }
    }

    func finishShove() {
        guard let shove, let store else { return }
        try? store.markPourSeen(shove.dates)
        self.shove = nil
        reload()
    }

    func logJar(amount: Int, categoryID: String, photo: Data?, day: String? = nil) {
        guard let store, amount > 0, let holder = snapshot.settings?.holderID else { return }
        let target = day ?? openDate
        if target != openDate {
            guard target == addDays(openDate, -1, timeZone: timeZone) else { return }
            shove = nil
            try? store.unsetSettled(from: target)
            try? store.clearPourSeen(from: target)
        }
        let now = stamp()
        let entry = Entry(id: UUID().uuidString, day: target, personID: holder, amount: amount, kind: "jar", categoryID: categoryID, chip: nil, rhythm: nil, note: nil, photo: photo, createdAt: now, updatedAt: now, originLocal: true)
        try? store.insertEntry(entry)
        reload()
        sync.enqueueSave(entry.id)
        morningNote = nil
        catchUp()
    }

    func logOutside(amount: Int, chip: Chip, rhythm: PayRhythm, note: String, day: String) {
        guard let store, amount > 0 else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = stamp()
        let entry = Entry(id: UUID().uuidString, day: day, personID: snapshot.settings?.holderID, amount: amount, kind: "outside", categoryID: nil, chip: chip.rawValue, rhythm: rhythm.rawValue, note: trimmed.isEmpty ? nil : trimmed, photo: nil, createdAt: now, updatedAt: now, originLocal: true)
        try? store.insertEntry(entry)
        reload()
        sync.enqueueSave(entry.id)
    }

    func deleteEntry(_ id: String) {
        guard let store, let entry = snapshot.entries.first(where: { $0.id == id }), canChange(entry) else { return }
        if entry.kind == "jar", entry.day != openDate {
            shove = nil
            try? store.unsetSettled(from: entry.day)
            try? store.clearPourSeen(from: entry.day)
        }
        try? store.deleteEntry(id)
        reload()
        sync.enqueueDelete(id)
        if entry.kind == "jar" { catchUp() }
    }

    func changeAmount(_ id: String, amount: Int) {
        guard let store, amount > 0, var entry = snapshot.entries.first(where: { $0.id == id }), canChange(entry) else { return }
        if entry.kind == "jar", entry.day != openDate {
            shove = nil
            try? store.unsetSettled(from: entry.day)
            try? store.clearPourSeen(from: entry.day)
        }
        entry.amount = amount
        entry.updatedAt = stamp()
        try? store.insertEntry(entry)
        reload()
        sync.enqueueSave(id)
        if entry.kind == "jar" { catchUp() }
    }

    func setHolder(_ id: String) {
        guard var settings = snapshot.settings, snapshot.people.contains(where: { $0.id == id }) else { return }
        settings.holderID = id
        try? store?.insertSettings(settings)
        reload()
    }

    func setUsualCap(_ cents: Int) {
        guard cents >= 0, var settings = snapshot.settings, settings.usualCap != cents else { return }
        settings.usualCap = cents
        settings.usualCapChangedAt = stamp()
        settings.usualCapSetBy = settings.holderID
        try? store?.insertSettings(settings)
        reload()
        sync.enqueueSave("settings")
    }

    func setGoal(_ cents: Int?) {
        guard var settings = snapshot.settings else { return }
        settings.savingsGoal = cents
        try? store?.insertSettings(settings)
        reload()
        sync.enqueueSave("settings")
    }

    func setCloseHour(_ hour: Int) {
        guard var settings = snapshot.settings, (0...23).contains(hour) else { return }
        settings.closeHour = hour
        try? store?.insertSettings(settings)
        reload()
        sync.enqueueSave("settings")
        catchUp()
    }

    func setTimezone(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil, var settings = snapshot.settings else { return }
        settings.timezone = identifier
        try? store?.insertSettings(settings)
        reload()
        sync.enqueueSave("settings")
        catchUp()
    }

    func setCategory(_ id: String, enabled: Bool) {
        guard var category = snapshot.categories.first(where: { $0.id == id }) else { return }
        category.enabled = enabled
        category.updatedAt = stamp()
        try? store?.insertCategory(category)
        reload()
        sync.enqueueSave(id)
    }

    func rename(_ id: String, to name: String) {
        guard var person = snapshot.people.first(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        person.displayName = trimmed
        try? store?.insertPerson(person)
        reload()
        sync.enqueueSave(id)
    }

    func addCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let category = JarCategory(id: UUID().uuidString, name: trimmed, enabled: true, builtIn: nil, sort: (snapshot.categories.map(\.sort).max() ?? -1) + 1, updatedAt: stamp())
        try? store?.insertCategory(category)
        reload()
        sync.enqueueSave(category.id)
    }

    func addMoney(income: Bool, name: String, amount: Int, rhythm: PayRhythm) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, amount >= 0 else { return }
        let row = MoneyRow(id: UUID().uuidString, name: trimmed, amount: amount, rhythm: rhythm.rawValue)
        try? store?.insertMoney(income ? "income" : "bills", row)
        reload()
        sync.enqueueSave(row.id)
    }

    func deleteMoney(income: Bool, id: String) {
        try? store?.deleteMoney(income ? "income" : "bills", id)
        reload()
        sync.enqueueDelete(id)
    }

    func jarSpent(_ day: String) -> Int {
        snapshot.entries.filter { $0.day == day && $0.kind == "jar" }.reduce(0) { $0 + $1.amount }
    }

    func outsideSpent(_ day: String) -> Int {
        snapshot.entries.filter { $0.day == day && $0.kind == "outside" }.reduce(0) { $0 + $1.amount }
    }

    func reload() {
        if let store, let snapshot = try? store.load() { self.snapshot = snapshot }
    }

    private func settledDays() -> [DayRow] {
        snapshot.days.filter(\.settled).sorted { $0.date < $1.date }
    }

    private func canChange(_ entry: Entry) -> Bool {
        if entry.kind == "outside" { return true }
        if entry.day == openDate { return true }
        return entry.day == addDays(openDate, -1, timeZone: timeZone) && yesterdayToken != nil
    }

    private func publishEverything() {
        sync.enqueueSave("settings")
        snapshot.people.forEach { sync.enqueueSave($0.id) }
        snapshot.categories.forEach { sync.enqueueSave($0.id) }
        snapshot.days.forEach { sync.enqueueSave($0.date) }
    }
}

extension Picture {
    var climbs: Bool {
        if case .climb = self { return true }
        return false
    }
}
