import Foundation
import Testing
@testable import NotchCurtain

@Test func settingsDecodePartialValuesAndKeepDefaults() throws {
    let partial = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"orcaEnabled":false,"language":"russian"}"#.utf8))
    #expect(partial.orcaEnabled == false)
    #expect(partial.language == .russian)
    #expect(partial.musicEnabled)
    #expect(partial.externalSessionsEnabled)
    #expect(partial.hoverDelay == 0.12)
}

@Test func settingsEncodeDecodeRoundTrips() throws {
    var settings = AppSettings()
    settings.orcaEnabled = false
    settings.orcaPath = "/Users/example/bin/orca"
    settings.launchAtLogin = true
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
}

@Test func orcaSearchUsesPathBeforeStandardLocations() {
    let found = OrcaLocator.find(path: "/example/bin:/bin", isExecutable: { $0 == "/bin/orca" || $0 == "/opt/homebrew/bin/orca" })
    #expect(found == "/bin/orca")
    #expect(OrcaLocator.candidates(path: "/custom").first == "/custom/orca")
}

@Test func localizationCatalogsContainRequiredKeys() throws {
    let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/NotchCurtain")
    for locale in ["en", "ru"] {
        let strings = try String(contentsOf: base.appendingPathComponent("\(locale).lproj/Localizable.strings"), encoding: .utf8)
        for key in ["Projects", "Music", "No active agents", "OUTSIDE ORCA", "%lld min ago", "Settings"] {
            #expect(strings.contains("\"\(key)\""))
        }
    }
}
