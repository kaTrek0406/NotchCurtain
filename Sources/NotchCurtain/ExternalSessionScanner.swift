import AppKit
import Foundation

struct ExternalSession: Identifiable, Equatable, Sendable {
    enum Agent: String, Sendable, CaseIterable { case claude, codex, gemini, cursorAgent = "cursor-agent", aider, opencode, copilot
        var label: String {
            let key: String
            switch self {
            case .claude: key = "Claude Code"
            case .codex: key = "Codex"
            case .gemini: key = "Gemini"
            case .cursorAgent: key = "Cursor Agent"
            case .aider: key = "Aider"
            case .opencode: key = "OpenCode"
            case .copilot: key = "Copilot CLI"
            }
            return AppText.value(key)
        }
    }
    enum State: Sendable { case working, waiting
        var label: String { AppText.value(self == .working ? "Working" : "Waiting") }
    }

    let pid: Int32
    let agent: Agent
    let cwd: String
    let projectName: String
    let parentPID: Int32?
    let parentName: String
    let cpu: Double
    let lastActivityAt: Date?
    let state: State
    var id: Int32 { pid }
}

enum ExternalProcessParser {
    struct ProcessRow: Equatable {
        let pid: Int32
        let ppid: Int32
        let elapsed: String
        let cpu: Double
        let command: String
        var argv0: String { command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "" }
        var agent: ExternalSession.Agent? {
            let name = URL(fileURLWithPath: argv0).lastPathComponent
            return ExternalSession.Agent(rawValue: name)
        }
    }

    static func parsePS(_ output: String) -> [ProcessRow] {
        output.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let columns = line.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard columns.count == 5, let pid = Int32(columns[0]), let ppid = Int32(columns[1]),
                  let cpu = Double(columns[3]) else { return nil }
            let row = ProcessRow(pid: pid, ppid: ppid, elapsed: String(columns[2]), cpu: cpu, command: String(columns[4]))
            guard row.agent != nil, !isHelper(row.command) else { return nil }
            return row
        }
    }

    static func excludingOrca(_ rows: [ProcessRow], orcaPIDs: Set<Int32>, orcaEnabled: Bool) -> [ProcessRow] {
        orcaEnabled ? rows.filter { !orcaPIDs.contains($0.pid) } : rows
    }

    static func isHelper(_ command: String) -> Bool {
        let value = command.lowercased()
        return ["codex-code-mode-host", "mcp", "claude-agent-view", "chrome-native-host"].contains(where: value.contains)
    }

    static func hasOrcaHandle(_ psEwwOutput: String) -> Bool {
        psEwwOutput.contains("ORCA_TERMINAL_HANDLE=")
    }

    static func parseCWDs(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var currentPID: Int32?
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p"), let pid = Int32(line.dropFirst()) { currentPID = pid }
            else if line.hasPrefix("n"), let pid = currentPID { result[pid] = String(line.dropFirst()) }
        }
        return result
    }
}

