import SwiftUI
import Foundation
import AppKit

private enum NotchTab: String, CaseIterable { case projects = "Projects", music = "Music", later = "More" }

struct NotchRootView: View {
    @ObservedObject var viewModel: ProjectsViewModel
    @ObservedObject var musicViewModel: MusicViewModel
    @ObservedObject var panelState: PanelState
    let notchRect: CGRect
    let notchRadius: CGFloat
    let onExpandedFrame: () -> Void
    let onContentHeightChange: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: NotchTab = .projects
    @State private var expandedContentHeight: CGFloat = 540
    @State private var contentMounted = false
    @State private var contentRevealed = false
    @Namespace private var tabNamespace

    var body: some View {
        let playing = musicViewModel.track?.playing == true
        let shape = NotchPanelShape(notchRect: notchRect, cornerRadius: notchRadius, progress: panelState.expansionProgress,
                                    idleMusic: playing ? 1 : 0, expandedHeight: expandedContentHeight)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if contentMounted {
                content
                    .padding(.top, notchRect.height + 10).padding(.horizontal, 14).padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(contentRevealed ? 1 : 0)
                    .blur(radius: contentRevealed ? 0 : 6)
                    .scaleEffect(contentRevealed ? 1 : 0.96, anchor: .top)
                    .animation(reduceMotion ? .linear(duration: 0) : .easeOut(duration: 0.20), value: contentRevealed)
                    .onAppear(perform: onExpandedFrame)
            }
            if panelState.expanded, let statusColor {
                NotchPanelOutline(notchRect: notchRect, cornerRadius: notchRadius, progress: panelState.expansionProgress,
                                  expandedHeight: expandedContentHeight)
                    .stroke(statusColor.opacity(0.72), style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
            }
            if !panelState.expanded, let track = musicViewModel.track, track.playing {
                IdleMusicMarker(track: track, notchRect: notchRect)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(shape)
        .background(Color.clear)
        .environment(\.locale, viewModel.activeLocale)
        .animation(reduceMotion ? .linear(duration: 0) : (panelState.isClosing ? .easeInOut(duration: 0.30) : .spring(response: 0.45, dampingFraction: 0.82)), value: panelState.expansionProgress)
        .animation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.45, dampingFraction: 0.82), value: expandedContentHeight)
        .animation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.38, dampingFraction: 0.86), value: playing)
        .onChange(of: panelState.expanded) { _, expanded in
            viewModel.setExpanded(expanded)
            if expanded {
                contentMounted = true
                contentRevealed = false
                DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.07)) {
                    guard panelState.expanded else { return }
                    contentRevealed = true
                }
            } else {
                contentRevealed = false
                DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.30)) {
                    if !panelState.expanded { contentMounted = false }
                }
            }
        }
        .onChange(of: musicViewModel.track?.playing) { _, playing in viewModel.setPlaying(playing == true) }
        .onChange(of: viewModel.collapseRequestID) { _, _ in
            withAnimation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.30)) {
                panelState.isClosing = true
                panelState.expansionProgress = 0
            }
        }
        .onChange(of: tab) { _, newTab in
            expandedContentHeight = newTab == .music ? 235 : 540
            onContentHeightChange(expandedContentHeight)
        }
        .alert(item: $viewModel.alert) { item in
            if item.requiresConfirmation {
                Alert(title: Text(item.title), message: Text(item.message),
                      primaryButton: .destructive(Text(item.confirmTitle), action: item.onConfirm),
                      secondaryButton: .cancel(Text("Cancel")))
            } else {
                Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text(item.confirmTitle), action: item.onConfirm))
            }
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                tabStrip
                Spacer(minLength: 0)
                if tab == .music {
                    if let track = musicViewModel.track {
                        Text(mediaSourceName(track.bundleIdentifier, title: track.title, artist: track.artist))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.orange)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                } else if tab == .projects {
                    PanelHeader(terminals: viewModel.terminals)
                }
            }
            if tab == .projects {
                QuotaSummary(limits: viewModel.rateLimits)
                if let error = viewModel.actionError {
                    Text(error).font(.system(size: 9)).foregroundStyle(.orange.opacity(0.9)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if viewModel.errorMessage != nil {
                    Text("Orca is unavailable")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            tabBody.frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases, id: \.self) { item in
                Button { selectTab(item) } label: {
                    Text(item.rawValue).font(.system(size: 12, weight: tab == item ? .semibold : .medium))
                        .foregroundStyle(tab == item ? Color.black : Color.white.opacity(0.58))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background {
                            if tab == item {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "active-tab", in: tabNamespace)
                            }
                        }
                }.buttonStyle(.plain).disabled(item == .later)
            }
        }.padding(3).background(Color.white.opacity(0.075), in: Capsule())
            .animation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.28, dampingFraction: 0.88), value: tab)
    }

    @ViewBuilder private var tabBody: some View {
        switch tab {
        case .projects: ProjectList(viewModel: viewModel).id(tab).transition(.opacity)
        case .music: MusicPlayerView(viewModel: musicViewModel).id(tab).transition(.opacity)
        case .later: EmptyMessage(title: "Coming soon", message: "This section will be available in a future version.").id(tab).transition(.opacity)
        }
    }

    private func selectTab(_ newTab: NotchTab) {
        guard tab != newTab else { return }
        withAnimation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.30, dampingFraction: 0.90)) {
            tab = newTab
        }
    }

    private var statusColor: Color? {
        guard !viewModel.terminals.isEmpty else { return nil }
        switch viewModel.aggregateState {
        case .working: return Color(red: 1, green: 0.72, blue: 0.24)
        case .ready: return Color(red: 0.25, green: 0.9, blue: 0.55)
        case .error: return Color(red: 1, green: 0.28, blue: 0.3)
        case .waiting, .none: return nil
        }
    }
}

