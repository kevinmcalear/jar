import CloudKit
import Foundation

enum InviteShareError: LocalizedError {
    case noLink
    case noAccount
    case restricted
    case unavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .noLink: "iCloud did not return an invite link."
        case .noAccount: "Sign in to iCloud to invite the other phone."
        case .restricted: "iCloud is restricted on this phone."
        case .unavailable: "iCloud is temporarily unavailable. Try again."
        case .timedOut: "iCloud took too long to make the invite link."
        }
    }
}

func shareFailureText(_ error: Error) -> String {
    guard let ck = error as? CKError else { return "Jar could not join the household. Open the invite again." }
    switch ck.code {
    case .notAuthenticated:
        return "Sign in to iCloud on this phone, then open the invite again."
    case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited:
        return "iCloud could not be reached. Open the invite again."
    default:
        return "Jar could not join the household. Open the invite again."
    }
}

// ponytail: one 30s race. The Messages card used to wait on this and spun forever; a hung CloudKit callback becomes an error. Raise the bound if an Apple ID prompt needs longer.
private nonisolated func inviteDeadline() async throws -> URL {
    try await Task.sleep(for: .seconds(30))
    throw InviteShareError.timedOut
}

@MainActor
final class HouseholdSync: NSObject, CKSyncEngineDelegate {
    weak var model: AppModel?
    var directory: URL?
    let container = CKContainer(identifier: "iCloud.com.kevinmcalear.dailyjar")
    private var privateEngine: CKSyncEngine?
    private var sharedEngine: CKSyncEngine?
    private var queued: [CKSyncEngine.PendingRecordZoneChange] = []

    func start() {
        let fresh = privateEngine == nil && sharedEngine == nil
        if privateEngine == nil {
            privateEngine = engine(container.privateCloudDatabase, "sync-private.json")
        }
        if sharedEngine == nil {
            sharedEngine = engine(container.sharedCloudDatabase, "sync-shared.json")
        }
        guard fresh else { return }
        let pending = queued
        queued = []
        writer?.state.add(pendingRecordZoneChanges: pending)
        Task { await installSubscriptions() }
    }

