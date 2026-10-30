import Foundation

protocol AgentSource {
    var isAvailable: Bool { get }
}

struct OrcaSource: AgentSource {
    var isAvailable: Bool { AppSettings.load().orcaEnabled && OrcaClient.isAvailable }
}

struct ExternalAgentSource: AgentSource {
    var isAvailable: Bool { AppSettings.load().externalSessionsEnabled }
}