private struct MusicPlayerView: View {
    @ObservedObject var viewModel: MusicViewModel
    private let accent = Color(red: 1, green: 0.60, blue: 0.02)
    var body: some View {
        Group {
            if let track = viewModel.track {
                VStack(spacing: 7) {
                    HStack(spacing: 12) {
                        artwork(track, size: 60)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text(track.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        Button(action: viewModel.toggle) {
                            Image(systemName: track.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                                .frame(width: 40, height: 40).background(Color.white, in: Circle())
                        }.buttonStyle(.plain).help(track.playing ? "Pause" : "Play")
                    }
                    if track.playing {
                        TimelineView(.periodic(from: .now, by: 1)) { context in progress(track, at: context.date) }
                    } else { progress(track, at: Date()) }
                    HStack(spacing: 10) {
                        VolumeControl().frame(width: 128)
                        Spacer()
                        Button(action: viewModel.previous) { Image(systemName: "backward.end.fill") }
                        Button(action: viewModel.next) { Image(systemName: "forward.end.fill") }
                    }.font(.system(size: 12, weight: .semibold)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.82))
                }
                .padding(12).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No music detected").font(.system(size: 13)).foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
            }
        }
    }
    private func artwork(_ track: MusicTrack, size: CGFloat) -> some View {
        Group {
            if let data = track.artwork, let image = ArtworkImageCache.image(for: data) { Image(nsImage: image).resizable().scaledToFill() }
            else { ZStack { Color.white.opacity(0.05); Image(systemName: "music.note").font(.system(size: 25)).foregroundStyle(accent.opacity(0.75)) } }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func progress(_ track: MusicTrack, at date: Date) -> some View {
        let current = track.currentTime(at: date)
        return HStack(spacing: 7) {
            Text(clock(current))
            ProgressSlider(value: Binding(get: { current }, set: { seek($0) }), range: 0...max(1, track.duration), color: accent)
                .frame(height: 14).disabled(track.duration <= 0)
            Text(clock(track.duration))
        }.font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.58))
    }
    private func clock(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
    private func seek(_ value: Double) { viewModel.seek(value) }
}

private struct ProgressSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = min(1, max(0, (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16)).frame(height: 4)
                Capsule().fill(color).frame(width: width * fraction, height: 4)
                Circle().fill(.white).frame(width: 9, height: 9).offset(x: max(0, width * fraction - 4.5))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                guard width > 0 else { return }
                let fraction = min(1, max(0, event.location.x / width))
                value = range.lowerBound + (range.upperBound - range.lowerBound) * fraction
            })
        }
    }
}

