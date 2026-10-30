import AppKit
import SwiftUI
import QuartzCore
import OSLog

private final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class NotchPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let viewModel = ProjectsViewModel()
    private let musicViewModel = MusicViewModel()
    private let panelState = PanelState()
    private var collapseWork: DispatchWorkItem?
    private var expandWork: DispatchWorkItem?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private var expansionStartedAt: CFTimeInterval?
    private var frameDisplayLink: CADisplayLink?
    private var frameTimestamps: [CFTimeInterval] = []
    private var visibleExpandedHeight: CGFloat = 540
    private var notchHoverStartedAt: CFTimeInterval?
    private var lastIgnoredPointer: CGPoint?
    private let logger = Logger(subsystem: AppBrand.bundleIdentifier, category: "panel")
    private var screenFrame = CGRect.zero
    private var notchScreenRect = CGRect.zero
    private var notchRect = CGRect.zero
    private var expandedSize = CGSize(width: 490, height: 540)
    private let shoulderRadius: CGFloat = 9
    private var notchDwell: TimeInterval = 0.12
    private let collapseDelay: TimeInterval = 0.20
    private var windowSize: CGSize { CGSize(width: expandedSize.width + shoulderRadius * 2, height: expandedSize.height) }
    private var notchRadius: CGFloat = 7
    func reloadSettings() {
        viewModel.reloadSettings()
        musicViewModel.reloadSettings()
        notchDwell = AppSettings.load().hoverDelay
    }

    func start() {
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.rebuildForDisplayChange() }
            }
        }
        if sleepObserver == nil {
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.viewModel.setScreenAwake(false) } }
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.viewModel.setScreenAwake(true) } }
            lockObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.viewModel.setLocked(true) } }
            unlockObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.viewModel.setLocked(false) } }
            NotificationCenter.default.addObserver(forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.viewModel.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled) } }
        }
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let geometry = NotchGeometry.resolve(
                screenFrame: screen.frame,
                safeAreaTop: screen.safeAreaInsets.top,
                leftArea: screen.auxiliaryTopLeftArea,
                rightArea: screen.auxiliaryTopRightArea
              ) else { return }

        screenFrame = screen.frame
        visibleExpandedHeight = 540
        notchScreenRect = geometry.frame
        notchRect = CGRect(
            x: geometry.frame.minX - (screen.frame.midX - windowSize.width / 2),
            y: 0,
            width: geometry.frame.width,
            height: geometry.frame.height
        )
        notchRadius = min(geometry.frame.height / 2, 8)
        expandedSize = CGSize(width: min(490, screen.frame.width - 42), height: min(540, screen.frame.height - 40))
        notchRect.origin.x = windowSize.width / 2 - geometry.frame.width / 2

        let root = NotchRootView(
            viewModel: viewModel,
            musicViewModel: musicViewModel,
            panelState: panelState,
            notchRect: notchRect,
            notchRadius: notchRadius,
            onExpandedFrame: { [weak self] in self?.logExpandedFrameReady() },
            onContentHeightChange: { [weak self] height in self?.visibleExpandedHeight = height }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: windowSize)

        let frame = CGRect(
            x: screen.frame.midX - windowSize.width / 2,
            y: screen.frame.maxY - expandedSize.height,
            width: windowSize.width,
            height: expandedSize.height
        )
        let created = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        created.setFrame(frame, display: true)
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        created.hidesOnDeactivate = false
        created.isFloatingPanel = true
        created.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        created.becomesKeyOnlyIfNeeded = true
        created.contentView = hosting
        created.delegate = self
        created.ignoresMouseEvents = true
        created.orderFrontRegardless()
        // NSPanel may initially honor the menu bar's visible frame; pin the
        // fixed-size panel to the physical screen top after it is ordered.
        created.setFrame(frame, display: true, animate: false)
        panel = created

        viewModel.start()
        musicViewModel.start()
        notchDwell = AppSettings.load().hoverDelay
        viewModel.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled)
        installPointerMonitors()
    }

    private func installPointerMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.updatePointerPresence() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            Task { @MainActor in self?.updatePointerPresence() }
            return event
        }
    }

    private func updatePointerPresence() {
        guard let panel else { return }
        let pointer = NSEvent.mouseLocation
        if !panelState.expanded {
            panel.ignoresMouseEvents = true
            guard isRestingHoverTarget(pointer) else {
                expandWork?.cancel()
                expandWork = nil
                notchHoverStartedAt = nil
                let nearCutout = notchScreenRect.insetBy(dx: -35, dy: -35).contains(pointer)
                if nearCutout, lastIgnoredPointer != pointer {
                    logPointerTransition("expand_ignored", point: pointer, extra: "outside_cutout")
                    lastIgnoredPointer = pointer
                }
                return
            }
            lastIgnoredPointer = nil
            guard expandWork == nil else { return }
            let enteredAt = CACurrentMediaTime()
            notchHoverStartedAt = enteredAt
            let work = DispatchWorkItem { [weak self] in
                guard let self, let panel = self.panel else { return }
                let current = NSEvent.mouseLocation
                guard self.isRestingHoverTarget(current) else {
                    self.notchHoverStartedAt = nil
                    self.expandWork = nil
                    return
                }
                let heldMilliseconds = (CACurrentMediaTime() - enteredAt) * 1_000
                self.notchHoverStartedAt = nil
                self.expandWork = nil
                self.expansionStartedAt = CACurrentMediaTime()
                self.panelState.isClosing = false
                panel.ignoresMouseEvents = false
                self.startFrameMeasurement()
                self.panelState.expansionProgress = 1
                self.viewModel.setExpanded(true)
                self.logPointerTransition("expand_trigger", point: current, extra: "hold_ms=\(String(format: "%.1f", heldMilliseconds))")
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + notchDwell, execute: work)
            return
        }

        let local = CGPoint(x: pointer.x - panel.frame.minX, y: panel.frame.maxY - pointer.y)
        let bounds = CGRect(origin: .zero, size: windowSize)
        let isInsideShape = NotchPanelShape.path(
            in: bounds,
            notchRect: notchRect,
            cornerRadius: notchRadius,
            progress: panelState.expansionProgress,
            idleMusic: musicViewModel.track?.playing == true ? 1 : 0,
            expandedHeight: visibleExpandedHeight
        ).contains(local)

        if isInsideShape {
            panel.ignoresMouseEvents = false
            collapseWork?.cancel()
            collapseWork = nil
        } else {
            panel.ignoresMouseEvents = true
            scheduleCollapse(at: pointer)
        }
    }

    private func scheduleCollapse(at pointer: CGPoint) {
        guard panelState.expanded, collapseWork == nil else { return }
        let scheduledAt = CACurrentMediaTime()
        logPointerTransition("collapse_trigger", point: pointer, extra: "delay_ms=200")
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let current = NSEvent.mouseLocation
            guard let panel = self.panel else { return }
            let local = CGPoint(x: current.x - panel.frame.minX, y: panel.frame.maxY - current.y)
            let bounds = CGRect(origin: .zero, size: self.windowSize)
            let stillInside = NotchPanelShape.path(in: bounds, notchRect: self.notchRect,
                                                   cornerRadius: self.notchRadius,
                                                   progress: self.panelState.expansionProgress,
                                                   idleMusic: self.musicViewModel.track?.playing == true ? 1 : 0,
                                                   expandedHeight: self.visibleExpandedHeight).contains(local)
            guard !stillInside else {
                panel.ignoresMouseEvents = false
                self.collapseWork = nil
                return
            }
            self.panelState.isClosing = true
            if let link = self.frameDisplayLink { self.finishFrameMeasurement(link) }
            self.panelState.expansionProgress = 0
            self.viewModel.setExpanded(false)
            self.expansionStartedAt = nil
            self.notchHoverStartedAt = nil
            panel.ignoresMouseEvents = true
            self.collapseWork = nil
            let elapsed = (CACurrentMediaTime() - scheduledAt) * 1_000
            self.logPointerTransition("collapse_complete", point: current, extra: "outside_ms=\(String(format: "%.1f", elapsed))")
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
    }

    private func startFrameMeasurement() {
        guard ProcessInfo.processInfo.environment["NOTCH_CURTAIN_FRAME_LOG"] == "1" else { return }
        frameDisplayLink?.invalidate()
        frameTimestamps.removeAll(keepingCapacity: true)
        guard let view = panel?.contentView else { return }
        let link = view.displayLink(target: self, selector: #selector(recordDisplayFrame(_:)))
        frameDisplayLink = link
        link.add(to: .main, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self, weak link] in
            guard let self, let link, self.frameDisplayLink === link else { return }
            self.finishFrameMeasurement(link)
        }
    }

    @objc private func recordDisplayFrame(_ link: CADisplayLink) {
        frameTimestamps.append(CACurrentMediaTime())
    }

    private func logFrameMeasurement(_ detail: String) {
        logger.info("expand_frame_intervals \(detail, privacy: .public)")
        appendLog("Notch expand_frame_intervals \(detail)")
    }

    private func finishFrameMeasurement(_ link: CADisplayLink) {
        guard frameDisplayLink === link else { return }
        link.invalidate()
        frameDisplayLink = nil
        let intervals = zip(frameTimestamps, frameTimestamps.dropFirst()).map { ($1 - $0) * 1_000 }
        guard let minValue = intervals.min(), let maxValue = intervals.max(), !intervals.isEmpty else {
            logFrameMeasurement("frames=0 (display link produced no samples)")
            return
        }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        logFrameMeasurement("frames=\(intervals.count) interval_ms min=\(String(format: "%.2f", minValue)) avg=\(String(format: "%.2f", average)) max=\(String(format: "%.2f", maxValue))")
    }

    private func isRestingHoverTarget(_ point: CGPoint) -> Bool {
        if NotchGeometry(frame: notchScreenRect).containsCursor(point) { return true }
        guard musicViewModel.track?.playing == true else { return false }
        var capsuleFrame = notchScreenRect.insetBy(dx: -64, dy: 0)
        capsuleFrame.size.height += 2
        return capsuleFrame.contains(point)
    }

    private func logPointerTransition(_ name: String, point: CGPoint, extra: String) {
        let line = "Notch \(name) x=\(String(format: "%.1f", point.x)) y=\(String(format: "%.1f", point.y)) \(extra)\n"
        logger.info("\(line, privacy: .public)")
        appendLog(line.trimmingCharacters(in: .newlines))
    }

    private func appendLog(_ line: String) {
        let url = AppBrand.logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) {
            file.seekToEndOfFile()
            file.write(Data(line.utf8))
            try? file.close()
        }
    }

    private func logExpandedFrameReady() {
        guard let startedAt = expansionStartedAt else { return }
        let elapsed = (CACurrentMediaTime() - startedAt) * 1_000
        expansionStartedAt = nil
        logger.info("expand_first_frame_ms=\(elapsed, privacy: .public)")
        let line = "Notch expand_first_frame_ms=\(String(format: "%.1f", elapsed))\n"
        let logURL = AppBrand.logURL
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let file = try? FileHandle(forWritingTo: logURL) {
            file.seekToEndOfFile()
            file.write(Data(line.utf8))
            try? file.close()
        }
    }

    private func rebuildForDisplayChange() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        viewModel.stop()
        expandWork?.cancel()
        expandWork = nil
        panel?.close()
        panel = nil
        panelState.expansionProgress = 0
        expansionStartedAt = nil
        start()
    }

    func windowDidResignKey(_ notification: Notification) { updatePointerPresence() }

    func stop() {
        viewModel.stop()
        musicViewModel.stop()
        if let frameDisplayLink { frameDisplayLink.invalidate() }
        if let panel { panel.close() }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }
        if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }
        frameDisplayLink?.invalidate()
    }
}