    /// Drop the shared-database cursor so the next fetch downloads the whole household, including spends from before this phone joined.
    func prepareForAcceptedShare() {
        sharedEngine = nil
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("sync-shared.json"))
    }

    func enqueueSave(_ name: String) {
        change(.saveRecord(recordID(name)))
    }

    func enqueueDelete(_ name: String) {
        change(.deleteRecord(recordID(name)))
    }

    func fetch() async {
        if privateEngine == nil { start() }
        await adoptSharedHousehold()
        try? await privateEngine?.fetchChanges()
        try? await sharedEngine?.fetchChanges()
        if UserDefaults.standard.bool(forKey: "jar.resync") {
            UserDefaults.standard.set(false, forKey: "jar.resync")
            resetSync()
        }
        model?.republishIfNeeded()
    }

    /// Link first, then the caller opens Messages. A collaboration item prepares inside that sheet and never finishes.
    func inviteLink() async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await self.householdLink() }
            group.addTask { try await inviteDeadline() }
            do {
                guard let url = try await group.next() else { throw InviteShareError.noLink }
                group.cancelAll()
                return url
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func householdLink() async throws -> URL {
        do {
            return try await existingOrNewShare()
        } catch let error as CKError where error.code == .notAuthenticated {
            throw InviteShareError.noAccount
        }
    }

    private func existingOrNewShare() async throws -> URL {
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "household", ownerName: CKCurrentUserDefaultName)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try await zoneShare(database, shareID) {
            if existing.publicPermission == .readWrite, let url = existing.url { return remember(url) }
            existing.publicPermission = .readWrite
            return try await savedURL(database, existing)
        }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        let share = CKShare(recordZoneID: zoneID)
        share.publicPermission = .readWrite
        share[CKShare.SystemFieldKey.title] = "Jar" as NSString
        return try await savedURL(database, share)
    }

    private func zoneShare(_ database: CKDatabase, _ shareID: CKRecord.ID) async throws -> CKShare? {
        do {
            return try await database.record(for: shareID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    private func savedURL(_ database: CKDatabase, _ share: CKShare, retry: Bool = true) async throws -> URL {
        do {
            let saved = try await database.modifyRecords(saving: [share], deleting: [])
            for result in saved.saveResults.values {
                switch result {
                case let .success(record):
                    if let url = (record as? CKShare)?.url { return remember(url) }
                case let .failure(error):
                    if let url = try await conflictURL(database, error, retry: retry) { return url }
                    throw error
                }
            }
        } catch {
            if let url = try await conflictURL(database, error, retry: retry) { return url }
            throw error
        }
        throw InviteShareError.noLink
    }

    private func conflictURL(_ database: CKDatabase, _ error: Error, retry: Bool) async throws -> URL? {
        guard let ck = error as? CKError else { return nil }
        if ck.code == .partialFailure {
            guard retry, let inner = ck.partialErrorsByItemID?.values.first else { return nil }
            return try await conflictURL(database, inner, retry: false)
        }
        guard let server = ck.serverRecord as? CKShare else { return nil }
        if server.publicPermission == .readWrite, let url = server.url { return remember(url) }
        guard retry else { return nil }
        server.publicPermission = .readWrite
        return try await savedURL(database, server, retry: false)
    }

    private func remember(_ url: URL) -> URL {
        UserDefaults.standard.set(true, forKey: "jar.republish")
        return url
    }

    func resetSync() {
        privateEngine = nil
        sharedEngine = nil
        guard let directory else { return }
        for name in ["sync-private.json", "sync-shared.json"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func adoptSharedHousehold() async {
        guard let zones = try? await container.sharedCloudDatabase.allRecordZones() else { return }
        let owners = zones.map(\.zoneID).filter { $0.zoneName == "household" }.map(\.ownerName)
        let adopted = adoptSharedZone(
            isOwner: model?.snapshot.settings?.isOwner != false,
            zoneOwner: model?.snapshot.settings?.zoneOwner,
            sharedZoneOwners: owners
        )
        guard var settings = model?.snapshot.settings else { return }
        guard settings.isOwner != adopted.isOwner || settings.zoneOwner != adopted.zoneOwner else { return }
        settings.isOwner = adopted.isOwner
        settings.zoneOwner = adopted.zoneOwner
        try? model?.store?.insertSettings(settings)
        model?.reload()
    }

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await self.deliver(event, syncEngine)
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            await self.record(named: id.recordName)
        }
    }

    private func deliver(_ event: CKSyncEngine.Event, _ engine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            guard privateEngine === engine || sharedEngine === engine else { break }
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                try? data.write(to: stateURL(engine), options: .atomic)
            }
        case .fetchedRecordZoneChanges(let changes):
            for change in changes.modifications { model?.apply(change.record) }
            for deletion in changes.deletions {
                model?.applyDelete(name: deletion.recordID.recordName, type: deletion.recordType)
            }
            await model?.flushNotices()
        case .sentRecordZoneChanges(let sent):
            for failure in sent.failedRecordSaves {
                if let server = failure.error.serverRecord {
                    model?.apply(server)
                } else if UserDefaults.standard.bool(forKey: "jar.republish") || UserDefaults.standard.bool(forKey: "jar.republishArmed") {
                    UserDefaults.standard.set(true, forKey: "jar.republish")
                    UserDefaults.standard.set(false, forKey: "jar.republishArmed")
                }
            }
        case .sentDatabaseChanges(let sent):
            if !sent.failedZoneSaves.isEmpty, UserDefaults.standard.bool(forKey: "jar.republishArmed") {
                UserDefaults.standard.set(true, forKey: "jar.republish")
                UserDefaults.standard.set(false, forKey: "jar.republishArmed")
            }
        case .didSendChanges:
            guard UserDefaults.standard.bool(forKey: "jar.republishArmed") else { break }
            let idle = [privateEngine, sharedEngine].allSatisfy { engine in
                engine?.state.pendingRecordZoneChanges.isEmpty != false && engine?.state.pendingDatabaseChanges.isEmpty != false
            }
            if idle {
                UserDefaults.standard.set(false, forKey: "jar.republish")
                UserDefaults.standard.set(false, forKey: "jar.republishArmed")
            }
        default:
            break
        }
    }

    private func record(named name: String) -> CKRecord? {
        model?.makeRecord(name: name)
    }

    private func engine(_ database: CKDatabase, _ file: String) -> CKSyncEngine {
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: state(file), delegate: self)
        configuration.subscriptionID = "jar-database"
        return CKSyncEngine(configuration)
    }

    private var writer: CKSyncEngine? {
        model?.snapshot.settings?.isOwner == false ? sharedEngine : privateEngine
    }

    private func change(_ change: CKSyncEngine.PendingRecordZoneChange) {
        if let writer {
            writer.state.add(pendingRecordZoneChanges: [change])
        } else {
            queued.append(change)
        }
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        let owner = model?.snapshot.settings?.isOwner == false ? (model?.snapshot.settings?.zoneOwner ?? CKCurrentUserDefaultName) : CKCurrentUserDefaultName
        return CKRecord.ID(recordName: name, zoneID: CKRecordZone.ID(zoneName: "household", ownerName: owner))
    }

    private func state(_ file: String) -> CKSyncEngine.State.Serialization? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func stateURL(_ engine: CKSyncEngine) -> URL {
        let file = engine.database.databaseScope == .shared ? "sync-shared.json" : "sync-private.json"
        return (directory ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent(file)
    }

    private func installSubscriptions() async {
        // Silent push only: content-available, no alert and no record fields. The amount stays ciphertext until this phone decrypts it.
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.shouldBadge = false
        let subscription = CKDatabaseSubscription(subscriptionID: "jar-database")
        subscription.notificationInfo = info
        for database in [container.privateCloudDatabase, container.sharedCloudDatabase] {
            _ = try? await database.modifySubscriptions(saving: [subscription], deleting: [])
            _ = try? await database.modifySubscriptions(saving: [], deleting: ["jar-entry"])
        }
    }
}