private struct VolumeControl: View {
    @State private var volume: Double = 0.5
    @State private var isEditing = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "headphones").font(.system(size: 13)).foregroundStyle(.white.opacity(0.68))
            Slider(value: $volume, in: 0...1) { editing in
                isEditing = editing
                if !editing { setSystemVolume(Int((volume * 100).rounded())) }
            }.tint(.white.opacity(0.8))
        }
        .task {
            while !Task.isCancelled {
                if let value = await readSystemVolume() {
                    if !isEditing { volume = Double(value) / 100 }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func readSystemVolume() async -> Int? {
        await Task.detached(priority: .utility) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "output volume of (get volume settings)"]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }

    private func setSystemVolume(_ value: Int) {
        Task.detached(priority: .utility) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "set volume output volume \(min(100, max(0, value)))"]
            process.standardOutput = Pipe(); process.standardError = Pipe(); try? process.run()
        }
    }
}

private struct IdleMusicMarker: View {
    let track: MusicTrack
    let notchRect: CGRect
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let data = track.artwork, let image = ArtworkImageCache.image(for: data) { Image(nsImage: image).resizable().scaledToFill() }
                else { Image(systemName: "music.note").foregroundStyle(.orange) }
            }
            .frame(width: 18, height: 18).clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
            .offset(x: notchRect.minX - 26, y: 9)
            ArtworkEqualizer(color: artworkAccent(track.artwork))
                .frame(width: 18, height: 18).offset(x: notchRect.maxX + 8, y: 9)
        }
    }
}

private enum ArtworkImageCache {
    private static let images = NSCache<NSData, NSImage>()
    static func image(for data: Data) -> NSImage? {
        let key = data as NSData
        if let image = images.object(forKey: key) { return image }
        guard let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}

private struct ArtworkEqualizer: NSViewRepresentable {
    let color: Color
    func makeNSView(context: Context) -> EqualizerLayerView { EqualizerLayerView(color: NSColor(color).cgColor) }
    func updateNSView(_ view: EqualizerLayerView, context: Context) { view.setColor(NSColor(color).cgColor) }
}

private final class EqualizerLayerView: NSView {
    private var bars: [CALayer] = []
    private var barColor: CGColor

