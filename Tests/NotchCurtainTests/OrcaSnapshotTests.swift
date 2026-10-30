import Testing
import Foundation
@testable import NotchCurtain

@Test func parsesSanitizedOrcaFixtureAndGroupsWorkspaces() throws {
    let data = try Data(contentsOf: Bundle.module.url(forResource: "terminal-list", withExtension: "json", subdirectory: "Fixtures")!)
    let terminals = try OrcaSnapshotParser.parse(data)
    #expect(terminals.count == 4)
    #expect(terminals.workspaces.count == 2)
    #expect(terminals.first(where: { $0.id == "term_fixture_0" })?.agent == .claude)
    #expect(terminals.first(where: { $0.id == "term_fixture_2" })?.state == .ready)
}

@Test func antigravityUsesShortProviderLabel() {
    #expect(OrcaTerminal.Agent.antigravity.label == "Antigravity")
}

@Test func successfulActionsProduceNoFeedbackMessage() {
    #expect(ActionFeedback.inlineMessage(success: true, error: nil) == nil)
    #expect(ActionFeedback.inlineMessage(success: true, error: "stale error") == nil)
    #expect(ActionFeedback.inlineMessage(success: false, error: "Orca is unavailable") == "Orca is unavailable")
}

@Test func rejectsGenericTitlesInFavorOfBranchNames() throws {
    let json = #"{"result":{"terminals":[{"handle":"t1","worktreePath":"/tmp/demo","title":"Terminal","branch":"refs/heads/feature/meaningful-branch","agentIdentity":"claude","preview":""}]}}"#
    let terminal = try #require(OrcaSnapshotParser.parse(Data(json.utf8)).first)
    #expect(terminal.displayTitle == "meaningful-branch")
}

@Test func unknownAgentIdentityKeepsItsProviderLabelAndGenericAvatarCase() throws {
    let json = #"{"result":{"terminals":[{"handle":"t1","worktreePath":"/tmp/demo","title":"Terminal","agentIdentity":"zcode","preview":""}]}}"#
    let terminal = try #require(OrcaSnapshotParser.parse(Data(json.utf8)).first)
    #expect(terminal.agent == .unknown)
    #expect(terminal.displayAgentLabel == "Zcode")
}

@Test func activeWorkerDataOverridesTerminalPreviewState() throws {
    let terminalJSON = #"{"result":{"terminals":[{"handle":"t1","worktreePath":"/tmp/demo","title":"Claude terminal 1","branch":"refs/heads/feature/demo","agentIdentity":"claude","preview":"new task?"}]}}"#
    let workerJSON = #"{"result":{"workers":[{"agentTerminalHandle":"t1","workerState":"unsupervised","dispatchStatus":"dispatched","projection":{"stage":{"activity":"working"},"liveness":{"verdict":"live"},"evidence":{"liveStatus":"fresh"}}}]}}"#
    let terminal = try #require(OrcaSnapshotParser.parse(Data(terminalJSON.utf8), workerData: Data(workerJSON.utf8)).first)
    #expect(terminal.state == .working)
}

@Test func ordinaryPreviewMentionsDoNotBecomeTerminalErrors() throws {
    let json = #"{"result":{"terminals":[{"handle":"t1","worktreePath":"/tmp/demo","title":"Claude shell","branch":"main","agentIdentity":"claude","preview":"The previous error was fixed; tests pass."}]}}"#
    let terminal = try #require(OrcaSnapshotParser.parse(Data(json.utf8)).first)
    #expect(terminal.state == .waiting)
}

@Test func currentExplicitErrorShowsThePreviewCause() throws {
    let now = Int(Date().timeIntervalSince1970 * 1_000)
    let json = #"{"result":{"terminals":[{"handle":"t1","worktreePath":"/tmp/demo","title":"Claude shell","agentIdentity":"claude","lastOutputAt":\#(now),"preview":"error: authentication expired"}]}}"#
    let terminal = try #require(OrcaSnapshotParser.parse(Data(json.utf8)).first)
    #expect(terminal.state == .error)
    #expect(terminal.errorReason == "error: authentication expired")
}

