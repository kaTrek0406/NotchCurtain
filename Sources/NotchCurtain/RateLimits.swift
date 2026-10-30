import Foundation
import OSLog

@discardableResult
func assignIfChanged<Value: Equatable>(_ current: inout Value, _ newValue: Value) -> Bool {
    guard current != newValue else { return false }
    current = newValue
    return true
}

struct UsageWindow: Equatable, Sendable {
    let usedPercent: Int
    let resetDescription: String?
    let resetsAt: Date?
}

struct ProviderRateLimits: Equatable, Sendable {
    let session: UsageWindow?
    let weekly: UsageWindow?
    var hasUsage: Bool { session != nil || weekly != nil }
}

struct RateLimitSnapshot: Equatable, Sendable {
    let providers: [String: ProviderRateLimits]
    static let unknown = RateLimitSnapshot(providers: [:])
    var hasAnyLimits: Bool { !providers.isEmpty }

    static func parse(_ data: Data) -> RateLimitSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unknown }
        let envelope = root["result"] as? [String: Any] ?? root
        let limits = envelope["rateLimits"] as? [String: Any] ?? envelope
        var parsed: [String: ProviderRateLimits] = [:]
        for (provider, value) in limits {
            guard let raw = value as? [String: Any] else { continue }
            let providerObject = envelope[provider] as? [String: Any] ?? [:]
            let accountRows = (envelope["accounts"] as? [String: Any])?[provider] as? [[String: Any]] ?? providerObject["accounts"] as? [[String: Any]]
            let systemAuth = (providerObject["systemDefault"] as? [String: Any])?["hasAuth"] as? Bool == true
            let result = ProviderRateLimits(session: parseWindow(raw["session"]), weekly: parseWindow(raw["weekly"]))
            let hasAccount = accountRows.map { !$0.isEmpty } ?? true
            if result.hasUsage && (hasAccount || systemAuth) { parsed[provider] = result }
        }
        return RateLimitSnapshot(providers: parsed)
    }

    private static func parseWindow(_ value: Any?) -> UsageWindow? {
        guard let raw = value as? [String: Any], let percent = raw["usedPercent"] as? NSNumber else { return nil }
        let reset = (raw["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1_000) }
        return UsageWindow(usedPercent: min(100, max(0, percent.intValue)), resetDescription: raw["resetDescription"] as? String, resetsAt: reset)
    }
}

enum PollingLevel: String, Equatable, Sendable { case collapsed, expanded, throttled, sleeping }
struct PollingState: Equatable, Sendable {
    var expanded = false
    var playing = false
    var screenAwake = true
    var locked = false
    var lowPower = false
    var batteryPercent: Int? = nil
    var orcaAvailable = true
    var economyMode = false
}
func pollInterval(state: PollingState) -> TimeInterval {
    if !state.screenAwake || state.locked || state.lowPower || (state.batteryPercent.map { $0 < 20 } ?? false) { return 120 }
    if !state.orcaAvailable { return 60 }
    if state.economyMode { return state.expanded ? 15 : 60 }
    if state.expanded { return 3 }
    return 15
}
func pollingLevel(state: PollingState) -> PollingLevel {
    if !state.screenAwake || state.locked || state.lowPower || (state.batteryPercent.map { $0 < 20 } ?? false) { return .sleeping }
    if state.expanded { return .expanded }
    if !state.orcaAvailable { return .throttled }
    return .collapsed
}

struct RateLimitPollResult: Sendable {
    let snapshot: RateLimitSnapshot
    let errorMessage: String?
}

actor RateLimitPoller {
    private var cached: RateLimitSnapshot = .unknown
    private let logger = Logger(subsystem: AppBrand.bundleIdentifier, category: "rate-limits")
    func refresh() -> RateLimitPollResult {
        var failures: [String] = []
        var attempted = false
        let candidates = [OrcaClient.executable]
        for path in candidates where AppSettings.load().orcaEnabled && FileManager.default.isExecutableFile(atPath: path) {
            attempted = true
            let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = ["account", "list", "--json"]
            process.environment = ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
            let output = Pipe(); let errors = Pipe(); process.standardOutput = output; process.standardError = errors
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile(); let errorData = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                guard process.terminationStatus == 0 else { failures.append(Self.concise(String(decoding: errorData, as: UTF8.self), fallback: "exit \(process.terminationStatus)")); continue }
                let snapshot = RateLimitSnapshot.parse(data)
                guard snapshot.hasAnyLimits else { failures.append("Response has no available rate limits"); continue }
                var providers = snapshot.providers
                if let codex = CodexRateLimitSource.read() { providers["codex"] = codex }
                cached = RateLimitSnapshot(providers: providers); logger.info("rate limits refreshed"); return RateLimitPollResult(snapshot: cached, errorMessage: nil)
            } catch { failures.append(error.localizedDescription) }
        }
        let error = attempted ? failures.joined(separator: " · ") : "orca executable not found"
        if let codex = CodexRateLimitSource.read() {
            var providers = cached.providers
            providers["codex"] = codex
            cached = RateLimitSnapshot(providers: providers)
            return RateLimitPollResult(snapshot: cached, errorMessage: nil)
        }
        if cached.hasAnyLimits { return RateLimitPollResult(snapshot: cached, errorMessage: nil) }
        logger.error("rate limits refresh failed: \(error, privacy: .public)")
        return RateLimitPollResult(snapshot: cached, errorMessage: Self.concise(error, fallback: "account list failed"))
    }
    private static func concise(_ value: String, fallback: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : String(text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(150))
    }
}

enum CodexRateLimitSource {
    static func executable(path: String? = ProcessInfo.processInfo.environment["PATH"]) -> String? {
        let locations = (path ?? "").split(separator: ":").map(String.init).map { URL(fileURLWithPath: $0).appendingPathComponent("codex").path }
            + ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"]
        return locations.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func read() -> ProviderRateLimits? {
        guard let executable = executable() else { return nil }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = ["app-server", "--listen", "stdio://"]
        let input = Pipe(), output = Pipe(); process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        defer { timeout.cancel(); if process.isRunning { process.terminate() }; process.waitUntilExit() }
        func send(_ value: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: value), let handle = input.fileHandleForWriting as FileHandle? else { return }
            handle.write(data); handle.write(Data([10]))
        }
        func line() -> [String: Any]? {
            var data = Data()
            while process.isRunning {
                let byte = output.fileHandleForReading.readData(ofLength: 1)
                if byte.isEmpty { return nil }
                if byte[0] == 10 { return try? JSONSerialization.jsonObject(with: data) as? [String: Any] }
                data.append(byte)
            }
            return nil
        }
        send(["method": "initialize", "id": 0, "params": ["clientInfo": ["name": "notch", "title": AppBrand.name, "version": "0.1.0"]]])
        guard line() != nil else { return nil }
        send(["method": "initialized", "params": [:]])
        send(["method": "account/rateLimits/read", "id": 1])
        var response: [String: Any]?
        while let message = line() { if (message["id"] as? Int) == 1 { response = message; break } }
        guard let raw = response?["result"] as? [String: Any], let limits = raw["rateLimits"] as? [String: Any] else { return nil }
        func window(_ key: String) -> UsageWindow? {
            guard let item = limits[key] as? [String: Any], let percent = item["usedPercent"] as? NSNumber else { return nil }
            let reset = (item["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return UsageWindow(usedPercent: min(100, max(0, percent.intValue)), resetDescription: nil, resetsAt: reset)
        }
        let result = ProviderRateLimits(session: window("primary"), weekly: window("secondary"))
        return result.hasUsage ? result : nil
    }
}
