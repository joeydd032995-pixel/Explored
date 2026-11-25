import Foundation
import SQLite3

final class DatabaseService: @unchecked Sendable {
    static let shared = DatabaseService()

    private var db: OpaquePointer?

    private init() {
        openDatabase()
        createTables()
        migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    private func openDatabase() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("explorer.db")

        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("Failed to open database")
        }
    }

    private func createTables() {
        let tables = [
            """
            CREATE TABLE IF NOT EXISTS coordinates (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                timestamp INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS discovered_hexes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hex_id TEXT UNIQUE NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS visited_counties (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fips TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                state TEXT NOT NULL,
                visited_date INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS visited_states (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                state_id TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                visited_date INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS visited_cities (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                city_id TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                state TEXT NOT NULL,
                visited_date INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS triggered_milestones (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                milestone_id TEXT UNIQUE NOT NULL,
                triggered_date INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS state_stats (
                state_id TEXT PRIMARY KEY,
                last_visit INTEGER NOT NULL DEFAULT 0,
                distance_m REAL NOT NULL DEFAULT 0
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS boundary_cell_counts (
                state_id TEXT PRIMARY KEY,
                total_cells INTEGER NOT NULL,
                boundary_version TEXT NOT NULL,
                computed_at INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS city_hexes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                city_id TEXT NOT NULL,
                hex_id TEXT NOT NULL,
                UNIQUE(city_id, hex_id)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS hex_visits (
                hex_id TEXT PRIMARY KEY,
                visits INTEGER NOT NULL,
                last_visit INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS state_hexes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                state_id TEXT NOT NULL,
                hex_id TEXT NOT NULL,
                UNIQUE(state_id, hex_id)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS county_hexes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                fips TEXT NOT NULL,
                hex_id TEXT NOT NULL,
                UNIQUE(fips, hex_id)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS overlay_points (
                id TEXT PRIMARY KEY,
                family TEXT NOT NULL,
                subkind TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                title TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                confidence REAL NOT NULL,
                confirmations INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                verified_at INTEGER NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS hazard_reports (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                created_at INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                confirmations INTEGER NOT NULL,
                synced INTEGER NOT NULL DEFAULT 0
            )
            """,
        ]

        for sql in tables {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    private func migrate() {
        let migrations = [
            "ALTER TABLE visited_cities ADD COLUMN county TEXT DEFAULT ''",
            // Phase-4 sync bookkeeping: rows not yet pushed to cell_claims.
            "ALTER TABLE state_hexes ADD COLUMN synced INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE county_hexes ADD COLUMN synced INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE city_hexes ADD COLUMN synced INTEGER NOT NULL DEFAULT 0",
            "CREATE INDEX IF NOT EXISTS idx_state_hexes_unsynced ON state_hexes (synced) WHERE synced = 0",
            "CREATE INDEX IF NOT EXISTS idx_county_hexes_unsynced ON county_hexes (synced) WHERE synced = 0",
            "CREATE INDEX IF NOT EXISTS idx_city_hexes_unsynced ON city_hexes (synced) WHERE synced = 0",
        ]
        for sql in migrations {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - Coordinates

    func insertCoordinate(latitude: Double, longitude: Double, timestamp: Int64) {
        let sql = "INSERT INTO coordinates (latitude, longitude, timestamp) VALUES (?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(statement, 1, latitude)
        sqlite3_bind_double(statement, 2, longitude)
        sqlite3_bind_int64(statement, 3, timestamp)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchAllCoordinates() -> [StoredCoordinate] {
        let sql = "SELECT id, latitude, longitude, timestamp FROM coordinates ORDER BY timestamp ASC"
        var statement: OpaquePointer?
        var results: [StoredCoordinate] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }

        while sqlite3_step(statement) == SQLITE_ROW {
            let coord = StoredCoordinate(
                id: sqlite3_column_int64(statement, 0),
                latitude: sqlite3_column_double(statement, 1),
                longitude: sqlite3_column_double(statement, 2),
                timestamp: sqlite3_column_int64(statement, 3)
            )
            results.append(coord)
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchDistinctCoordinateDays() -> [String] {
        let sql = "SELECT DISTINCT date(timestamp, 'unixepoch', 'localtime') as day FROM coordinates ORDER BY day DESC"
        var statement: OpaquePointer?
        var results: [String] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                results.append(String(cString: cString))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    // MARK: - Hexes

    func insertDiscoveredHex(_ hexId: String) {
        let sql = "INSERT OR IGNORE INTO discovered_hexes (hex_id) VALUES (?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (hexId as NSString).utf8String, -1, nil)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchAllDiscoveredHexes() -> Set<String> {
        let sql = "SELECT hex_id FROM discovered_hexes"
        var statement: OpaquePointer?
        var results: Set<String> = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                results.insert(String(cString: cString))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchDiscoveredHexCount() -> Int {
        let sql = "SELECT COUNT(*) FROM discovered_hexes"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        sqlite3_finalize(statement)
        return count
    }

    // MARK: - States

    func insertVisitedState(stateId: String, name: String, visitedDate: Int64) {
        let sql = "INSERT OR IGNORE INTO visited_states (state_id, name, visited_date) VALUES (?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (stateId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 3, visitedDate)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchVisitedStates() -> [VisitedStateRecord] {
        let sql = "SELECT state_id, name, visited_date FROM visited_states ORDER BY name ASC"
        var statement: OpaquePointer?
        var results: [VisitedStateRecord] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }

        while sqlite3_step(statement) == SQLITE_ROW {
            let stateId = String(cString: sqlite3_column_text(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let date = sqlite3_column_int64(statement, 2)
            results.append(VisitedStateRecord(stateId: stateId, name: name, visitedDate: date))
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchVisitedStatesCount() -> Int {
        let sql = "SELECT COUNT(*) FROM visited_states"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        sqlite3_finalize(statement)
        return count
    }

    // MARK: - Counties

    func insertVisitedCounty(fips: String, name: String, state: String, visitedDate: Int64) {
        let sql = "INSERT OR IGNORE INTO visited_counties (fips, name, state, visited_date) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (fips as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (state as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 4, visitedDate)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchVisitedCounties() -> [VisitedCountyRecord] {
        let sql = "SELECT fips, name, state, visited_date FROM visited_counties ORDER BY visited_date DESC"
        var statement: OpaquePointer?
        var results: [VisitedCountyRecord] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(VisitedCountyRecord(
                fips: String(cString: sqlite3_column_text(statement, 0)),
                name: String(cString: sqlite3_column_text(statement, 1)),
                state: String(cString: sqlite3_column_text(statement, 2)),
                visitedDate: sqlite3_column_int64(statement, 3)
            ))
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchVisitedCities() -> [VisitedCityRecord] {
        let sql = "SELECT city_id, name, state, county, visited_date FROM visited_cities ORDER BY visited_date DESC"
        var statement: OpaquePointer?
        var results: [VisitedCityRecord] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(VisitedCityRecord(
                cityId: String(cString: sqlite3_column_text(statement, 0)),
                name: String(cString: sqlite3_column_text(statement, 1)),
                state: String(cString: sqlite3_column_text(statement, 2)),
                county: sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "",
                visitedDate: sqlite3_column_int64(statement, 4)
            ))
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchCountiesForState(state: String) -> [VisitedCountyRecord] {
        let sql = "SELECT fips, name, state, visited_date FROM visited_counties WHERE state = ? ORDER BY name ASC"
        var statement: OpaquePointer?
        var results: [VisitedCountyRecord] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        sqlite3_bind_text(statement, 1, (state as NSString).utf8String, -1, nil)

        while sqlite3_step(statement) == SQLITE_ROW {
            let fips = String(cString: sqlite3_column_text(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let st = String(cString: sqlite3_column_text(statement, 2))
            let date = sqlite3_column_int64(statement, 3)
            results.append(VisitedCountyRecord(fips: fips, name: name, state: st, visitedDate: date))
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchVisitedCountiesCount() -> Int {
        let sql = "SELECT COUNT(*) FROM visited_counties"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        sqlite3_finalize(statement)
        return count
    }

    // MARK: - Cities

    func insertVisitedCity(cityId: String, name: String, state: String, county: String, visitedDate: Int64) {
        let sql = "INSERT OR IGNORE INTO visited_cities (city_id, name, state, county, visited_date) VALUES (?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (cityId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (state as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (county as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 5, visitedDate)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchCitiesForState(state: String) -> [VisitedCityRecord] {
        let sql = "SELECT city_id, name, state, county, visited_date FROM visited_cities WHERE state = ? ORDER BY name ASC"
        var statement: OpaquePointer?
        var results: [VisitedCityRecord] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        sqlite3_bind_text(statement, 1, (state as NSString).utf8String, -1, nil)

        while sqlite3_step(statement) == SQLITE_ROW {
            let cityId = String(cString: sqlite3_column_text(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let st = String(cString: sqlite3_column_text(statement, 2))
            let county = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let date = sqlite3_column_int64(statement, 4)
            results.append(VisitedCityRecord(cityId: cityId, name: name, state: st, county: county, visitedDate: date))
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchCitiesForCounty(county: String, state: String) -> [VisitedCityRecord] {
        let sql = "SELECT city_id, name, state, county, visited_date FROM visited_cities WHERE county = ? AND state = ? ORDER BY name ASC"
        var statement: OpaquePointer?
        var results: [VisitedCityRecord] = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        sqlite3_bind_text(statement, 1, (county as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (state as NSString).utf8String, -1, nil)

        while sqlite3_step(statement) == SQLITE_ROW {
            let cityId = String(cString: sqlite3_column_text(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            let st = String(cString: sqlite3_column_text(statement, 2))
            let cnty = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let date = sqlite3_column_int64(statement, 4)
            results.append(VisitedCityRecord(cityId: cityId, name: name, state: st, county: cnty, visitedDate: date))
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchVisitedCitiesCount() -> Int {
        let sql = "SELECT COUNT(*) FROM visited_cities"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        sqlite3_finalize(statement)
        return count
    }

    // MARK: - Overlay Points (camera contributions)

    func insertOverlayPoint(id: String, family: String, subkind: String, latitude: Double, longitude: Double, title: String, note: String, confidence: Double, confirmations: Int, createdAt: Int64) {
        let sql = """
            INSERT OR REPLACE INTO overlay_points
            (id, family, subkind, latitude, longitude, title, note, confidence, confirmations, created_at, verified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (family as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (subkind as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 4, latitude)
        sqlite3_bind_double(statement, 5, longitude)
        sqlite3_bind_text(statement, 6, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 7, (note as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 8, confidence)
        sqlite3_bind_int(statement, 9, Int32(confirmations))
        sqlite3_bind_int64(statement, 10, createdAt)
        sqlite3_bind_int64(statement, 11, createdAt)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchOverlayPoints(kind family: String) -> [StoredOverlayPoint] {
        let sql = "SELECT id, subkind, latitude, longitude, title, note, confidence, confirmations, created_at FROM overlay_points WHERE family = ? ORDER BY created_at DESC"
        var statement: OpaquePointer?
        var results: [StoredOverlayPoint] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        sqlite3_bind_text(statement, 1, (family as NSString).utf8String, -1, nil)

        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(StoredOverlayPoint(
                id: String(cString: sqlite3_column_text(statement, 0)),
                subkind: String(cString: sqlite3_column_text(statement, 1)),
                latitude: sqlite3_column_double(statement, 2),
                longitude: sqlite3_column_double(statement, 3),
                title: String(cString: sqlite3_column_text(statement, 4)),
                note: sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "",
                confidence: sqlite3_column_double(statement, 6),
                confirmations: Int(sqlite3_column_int(statement, 7)),
                createdAt: sqlite3_column_int64(statement, 8)
            ))
        }
        sqlite3_finalize(statement)
        return results
    }

    func updateOverlayPointVerification(id: String, confidence: Double, confirmations: Int, verifiedAt: Int64) {
        let sql = "UPDATE overlay_points SET confidence = ?, confirmations = ?, verified_at = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(statement, 1, confidence)
        sqlite3_bind_int(statement, 2, Int32(confirmations))
        sqlite3_bind_int64(statement, 3, verifiedAt)
        sqlite3_bind_text(statement, 4, (id as NSString).utf8String, -1, nil)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    // MARK: - Hazard Reports

    func insertHazardReport(id: String, kind: String, latitude: Double, longitude: Double, createdAt: Int64, expiresAt: Int64, confirmations: Int) {
        let sql = "INSERT OR REPLACE INTO hazard_reports (id, kind, latitude, longitude, created_at, expires_at, confirmations, synced) VALUES (?, ?, ?, ?, ?, ?, ?, 0)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (kind as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 3, latitude)
        sqlite3_bind_double(statement, 4, longitude)
        sqlite3_bind_int64(statement, 5, createdAt)
        sqlite3_bind_int64(statement, 6, expiresAt)
        sqlite3_bind_int(statement, 7, Int32(confirmations))
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchActiveHazardReports(now: Int64) -> [StoredHazardReport] {
        let sql = "SELECT id, kind, latitude, longitude, created_at, expires_at, confirmations FROM hazard_reports WHERE expires_at > ? ORDER BY created_at DESC"
        var statement: OpaquePointer?
        var results: [StoredHazardReport] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        sqlite3_bind_int64(statement, 1, now)

        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(StoredHazardReport(
                id: String(cString: sqlite3_column_text(statement, 0)),
                kind: String(cString: sqlite3_column_text(statement, 1)),
                latitude: sqlite3_column_double(statement, 2),
                longitude: sqlite3_column_double(statement, 3),
                createdAt: sqlite3_column_int64(statement, 4),
                expiresAt: sqlite3_column_int64(statement, 5),
                confirmations: Int(sqlite3_column_int(statement, 6))
            ))
        }
        sqlite3_finalize(statement)
        return results
    }

    func updateHazardReport(id: String, expiresAt: Int64, confirmations: Int) {
        let sql = "UPDATE hazard_reports SET expires_at = ?, confirmations = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(statement, 1, expiresAt)
        sqlite3_bind_int(statement, 2, Int32(confirmations))
        sqlite3_bind_text(statement, 3, (id as NSString).utf8String, -1, nil)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    /// Deletes expired rows; returns true when the statement ran.
    func deleteExpiredHazardReports(now: Int64) -> Bool {
        let sql = "DELETE FROM hazard_reports WHERE expires_at <= ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_int64(statement, 1, now)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
        return true
    }

    // MARK: - Hex Visits (dwell weighting)

    func recordHexVisit(hexId: String, at timestamp: Int64) {
        let sql = """
            INSERT INTO hex_visits (hex_id, visits, last_visit) VALUES (?, 1, ?)
            ON CONFLICT(hex_id) DO UPDATE SET visits = visits + 1, last_visit = ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (hexId as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, timestamp)
        sqlite3_bind_int64(statement, 3, timestamp)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    // MARK: - State / County / City Hex Attribution

    func insertStateHex(stateId: String, hexId: String) {
        let sql = "INSERT OR IGNORE INTO state_hexes (state_id, hex_id) VALUES (?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (stateId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (hexId as NSString).utf8String, -1, nil)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func insertCountyHex(fips: String, hexId: String) {
        let sql = "INSERT OR IGNORE INTO county_hexes (fips, hex_id) VALUES (?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (fips as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (hexId as NSString).utf8String, -1, nil)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func insertCityHex(cityId: String, hexId: String) {
        let sql = "INSERT OR IGNORE INTO city_hexes (city_id, hex_id) VALUES (?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (cityId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (hexId as NSString).utf8String, -1, nil)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchStateHexCounts() -> [String: Int] {
        let sql = "SELECT state_id, COUNT(*) FROM state_hexes GROUP BY state_id"
        return groupedCounts(sql: sql)
    }

    func fetchCountyHexCounts() -> [String: Int] {
        let sql = "SELECT fips, COUNT(*) FROM county_hexes GROUP BY fips"
        return groupedCounts(sql: sql)
    }

    func fetchCityHexCounts() -> [String: Int] {
        let sql = "SELECT city_id, COUNT(*) FROM city_hexes GROUP BY city_id"
        return groupedCounts(sql: sql)
    }

    private func groupedCounts(sql: String) -> [String: Int] {
        var statement: OpaquePointer?
        var results: [String: Int] = [:]
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let key = sqlite3_column_text(statement, 0) {
                results[String(cString: key)] = Int(sqlite3_column_int(statement, 1))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchCountyCountsByState() -> [String: Int] {
        let sql = "SELECT state, COUNT(*) FROM visited_counties GROUP BY state"
        return groupedCounts(sql: sql)
    }

    func fetchCityCountsByState() -> [String: Int] {
        let sql = "SELECT state, COUNT(*) FROM visited_cities GROUP BY state"
        return groupedCounts(sql: sql)
    }

    // MARK: - State Stats (last visit + geodesic distance inside polygon)

    func updateStateVisit(stateId: String, at timestamp: Int64, addDistance meters: Double) {
        let sql = """
            INSERT INTO state_stats (state_id, last_visit, distance_m) VALUES (?, ?, ?)
            ON CONFLICT(state_id) DO UPDATE SET last_visit = ?, distance_m = distance_m + ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (stateId as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, timestamp)
        sqlite3_bind_double(statement, 3, meters)
        sqlite3_bind_int64(statement, 4, timestamp)
        sqlite3_bind_double(statement, 5, meters)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchStateStats() -> [String: StateStatRecord] {
        let sql = "SELECT state_id, last_visit, distance_m FROM state_stats"
        var statement: OpaquePointer?
        var results: [String: StateStatRecord] = [:]
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        while sqlite3_step(statement) == SQLITE_ROW {
            let stateId = String(cString: sqlite3_column_text(statement, 0))
            results[stateId] = StateStatRecord(
                stateId: stateId,
                lastVisit: sqlite3_column_int64(statement, 1),
                distanceMeters: sqlite3_column_double(statement, 2)
            )
        }
        sqlite3_finalize(statement)
        return results
    }

    // MARK: - Boundary Cell Counts

    func upsertBoundaryCellCount(stateId: String, totalCells: Int, boundaryVersion: String) {
        let sql = """
            INSERT OR REPLACE INTO boundary_cell_counts (state_id, total_cells, boundary_version, computed_at)
            VALUES (?, ?, ?, ?)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (stateId as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(totalCells))
        sqlite3_bind_text(statement, 3, (boundaryVersion as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 4, Int64(Date().timeIntervalSince1970))
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchBoundaryCellCount(stateId: String) -> Int? {
        let sql = "SELECT total_cells FROM boundary_cell_counts WHERE state_id = ? AND boundary_version = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(statement, 1, (stateId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (BoundaryService.boundaryVersion as NSString).utf8String, -1, nil)
        var result: Int?
        if sqlite3_step(statement) == SQLITE_ROW {
            result = Int(sqlite3_column_int(statement, 0))
        }
        sqlite3_finalize(statement)
        return result
    }

    // MARK: - Milestones

    func insertTriggeredMilestone(_ milestoneId: String) {
        let sql = "INSERT OR IGNORE INTO triggered_milestones (milestone_id, triggered_date) VALUES (?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (milestoneId as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, Int64(Date().timeIntervalSince1970))
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func fetchTriggeredMilestones() -> Set<String> {
        let sql = "SELECT milestone_id FROM triggered_milestones"
        var statement: OpaquePointer?
        var results: Set<String> = []

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let cString = sqlite3_column_text(statement, 0) {
                results.insert(String(cString: cString))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    // MARK: - Cell-Claim Sync (phase 4)

    /// Unsynced claim rows from an attribution table (state_hexes / county_hexes
    /// / city_hexes), oldest first, capped per pass.
    func fetchUnsyncedClaims(table: String, idColumn: String, limit: Int = 400) -> [(rowId: Int64, hexId: String, entityId: String)] {
        let sql = "SELECT rowid, hex_id, \(idColumn) FROM \(table) WHERE synced = 0 ORDER BY rowid LIMIT ?"
        var statement: OpaquePointer?
        var results: [(Int64, String, String)] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        sqlite3_bind_int(statement, 1, Int32(limit))
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(statement, 0)
            let hexId = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let entityId = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            results.append((rowId, hexId, entityId))
        }
        sqlite3_finalize(statement)
        return results
    }

    func markClaimsSynced(table: String, rowIds: [Int64]) {
        guard !rowIds.isEmpty else { return }
        let placeholders = rowIds.map { _ in "?" }.joined(separator: ",")
        let sql = "UPDATE \(table) SET synced = 1 WHERE rowid IN (\(placeholders))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        for (index, rowId) in rowIds.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), rowId)
        }
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    /// Merges a remote claim (another device, same explorer id) into the local
    /// store. Union semantics: rows are additive; visits keep the max.
    /// Returns true when local state changed.
    func mergeRemoteClaim(level: Int16, entityId: String, hexId: String, visits: Int, lastSeen: Int64) -> Bool {
        var changed = false

        // The underlying discovery is the same physical cell regardless of level.
        changed = insertDiscoveredHexIfNew(hexId) || changed

        let table: String
        let idColumn: String
        switch level {
        case 2: table = "state_hexes"; idColumn = "state_id"
        case 3: table = "county_hexes"; idColumn = "fips"
        default: table = "city_hexes"; idColumn = "city_id"
        }
        changed = insertAttributionIfNew(table: table, idColumn: idColumn, entityId: entityId, hexId: hexId) || changed

        mergeRemoteVisit(hexId: hexId, visits: visits, lastSeen: lastSeen)
        return changed
    }

    private func insertDiscoveredHexIfNew(_ hexId: String) -> Bool {
        let sql = "INSERT OR IGNORE INTO discovered_hexes (hex_id) VALUES (?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (hexId as NSString).utf8String, -1, nil)
        let inserted = sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(db) > 0
        sqlite3_finalize(statement)
        return inserted
    }

    private func insertAttributionIfNew(table: String, idColumn: String, entityId: String, hexId: String) -> Bool {
        let sql = "INSERT OR IGNORE INTO \(table) (\(idColumn), hex_id, synced) VALUES (?, ?, 1)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, (entityId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (hexId as NSString).utf8String, -1, nil)
        _ = sqlite3_step(statement)
        let inserted = sqlite3_changes(db) > 0
        sqlite3_finalize(statement)
        return inserted
    }

    private func mergeRemoteVisit(hexId: String, visits: Int, lastSeen: Int64) {
        // Keep the greater of local/remote dwell counters (union merge).
        let sql = """
            INSERT INTO hex_visits (hex_id, visits, last_visit) VALUES (?, ?, ?)
            ON CONFLICT(hex_id) DO UPDATE SET
                visits = MAX(visits, excluded.visits),
                last_visit = MAX(last_visit, excluded.last_visit)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(statement, 1, (hexId as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(visits))
        sqlite3_bind_int64(statement, 3, lastSeen)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    // MARK: - Privacy (phase 4)

    /// Deletes raw breadcrumbs and visit rows whose timestamp falls inside
    /// [from, to]. Unique-cell discoveries and aggregate attribution are
    /// identity-level and are erased via full erasure instead.
    func deleteRange(from: Int64, to: Int64) {
        let statements = [
            "DELETE FROM coordinates WHERE timestamp BETWEEN ? AND ?",
            "DELETE FROM hex_visits WHERE last_visit BETWEEN ? AND ?",
            "DELETE FROM state_stats WHERE last_visit BETWEEN ? AND ?",
        ]
        for sql in statements {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            sqlite3_bind_int64(statement, 1, from)
            sqlite3_bind_int64(statement, 2, to)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func fetchAllHexVisits() -> [(hexId: String, visits: Int, lastVisit: Int64)] {
        let sql = "SELECT hex_id, visits, last_visit FROM hex_visits"
        var statement: OpaquePointer?
        var results: [(String, Int, Int64)] = []
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return results }
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append((
                sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "",
                Int(sqlite3_column_int(statement, 1)),
                sqlite3_column_int64(statement, 2)
            ))
        }
        sqlite3_finalize(statement)
        return results
    }

    /// Full local erasure: breadcrumbs, visits, attribution, discoveries,
    /// aggregates and milestones. Server-side rows are deleted separately
    /// (see PrivacyService.eraseEverything).
    func wipeDiscoveryData() {
        let tables = [
            "coordinates", "hex_visits", "state_hexes", "county_hexes",
            "city_hexes", "discovered_hexes", "state_stats",
            "visited_states", "visited_counties", "visited_cities",
            "triggered_milestones",
        ]
        for table in tables {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM \(table)", -1, &statement, nil) == SQLITE_OK else { continue }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }
}
