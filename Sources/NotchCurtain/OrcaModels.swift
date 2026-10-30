import Foundation

struct OrcaDispatchInfo: Equatable, Sendable {
    let dispatchID: String
    let taskID: String
    let status: String
    let summary: String?
    let reason: String?
}

struct OrcaTerminal: Identifiable, Equatable, Sendable {
    enum Agent: String, CaseIterable, Sendable {
        case claude, codex, antigravity, hermes, unknown
        var label: String {
            switch self {
            case .claude: "Claude Code"
            case .codex: "Codex"
            case .antigravity: "Antigravity"
            case .hermes: "Hermes"
            case .unknown: AppText.value("Terminal")
            }
        }
    }

    enum State: String, Sendable {
        case working, waiting, ready, error
        var label: String {
            switch self {
            case .working: AppText.value("Working")
            case .waiting: AppText.value("Waiting")
            case .ready: AppText.value("Ready")
            case .error: AppText.value("Error")
            }
        }
    }

    let id: String
    let title: String
    let workspacePath: String
    let branch: String?
    let agent: Agent
    let providerIdentity: String?
    let model: String?
    let state: State
    let preview: String
    let lastOutputAt: Date?
    let dispatch: OrcaDispatchInfo?
    let errorReason: String?

    var workspaceName: String { URL(fileURLWithPath: workspacePath).lastPathComponent }
    var displayTitle: String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleaned.lowercased()
        let parts = normalized.split(whereSeparator: \.isWhitespace)
        let generic = normalized.isEmpty || normalized == "terminal" || normalized.hasPrefix("terminal ") ||
            (parts.count <= 3 && parts.contains("terminal"))
        guard generic else { return cleaned }
        let branchName = branch?.split(separator: "/").last.map(String.init)
        return branchName ?? workspaceName
    }

    var previewLines: [String] { OrcaSnapshotParser.cleanedPreview(preview) }
    var displayAgentLabel: String {
        guard agent == .unknown, let providerIdentity, !providerIdentity.isEmpty else { return agent.label }
        if providerIdentity.localizedCaseInsensitiveContains("cursor") { return "Cursor Agent" }
        let parts = providerIdentity.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-" )).inverted)
        return parts.last(where: { !$0.isEmpty })?.capitalized ?? agent.label
    }
}

struct OrcaWorkspace: Identifiable, Sendable {
    let path: String
    let terminals: [OrcaTerminal]
    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

enum OrcaSnapshotParser {
    private struct WorkerRecord {
        let runID: String?
        let taskID: String?
        let dispatchID: String?
        let dispatchStatus: String?
        let workerState: String?
        let activity: String?
        let liveness: String?
        let evidence: String?
        let agentID: String?
        let model: String?
        let failureReason: String?
    }

    static func parse(_ data: Data, workerData: Data? = nil, taskData: [Data] = [], failureData: [Data] = []) throws -> [OrcaTerminal] {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let object = root as? [String: Any] else { throw ParseError.invalidRoot }
        let payload = (object["result"] as? [String: Any]) ?? object
        guard let rows = payload["terminals"] as? [[String: Any]] else { throw ParseError.missingTerminals }
        let workers = parseWorkers(workerData, failureData: failureData)
        let tasks = parseTasks(taskData)

        return rows.compactMap { row in
            guard let handle = row["handle"] as? String,
                  let path = (row["worktreePath"] as? String) ?? (row["cwd"] as? String) else { return nil }
            let worker = workers[handle]
            let title = row["tabTitle"] as? String ?? row["title"] as? String ?? ""
            let branch = row["branch"] as? String
            let preview = row["preview"] as? String ?? ""
            let providerID = (row["agentIdentity"] as? String) ?? worker?.agentID ?? ""
            let agentText = providerID + " " + title + " " + preview
            let agent = OrcaTerminal.Agent.allCases.first {
                $0 != .unknown && agentText.localizedCaseInsensitiveContains($0.rawValue)
            } ?? inferAgent(agentText)
            let model = normalizedModel((row["model"] as? String) ?? worker?.model) ?? inferModel(title + "\n" + preview)
            let dispatch = makeDispatch(worker: worker, tasks: tasks)
            let timestamp = (row["lastOutputAt"] as? NSNumber)?.doubleValue
            let lastOutputAt = timestamp.map { Date(timeIntervalSince1970: $0 / 1_000) }
            let age = lastOutputAt.map { Date().timeIntervalSince($0) }
            let recent = age.map { $0 < 30 * 60 && $0 >= -60 } ?? false
            return OrcaTerminal(
                id: handle,
                title: title,
                workspacePath: path,
                branch: branch,
                agent: agent,
                providerIdentity: providerID.isEmpty ? nil : providerID,
                model: model,
                state: inferState(row: row, preview: preview, worker: worker, recent: recent),
                preview: preview,
                lastOutputAt: lastOutputAt,
                dispatch: dispatch,
                errorReason: recent ? (worker?.failureReason ?? detectedErrorReason(row: row, preview: preview)) : nil
            )
        }
    }

