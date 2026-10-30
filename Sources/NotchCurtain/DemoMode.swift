import AppKit
import Foundation

enum DemoMode {
    static let enabled = ProcessInfo.processInfo.environment["NC_DEMO"] == "1" || CommandLine.arguments.contains("--demo")

    static let terminals: [OrcaTerminal] = [
        make("demo-claude", "Claude Code", .claude, "acme-web", .working, "Implementing the navigation layout"),
        make("demo-codex", "Codex", .codex, "api-server", .waiting, "Waiting for the next instruction"),
        make("demo-gemini", "Gemini", .antigravity, "docs-site", .ready, "Documentation update complete"),
        make("demo-cursor", "Cursor Agent", .unknown, "acme-web", .error, "Error: demo task needs attention"),
        make("demo-aider", "Aider", .unknown, "api-server", .working, "Reviewing the API changes")
    ]

    static let rateLimits = RateLimitSnapshot(providers: [
        "claude": ProviderRateLimits(session: UsageWindow(usedPercent: 41, resetDescription: nil, resetsAt: nil), weekly: UsageWindow(usedPercent: 14, resetDescription: nil, resetsAt: nil)),
        "codex": ProviderRateLimits(session: UsageWindow(usedPercent: 22, resetDescription: nil, resetsAt: nil), weekly: UsageWindow(usedPercent: 9, resetDescription: nil, resetsAt: nil))
    ])

    static let track = MusicTrack(title: "Demo Track", artist: "Demo Artist", album: "Demo Album",
                                  artwork: artwork, artworkMimeType: "image/png", playing: true,
                                  elapsedTime: 42, duration: 198, timestamp: Date().timeIntervalSince1970,
                                  bundleIdentifier: "demo.notchcurtain.player")

    private static func make(_ id: String, _ title: String, _ agent: OrcaTerminal.Agent, _ project: String,
                             _ state: OrcaTerminal.State, _ preview: String) -> OrcaTerminal {
        OrcaTerminal(id: id, title: title, workspacePath: "/demo/\(project)", branch: "main", agent: agent,
                     providerIdentity: title, model: nil, state: state, preview: preview,
                     lastOutputAt: Date(), dispatch: nil, errorReason: state == .error ? "Demo error state" : nil)
    }

    private static let artwork: Data? = {
        let side = 256
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.38, blue: 0.52, alpha: 1),
                   ending: NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.25, alpha: 1))?.draw(in: bounds, angle: 45)
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: CGRect(x: 36, y: 38, width: 180, height: 180)).fill()
        NSColor.white.withAlphaComponent(0.20).setFill()
        NSBezierPath(ovalIn: CGRect(x: 84, y: 76, width: 100, height: 100)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }()
}