    init(color: CGColor) {
        barColor = color
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    func setColor(_ color: CGColor) {
        barColor = color
        bars.forEach { $0.backgroundColor = color }
    }

    override func layout() {
        super.layout()
        guard let root = layer else { return }
        if bars.isEmpty {
            for index in 0..<3 {
                let bar = CALayer()
                bar.backgroundColor = barColor
                bar.cornerRadius = 1.25
                root.addSublayer(bar)
                bars.append(bar)
                let animation = CABasicAnimation(keyPath: "transform.scale.y")
                animation.fromValue = 0.35
                animation.toValue = 1.0
                animation.duration = 0.48 + Double(index) * 0.13
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.beginTime = CACurrentMediaTime() + Double(index) * 0.11
                bar.add(animation, forKey: "bar-pulse")
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let height: CGFloat = [10, 14, 8][index]
            bar.bounds = CGRect(x: 0, y: 0, width: 2.5, height: height)
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.position = CGPoint(x: 2.5 + CGFloat(index) * 4.5, y: bounds.midY)
        }
        CATransaction.commit()
    }
}

private func artworkAccent(_ data: Data?) -> Color {
    guard let data, let image = ArtworkImageCache.image(for: data),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let bytes = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(bytes) else {
        return Color(red: 1, green: 0.34, blue: 0)
    }
    let count = cg.width * cg.height
    guard count > 0 else { return .orange }
    let step = max(1, count / 256)
    var r = 0.0, g = 0.0, b = 0.0, samples = 0.0
    for pixel in stride(from: 0, to: count, by: step) {
        let index = pixel * 4
        r += Double(ptr[index]); g += Double(ptr[index + 1]); b += Double(ptr[index + 2]); samples += 1
    }
    let average = [r, g, b].map { $0 / (samples * 255) }
    let peak = max(average[0], average[1], average[2])
    let lift = peak < 0.50 ? min(2.2, 0.50 / max(peak, 0.001)) : 1
    return Color(red: min(1, average[0] * lift), green: min(1, average[1] * lift), blue: min(1, average[2] * lift))
}

private struct PanelHeader: View {
    let terminals: [OrcaTerminal]
    private var working: Int { terminals.filter { $0.state == .working }.count }
    private var waiting: Int { terminals.filter { $0.state == .waiting }.count }
    private var errors: Int { terminals.filter { $0.state == .error }.count }

    var body: some View {
        HStack(spacing: 9) {
            SummaryCount(value: working, color: .working, label: working == 1 ? "working" : "working")
            SummaryCount(value: waiting, color: .waiting, label: "waiting")
            SummaryCount(value: errors, color: errors == 0 ? .ready : .error, label: "errors")
        }
        .fixedSize()
    }
}

private struct QuotaSummary: View {
    let limits: RateLimitSnapshot
    var body: some View {
        HStack(spacing: 7) {
            ForEach(limits.providers.keys.sorted(), id: \.self) { key in
                quotaPill(key.capitalized, limits.providers[key]!, compact: limits.providers.count > 1)
            }
        }
    }
    private func quotaPill(_ provider: String, _ limits: ProviderRateLimits, compact: Bool) -> some View {
        let session = limits.session?.usedPercent
        let weekly = limits.weekly?.usedPercent
        let tone = provider.lowercased() == "claude" ? Color(red: 0.96, green: 0.62, blue: 0.04) : Color(red: 0.06, green: 0.64, blue: 0.50)
        return HStack(spacing: 5) {
            Text(provider).fontWeight(.semibold).foregroundStyle(tone).lineLimit(1).minimumScaleFactor(0.78)
            if compact, let session, let weekly {
                Text("\(session)% · \(weekly)%").foregroundStyle(.white.opacity(0.78)).lineLimit(1).minimumScaleFactor(0.78)
            } else if let session, let weekly {
                Text("\(session)% · \(weekly)%").foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(tone).frame(width: proxy.size.width * CGFloat(session) / 100)
                    }
                }.frame(width: 24, height: 4)
                Text(AppText.format("Resets %@", resetLabel(limits.session)))
                    .foregroundStyle(.white.opacity(0.52)).lineLimit(1)
            } else if let session {
                Text("\(session)% · session").foregroundStyle(.white.opacity(0.78)).lineLimit(1)
            } else if let weekly {
                Text("\(weekly)% · weekly").foregroundStyle(.white.opacity(0.78)).lineLimit(1)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(tone.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
    private func resetLabel(_ window: UsageWindow?) -> String {
        guard let date = window?.resetsAt else { return window?.resetDescription ?? AppText.value("Unknown") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct SummaryCount: View {
    enum Tone { case working, waiting, ready, error }
    let value: Int
    let color: Tone
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(colorValue).frame(width: 5, height: 5)
            Text("\(value) \(label)").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        }
    }
    private var colorValue: Color {
        switch color {
        case .working: Color(red: 1, green: 0.72, blue: 0.24)
        case .waiting: Color.white.opacity(0.4)
        case .ready: Color(red: 0.25, green: 0.9, blue: 0.55)
        case .error: Color(red: 1, green: 0.28, blue: 0.3)
        }
    }
}

private struct AgentAvatar: View {
    let agent: OrcaTerminal.Agent
    private var symbol: String {
        switch agent {
        case .claude: "sparkle"
        case .codex: "square.stack.3d.up.fill"
        case .hermes: "bolt.fill"
        case .antigravity: "circle.fill"
        case .unknown: "terminal.fill"
        }
    }
    private var tint: Color {
        switch agent {
        case .claude: Color(red: 1, green: 0.55, blue: 0.18)
        case .codex: Color(red: 0.18, green: 0.78, blue: 0.51)
        case .hermes: Color(red: 0.30, green: 0.68, blue: 1)
        case .antigravity: Color(red: 0.30, green: 0.64, blue: 1)
        case .unknown: Color(red: 0.52, green: 0.65, blue: 0.80)
        }
    }
    var body: some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 22, height: 22).background(tint.opacity(0.19), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct ProjectList: View {
    @ObservedObject var viewModel: ProjectsViewModel
    var body: some View {
        Group {
            if viewModel.loading {
                HStack(spacing: 9) { ProgressView().controlSize(.small).tint(.white.opacity(0.7)); Text("Connecting to Orca…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.62)) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.terminals.isEmpty && viewModel.externalSessions.isEmpty {
                EmptyMessage(title: viewModel.errorMessage == nil ? "No active agents" : "No active agents", message: viewModel.errorMessage == nil ? "Start an agent in Orca to see it here." : "Orca is unavailable. Open Orca to see its terminals.")
            } else {
                terminalList
            }
        }
    }

    private var terminalList: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                let hiddenIDs = hiddenTerminalIDs
                let viewportFrame = viewport.frame(in: .global)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !viewModel.externalSessions.isEmpty {
                            ExternalSessionsSection(sessions: viewModel.externalSessions)
                        }
                        if viewModel.workspaces.isEmpty {
                            EmptyMessage(title: "No Orca terminals", message: "Showing sessions running outside Orca.")
                                .frame(height: 74)
                        }
                ForEach(viewModel.workspaces) { workspace in
                            WorkspaceSection(workspace: workspace, viewModel: viewModel)
                        }
                        if viewModel.errorMessage != nil {
                            Text("Orca is unavailable").font(.system(size: 9)).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
                        }
                    }
                    .padding(.bottom, 10)
                }
                .coordinateSpace(name: "terminal-scroll")
                .onAppear {
                    viewportMinY = viewportFrame.minY
                    viewportHeight = viewportFrame.height
                }
                .onChange(of: viewportFrame) { _, frame in
                    viewportMinY = frame.minY
                    viewportHeight = frame.height
                }
                .onPreferenceChange(VisibleTerminalFramesKey.self) { frames in
                    if rowFrames != frames { rowFrames = frames }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let nextID = hiddenIDs.first {
                        Button {
                            withAnimation(.easeInOut(duration: 0.28)) {
                                proxy.scrollTo(nextID, anchor: .top)
                            }
                        } label: {
                            Text("Show \(hiddenIDs.count) more terminals ↓")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.82))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Color.black, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                                .shadow(color: .black.opacity(0.65), radius: 5, y: 1)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 3)
                        .padding(.trailing, 2)
                        .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: hiddenIDs.count)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @State private var rowFrames: [String: CGRect] = [:]
    @State private var viewportHeight: CGFloat = 0
    @State private var viewportMinY: CGFloat = 0
    private var hiddenTerminalIDs: [String] {
        TerminalScrollMetrics.hiddenBelowViewportIDs(
            orderedIDs: viewModel.workspaces.flatMap(\.terminals).map(\.id),
            frames: rowFrames,
            viewportHeight: viewportHeight,
            viewportMinY: viewportMinY
        )
    }
}

private struct ExternalSessionsSection: View {
    let sessions: [ExternalSession]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square.fill").font(.system(size: 10)).foregroundStyle(.orange.opacity(0.85))
                Text("OUTSIDE ORCA").font(.system(size: 10, weight: .bold)).tracking(0.55).foregroundStyle(.white.opacity(0.76))
                Spacer()
                Text("\(sessions.count)").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.43))
            }
            ForEach(sessions) { session in ExternalSessionRow(session: session) }
        }
        .padding(.top, 3)
    }
}

private struct ExternalSessionRow: View {
    let session: ExternalSession
    private var tint: Color { session.state == .working ? Color(red: 1, green: 0.72, blue: 0.24) : Color(red: 0.48, green: 0.62, blue: 0.76) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                AgentAvatar(agent: session.agent == .claude ? .claude : .codex)
                Text(session.agent.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
                Text(session.projectName).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                Spacer(minLength: 2)
                Label(session.state.label, systemImage: session.state == .working ? "circle.fill" : "pause.fill")
                    .font(.system(size: 9, weight: .bold)).tracking(0.25).foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(tint.opacity(0.14), in: Capsule())
            }
            HStack(spacing: 6) {
                Button(action: activateParent) {
                    Group {
                        if let app = session.parentPID.flatMap({ NSRunningApplication(processIdentifier: $0) }), let icon = app.icon {
                            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 15, height: 15)
                        } else { Image(systemName: "terminal.fill").font(.system(size: 11)).frame(width: 15, height: 15) }
                    }
                    .foregroundStyle(.white.opacity(0.76)).frame(width: 21, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Switch to \(session.parentName)")
                Text("\(session.parentName) · PID \(session.pid) · \(session.cwd)")
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 2)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(activityAge(session.lastActivityAt, now: context.date)).lineLimit(1)
                }
            }
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.56))
        }
        .padding(.leading, 11).padding(.trailing, 8).padding(.vertical, 7)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) { tint.frame(width: 3).padding(.vertical, 2).clipShape(Capsule()) }
    }
    private func activateParent() {
        guard let pid = session.parentPID, let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: [.activateAllWindows])
    }
    private func activityAge(_ date: Date?, now: Date) -> String {
        guard let date else { return AppText.value("No log") }
        let mins = max(0, Int(now.timeIntervalSince(date) / 60))
        return mins == 0 ? AppText.value("Now") : AppText.format("%lld min ago", mins)
    }
}