extension AppModel {
    var zoneID: CKRecordZone.ID {
        let owner = snapshot.settings?.isOwner == false ? (snapshot.settings?.zoneOwner ?? CKCurrentUserDefaultName) : CKCurrentUserDefaultName
        return CKRecordZone.ID(zoneName: "household", ownerName: owner)
    }

    func makeRecord(name: String) -> CKRecord? {
        guard let key else { return nil }
        let id = CKRecord.ID(recordName: name, zoneID: zoneID)
        if name == "settings", let settings = snapshot.settings {
            let record = CKRecord(recordType: "Settings", recordID: id)
            record["timezone"] = settings.timezone as NSString
            record["closeHour"] = settings.closeHour as NSNumber
            record["usualCapChangedAt"] = date(from: settings.usualCapChangedAt) as NSDate?
            if let by = settings.usualCapSetBy { record["usualCapSetBy"] = reference(by) }
            if let salt = settings.kdfSalt { record["kdfSalt"] = salt as NSData }
            if let iterations = settings.kdfIterations { record["kdfIterations"] = iterations as NSNumber }
            assign(record, "usualCap", sealCents(settings.usualCap, name, "usualCap"))
            if let goal = settings.savingsGoal {
                assign(record, "savingsGoal", sealCents(goal, name, "savingsGoal"))
            }
            assign(record, "verifier", settings.verifier)
            return record
        }
        if let person = snapshot.people.first(where: { $0.id == name }) {
            let record = CKRecord(recordType: "Person", recordID: id)
            record["displayName"] = person.displayName as NSString
            record["sticker"] = person.sticker as NSString
            return record
        }
        if let category = snapshot.categories.first(where: { $0.id == name }) {
            let record = CKRecord(recordType: "Category", recordID: id)
            record["name"] = category.name as NSString
            record["enabled"] = (category.enabled ? 1 : 0) as NSNumber
            if let builtIn = category.builtIn { record["builtIn"] = builtIn as NSString }
            record["sort"] = category.sort as NSNumber
            record["updatedAt"] = date(from: category.updatedAt) as NSDate?
            return record
        }
        if let day = snapshot.days.first(where: { $0.date == name }) {
            let record = CKRecord(recordType: "Day", recordID: id)
            assign(record, "cap", sealCents(day.cap, name, "cap"))
            return record
        }
        if let entry = snapshot.entries.first(where: { $0.id == name }) {
            let record = CKRecord(recordType: "Entry", recordID: id)
            record["day"] = entry.day as NSString
            if let person = entry.personID { record["person"] = reference(person) }
            record["kind"] = entry.kind as NSString
            if let category = entry.categoryID { record["category"] = reference(category) }
            if let chip = entry.chip { record["chip"] = chip as NSString }
            if let rhythm = entry.rhythm { record["rhythm"] = rhythm as NSString }
            record["createdAt"] = date(from: entry.createdAt) as NSDate?
            record["updatedAt"] = date(from: entry.updatedAt) as NSDate?
            assign(record, "amount", sealCents(entry.amount, name, "amount"))
            if let note = entry.note, let sealed = try? sealField(Data(note.utf8), record: name, field: "note", key: key) {
                record["note"] = sealed as NSData
            }
            if let photo = entry.photo, let sealed = try? sealField(photo, record: name, field: "photo", key: key) {
                let url = sync.directory?.appendingPathComponent("photo-\(name).bin") ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("photo-\(name).bin")
                try? sealed.write(to: url)
                record["photo"] = CKAsset(fileURL: url)
            }
            return record
        }
        if let row = snapshot.income.first(where: { $0.id == name }) ?? snapshot.bills.first(where: { $0.id == name }) {
            let type = snapshot.income.contains(where: { $0.id == name }) ? "IncomeSource" : "Bill"
            let record = CKRecord(recordType: type, recordID: id)
            record["name"] = row.name as NSString
            record["rhythm"] = row.rhythm as NSString
            assign(record, "amount", sealCents(row.amount, name, "amount"))
            return record
        }
        return nil
    }

