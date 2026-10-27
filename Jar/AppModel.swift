import CloudKit
import CryptoKit
import Foundation
import Observation
import WidgetKit

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
    var suspendLock = false
    private var waking = false
    var loadError: String?
    var shareError: String?
    var acceptingShare = false
    var morningNote: String?
    var shove: ShoveShow?
    var addToken: SheetToken?
    var addDay: String?
    var pendingAdd = false
    var outsideToken: SheetToken?
    var settingsToken: SheetToken?
    var shareToken: SheetToken?
    var yesterdayToken: SheetToken?
    var editEntryID: String?
    var tab = "today"
    var pendingNotices: [SpendNotice] = []
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
            loadWaiting()
            if snapshot.settings != nil {
                collapseHouseholdCopies()
                alignCategories()
            }
        } catch {
            loadError = error.localizedDescription
        }
        booted = true
        publishPile()
    }

    func openAdd(on day: String? = nil) {
        guard unlocked, snapshot.settings != nil else {
            pendingAdd = true
            return
        }
        pendingAdd = false
        addDay = day
        if day == nil { tab = "today" }
        addToken = SheetToken()
    }

    /// Joining kept this phone's setup and also downloaded the household's, so built-ins showed twice.
    func collapseHouseholdCopies() {
        guard let store else { return }
        let now = stamp()
        var changed = false
        for key in Set(snapshot.categories.compactMap(\.builtIn)) {
            let rows = snapshot.categories.filter { $0.builtIn == key }
            guard rows.count > 1, let keep = keptDuplicate(rows.map { row in
                DuplicateRow(id: row.id, updatedAt: row.updatedAt, uses: snapshot.entries.filter { $0.categoryID == row.id }.count)
            }) else { continue }
            for extra in rows where extra.id != keep {
                let moved = snapshot.entries.filter { $0.categoryID == extra.id }.map(\.id)
                do {
                    try store.retargetCategory(from: extra.id, to: keep, updatedAt: now)
                    try store.deleteCategory(extra.id)
                } catch { continue }
                moved.forEach { sync.enqueueSave($0) }
                sync.enqueueSave(keep)
                sync.enqueueDelete(extra.id)
                changed = true
            }
        }
        for sticker in ["kevin", "bridget"] {
            let rows = snapshot.people.filter { $0.sticker == sticker }
            guard rows.count > 1, let keep = keptDuplicate(rows.map { row in
                DuplicateRow(id: row.id, updatedAt: "", uses: snapshot.entries.filter { $0.personID == row.id }.count)
            }) else { continue }
            for extra in rows where extra.id != keep {
                let moved = snapshot.entries.filter { $0.personID == extra.id }.map(\.id)
                do {
                    try store.retargetPerson(from: extra.id, to: keep, updatedAt: now)
                    try store.deletePerson(extra.id)
                } catch { continue }
                if var settings = snapshot.settings {
                    var settingsChanged = false
                    if settings.holderID == extra.id { settings.holderID = keep; settingsChanged = true }
                    if settings.usualCapSetBy == extra.id { settings.usualCapSetBy = keep; settingsChanged = true }
                    if settingsChanged {
                        try? store.insertSettings(settings)
                        snapshot.settings = settings
                    }
                }
                moved.forEach { sync.enqueueSave($0) }
                sync.enqueueSave(keep)
                sync.enqueueDelete(extra.id)
                changed = true
            }
        }
        if changed { reload() }
    }

    private func alignCategories() {
        guard let store else { return }
        let now = stamp()
        var changed = false
        for (index, item) in builtInCategories.enumerated() {
            if var category = snapshot.categories.first(where: { $0.builtIn == item.key }) {
                guard category.sort != index else { continue }
                category.sort = index
                category.updatedAt = now
                try? store.insertCategory(category)
                sync.enqueueSave(category.id)
                changed = true
            } else {
                let category = JarCategory(id: UUID().uuidString, name: item.name, enabled: true, builtIn: item.key, sort: index, updatedAt: now)
                try? store.insertCategory(category)
                sync.enqueueSave(category.id)
                changed = true
            }
        }
        let customs = snapshot.categories.filter { $0.builtIn == nil }.sorted { $0.sort < $1.sort }
        for (offset, var category) in customs.enumerated() {
            let sort = builtInCategories.count + offset
            guard category.sort != sort else { continue }
            category.sort = sort
            category.updatedAt = now
            try? store.insertCategory(category)
            sync.enqueueSave(category.id)
            changed = true
        }
        if changed { reload() }
    }

    func wake() async {
        guard booted, snapshot.settings != nil else { return }
        if key == nil {
            let reset = UserDefaults.standard.bool(forKey: "jar.passphraseReset")
            guard shouldPromptToUnlock(passphraseReset: reset, hasKey: false) else {
                unlocked = false
                return
            }
            guard !waking else { return }
            waking = true
            defer { waking = false }
            guard let context = await evaluateUnlock() else {
                unlocked = false
                return
            }
            key = readHouseholdKey(context: context)
        }
        unlocked = key != nil
        guard unlocked else { return }
        if pendingAdd { openAdd() }
        sync.start()
        drainWaiting()
        catchUp()
        await sync.fetch()
        await flushNotices()
        markNoticesLive()
    }

    func lock() {
        guard !suspendLock else { return }
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
        UserDefaults.standard.set(false, forKey: "jar.passphraseReset")
        unlocked = true
        if pendingAdd { openAdd() }
        sync.start()
        drainWaiting()
        catchUp()
        Task {
            await sync.fetch()
            await flushNotices()
            markNoticesLive()
        }
        return true
    }

    var noticesLive: Bool { UserDefaults.standard.object(forKey: "jar.noticesLive") != nil }

    func flushNotices() async {
        let notes = pendingNotices
        pendingNotices.removeAll()
        for notice in notes { await postSpendNotice(notice) }
    }

    func markNoticesLive() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "jar.noticesLive") == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: "jar.noticesLive")
        }
    }

    func receiveRemoteChange() async -> Bool {
        boot()
        guard snapshot.settings != nil else { return false }
        if key == nil { key = readHouseholdKey() }
        guard key != nil else { return false }
        sync.start()
        await sync.fetch()
        await flushNotices()
        markNoticesLive()
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
        guard canEditJarDay(target, open: openDate) else { return }
        if target != openDate {
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
        publishPile()
    }

    private func publishPile() {
        guard snapshot.settings != nil else { return }
        PileBoard.write(pileLeftCents(cap: todayCap, spent: todaySpent))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func settledDays() -> [DayRow] {
        snapshot.days.filter(\.settled).sorted { $0.date < $1.date }
    }

    private func canChange(_ entry: Entry) -> Bool {
        if entry.kind == "outside" { return true }
        return canEditJarDay(entry.day, open: openDate)
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
