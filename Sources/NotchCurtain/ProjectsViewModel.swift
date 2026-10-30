import Foundation
import SwiftUI
import OSLog
import IOKit.ps

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published private(set) var activeLocale = AppSettings.load().locale
    @Published private(set) var terminals: [OrcaTerminal] = []
    @Published private(set) var externalSessions: [ExternalSession] = []
    @Published private(set) var loading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var rateLimits: RateLimitSnapshot = .unknown
    @Published private(set) var rateLimitError: String?
    @Published var alert: TerminalAlert?
    @Published private(set) var actionError: String?
    @Published private(set) var collapseRequestID = 0
    private var pollTimer: DispatchSourceTimer?
    private var pollState = PollingState()
    private let logger = Logger(subsystem: AppBrand.bundleIdentifier, category: "polling")
    private var lastLevel: PollingLevel?
    private var polling = false
    private let rateLimitPoller = RateLimitPoller()
    private let externalScanner = ExternalSessionScanner()
    private var taskCache: [String: Data] = [:]
    private var taskCacheUpdatedAt = Date.distantPast
    private var failureCache: [String: Data] = [:]
    private var failureCacheUpdatedAt = Date.distantPast
    private var workerCache: Data?
    private var workerCacheUpdatedAt = Date.distantPast
    private var lastWorkerPoll = Date.distantPast
    private var lastQuotaPoll = Date.distantPast
    private var lastExternalPoll = Date.distantPast
    private var settings = AppSettings.load()

    var workspaces: [OrcaWorkspace] { terminals.workspaces }
    var aggregateState: OrcaTerminal.State? { terminals.aggregateState }
    var showsWorkspaceGroups: Bool { settings.showGroups }

    func start() {
        if DemoMode.enabled {
            terminals = DemoMode.terminals
            rateLimits = DemoMode.rateLimits
            loading = false
            errorMessage = nil
            externalSessions = []
            return
        }
        pollState.orcaAvailable = OrcaSource().isAvailable
        pollState.economyMode = settings.economyMode
        if pollState.orcaAvailable { refresh() } else { loading = false }
        lastWorkerPoll = Date()
        workerCacheUpdatedAt = lastWorkerPoll
        if settings.limitsEnabled { refreshRateLimits() }
        refreshExternalSessions()
        lastQuotaPoll = Date()
        guard pollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in self?.pollTick() }
        pollTimer = timer
        scheduleNextPoll()
        timer.resume()
    }

    func stop() {
        pollTimer?.cancel(); pollTimer = nil
    }

    func setExpanded(_ expanded: Bool) { pollState.expanded = expanded; scheduleNextPoll() }
    func setPlaying(_ playing: Bool) { pollState.playing = playing; scheduleNextPoll() }
    func setScreenAwake(_ awake: Bool) { pollState.screenAwake = awake; scheduleNextPoll() }
    func setLocked(_ locked: Bool) { pollState.locked = locked; scheduleNextPoll() }
    func setLowPower(_ enabled: Bool) { pollState.lowPower = enabled; scheduleNextPoll() }
    func setBatteryPercent(_ percent: Int?) { pollState.batteryPercent = percent; scheduleNextPoll() }
    func reloadSettings() {
        settings = AppSettings.load()
        activeLocale = settings.locale
        if DemoMode.enabled { return }
        pollState.orcaAvailable = OrcaSource().isAvailable
        pollState.economyMode = settings.economyMode
        if pollState.orcaAvailable { refresh() } else { terminals = []; errorMessage = nil }
        if settings.limitsEnabled { refreshRateLimits() } else { rateLimits = .unknown }
        refreshExternalSessions()
        scheduleNextPoll()
    }

    private func scheduleNextPoll() {
        guard let pollTimer else { return }
        let interval = pollInterval(state: pollState)
        let level = pollingLevel(state: pollState)
        if lastLevel != level {
            logger.info("poll level: \(level.rawValue, privacy: .public), interval: \(interval, privacy: .public)s")
            let line = "Notch poll_level=\(level.rawValue) interval_s=\(Int(interval))\n"
            let url = AppBrand.logURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            if let file = try? FileHandle(forWritingTo: url) { file.seekToEndOfFile(); file.write(Data(line.utf8)); try? file.close() }
            lastLevel = level
        }
        pollTimer.schedule(deadline: .now() + interval, leeway: .milliseconds(max(1, Int(interval * 200))))
    }

    private func pollTick() {
        pollState.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        pollState.batteryPercent = Self.batteryPercent()
        let pollWorkers = Date().timeIntervalSince(lastWorkerPoll) >= 60
        if pollWorkers { lastWorkerPoll = Date() }
        if settings.orcaEnabled && OrcaClient.isAvailable { refresh(loadWorkers: pollWorkers) }
        if settings.limitsEnabled && Date().timeIntervalSince(lastQuotaPoll) >= 120 {
            lastQuotaPoll = Date()
            refreshRateLimits()
        }
        let externalInterval: TimeInterval = pollState.expanded ? 6 : 30
        if settings.externalSessionsEnabled && Date().timeIntervalSince(lastExternalPoll) >= externalInterval {
            lastExternalPoll = Date()
            refreshExternalSessions()
        }
        scheduleNextPoll()
    }

    private func refreshExternalSessions() {
        guard ExternalAgentSource().isAvailable else { externalSessions = []; return }
        let scanner = externalScanner
        let orcaEnabled = OrcaSource().isAvailable
        Task.detached(priority: .utility) { [weak self] in
            let sessions = await scanner.scan(orcaEnabled: orcaEnabled)
            await self?.receiveExternal(sessions)
        }
    }

    private static func batteryPercent() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return min(100, max(0, current * 100 / maximum))
        }
        return nil
    }

    private func refreshRateLimits() {
        let poller = rateLimitPoller
        Task { [weak self] in
            let result = await poller.refresh()
            await MainActor.run {
                if let self { assignIfChanged(&self.rateLimits, result.snapshot) }
                self?.rateLimitError = nil
            }
        }
    }

    func refresh(loadWorkers: Bool = true) {
        guard !DemoMode.enabled else { return }
        guard !polling else { return }
        polling = true
        let cachedTasks = taskCache
        let cachedAt = taskCacheUpdatedAt
        let cachedFailures = failureCache
        let failureAt = failureCacheUpdatedAt
        let cachedWorkerData = workerCache
        let workerAt = workerCacheUpdatedAt
        let shouldPollWorkers = loadWorkers || Date().timeIntervalSince(workerAt) >= 60
        Task.detached(priority: .utility) { [weak self] in
            do {
                let data = try OrcaClient.run(["terminal", "list", "--json"])
                var workers = cachedWorkerData
                if shouldPollWorkers {
                    workers = try? OrcaClient.run(["orchestration", "worker-list", "--json", "--limit", "100"])
                }
                var failuresByDispatch = cachedFailures
                let failedIDs = OrcaSnapshotParser.failedDispatchIDs(workers)
                if Date().timeIntervalSince(failureAt) >= 60 || failedIDs.contains(where: { failuresByDispatch[$0] == nil }) {
                    for dispatchID in failedIDs {
                        if let data = try? OrcaClient.run(["orchestration", "worker-show", "--dispatch", dispatchID, "--json"]) {
                            failuresByDispatch[dispatchID] = data
                        }
                    }
                }
                var tasksByRun = cachedTasks
                let runIDs = OrcaSnapshotParser.workerRunIDs(workers)
                if Date().timeIntervalSince(cachedAt) >= 60 || runIDs.contains(where: { tasksByRun[$0] == nil }) {
                    for runID in runIDs {
                        if let taskData = try? OrcaClient.run(["orchestration", "task-list", "--run", runID, "--json", "--brief"]) {
                            tasksByRun[runID] = taskData
                        }
                    }
                }
                let result = try OrcaSnapshotParser.parse(data, workerData: workers, taskData: Array(tasksByRun.values), failureData: Array(failuresByDispatch.values))
                await self?.receive(result: result, tasksByRun: tasksByRun, failuresByDispatch: failuresByDispatch,
                                    workerData: workers, didPollWorkers: shouldPollWorkers)
            } catch {
                await self?.receive(error: error)
            }
        }
    }

    func focus(_ terminal: OrcaTerminal) {
        runAction(["terminal", "switch", "--terminal", terminal.id], activateOrca: true, collapseOnSuccess: true)
    }

    func clear(_ terminal: OrcaTerminal) {
        alert = TerminalAlert(title: AppText.value("Clear context?"), message: String(format: AppText.value("Send /clear to terminal %@?"), terminal.displayTitle), confirmTitle: AppText.value("Send /clear"), requiresConfirmation: true) { [weak self] in
            self?.runAction(["terminal", "send", "--terminal", terminal.id, "--text", "/clear", "--enter"])
        }
    }

    func launch(agent: OrcaTerminal.Agent, workspace: OrcaWorkspace) {
        guard agent != .unknown else { return }
        runAction(["agent", "launch", "--agent", agent.rawValue, "--worktree", "path:\(workspace.path)", "--surface", "terminal", "--json"])
    }

    private func runAction(_ arguments: [String], activateOrca: Bool = false, collapseOnSuccess: Bool = false) {
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if activateOrca { try OrcaClient.activateOrca() }
                _ = try OrcaClient.run(arguments)
                await self?.finishAction(success: true, message: nil, collapse: collapseOnSuccess)
            } catch {
                await self?.finishAction(success: false, message: error.localizedDescription, collapse: false)
            }
        }
    }

    private func finishAction(success: Bool, message: String?, collapse: Bool) {
        actionError = ActionFeedback.inlineMessage(success: success, error: message)
        if success && collapse { collapseRequestID += 1 }
    }

    private func receive(result: [OrcaTerminal], tasksByRun: [String: Data], failuresByDispatch: [String: Data],
                         workerData: Data?, didPollWorkers: Bool) {
        pollState.orcaAvailable = true
        scheduleNextPoll()
        assignIfChanged(&terminals, result)
        if errorMessage != nil { errorMessage = nil }
        taskCache = tasksByRun
        taskCacheUpdatedAt = Date()
        failureCache = failuresByDispatch
        failureCacheUpdatedAt = Date()
        if didPollWorkers { workerCache = workerData; workerCacheUpdatedAt = Date() }
        loading = false
        polling = false
    }

    private func receiveExternal(_ sessions: [ExternalSession]) {
        if externalSessions != sessions { externalSessions = sessions }
    }

    private func receive(error: Error) {
        if errorMessage != error.localizedDescription { errorMessage = error.localizedDescription }
        loading = false
        polling = false
        pollState.orcaAvailable = false
        scheduleNextPoll()
        logger.info("Orca unavailable; next check in 60s")
    }

}

enum ActionFeedback {
    static func inlineMessage(success: Bool, error: String?) -> String? {
        guard !success else { return nil }
        return error?.isEmpty == false ? error : AppText.value("Command failed")
    }
}

struct TerminalAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    var requiresConfirmation = false
    let onConfirm: () -> Void
}