    func apply(_ record: CKRecord) {
        if record.recordType != "Person", record.recordType != "Category", !canReadSealed(record) {
            if record.recordType == "Settings" {
                applySettings(record)
                reload()
                lockIfKeyDoesNotOpenHousehold()
            }
            park(record)
            return
        }
        let name = record.recordID.recordName
        switch record.recordType {
        case "Settings": applySettings(record)
        case "Person":
            let person = Person(id: name, displayName: string(record, "displayName") ?? "Someone", sticker: string(record, "sticker") ?? "kevin")
            try? store?.insertPerson(person)
        case "Category":
            let remote = stamp(date(record, "updatedAt") ?? Date())
            if let local = snapshot.categories.first(where: { $0.id == name }), local.updatedAt > remote {
                sync.enqueueSave(name)
                return
            }
            let category = JarCategory(id: name, name: string(record, "name") ?? "Category", enabled: number(record, "enabled") != 0, builtIn: string(record, "builtIn"), sort: number(record, "sort"), updatedAt: remote)
            try? store?.insertCategory(category)
        case "Day":
            guard let cap = openCents(data(record, "cap"), name, "cap") else { return }
            if snapshot.days.contains(where: { $0.date == name }) { return }
            try? store?.insertDay(DayRow(date: name, cap: cap, settled: false))
        case "Entry":
            applyEntry(record)
        case "IncomeSource", "Bill":
            guard let amount = openCents(data(record, "amount"), name, "amount") else { return }
            let table = record.recordType == "Bill" ? "bills" : "income"
            try? store?.insertMoney(table, MoneyRow(id: name, name: string(record, "name") ?? "", amount: amount, rhythm: string(record, "rhythm") ?? PayRhythm.monthly.rawValue))
        default:
            break
        }
        reload()
    }

