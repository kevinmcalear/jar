import Foundation
import SQLite3

struct StoreError: Error, CustomStringConvertible {
    var message: String
    var description: String { message }
}

final class Store {
    // ponytail: deinit is nonisolated, so this handle is closed there. Queries stay on the main actor; nothing else holds the pointer.
    nonisolated(unsafe) private var db: OpaquePointer?
    let directory: URL

    init() throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = base.appendingPathComponent("Jar", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = directory
        try folder.setResourceValues(values)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        let path = directory.appendingPathComponent("jar.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw StoreError(message: "The jar cache did not open.")
        }
        try exec("PRAGMA journal_mode = WAL")
        try exec("PRAGMA foreign_keys = ON")
        try migrate()
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
    }

    deinit { sqlite3_close(db) }

    func load() throws -> Snapshot {
        guard let settings = try loadSettings() else {
            return Snapshot()
        }
        return Snapshot(
            settings: settings,
            people: try loadPeople(),
            categories: try loadCategories(),
            days: try loadDays(),
            entries: try loadEntries(),
            income: try loadMoney("income"),
            bills: try loadMoney("bills"),
            pourSeen: try loadPourSeen()
        )
    }

    func insertSettings(_ settings: HouseholdSettings) throws {
        try run(
            """
            INSERT INTO settings (id, timezone, close_hour, usual_cap, usual_cap_changed_at, usual_cap_set_by, savings_goal, kdf_salt, kdf_iterations, verifier, holder_id, is_owner, zone_owner)
            VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              timezone = excluded.timezone,
              close_hour = excluded.close_hour,
              usual_cap = excluded.usual_cap,
              usual_cap_changed_at = excluded.usual_cap_changed_at,
              usual_cap_set_by = excluded.usual_cap_set_by,
              savings_goal = excluded.savings_goal,
              kdf_salt = excluded.kdf_salt,
              kdf_iterations = excluded.kdf_iterations,
              verifier = excluded.verifier,
              holder_id = excluded.holder_id,
              is_owner = excluded.is_owner,
              zone_owner = excluded.zone_owner
            """,
            binds(settings)
        )
    }

    func insertPerson(_ person: Person) throws {
        try run(
            "INSERT INTO people (id, display_name, sticker) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET display_name = excluded.display_name, sticker = excluded.sticker",
            [.text(person.id), .text(person.displayName), .text(person.sticker)]
        )
    }

    func insertCategory(_ category: JarCategory) throws {
        try run(
            "INSERT INTO categories (id, name, enabled, built_in, sort, updated_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, enabled = excluded.enabled, built_in = excluded.built_in, sort = excluded.sort, updated_at = excluded.updated_at",
            [.text(category.id), .text(category.name), .int(category.enabled ? 1 : 0), category.builtIn.map(Bind.text) ?? .null, .int(category.sort), .text(category.updatedAt)]
        )
    }

    func insertDay(_ day: DayRow) throws {
        try run(
            "INSERT INTO days (date, cap, settled) VALUES (?, ?, ?) ON CONFLICT(date) DO NOTHING",
            [.text(day.date), .int(day.cap), .int(day.settled ? 1 : 0)]
        )
    }

    func setSettled(_ date: String, _ settled: Bool) throws {
        try run("UPDATE days SET settled = ? WHERE date = ?", [.int(settled ? 1 : 0), .text(date)])
    }

    func unsetSettled(from date: String) throws {
        try run("UPDATE days SET settled = 0 WHERE date >= ?", [.text(date)])
    }

    func insertEntry(_ entry: Entry) throws {
        try run(
            """
            INSERT INTO entries (id, day, person_id, amount, kind, category_id, chip, rhythm, note, photo, created_at, updated_at, origin_local)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              day = excluded.day, person_id = excluded.person_id, amount = excluded.amount, kind = excluded.kind,
              category_id = excluded.category_id, chip = excluded.chip, rhythm = excluded.rhythm, note = excluded.note,
              photo = excluded.photo, updated_at = excluded.updated_at, origin_local = excluded.origin_local
            """,
            [
                .text(entry.id), .text(entry.day), entry.personID.map(Bind.text) ?? .null, .int(entry.amount), .text(entry.kind),
                entry.categoryID.map(Bind.text) ?? .null, entry.chip.map(Bind.text) ?? .null, entry.rhythm.map(Bind.text) ?? .null,
                entry.note.map(Bind.text) ?? .null, entry.photo.map(Bind.blob) ?? .null, .text(entry.createdAt), .text(entry.updatedAt),
                .int(entry.originLocal ? 1 : 0),
            ]
        )
    }

