import Testing
import Foundation
@testable import NotchCurtain

private func outsideFixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

@Test func parsesOnlyClaudeAndCodexCliRowsAndExcludesHelpers() throws {
    let rows = ExternalProcessParser.parsePS(try outsideFixture("outside-ps"))
    #expect(rows.map(\.pid) == [101, 102])
    #expect(rows[0].agent == .claude)
    #expect(rows[1].agent == .codex)
    #expect(rows[1].cpu == 4.1)
}

@Test func recognizesOrcaEnvironmentAndParsesBatchedLsofRows() throws {
    #expect(ExternalProcessParser.hasOrcaHandle(try outsideFixture("outside-eww").components(separatedBy: "\n")[1]))
    #expect(!ExternalProcessParser.hasOrcaHandle("  102 ?? S 0:01 codex PATH=/usr/bin"))
    let cwd = ExternalProcessParser.parseCWDs(try outsideFixture("outside-lsof"))
    #expect(cwd[101] == "/Users/me/sample-project")
    #expect(cwd[102] == "/Users/me/other-project")
}

@Test func parsesGeneralAgentCLICommandsAndOnlyFiltersOrcaWhenEnabled() throws {
    let rows = ExternalProcessParser.parsePS("""
      PID PPID ELAPSED %CPU COMMAND
      201 100 00:03 0.1 gemini --prompt x
      202 100 00:04 0.2 cursor-agent
      203 100 00:05 0.3 aider
      204 100 00:06 0.4 opencode
      205 100 00:07 0.5 copilot
      206 100 00:08 0.6 codex
    """)
    #expect(rows.map(\.agent) == [.gemini, .cursorAgent, .aider, .opencode, .copilot, .codex])
    #expect(ExternalProcessParser.excludingOrca(rows, orcaPIDs: [206], orcaEnabled: false).count == 6)
    #expect(ExternalProcessParser.excludingOrca(rows, orcaPIDs: [206], orcaEnabled: true).count == 5)
}