    static func workerRunIDs(_ data: Data?) -> [String] {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = (root["result"] as? [String: Any]) ?? Optional(root),
              let rows = payload["workers"] as? [[String: Any]] else { return [] }
        var runIDs: [String] = []
        var seenTerminals = Set<String>()
        for row in rows {
            guard let handle = row["agentTerminalHandle"] as? String,
                  seenTerminals.insert(handle).inserted,
                  let runID = row["runId"] as? String,
                  !runIDs.contains(runID) else { continue }
            runIDs.append(runID)
            if runIDs.count == 8 { break }
        }
        return runIDs
    }

    static func failedDispatchIDs(_ data: Data?) -> [String] {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = (root["result"] as? [String: Any]) ?? Optional(root),
              let rows = payload["workers"] as? [[String: Any]] else { return [] }
        return Array(rows.compactMap { row -> String? in
            guard row["dispatchStatus"] as? String == "failed" || row["workerState"] as? String == "failed",
                  let id = row["dispatchId"] as? String else { return nil }
            return id
        }.prefix(5))
    }

    static func cleanedPreview(_ preview: String) -> [String] {
        let withoutANSI = preview.replacingOccurrences(
            of: "\\u001B(?:\\[[0-?]*[ -/]*[@-~]|\\][^\\u0007]*(?:\\u0007|\\u001B\\\\))",
            with: "",
            options: .regularExpression
        )
        let drawing = CharacterSet(charactersIn: "─━┄┈┅┆╍╎┌┐└┘├┤┬┴┼│┃╭╮╰╯╱╲╳═║╔╗╚╝╠╣╦╩╬")
        let cleaned = withoutANSI.components(separatedBy: .newlines).compactMap { line -> String? in
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.replacingOccurrences(of: #"(?i)(/restart\s+to\s+apply)[A-Z]+$"#, with: "$1", options: .regularExpression)
            let lower = value.lowercased()
            let statusFragments = ["esc to interrupt", "worked for", "uncached", "/clear to start fresh", "yolo", "/1m", "k/1m", "ctx"]
            if statusFragments.contains(where: lower.contains) || lower == "ok)" { return nil }
            let tokens = value.split(whereSeparator: \.isWhitespace)
            if value.count <= 2 || tokens.allSatisfy({ $0.count <= 1 }) || lower == "k)" { return nil }
            let blockGlyphs = CharacterSet(charactersIn: "█▓▒░▰▱■□▪▫")
            if value.unicodeScalars.contains(where: { blockGlyphs.contains($0) }) { return nil }
            let workFragments = lower.components(separatedBy: "work").count - 1
            if workFragments >= 4 { return nil }
            let stutterPattern = #"([a-z0-9]{2,10})(?:\1){2,}"#
            if let range = lower.range(of: stutterPattern, options: .regularExpression) {
                var prefix = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let lastSpace = prefix.lastIndex(where: \.isWhitespace) {
                    prefix = String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard prefix.count >= 12 else { return nil }
                return String(prefix.suffix(180))
            }
            let visibleScalars = value.unicodeScalars.filter {
                !drawing.contains($0) && !(0x2800...0x28FF).contains($0.value) && !CharacterSet.controlCharacters.contains($0)
            }
            let visible = String(String.UnicodeScalarView(visibleScalars))
                .replacingOccurrences(of: "[•✻✽✦◦◉⠋⠙]", with: "", options: .regularExpression)
            let boxCount = value.unicodeScalars.filter { drawing.contains($0) }.count
            if boxCount > 0 && Double(boxCount) / Double(max(1, value.unicodeScalars.count)) > 0.35 { return nil }
            guard !visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let condensed = visible.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return String(condensed.suffix(180))
        }
        var unique: [String] = []
        for line in cleaned where unique.last != line { unique.append(line) }
        return Array(unique.suffix(1))
    }

    private static func parseWorkers(_ data: Data?, failureData: [Data]) -> [String: WorkerRecord] {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = (root["result"] as? [String: Any]) ?? Optional(root),
              let rows = payload["workers"] as? [[String: Any]] else { return [:] }
        var reasons: [String: String] = [:]
        for detail in failureData {
            guard let root = try? JSONSerialization.jsonObject(with: detail) as? [String: Any],
                  let payload = root["result"] as? [String: Any],
                  let worker = payload["worker"] as? [String: Any],
                  let dispatchID = (payload["dispatch"] as? [String: Any])?["id"] as? String else { continue }
            let dispatch = payload["dispatch"] as? [String: Any] ?? [:]
            let reason = worker["lastError"] as? String ?? dispatch["lastFailure"] as? String
            if let reason, !reason.isEmpty { reasons[dispatchID] = reason }
        }
        var byHandle: [String: WorkerRecord] = [:]
        for row in rows {
            guard let handle = row["agentTerminalHandle"] as? String, byHandle[handle] == nil else { continue }
            let projection = row["projection"] as? [String: Any] ?? [:]
            let stage = projection["stage"] as? [String: Any] ?? [:]
            let liveness = projection["liveness"] as? [String: Any] ?? [:]
            let evidence = projection["evidence"] as? [String: Any] ?? [:]
            let provider = projection["provider"] as? [String: Any] ?? [:]
            byHandle[handle] = WorkerRecord(
                runID: row["runId"] as? String,
                taskID: row["taskId"] as? String,
                dispatchID: row["dispatchId"] as? String,
                dispatchStatus: row["dispatchStatus"] as? String,
                workerState: row["workerState"] as? String,
                activity: stage["activity"] as? String,
                liveness: liveness["verdict"] as? String,
                evidence: evidence["liveStatus"] as? String,
                agentID: provider["id"] as? String,
                model: provider["model"] as? String,
                failureReason: reasons[row["dispatchId"] as? String ?? ""] ?? ((row["dispatchStatus"] as? String) == "failed"
                    ? "Dispatch finished with failed status" : nil)
            )
        }
        return byHandle
    }

    private static func parseTasks(_ sources: [Data]) -> [String: (String, String)] {
        var tasks: [String: (String, String)] = [:]
        for data in sources {
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = (root["result"] as? [String: Any]) ?? Optional(root),
                  let rows = payload["tasks"] as? [[String: Any]] else { continue }
            for row in rows {
                guard let id = row["id"] as? String else { continue }
                let spec = (row["spec"] as? String ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                tasks[id] = (String(spec.prefix(150)), row["status"] as? String ?? "")
            }
        }
        return tasks
    }

    private static func makeDispatch(worker: WorkerRecord?, tasks: [String: (String, String)]) -> OrcaDispatchInfo? {
        guard let worker, let dispatchID = worker.dispatchID, let taskID = worker.taskID else { return nil }
        let task = tasks[taskID]
        return OrcaDispatchInfo(dispatchID: dispatchID, taskID: taskID,
            status: worker.dispatchStatus ?? task?.1 ?? "unknown", summary: task?.0, reason: worker.failureReason)
    }

    private static func inferState(row: [String: Any], preview: String, worker: WorkerRecord?, recent: Bool) -> OrcaTerminal.State {
        let explicit = ["status", "agentStatus", "state"].compactMap { row[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if recent && explicit.contains(where: { ["error", "failed", "failure", "escalated", "escalation"].contains($0) }) { return .error }
        if explicit.contains(where: { ["working", "running", "active"].contains($0) }) { return .working }
        if explicit.contains(where: { ["ready", "completed", "done"].contains($0) }) { return .ready }
        if explicit.contains(where: { ["waiting", "idle"].contains($0) }) { return .waiting }

        let activePreview = isCurrentProgress(title: row["title"] as? String ?? "", preview: preview)
        if activePreview { return .working }
        if let worker {
            let live = worker.liveness == "live" && worker.evidence == "fresh"
            if live, worker.activity == "working" { return .working }
            if live, worker.activity == "waiting" { return .waiting }
            if recent && (worker.workerState == "failed" || worker.dispatchStatus == "failed") { return .error }
            if worker.workerState == "succeeded" || worker.dispatchStatus == "completed" { return .ready }
        }

        let lines = preview.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if recent && lines.contains(where: isExplicitErrorLine) { return .error }
        if lines.contains(where: { $0.contains("ready") || $0.contains("worked for") || $0.contains("new task?") || $0.hasPrefix("› ask ") || containsRussianReadyMarker($0) }) { return .ready }
        return .waiting
    }

    private static func containsRussianReadyMarker(_ line: String) -> Bool {
        let markers: [[UInt32]] = [
            [0x0440, 0x0430, 0x0431, 0x043E, 0x0442, 0x0430, 0x0020, 0x0437, 0x0430, 0x0432, 0x0435, 0x0440, 0x0448, 0x0435, 0x043D, 0x0430],
            [0x0433, 0x043E, 0x0442, 0x043E, 0x0432, 0x043E]
        ]
        return markers.contains { points in
            let scalars = points.compactMap(Unicode.Scalar.init)
            return line.contains(String(String.UnicodeScalarView(scalars)))
        }
    }

    private static func inferAgent(_ text: String) -> OrcaTerminal.Agent {
        let value = text.lowercased()
        if value.contains("brewed for") || value.contains("claude code") { return .claude }
        if value.contains("worked for") || value.contains("openai codex") || value.contains("gpt-") { return .codex }
        if value.contains("antigravity") || value.contains("gemini") { return .antigravity }
        if value.contains("hermes") { return .hermes }
        return .unknown
    }

    private static func inferModel(_ preview: String) -> String? {
        let pattern = #"(?i)\b(gpt-[a-z0-9.-]+|(?:sonnet|opus|haiku)(?:\s+\d+(?:\.\d+)*)?)\b"#
        guard let range = preview.range(of: pattern, options: .regularExpression) else { return nil }
        return String(preview[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedModel(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let unknown = ["unknown", "model unknown", "\u{043C}\u{043E}\u{0434}\u{0435}\u{043B}\u{044C} \u{043D}\u{0435}\u{0438}\u{0437}\u{0432}\u{0435}\u{0441}\u{0442}\u{043D}\u{0430}", "\u{043D}\u{0435}\u{0438}\u{0437}\u{0432}\u{0435}\u{0441}\u{0442}\u{043D}\u{043E}"]
        return cleaned.isEmpty || unknown.contains(cleaned.lowercased()) ? nil : cleaned
    }

    private static func isCurrentProgress(title: String, preview: String) -> Bool {
        if title.first.map(String.init).map({ "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏".contains($0) }) == true { return true }
        return preview.components(separatedBy: .newlines).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return (line.contains("working (") && line.contains("esc to interrupt")) ||
                line.hasPrefix("(⊙_⊙)") || line.hasPrefix("· thinking") || line.hasPrefix("· musing") || line.hasPrefix("· formulating")
        }
    }

    private static func isExplicitErrorLine(_ line: String) -> Bool {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["error:", "failed:", "failure:", "escalation:"].contains(where: { line.hasPrefix($0) }) ||
            line.hasPrefix("⚠ escalation") || line.hasPrefix("✖ ")
    }

    private static func detectedErrorReason(row: [String: Any], preview: String) -> String? {
        for key in ["status", "agentStatus", "state"] {
            guard let value = row[key] as? String else { continue }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["error", "failed", "failure", "escalated", "escalation"].contains(normalized) {
                return "Terminal status: \(normalized)"
            }
        }
        return preview.components(separatedBy: .newlines).first(where: { isExplicitErrorLine($0) })
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)) }
    }

    enum ParseError: Error { case invalidRoot, missingTerminals }
}

extension Array where Element == OrcaTerminal {
    var workspaces: [OrcaWorkspace] {
        Dictionary(grouping: self, by: \.workspacePath).map { OrcaWorkspace(path: $0.key, terminals: $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var aggregateState: OrcaTerminal.State? {
        if contains(where: { $0.state == .error }) { return .error }
        if contains(where: { $0.state == .working }) { return .working }
        if contains(where: { $0.state == .ready }) { return .ready }
        return contains(where: { $0.state == .waiting }) ? .waiting : nil
    }
}
