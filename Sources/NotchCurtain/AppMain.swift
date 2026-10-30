import AppKit
import Darwin
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var terminationSignal: DispatchSourceSignal?
    private var statusItem: NSStatusItem?
    private var loginMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signalSource.setEventHandler { NSApp.terminate(nil) }
        signalSource.resume()
        terminationSignal = signalSource
        if !DemoMode.enabled {
            for instance in NSRunningApplication.runningApplications(withBundleIdentifier: AppBrand.bundleIdentifier) where instance.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                instance.terminate()
            }
        }
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        applyLoginSetting()
        let controller = NotchPanelController()
        panelController = controller
        controller.start()
        if DemoMode.enabled && CommandLine.arguments.contains("--demo-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showSettings() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule", accessibilityDescription: AppBrand.name)
        let menu = NSMenu()
        menu.addItem(withTitle: AppText.value("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: AppText.value("Launch at Login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.state = AppSettings.load().launchAtLogin ? .on : .off
        loginMenuItem = login
        menu.addItem(withTitle: AppText.format("About %@", AppBrand.name), action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: AppText.value("Quit"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showSettings() {
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 510), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = AppText.value("Settings")
        window.contentView = NSHostingView(rootView: SettingsView(onChange: { [weak self] in
            self?.panelController?.reloadSettings()
            self?.loginMenuItem?.state = AppSettings.load().launchAtLogin ? .on : .off
        }))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func toggleLogin() {
        guard !DemoMode.enabled else { return }
        var settings = AppSettings.load(); settings.launchAtLogin.toggle(); try? settings.save(); applyLoginSetting(); loginMenuItem?.state = settings.launchAtLogin ? .on : .off
    }
    private func applyLoginSetting() {
        guard !DemoMode.enabled else { return }
        let desired = AppSettings.load().launchAtLogin
        do {
            if desired && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if !desired && SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        } catch { NSLog("Launch at login update failed: %@", error.localizedDescription) }
    }
    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppBrand.name]) }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stop()
        terminationSignal?.cancel()
        terminationSignal = nil
    }
}

@main
enum NotchApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