@Test func staleFailedDispatchDoesNotRemainAnError() throws {
    let old = Int((Date().timeIntervalSince1970 - 3_600) * 1_000)
    let terminals = #"{"result":{"terminals":[{"handle":"t1","worktreePath":"/tmp/demo","title":"Terminal","agentIdentity":"claude","lastOutputAt":\#(old),"preview":""}]}}"#
    let workers = #"{"result":{"workers":[{"agentTerminalHandle":"t1","taskId":"task1","dispatchId":"dispatch1","dispatchStatus":"failed","workerState":"failed","projection":{"provider":{"id":"claude"}}}]}}"#
    let failure = #"{"result":{"dispatch":{"id":"dispatch1","status":"failed","lastFailure":"timeout"},"worker":{"agentTerminalHandle":"t1","lastError":"timeout"}}}"#
    let terminal = try #require(OrcaSnapshotParser.parse(Data(terminals.utf8), workerData: Data(workers.utf8), failureData: [Data(failure.utf8)]).first)
    #expect(terminal.state == .waiting)
    #expect(terminal.errorReason == nil)
}

@Test func recentFailureGetsCauseAndPreviewHintsAgentAndModel() throws {
    let now = Int(Date().timeIntervalSince1970 * 1_000)
    let terminals = #"{"result":{"terminals":[{"handle":"t1","worktreePath":"/tmp/demo","title":"Terminal","preview":"✻ Brewed for 2m · Sonnet 5.5","lastOutputAt":\#(now)}]}}"#
    let workers = #"{"result":{"workers":[{"agentTerminalHandle":"t1","taskId":"task1","dispatchId":"dispatch1","dispatchStatus":"failed","workerState":"failed","projection":{"provider":{"id":"claude"}}}]}}"#
    let failure = #"{"result":{"dispatch":{"id":"dispatch1","status":"failed","lastFailure":"timeout"},"worker":{"agentTerminalHandle":"t1","lastError":"timeout"}}}"#
    let terminal = try #require(OrcaSnapshotParser.parse(Data(terminals.utf8), workerData: Data(workers.utf8), failureData: [Data(failure.utf8)]).first)
    #expect(terminal.agent == .claude)
    #expect(terminal.model?.lowercased() == "sonnet 5.5")
    #expect(terminal.state == .error)
    #expect(terminal.errorReason == "timeout")
    #expect(terminal.dispatch?.reason == "timeout")
}

@Test func modelCanBeInferredFromTerminalTitleWhenPreviewHasNone() throws {
    let terminals = #"{"result":{"terminals":[{"handle":"t1","worktreePath":"/tmp/demo","title":"Claude Code · Sonnet 5.5","preview":""}]}}"#
    let terminal = try #require(OrcaSnapshotParser.parse(Data(terminals.utf8)).first)
    #expect(terminal.model?.lowercased() == "sonnet 5.5")
}

@Test func previewDropsBoxDrawingSeparators() {
    let lines = OrcaSnapshotParser.cleanedPreview("────────────────── [work] Project ───\nlatest output")
    #expect(lines == ["latest output"])
}

@Test func previewDropsSingleCharacterAndShellPromptNoise() {
    for sample in [">", "+", "4", "k)", "2 2", "$", "%"] {
        #expect(OrcaSnapshotParser.cleanedPreview(sample).isEmpty)
    }
    #expect(OrcaSnapshotParser.cleanedPreview("Build passed").isEmpty == false)
}

@Test func previewDropsBrailleSpinnerRepeatedWorkPrefixesAndStatusBars() {
    let noisy = "…orWorkWork•WorkWorkWorki•Worki7Workin•Workinorking…"
    #expect(OrcaSnapshotParser.cleanedPreview(noisy).isEmpty)
    #expect(OrcaSnapshotParser.cleanedPreview("⠋⠙\u{001B}[32mBuild passed ✓\u{001B}[0m") == ["Build passed ✓"])
    #expect(OrcaSnapshotParser.cleanedPreview("Working (12s · esc to interrupt)").isEmpty)
    #expect(OrcaSnapshotParser.cleanedPreview("Important result summary orkngrkingrkingrkingrking") == ["Important result summary"])
    #expect(OrcaSnapshotParser.cleanedPreview("Latest output\nLatest output") == ["Latest output"])
}

@Test func previewDropsRestartApplySpinnerTail() {
    #expect(OrcaSnapshotParser.cleanedPreview("Ready · /restart to applyB") == ["Ready · /restart to apply"])
}

