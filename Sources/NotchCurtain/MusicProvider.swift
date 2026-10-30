import AppKit
import Foundation
import Darwin

private final class AdapterProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    func set(_ process: Process?) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
        if stopped, let process { Self.terminate(process) }
    }
    func stop() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        if let process, process.isRunning { Self.terminate(process) }
    }
    private static func terminate(_ process: Process) {
        let pid = process.processIdentifier
        _ = Darwin.kill(pid, SIGTERM)
        usleep(150_000)
        if process.isRunning { _ = Darwin.kill(pid, SIGKILL) }
    }
}

private enum ArtworkDataCache {
    static let cache = NSCache<NSString, NSData>()
    static func data(_ encoded: String?, key: String) -> Data? {
        guard let encoded else { return nil }
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached as Data }
        guard let decoded = Data(base64Encoded: encoded) else { return nil }
        cache.setObject(decoded as NSData, forKey: cacheKey)
        return decoded
    }
}

struct MusicTrack: Equatable {
    let title: String
    let artist: String
    let album: String?
    let artwork: Data?
    let artworkMimeType: String?
    let playing: Bool
    let elapsedTime: Double
    let duration: Double
    let timestamp: Double
    let bundleIdentifier: String?

    var currentTime: Double { currentTime(at: Date()) }

    func currentTime(at date: Date) -> Double {
        let liveElapsed = elapsedTime + (playing && timestamp > 0 ? date.timeIntervalSince1970 - timestamp : 0)
        return min(max(0, liveElapsed), duration > 0 ? duration : .greatestFiniteMagnitude)
    }

    func hasSameVisibleState(as other: MusicTrack) -> Bool {
        guard title == other.title, artist == other.artist, album == other.album, artwork == other.artwork,
              artworkMimeType == other.artworkMimeType, playing == other.playing, duration == other.duration,
              bundleIdentifier == other.bundleIdentifier else { return false }
        return playing || elapsedTime == other.elapsedTime
    }

    static func parse(_ data: Data) -> MusicTrack? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if object is NSNull { return nil }
        let envelope = object as? [String: Any]
        guard let json = (envelope?["payload"] as? [String: Any]) ?? envelope,
              let title = json["title"] as? String, !title.isEmpty else { return nil }
        func number(_ key: String) -> Double { (json[key] as? NSNumber)?.doubleValue ?? 0 }
        let timestamp: Double
        if let number = json["timestamp"] as? NSNumber {
            timestamp = number.doubleValue
        } else if let value = json["timestamp"] as? String,
                  let date = ISO8601DateFormatter().date(from: value) {
            timestamp = date.timeIntervalSince1970
        } else {
            timestamp = 0
        }
        let itemKey = (json["contentItemIdentifier"] as? String) ?? "\(json["bundleIdentifier"] as? String ?? "")|\(title)"
        let art = ArtworkDataCache.data(json["artworkData"] as? String, key: itemKey)
        return MusicTrack(title: title, artist: json["artist"] as? String ?? AppText.value("Unknown Artist"),
                          album: json["album"] as? String, artwork: art,
                          artworkMimeType: json["artworkMimeType"] as? String,
                          playing: json["playing"] as? Bool ?? false,
                          elapsedTime: number("elapsedTime"), duration: number("duration"),
                          timestamp: timestamp, bundleIdentifier: json["bundleIdentifier"] as? String)
    }
}

/// Owns the long-lived adapter process. Blocking pipe reads and relaunch delays stay off the UI actor.
actor MusicProvider {
    private var runner: Task<Void, Never>?
    private nonisolated let processBox = AdapterProcessBox()

    func start(onTrack: @escaping @Sendable (MusicTrack?) async -> Void) {
        guard runner == nil else { return }
        let processBox = self.processBox
        runner = Task.detached(priority: .utility) {
            let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            let script = resources.appendingPathComponent("mediaremote-adapter.pl")
            let framework = resources.appendingPathComponent("MediaRemoteAdapter.framework")
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
                process.arguments = [script.path, framework.path, "stream", "--no-diff"]
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    processBox.set(process)
                    backoff = 1
                    var pending = Data()
                    while process.isRunning && !Task.isCancelled {
                        let bytes = pipe.fileHandleForReading.availableData
                        if bytes.isEmpty { break }
                        pending.append(bytes)
                        while let newline = pending.firstIndex(of: 10) {
                            let line = Data(pending[..<newline]); pending.removeSubrange(...newline)
                            await onTrack(MusicTrack.parse(line))
                        }
                    }
                    if process.isRunning { process.terminate() }
                    process.waitUntilExit()
                    processBox.set(nil)
                } catch {
                    await onTrack(nil)
                }
                await onTrack(nil)
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 30)
            }
        }
    }

    func stop() {
        processBox.stop()
        runner?.cancel()
        runner = nil
    }

    nonisolated func stopImmediately() {
        processBox.stop()
        Task { await stop() }
    }

    func send(_ command: Int) {
        Task.detached(priority: .userInitiated) {
            let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [resources.appendingPathComponent("mediaremote-adapter.pl").path,
                                 resources.appendingPathComponent("MediaRemoteAdapter.framework").path, "send", String(command)]
            process.standardOutput = Pipe(); process.standardError = Pipe()
            do { try process.run(); process.waitUntilExit(); if process.terminationStatus != 0 { Self.sendMediaKey(command) } }
            catch { Self.sendMediaKey(command) }
        }
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        Task.detached(priority: .userInitiated) {
            let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [resources.appendingPathComponent("mediaremote-adapter.pl").path,
                                 resources.appendingPathComponent("MediaRemoteAdapter.framework").path,
                                 "seek", String(Int(seconds * 1_000_000))]
            process.standardOutput = Pipe(); process.standardError = Pipe()
            try? process.run(); process.waitUntilExit()
        }
    }

    private nonisolated static func sendMediaKey(_ command: Int) {
        let key: Int32 = command == 2 ? 16 : (command == 4 ? 17 : 18)
        let data = (key << 16) | (0xA << 8)
        for state: Int32 in [0xA00, 0xB00] {
            if let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                              modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: 0, context: nil, subtype: 8,
                                              data1: Int(data | state), data2: -1)?.cgEvent {
                event.post(tap: CGEventTapLocation.cghidEventTap)
            }
        }
    }
}