    func deleteEntry(_ id: String) throws {
        try run("DELETE FROM entries WHERE id = ?", [.text(id)])
    }

    func deleteCategory(_ id: String) throws {
        try run("DELETE FROM categories WHERE id = ?", [.text(id)])
    }

    func retargetCategory(from: String, to: String, updatedAt: String) throws {
        try run("UPDATE entries SET category_id = ?, updated_at = ? WHERE category_id = ?", [.text(to), .text(updatedAt), .text(from)])
    }

    func deletePerson(_ id: String) throws {
        try run("DELETE FROM people WHERE id = ?", [.text(id)])
    }

    func retargetPerson(from: String, to: String, updatedAt: String) throws {
        try run("UPDATE entries SET person_id = ?, updated_at = ? WHERE person_id = ?", [.text(to), .text(updatedAt), .text(from)])
    }

    func insertMoney(_ table: String, _ row: MoneyRow) throws {
        guard table == "income" || table == "bills" else { return }
        try run(
            "INSERT INTO \(table) (id, name, amount, rhythm) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, amount = excluded.amount, rhythm = excluded.rhythm",
            [.text(row.id), .text(row.name), .int(row.amount), .text(row.rhythm)]
        )
    }

    func deleteMoney(_ table: String, _ id: String) throws {
        guard table == "income" || table == "bills" else { return }
        try run("DELETE FROM \(table) WHERE id = ?", [.text(id)])
    }

    func markPourSeen(_ dates: [String]) throws {
        for date in dates {
            try run("INSERT INTO pour_seen (date) VALUES (?) ON CONFLICT(date) DO NOTHING", [.text(date)])
        }
    }

    func clearPourSeen(from date: String) throws {
        try run("DELETE FROM pour_seen WHERE date >= ?", [.text(date)])
    }

    func saveScore(jar: Int, debt: Int) throws {
        try run(
            "INSERT INTO score_cache (id, jar, debt) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET jar = excluded.jar, debt = excluded.debt",
            [.int(jar), .int(debt)]
        )
    }

    private func migrate() throws {
        try exec(
            """
            CREATE TABLE IF NOT EXISTS settings (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              timezone TEXT NOT NULL,
              close_hour INTEGER NOT NULL,
              usual_cap INTEGER NOT NULL,
              usual_cap_changed_at TEXT NOT NULL,
              usual_cap_set_by TEXT,
              savings_goal INTEGER,
              kdf_salt BLOB,
              kdf_iterations INTEGER,
              verifier BLOB,
              holder_id TEXT,
              is_owner INTEGER NOT NULL DEFAULT 1,
              zone_owner TEXT
            );
            CREATE TABLE IF NOT EXISTS people (
              id TEXT PRIMARY KEY,
              display_name TEXT NOT NULL,
              sticker TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS categories (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              enabled INTEGER NOT NULL,
              built_in TEXT,
              sort INTEGER NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS days (
              date TEXT PRIMARY KEY,
              cap INTEGER NOT NULL,
              settled INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS entries (
              id TEXT PRIMARY KEY,
              day TEXT NOT NULL,
              person_id TEXT,
              amount INTEGER NOT NULL,
              kind TEXT NOT NULL,
              category_id TEXT,
              chip TEXT,
              rhythm TEXT,
              note TEXT,
              photo BLOB,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              origin_local INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS income (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              amount INTEGER NOT NULL,
              rhythm TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS bills (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              amount INTEGER NOT NULL,
              rhythm TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS pour_seen (date TEXT PRIMARY KEY);
            CREATE TABLE IF NOT EXISTS score_cache (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              jar INTEGER NOT NULL,
              debt INTEGER NOT NULL
            );
            """
        )
    }

    private func loadSettings() throws -> HouseholdSettings? {
        var found: HouseholdSettings?
        try query("SELECT timezone, close_hour, usual_cap, usual_cap_changed_at, usual_cap_set_by, savings_goal, kdf_salt, kdf_iterations, verifier, holder_id, is_owner, zone_owner FROM settings WHERE id = 1") { stmt in
            found = HouseholdSettings(
                timezone: text(stmt, 0),
                closeHour: int(stmt, 1),
                usualCap: int(stmt, 2),
                usualCapChangedAt: text(stmt, 3),
                usualCapSetBy: optionalText(stmt, 4),
                savingsGoal: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : int(stmt, 5),
                kdfSalt: blob(stmt, 6),
                kdfIterations: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : int(stmt, 7),
                verifier: blob(stmt, 8),
                holderID: optionalText(stmt, 9),
                isOwner: int(stmt, 10) != 0,
                zoneOwner: optionalText(stmt, 11)
            )
        }
        return found
    }