private struct WorkspaceSection: View {
    let workspace: OrcaWorkspace
    @ObservedObject var viewModel: ProjectsViewModel
    private let agents: [OrcaTerminal.Agent] = [.claude, .codex, .antigravity, .hermes]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if viewModel.showsWorkspaceGroups { HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                Text(workspace.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                Spacer(minLength: 2)
                Menu {
                    ForEach(agents, id: \.self) { agent in
                        Button("Launch \(agent.label)") { viewModel.launch(agent: agent, workspace: workspace) }
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5)).frame(width: 26, height: 22).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).help("Launch agent in workspace")
            } }
            ForEach(workspace.terminals) { terminal in
                TerminalRow(terminal: terminal, focus: { viewModel.focus(terminal) })
                    .id(terminal.id)
            }
        }
    }
}

private struct TerminalRow: View {
    let terminal: OrcaTerminal
    let focus: () -> Void
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: focus) {
                    HStack(spacing: 5) {
                        AgentAvatar(agent: terminal.agent)
                        Text(terminal.displayAgentLabel).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
                        if let model = terminal.model {
                            Text(model).font(.system(size: 11)).foregroundStyle(.white.opacity(0.57)).lineLimit(1)
                        }
                        Text("·").foregroundStyle(.white.opacity(0.34))
                        Text(terminal.workspaceName).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.76)).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(terminal.displayAgentLabel), \(terminal.displayTitle) in Orca")
                Label(terminal.state.label.uppercased(), systemImage: stateSymbol)
                    .font(.system(size: 9, weight: .bold)).tracking(0.25)
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(stateColor.opacity(0.14), in: Capsule())
            }
            let preview = terminal.previewLines
            VStack(alignment: .leading, spacing: 1) {
                if preview.isEmpty {
                    Text("No recent output")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.52)).lineLimit(1)
                } else {
                    ForEach(Array(preview.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.72)).lineLimit(1).truncationMode(.head)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 7) {
                Text(terminal.id).lineLimit(1).truncationMode(.middle)
                if let dispatch = terminal.dispatch {
                    Text("· Dispatch \(dispatch.dispatchID)").lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 2)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(activityAge(terminal.lastOutputAt, now: context.date)).lineLimit(1)
                }
                Button { withAnimation(.easeOut(duration: 0.16)) { showsDetails.toggle() } } label: {
                    Image(systemName: showsDetails ? "chevron.up" : "info.circle")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.62)).frame(width: 22, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Terminal details")
                Button(action: focus) {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 10)).foregroundStyle(.white.opacity(0.78)).frame(width: 22, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Activate Orca and focus terminal")
            }
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.56))
            if showsDetails {
                detailView.padding(.top, 2)
            }
        }
        .padding(.leading, 11).padding(.trailing, 8).padding(.vertical, 6)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) { stateColor.frame(width: 3).padding(.vertical, 2).clipShape(Capsule()) }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: VisibleTerminalFramesKey.self, value: [terminal.id: proxy.frame(in: .global)])
        })
    }

    @ViewBuilder private var detailView: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let branch = terminal.branch { DetailLine(label: "Branch", value: branch.split(separator: "/").last.map(String.init) ?? branch) }
            DetailLine(label: "Path", value: terminal.workspacePath)
            if let reason = terminal.errorReason { DetailLine(label: "Reason", value: reason) }
            if let dispatch = terminal.dispatch {
                DetailLine(label: "Dispatch", value: "\(dispatch.taskID) · \(dispatch.status)")
                if let reason = dispatch.reason { DetailLine(label: "Reason", value: reason) }
                if let summary = dispatch.summary, !summary.isEmpty { Text(summary).font(.system(size: 9)).foregroundStyle(.white.opacity(0.58)).lineLimit(2) }
            }
        }
    }

    private var stateColor: Color {
        switch terminal.state {
        case .working: Color(red: 1, green: 0.72, blue: 0.24)
        case .ready: Color(red: 0.25, green: 0.9, blue: 0.55)
        case .error: Color(red: 1, green: 0.28, blue: 0.3)
        case .waiting: Color(red: 0.48, green: 0.62, blue: 0.76)
        }
    }

    private var stateSymbol: String {
        switch terminal.state {
        case .working: "circle.fill"
        case .ready: "checkmark"
        case .waiting: "pause.fill"
        case .error: "exclamationmark"
        }
    }

    private func activityAge(_ date: Date?, now: Date) -> String {
        guard let date else { return AppText.value("Time unknown") }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return minutes == 0 ? AppText.value("Just now") : AppText.format("%lld min ago", minutes)
    }
}