actor ExternalSessionScanner {
    private struct CachedCWD { let value: String; let checkedAt: Date }
    private let cwdCache = LockedCWDCache()
    private let knownApps: Set<String> = ["Terminal", "iTerm2", "Code", "Claude", "Warp", "Ghostty", "Cursor"]

    func scan(now: Date = Date(), orcaEnabled: Bool = AppSettings.load().orcaEnabled) -> [ExternalSession] {
        guard let ps = Self.run("/bin/ps", ["-axo", "pid,ppid,etime,%cpu,command"]) else { return [] }
        let candidates = ExternalProcessParser.parsePS(ps)
        cwdCache.removeMissing(keeping: Set(candidates.map(\.pid)))
        guard !candidates.isEmpty else { return [] }
        let envDump = orcaEnabled ? (Self.run("/bin/ps", ["eww", "-p", candidates.map { String($0.pid) }.joined(separator: ",")]) ?? "") : ""
        let orcaPIDs = Set(envDump.split(whereSeparator: \.isNewline).compactMap { line -> Int32? in
            guard ExternalProcessParser.hasOrcaHandle(String(line)) else { return nil }
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.first.flatMap { Int32($0) }
        })
        let external = ExternalProcessParser.excludingOrca(candidates, orcaPIDs: orcaPIDs, orcaEnabled: orcaEnabled)
        guard !external.isEmpty else { return [] }
        let uncached = external.filter { cwdCache.get($0.pid) == nil }
        var cwdByPID: [Int32: String] = [:]
        if !uncached.isEmpty,
           let lsof = Self.run("/usr/sbin/lsof", ["-a", "-p", uncached.map { String($0.pid) }.joined(separator: ","), "-d", "cwd", "-Fn"]) {
            cwdByPID = ExternalProcessParser.parseCWDs(lsof)
            for (pid, cwd) in cwdByPID { cwdCache.set(pid, cwd) }
        }
        let parentRows = Self.parentProcessTable()
        return external.compactMap { row in
            guard let cwd = cwdCache.get(row.pid) ?? cwdByPID[row.pid] else { return nil }
            let parent = parentApplication(for: row, rows: parentRows)
            let project = Self.projectName(at: cwd)
            let logDate = Self.latestSessionMTime(agent: row.agent!, cwd: cwd, now: now)
            let activeLog = logDate.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 20 } ?? false
            return ExternalSession(pid: row.pid, agent: row.agent!, cwd: cwd, projectName: project,
                                   parentPID: parent?.0, parentName: parent?.1 ?? "Terminal",
                                   cpu: row.cpu, lastActivityAt: logDate,
                                   state: row.cpu > 3 || activeLog ? .working : .waiting)
        }.sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
    }

    private func parentApplication(for row: ExternalProcessParser.ProcessRow, rows: [Int32: (String, Int32)]) -> (Int32, String)? {
        var current = row.ppid
        var visited = Set<Int32>()
        while current > 1, visited.insert(current).inserted {
            let processName = rows[current]?.0 ?? ""
            let name = URL(fileURLWithPath: processName).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            if knownApps.contains(name) { return (current, name == "Code" ? "Visual Studio Code" : name) }
            guard let next = rows[current]?.1 else { break }
            current = next
        }
        return nil
    }

    private static func parentProcessTable() -> [Int32: (String, Int32)] {
        guard let output = run("/bin/ps", ["-axo", "pid=,ppid=,comm="]) else { return [:] }
        var result: [Int32: (String, Int32)] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard parts.count == 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            result[pid] = (String(parts[2]), ppid)
        }
        return result
    }

    private static func projectName(at cwd: String) -> String {
        var url = URL(fileURLWithPath: cwd).standardizedFileURL
        let fm = FileManager.default
        var cursor = url
        while cursor.path != "/" {
            if fm.fileExists(atPath: cursor.appendingPathComponent(".git").path) {
                url = cursor
                break
            }
            cursor.deleteLastPathComponent()
        }
        return url.lastPathComponent
    }

    private static func latestSessionMTime(agent: ExternalSession.Agent, cwd: String, now: Date) -> Date? {
        let fm = FileManager.default
        let roots: [URL]
        switch agent {
        case .claude:
            let key = cwd.replacingOccurrences(of: "/", with: "-")
            roots = [fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects/\(key)")]
        case .codex:
            roots = [fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")]
        default:
            roots = []
        }
        var latest: Date?
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      (values.fileSize ?? 0) > 0, let date = values.contentModificationDate, date <= now,
                      latest == nil || date > latest! else { continue }
                latest = date
            }
        }
        return latest
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); return String(data: data, encoding: .utf8) }
        catch { return nil }
    }
}

private final class LockedCWDCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int32: String] = [:]
    func get(_ pid: Int32) -> String? { lock.lock(); defer { lock.unlock() }; return values[pid] }
    func set(_ pid: Int32, _ value: String) { lock.lock(); defer { lock.unlock() }; values[pid] = value }
    func removeMissing(keeping pids: Set<Int32>) { lock.lock(); defer { lock.unlock() }; values = values.filter { pids.contains($0.key) } }
}
