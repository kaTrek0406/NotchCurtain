import Foundation

enum AppBrand {
    static let name = "NotchCurtain"
    static let supportDirName = "NotchCurtain"
    static let logName = "NotchCurtain.log"
    static let bundleIdentifier = "io.github.katrek0406.NotchCurtain"
    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true).appendingPathComponent(logName)
    }
    static var settingsURL: URL {
        if let override = ProcessInfo.processInfo.environment["NOTCH_CURTAIN_SETTINGS_PATH"], !override.isEmpty { return URL(fileURLWithPath: override) }
        if DemoMode.enabled { return FileManager.default.temporaryDirectory.appendingPathComponent("notch-curtain-demo-settings.json") }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportDirName, isDirectory: true).appendingPathComponent("settings.json")
    }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, english, russian
    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable {
    var language: AppLanguage = .system
    var orcaEnabled = true
    var orcaPath = ""
    var musicEnabled = true
    var limitsEnabled = true
    var externalSessionsEnabled = true
    var economyMode = false
    var hoverDelay = 0.12
    var launchAtLogin = false
    var showGroups = true
    var locale: Locale {
        switch language {
        case .russian: Locale(identifier: "ru")
        case .english: Locale(identifier: "en")
        case .system: Locale.current
        }
    }

    private enum CodingKeys: String, CodingKey { case language, orcaEnabled, orcaPath, musicEnabled, limitsEnabled, externalSessionsEnabled, economyMode, hoverDelay, launchAtLogin, showGroups }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        orcaEnabled = try c.decodeIfPresent(Bool.self, forKey: .orcaEnabled) ?? true
        orcaPath = try c.decodeIfPresent(String.self, forKey: .orcaPath) ?? ""
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? true
        limitsEnabled = try c.decodeIfPresent(Bool.self, forKey: .limitsEnabled) ?? true
        externalSessionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .externalSessionsEnabled) ?? true
        economyMode = try c.decodeIfPresent(Bool.self, forKey: .economyMode) ?? false
        hoverDelay = try c.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? 0.12
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showGroups = try c.decodeIfPresent(Bool.self, forKey: .showGroups) ?? true
    }

    static func load(from url: URL = AppBrand.settingsURL) -> AppSettings {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return value
    }
    func save(to url: URL = AppBrand.settingsURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

enum OrcaLocator {
    static func candidates(path: String?) -> [String] {
        let env = path ?? ""
        return env.split(separator: ":").map(String.init).map { URL(fileURLWithPath: $0).appendingPathComponent("orca").path }
            + ["/usr/local/bin/orca", "/opt/homebrew/bin/orca", "/Applications/Orca.app/Contents/Resources/bin/orca"]
    }
    static func find(path: String? = ProcessInfo.processInfo.environment["PATH"], isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String? {
        candidates(path: path).first(where: isExecutable)
    }
}

enum AppText {
    static func value(_ key: String) -> String {
        let language = AppSettings.load().language
        let code = language == .russian ? "ru" : (language == .english ? "en" : Locale.current.language.languageCode?.identifier ?? "en")
        let mainBundle = Bundle.main
        guard let path = mainBundle.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    static func format(_ key: String, _ values: CVarArg...) -> String { String(format: value(key), locale: AppSettings.load().locale, arguments: values) }
}