private struct DetailLine: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label).foregroundStyle(.white.opacity(0.38))
            Text(value).foregroundStyle(.white.opacity(0.62)).lineLimit(1).truncationMode(.middle)
        }.font(.system(size: 9, design: .monospaced))
    }
}

private struct EmptyMessage: View {
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.82))
            Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineSpacing(2).textSelection(.enabled)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

final class PanelState: ObservableObject {
    @Published var expansionProgress: CGFloat = 0
    @Published var isClosing = false
    var expanded: Bool { expansionProgress > 0.01 }
}

private struct VisibleTerminalFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

protocol MusicSource {
    var title: String? { get }
    var artist: String? { get }
    var artwork: NSImage? { get }
    var isPlaying: Bool { get }
    func play()
    func pause()
    func next()
    func prev()
}

struct NotchPanelShape: Shape {
    var notchRect: CGRect
    var cornerRadius: CGFloat
    var progress: CGFloat
    var idleMusic: CGFloat = 0
    var expandedHeight: CGFloat = 560

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(progress, AnimatablePair(idleMusic, expandedHeight)) }
        set { progress = newValue.first; idleMusic = newValue.second.first; expandedHeight = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        Self.path(in: rect, notchRect: notchRect, cornerRadius: cornerRadius, progress: progress,
                  idleMusic: idleMusic, expandedHeight: expandedHeight)
    }

    static func path(in rect: CGRect, notchRect: CGRect, cornerRadius: CGFloat, progress: CGFloat,
                     idleMusic: CGFloat = 0, expandedHeight: CGFloat = 560) -> Path {
        let t = min(1, max(0, progress))
        let idle = min(1, max(0, idleMusic)) * (1 - t)
        let idleShoulder = max(0, 64 - notchRect.height / 2)
        let left = notchRect.minX + (notchRect.minX - idleShoulder - notchRect.minX) * idle + (9 - notchRect.minX) * t
        let right = notchRect.maxX + (notchRect.maxX + idleShoulder - notchRect.maxX) * idle + ((rect.maxX - 9) - notchRect.maxX) * t
        let bottom = notchRect.maxY + 2 * idle + (min(rect.maxY, expandedHeight) - notchRect.maxY) * t
        let upperRadius = (notchRect.height / 2) * idle + 9 * t
        let outerLeft = left - upperRadius
        let outerRight = right + upperRadius
        let lowerRadius = cornerRadius + (14 - cornerRadius) * idle + (28 - cornerRadius) * t
        var path = Path()
        path.move(to: CGPoint(x: outerLeft, y: 0))
        path.addLine(to: CGPoint(x: outerRight, y: 0))
        path.addCurve(to: CGPoint(x: right, y: upperRadius),
                      control1: CGPoint(x: outerRight - upperRadius * 0.5523, y: 0),
                      control2: CGPoint(x: right, y: upperRadius * 0.4477))
        path.addLine(to: CGPoint(x: right, y: bottom - lowerRadius))
        path.addQuadCurve(to: CGPoint(x: right - lowerRadius, y: bottom),
                          control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + lowerRadius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - lowerRadius),
                          control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: upperRadius))
        path.addCurve(to: CGPoint(x: outerLeft, y: 0),
                      control1: CGPoint(x: left, y: upperRadius * 0.4477),
                      control2: CGPoint(x: outerLeft + upperRadius * 0.5523, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct NotchPanelOutline: Shape {
    var notchRect: CGRect
    var cornerRadius: CGFloat
    var progress: CGFloat
    var expandedHeight: CGFloat = 560

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, expandedHeight) }
        set { progress = newValue.first; expandedHeight = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(1, max(0, progress))
        let left = notchRect.minX + (9 - notchRect.minX) * t
        let right = notchRect.maxX + ((rect.maxX - 9) - notchRect.maxX) * t
        let bottom = notchRect.maxY + (min(rect.maxY, expandedHeight) - notchRect.maxY) * t
        let upperRadius = 9 * t
        let lowerRadius = cornerRadius + (28 - cornerRadius) * t
        var path = Path()
        path.move(to: CGPoint(x: left, y: upperRadius))
        path.addLine(to: CGPoint(x: left, y: bottom - lowerRadius))
        path.addQuadCurve(to: CGPoint(x: left + lowerRadius, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right - lowerRadius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom - lowerRadius), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: upperRadius))
        return path
    }
}
