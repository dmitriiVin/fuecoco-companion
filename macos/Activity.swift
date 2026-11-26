import Foundation
import SQLite3

struct Activity {
    var working = false
    var failedAt: Double = 0
    var finishedAt: Double = 0
}

struct CodexActivity {
    let directory: URL
    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.directory = directory
    }
    private func historyFile() -> URL? {
        let candidates = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return candidates.compactMap { url -> (Int, URL)? in
            let name = url.deletingPathExtension().lastPathComponent
            let prefix = "thread_history_"
            guard url.pathExtension == "sqlite", name.hasPrefix(prefix),
                  let version = Int(name.dropFirst(prefix.count)) else { return nil }
            return (version, url)
        }.max { $0.0 < $1.0 }?.1
    }
    func sample(at now: Double) -> Activity? {
        guard let file = historyFile() else { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 100)
        // Use only status and timing fields. A stale unfinished turn can survive a previous Codex crash.
        let sql = """
        WITH live AS (
          SELECT thread_id, turn_id FROM thread_turns t WHERE status='inProgress'
            AND (started_at >= ?1 - 900 OR EXISTS (
              SELECT 1 FROM thread_items i WHERE i.thread_id=t.thread_id AND i.turn_id=t.turn_id
                AND MAX(i.created_at_ms,COALESCE(i.completed_at_ms,0)) >= (?1-900)*1000
            ))
        ), recent AS (
          SELECT * FROM live UNION
          SELECT thread_id, turn_id FROM thread_turns WHERE completed_at >= ?1 - 20
        )
        SELECT EXISTS(SELECT 1 FROM live),
          MAX(COALESCE((SELECT MAX(completed_at) FROM thread_turns WHERE status='failed' AND completed_at >= ?1-20),0),
              COALESCE((SELECT MAX(i.completed_at_ms)/1000.0 FROM recent r JOIN thread_items i
                ON i.thread_id=r.thread_id AND i.turn_id=r.turn_id WHERE i.completed_at_ms >= (?1-20)*1000
                AND i.item_type IN ('commandExecution','mcpToolCall','fileChange','imageGeneration')
                AND (json_extract(i.item_json,'$.status')='failed' OR
                    (i.item_type='commandExecution' AND COALESCE(json_extract(i.item_json,'$.exitCode'),0)<>0))),0)),
          COALESCE((SELECT MAX(completed_at) FROM thread_turns WHERE status='completed' AND completed_at >= ?1-20),0)
        """
        var query: OpaquePointer?
        defer { sqlite3_finalize(query) }
        guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_double(query, 1, now)
        guard sqlite3_step(query) == SQLITE_ROW else { return nil }
        return Activity(working: sqlite3_column_int(query,0) != 0, failedAt: sqlite3_column_double(query,1), finishedAt: sqlite3_column_double(query,2))
    }
}