@Test func previewDropsAgentStatusBarsAndKeepsLatestMeaningfulLine() {
    let preview = "Useful earlier answer\n…n-3-ultra-550b-a... 121K/1M [██░░] 12% 16m ⏲ 4m 56s ⚠ YOLO\nok)\nuncached\n/clear to start fresh\nFinal useful result"
    #expect(OrcaSnapshotParser.cleanedPreview(preview) == ["Final useful result"])
}

@Test func unknownModelPlaceholderIsNotDisplayed() throws {
    let json = #"{"result":{"terminals":[{"handle":"t1","worktreePath":"/tmp/demo","title":"Claude shell","model":"model unknown","preview":""}]}}"#
    let terminal = try #require(OrcaSnapshotParser.parse(Data(json.utf8)).first)
    #expect(terminal.model == nil)
}

@Test func parsesSessionAndWeeklyRateLimitsFixture() throws {
    let url = try #require(Bundle.module.url(forResource: "rate-limits", withExtension: "json", subdirectory: "Fixtures"))
    let limits = RateLimitSnapshot.parse(try Data(contentsOf: url))
    #expect(limits.providers["claude"]?.session?.usedPercent == 49)
    #expect(limits.providers["claude"]?.session?.resetDescription == "1:59 PM")
    #expect(limits.providers["claude"]?.weekly?.usedPercent == 15)
    #expect(limits.providers["claude"]?.weekly?.resetsAt != nil)
    #expect(limits.providers["codex"]?.session?.usedPercent == 16)
    #expect(limits.providers["codex"]?.weekly?.usedPercent == 9)
    #expect(limits.providers["antigravity"]?.session?.usedPercent == 100)
    #expect(limits.providers["antigravity"]?.weekly?.usedPercent == 51)
}

@Test func absentRateLimitsStayUnknown() {
    let limits = RateLimitSnapshot.parse(Data(#"{"result":{"runtime":{"state":"ready"}}}"#.utf8))
    #expect(limits.providers.isEmpty)
}

@Test func providerSelectionTracksAccountsAndAvailableRateLimits() {
    let one = #"{"result":{"accounts":{"gemini":[{"id":"g"}],"claude":[],"codex":[]},"rateLimits":{"gemini":{"session":{"usedPercent":20}},"claude":{"weekly":{"usedPercent":40}},"codex":{"session":{"usedPercent":10}}}}}"#
    #expect(RateLimitSnapshot.parse(Data(one.utf8)).providers.keys.sorted() == ["gemini"])
    let two = #"{"result":{"accounts":{"claude":[{"id":"c"}],"codex":[{"id":"x"}]},"rateLimits":{"claude":{"weekly":{"usedPercent":40}},"codex":{"session":{"usedPercent":10}}}}}"#
    #expect(RateLimitSnapshot.parse(Data(two.utf8)).providers.keys.sorted() == ["claude", "codex"])
    let none = #"{"result":{"accounts":{"claude":[]},"rateLimits":{"claude":{"session":{"usedPercent":20}}}}}"#
    #expect(RateLimitSnapshot.parse(Data(none.utf8)).providers.isEmpty)
}

@Test func unchangedSnapshotsCompareEqualForUpdateSuppression() {
    var snapshot = RateLimitSnapshot(providers: ["codex": ProviderRateLimits(session: UsageWindow(usedPercent: 22, resetDescription: nil, resetsAt: nil), weekly: nil)])
    #expect(!assignIfChanged(&snapshot, snapshot))
    let changed = RateLimitSnapshot(providers: [:])
    #expect(assignIfChanged(&snapshot, changed))
}

@Test func pollIntervalPolicyCoversExpandedIdleAndUnavailableStates() {
    #expect(pollInterval(state: PollingState()) == 15)
    #expect(pollInterval(state: PollingState(expanded: true)) == 3)
    #expect(pollInterval(state: PollingState(orcaAvailable: false)) == 60)
    #expect(pollInterval(state: PollingState(screenAwake: false)) == 120)
    #expect(pollInterval(state: PollingState(locked: true)) == 120)
    #expect(pollInterval(state: PollingState(lowPower: true)) == 120)
    #expect(pollInterval(state: PollingState(batteryPercent: 19)) == 120)
}