@MainActor final class MusicViewModel: ObservableObject {
    @Published private(set) var track: MusicTrack?
    private let provider = MusicProvider()
    private var started = false
    private var fakeMode = false
    private var enabled = AppSettings.load().musicEnabled
    func reloadSettings() {
        enabled = AppSettings.load().musicEnabled
        if !enabled { stop(); track = nil } else { start() }
    }
    func start() {
        guard !started, enabled else { return }; started = true
        if DemoMode.enabled {
            track = DemoMode.track
            fakeMode = true
            return
        }
        if Self.fakePlayingEnabled {
            fakeMode = true
            track = Self.fakeTrack
            return
        }
        Task { await provider.start { [weak self] track in await self?.receive(track) } }
    }
    func stop() { provider.stopImmediately(); started = false }
    private func receive(_ track: MusicTrack?) {
        if let current = self.track, let track, current.hasSameVisibleState(as: track) { return }
        if self.track != track { self.track = track }
    }
    func toggle() {
        if fakeMode { setFakePlaying(track?.playing != true); return }
        Task { await provider.send(2) }
    }
    func previous() { guard !fakeMode else { return }; Task { await provider.send(5) } }
    func next() { guard !fakeMode else { return }; Task { await provider.send(4) } }
    func seek(_ seconds: Double) {
        if fakeMode, let track {
            self.track = MusicTrack(title: track.title, artist: track.artist, album: track.album, artwork: track.artwork,
                                    artworkMimeType: track.artworkMimeType, playing: track.playing,
                                    elapsedTime: seconds, duration: track.duration, timestamp: Date().timeIntervalSince1970,
                                    bundleIdentifier: track.bundleIdentifier)
            return
        }
        Task { await provider.seek(seconds) }
    }

    private func setFakePlaying(_ playing: Bool) {
        guard let track else { return }
        self.track = MusicTrack(title: track.title, artist: track.artist, album: track.album, artwork: track.artwork,
                                artworkMimeType: track.artworkMimeType, playing: playing,
                                elapsedTime: track.currentTime, duration: track.duration,
                                timestamp: Date().timeIntervalSince1970, bundleIdentifier: track.bundleIdentifier)
    }

    private static var fakePlayingEnabled: Bool {
        ProcessInfo.processInfo.environment["NOTCH_CURTAIN_DEMO_PLAYING"] == "1" ||
            FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".notch-curtain-demo-playing").path)
    }

    private static var fakeTrack: MusicTrack {
        MusicTrack(title: "Demo Track", artist: "Demo Artist", album: "Demo Album",
                   artwork: fakeArtwork(), artworkMimeType: "image/png", playing: true,
                   elapsedTime: 205, duration: 224, timestamp: 0,
                   bundleIdentifier: "com.google.Chrome.app.fake")
    }

    private static func fakeArtwork() -> Data? {
        let side = 120
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
        for inset in stride(from: 4, through: 44, by: 10) {
            NSColor(calibratedRed: 0.13, green: 0.23, blue: 0.39, alpha: 0.42).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2))
            ring.lineWidth = 2
            ring.stroke()
        }
        NSColor(calibratedRed: 1, green: 0.38, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 49, y: 49, width: 22, height: 22)).fill()
        NSColor(calibratedRed: 1, green: 0.69, blue: 0.30, alpha: 0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: 56, y: 56, width: 8, height: 8)).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}

func mediaSourceName(_ identifier: String?, title: String? = nil, artist: String? = nil) -> String {
    guard let identifier else { return "Media Player" }
    let id = identifier.lowercased()
    if id.hasPrefix("com.google.chrome.app.") { return "SoundCloud" }
    if id.contains("chrome") { return "Google Chrome" }
    if id.contains("safari") { return "Safari" }
    if id.contains("firefox") { return "Firefox" }
    if id.contains("vk") { return "VK Music" }
    if id.contains("soundcloud") { return "SoundCloud" }
    return identifier.components(separatedBy: ".").last?.capitalized ?? identifier
}
