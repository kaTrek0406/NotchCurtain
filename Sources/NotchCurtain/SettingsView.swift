import SwiftUI

struct SettingsView: View {
    let onChange: () -> Void
    @State private var settings = AppSettings.load()
    @State private var path = ""
    @State private var status = ""

    var body: some View {
        Form {
            Picker("Language", selection: $settings.language) {
                Text("System").tag(AppLanguage.system)
                Text("English").tag(AppLanguage.english)
                Text("Russian").tag(AppLanguage.russian)
            }
            Toggle("Enable Orca integration", isOn: $settings.orcaEnabled)
            HStack {
                TextField("Path to orca", text: $settings.orcaPath)
                Button("Auto-detect") { settings.orcaPath = OrcaLocator.find() ?? "" }
            }
            Toggle("Music", isOn: $settings.musicEnabled)
            Toggle("Usage limits", isOn: $settings.limitsEnabled)
            Toggle("External agent sessions", isOn: $settings.externalSessionsEnabled)
            Toggle("Economy polling", isOn: $settings.economyMode)
            Toggle("Show groups", isOn: $settings.showGroups)
            HStack { Text("Hover delay"); Slider(value: $settings.hoverDelay, in: 0...0.8); Text("\(settings.hoverDelay, specifier: "%.2f")s") }
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .environment(\.locale, settings.locale)
        .onChange(of: settings) { _, value in
            do { try value.save(); status = "Saved"; onChange() }
            catch { status = error.localizedDescription }
        }
        .onAppear {
            guard !DemoMode.enabled else { return }
            settings.orcaPath = AppSettings.load().orcaPath.isEmpty ? (OrcaLocator.find() ?? "") : AppSettings.load().orcaPath
        }
    }
}