    func applyDelete(name: String, type: String) {
        if type == "Entry", let entry = snapshot.entries.first(where: { $0.id == name }) {
            try? store?.deleteEntry(name)
            if entry.kind == "jar" {
                try? store?.unsetSettled(from: entry.day)
                try? store?.clearPourSeen(from: entry.day)
            }
            reload()
            catchUp()
        } else if type == "IncomeSource" {
            try? store?.deleteMoney("income", name)
            reload()
        } else if type == "Bill" {
            try? store?.deleteMoney("bills", name)
            reload()
        }
    }

    func drainWaiting() {
        let records = waiting
        waiting = []
        records.forEach(apply)
        if waiting.isEmpty, let directory = sync.directory {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("waiting.ckrecords"))
        }
    }

    func joinSharedZone(ownerName: String) {
        guard !ownerName.isEmpty else { return }
        var settings = snapshot.settings ?? HouseholdSettings(
            timezone: TimeZone.current.identifier, closeHour: 4, usualCap: 5000, usualCapChangedAt: stamp(),
            usualCapSetBy: nil, savingsGoal: nil, kdfSalt: nil, kdfIterations: nil, verifier: nil, holderID: nil,
            isOwner: false, zoneOwner: ownerName
        )
        settings.isOwner = false
        settings.zoneOwner = ownerName
        try? store?.insertSettings(settings)
        reload()
    }

    func acceptShare(url: URL) async {
        guard isCloudKitShareURL(url) else { return }
        do {
            await acceptShare(try await sync.container.shareMetadata(for: url))
        } catch {
            shareError = shareFailureText(error)
        }
    }

    func acceptShare(_ metadata: CKShare.Metadata) async {
        guard !acceptingShare else { return }
        acceptingShare = true
        defer { acceptingShare = false }
        boot()
        let owner = metadata.share.recordID.zoneID.ownerName
        guard !owner.isEmpty else {
            shareError = "Jar could not join the household. Open the invite again."
            return
        }
        let container = metadata.containerIdentifier.isEmpty ? sync.container : CKContainer(identifier: metadata.containerIdentifier)
        do {
            _ = try await container.accept(metadata)
        } catch {
            let zones = (try? await sync.container.sharedCloudDatabase.allRecordZones()) ?? []
            let joined = zones.contains { $0.zoneID.zoneName == "household" && $0.zoneID.ownerName == owner }
            if !joined {
                shareError = shareFailureText(error)
                return
            }
        }
        shareError = nil
        let mine = try? await container.userRecordID()
        let ownsZone = owner == CKCurrentUserDefaultName || mine?.recordName == owner
        if !ownsZone {
            joinSharedZone(ownerName: owner)
            sync.prepareForAcceptedShare()
        }
        sync.start()
        await sync.fetch()
        if key != nil, opensHousehold() {
            unlocked = true
            drainWaiting()
        } else if snapshot.settings?.verifier != nil {
            key = nil
            unlocked = false
            UserDefaults.standard.set(true, forKey: "jar.passphraseReset")
        }
        await flushNotices()
        markNoticesLive()
        tab = "month"
    }

    func republishIfNeeded() {
        // ponytail: one flag re-sends the whole household after a passphrase change. Fine for two phones; per-record change tags if the zone gets large.
        guard UserDefaults.standard.bool(forKey: "jar.republish"), opensHousehold() else { return }
        sync.enqueueSave("settings")
        snapshot.people.forEach { sync.enqueueSave($0.id) }
        snapshot.categories.forEach { sync.enqueueSave($0.id) }
        snapshot.days.forEach { sync.enqueueSave($0.date) }
        snapshot.entries.forEach { sync.enqueueSave($0.id) }
        snapshot.income.forEach { sync.enqueueSave($0.id) }
        snapshot.bills.forEach { sync.enqueueSave($0.id) }
        UserDefaults.standard.set(true, forKey: "jar.republishArmed")
    }

    func opensHousehold() -> Bool {
        guard let key, let verifier = snapshot.settings?.verifier else { return false }
        return (try? openField(verifier, record: "settings", field: "verifier", key: key)) == householdVerifier
    }

    private func canReadSealed(_ record: CKRecord) -> Bool {
        guard let key else { return false }
        let name = record.recordID.recordName
        switch record.recordType {
        case "Settings":
            if let verifier = data(record, "verifier"), (try? openField(verifier, record: name, field: "verifier", key: key)) == nil { return false }
            if data(record, "usualCap") != nil, openCents(data(record, "usualCap"), name, "usualCap") == nil { return false }
            if let goal = data(record, "savingsGoal"), openCents(goal, name, "savingsGoal") == nil { return false }
            return true
        case "Day":
            return data(record, "cap") == nil || openCents(data(record, "cap"), name, "cap") != nil
        case "Entry", "IncomeSource", "Bill":
            return data(record, "amount") == nil || openCents(data(record, "amount"), name, "amount") != nil
        default:
            return true
        }
    }

    private func lockIfKeyDoesNotOpenHousehold() {
        guard key != nil, snapshot.settings?.verifier != nil, !opensHousehold() else { return }
        key = nil
        unlocked = false
        deleteHouseholdKey()
        UserDefaults.standard.set(true, forKey: "jar.passphraseReset")
        // A participant's old local copy must not be written over the household she just joined.
        guard snapshot.settings?.isOwner != false else { return }
        UserDefaults.standard.set(true, forKey: "jar.republish")
        UserDefaults.standard.set(true, forKey: "jar.resync")
    }

    private func park(_ record: CKRecord) {
        waiting.removeAll { $0.recordID == record.recordID }
        waiting.append(record)
        guard let directory = sync.directory else { return }
        let url = directory.appendingPathComponent("waiting.ckrecords")
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: waiting as NSArray, requiringSecureCoding: true) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func loadWaiting() {
        guard let directory = sync.directory else { return }
        let url = directory.appendingPathComponent("waiting.ckrecords")
        guard let data = try? Data(contentsOf: url) else { return }
        let classes: [AnyClass] = [NSArray.self, CKRecord.self, NSString.self, NSData.self, NSDate.self, NSNumber.self, NSURL.self, CKAsset.self]
        guard let records = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? [CKRecord] else { return }
        waiting = records
    }

    private func applySettings(_ record: CKRecord) {
        let name = record.recordID.recordName
        var settings = snapshot.settings ?? HouseholdSettings(timezone: TimeZone.current.identifier, closeHour: 4, usualCap: 5000, usualCapChangedAt: stamp(), usualCapSetBy: nil, savingsGoal: nil, kdfSalt: nil, kdfIterations: nil, verifier: nil, holderID: nil, isOwner: false, zoneOwner: snapshot.settings?.zoneOwner)
        if let timezone = string(record, "timezone") { settings.timezone = timezone }
        let hour = number(record, "closeHour")
        if hour >= 0, hour <= 23 { settings.closeHour = hour }
        if let salt = data(record, "kdfSalt") { settings.kdfSalt = salt }
        let iterations = number(record, "kdfIterations")
        if iterations > 0 { settings.kdfIterations = iterations }
        if let verifier = data(record, "verifier") { settings.verifier = verifier }
        let remoteStamp = stamp(date(record, "usualCapChangedAt") ?? Date.distantPast)
        if remoteStamp >= settings.usualCapChangedAt, let cap = openCents(data(record, "usualCap"), name, "usualCap"), cap >= 0 {
            settings.usualCap = cap
            settings.usualCapChangedAt = remoteStamp
            settings.usualCapSetBy = referenceName(record, "usualCapSetBy")
            if let goalData = data(record, "savingsGoal"), let goal = openCents(goalData, name, "savingsGoal") {
                settings.savingsGoal = goal
            }
        } else if remoteStamp < settings.usualCapChangedAt {
            sync.enqueueSave("settings")
        }
        try? store?.insertSettings(settings)
    }

    private func applyEntry(_ record: CKRecord) {
        let name = record.recordID.recordName
        guard let amount = openCents(data(record, "amount"), name, "amount"), let day = string(record, "day") else { return }
        let remote = stamp(date(record, "updatedAt") ?? date(record, "createdAt") ?? Date())
        if let local = snapshot.entries.first(where: { $0.id == name }), local.updatedAt > remote {
            sync.enqueueSave(name)
            return
        }
        let existed = snapshot.entries.contains { $0.id == name }
        let origin = existed && (snapshot.entries.first { $0.id == name }?.originLocal == true)
        let note: String?
        if let key, let sealed = data(record, "note"), let plain = try? openField(sealed, record: name, field: "note", key: key) {
            note = String(data: plain, encoding: .utf8)
        } else {
            note = nil
        }
        var photo: Data?
        if let asset = record["photo"] as? CKAsset, let url = asset.fileURL, let sealed = try? Data(contentsOf: url), let key {
            photo = try? openField(sealed, record: name, field: "photo", key: key)
        }
        let entry = Entry(
            id: name, day: day, personID: referenceName(record, "person"), amount: amount, kind: string(record, "kind") ?? "jar",
            categoryID: referenceName(record, "category"), chip: string(record, "chip"), rhythm: string(record, "rhythm"), note: note,
            photo: photo, createdAt: stamp(date(record, "createdAt") ?? Date()), updatedAt: remote, originLocal: origin
        )
        try? store?.insertEntry(entry)
        reload()
        let created = date(from: entry.createdAt)?.timeIntervalSince1970 ?? 0
        let live = noticesLive && created >= UserDefaults.standard.double(forKey: "jar.noticesLive")
        guard shouldPostSpendNotice(kind: entry.kind, existed: existed, originLocal: entry.originLocal, noticesLive: live) else { return }
        let cap = snapshot.days.first { $0.date == day }?.cap ?? snapshot.settings?.usualCap ?? 0
        let spent = snapshot.entries.filter { $0.day == day && $0.kind == "jar" }.reduce(0) { $0 + $1.amount }
        let person = snapshot.people.first { $0.id == entry.personID }
        let category = snapshot.categories.first { $0.id == entry.categoryID }
        pendingNotices.append(SpendNotice(
            person: person?.displayName ?? "Someone", sticker: person?.sticker ?? "kevin",
            category: category?.name ?? "Something", amount: amount, left: max(0, cap - spent)
        ))
    }

    private func sealCents(_ cents: Int, _ record: String, _ field: String) -> Data? {
        guard let key else { return nil }
        return try? sealField(centsPlaintext(cents), record: record, field: field, key: key)
    }

    private func openCents(_ data: Data?, _ record: String, _ field: String) -> Int? {
        guard let data, let key, let plain = try? openField(data, record: record, field: field, key: key) else { return nil }
        return cents(from: plain)
    }

    private func assign(_ record: CKRecord, _ field: String, _ data: Data?) {
        if let data { record[field] = data as NSData }
    }

    private func reference(_ name: String) -> CKRecord.Reference {
        CKRecord.Reference(recordID: CKRecord.ID(recordName: name, zoneID: zoneID), action: CKRecord.ReferenceAction.none)
    }

    private func referenceName(_ record: CKRecord, _ field: String) -> String? {
        (record[field] as? CKRecord.Reference)?.recordID.recordName
    }

    private func string(_ record: CKRecord, _ field: String) -> String? {
        record[field] as? String
    }

    private func number(_ record: CKRecord, _ field: String) -> Int {
        (record[field] as? NSNumber)?.intValue ?? 0
    }

    private func data(_ record: CKRecord, _ field: String) -> Data? {
        record[field] as? Data
    }

    private func date(_ record: CKRecord, _ field: String) -> Date? {
        record[field] as? Date
    }

    private func date(from stamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: stamp)
    }
}