    private func loadPeople() throws -> [Person] {
        var rows: [Person] = []
        try query("SELECT id, display_name, sticker FROM people") { stmt in
            rows.append(Person(id: text(stmt, 0), displayName: text(stmt, 1), sticker: text(stmt, 2)))
        }
        return rows
    }

    private func loadCategories() throws -> [JarCategory] {
        var rows: [JarCategory] = []
        try query("SELECT id, name, enabled, built_in, sort, updated_at FROM categories ORDER BY sort") { stmt in
            rows.append(JarCategory(id: text(stmt, 0), name: text(stmt, 1), enabled: int(stmt, 2) != 0, builtIn: optionalText(stmt, 3), sort: int(stmt, 4), updatedAt: text(stmt, 5)))
        }
        return rows
    }

    private func loadDays() throws -> [DayRow] {
        var rows: [DayRow] = []
        try query("SELECT date, cap, settled FROM days ORDER BY date") { stmt in
            rows.append(DayRow(date: text(stmt, 0), cap: int(stmt, 1), settled: int(stmt, 2) != 0))
        }
        return rows
    }

    private func loadEntries() throws -> [Entry] {
        var rows: [Entry] = []
        try query("SELECT id, day, person_id, amount, kind, category_id, chip, rhythm, note, photo, created_at, updated_at, origin_local FROM entries ORDER BY created_at") { stmt in
            rows.append(Entry(
                id: text(stmt, 0), day: text(stmt, 1), personID: optionalText(stmt, 2), amount: int(stmt, 3), kind: text(stmt, 4),
                categoryID: optionalText(stmt, 5), chip: optionalText(stmt, 6), rhythm: optionalText(stmt, 7), note: optionalText(stmt, 8),
                photo: blob(stmt, 9), createdAt: text(stmt, 10), updatedAt: text(stmt, 11), originLocal: int(stmt, 12) != 0
            ))
        }
        return rows
    }

    private func loadMoney(_ table: String) throws -> [MoneyRow] {
        var rows: [MoneyRow] = []
        try query("SELECT id, name, amount, rhythm FROM \(table)") { stmt in
            rows.append(MoneyRow(id: text(stmt, 0), name: text(stmt, 1), amount: int(stmt, 2), rhythm: text(stmt, 3)))
        }
        return rows
    }

    private func loadPourSeen() throws -> Set<String> {
        var dates: Set<String> = []
        try query("SELECT date FROM pour_seen") { stmt in dates.insert(text(stmt, 0)) }
        return dates
    }

    private func binds(_ settings: HouseholdSettings) -> [Bind] {
        [
            .text(settings.timezone), .int(settings.closeHour), .int(settings.usualCap), .text(settings.usualCapChangedAt),
            settings.usualCapSetBy.map(Bind.text) ?? .null, settings.savingsGoal.map(Bind.int) ?? .null,
            settings.kdfSalt.map(Bind.blob) ?? .null, settings.kdfIterations.map(Bind.int) ?? .null,
            settings.verifier.map(Bind.blob) ?? .null, settings.holderID.map(Bind.text) ?? .null,
            .int(settings.isOwner ? 1 : 0), settings.zoneOwner.map(Bind.text) ?? .null,
        ]
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "sql"
            sqlite3_free(error)
            throw StoreError(message: message)
        }
    }

    private func run(_ sql: String, _ values: [Bind] = []) throws {
        try query(sql, values) { _ in }
    }

    private func query(_ sql: String, _ values: [Bind] = [], _ read: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StoreError(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (index, value) in values.enumerated() {
            try value.bind(stmt, Int32(index + 1))
        }
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW { read(stmt) }
            else if step == SQLITE_DONE { break }
            else { throw StoreError(message: String(cString: sqlite3_errmsg(db))) }
        }
    }

    private func text(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let raw = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: raw)
    }

    private func optionalText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : text(stmt, index)
    }

    private func int(_ stmt: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, index))
    }

    private func blob(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL, let raw = sqlite3_column_blob(stmt, index) else { return nil }
        return Data(bytes: raw, count: Int(sqlite3_column_bytes(stmt, index)))
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private enum Bind {
    case text(String), int(Int), blob(Data), null
    func bind(_ stmt: OpaquePointer, _ index: Int32) throws {
        let status: Int32
        switch self {
        case .text(let value):
            status = sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
        case .int(let value):
            status = sqlite3_bind_int64(stmt, index, Int64(value))
        case .blob(let value):
            status = value.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(value.count), sqliteTransient)
            }
        case .null:
            status = sqlite3_bind_null(stmt, index)
        }
        if status != SQLITE_OK { throw StoreError(message: "bind") }
    }
}
