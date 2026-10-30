import Testing
import CoreGraphics
@testable import NotchCurtain

@Test func computesCutoutBetweenAuxiliaryMenuAreas() {
    let geometry = NotchGeometry.resolve(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 37,
        leftArea: CGRect(x: 0, y: 945, width: 640, height: 37),
        rightArea: CGRect(x: 872, y: 945, width: 640, height: 37)
    )
    #expect(geometry?.frame == CGRect(x: 640, y: 945, width: 232, height: 37))
}

@Test func notchHitTestUsesOnlyPhysicalCutoutBounds() {
    let geometry = NotchGeometry(frame: CGRect(x: 640, y: 945, width: 232, height: 37))
    #expect(geometry.containsCursor(CGPoint(x: 756, y: 963)))
    #expect(!geometry.containsCursor(CGPoint(x: 620, y: 963)))
    #expect(!geometry.containsCursor(CGPoint(x: 892, y: 963)))
    #expect(!geometry.containsCursor(CGPoint(x: 756, y: 940)))
}

@Test func rejectsScreensWithoutNotchGeometry() {
    #expect(NotchGeometry.resolve(screenFrame: .zero, safeAreaTop: 0, leftArea: nil, rightArea: nil) == nil)
}

@Test func expandedNotchShapeIncludesNinePointFlareAndCollapsedShapeMatchesCutout() {
    let window = CGRect(x: 0, y: 0, width: 698, height: 560)
    let cutout = CGRect(x: 244.5, y: 0, width: 209, height: 38)
    let expanded = NotchPanelShape.path(in: window, notchRect: cutout, cornerRadius: 8, progress: 1).boundingRect
    let collapsed = NotchPanelShape.path(in: window, notchRect: cutout, cornerRadius: 8, progress: 0).boundingRect
    #expect(expanded.minX == 0)
    #expect(expanded.maxX == 698)
    #expect(expanded.minY == 0)
    #expect(expanded.maxY == 560)
    #expect(collapsed.minX == cutout.minX)
    #expect(collapsed.maxX == cutout.maxX)
    #expect(collapsed.maxY == cutout.maxY)
}

@Test func playingIdleCapsuleWidensCutoutBySixtyFourPointsEachSideAndTwoPointsDown() {
    let window = CGRect(x: 0, y: 0, width: 698, height: 560)
    let cutout = CGRect(x: 244.5, y: 0, width: 209, height: 38)
    let capsule = NotchPanelShape.path(in: window, notchRect: cutout, cornerRadius: 8, progress: 0, idleMusic: 1).boundingRect
    #expect(abs(capsule.minX - (cutout.minX - 64)) < 0.01)
    #expect(abs(capsule.maxX - (cutout.maxX + 64)) < 0.01)
    #expect(capsule.maxY == cutout.maxY + 2)
}

@Test func remainingTerminalCountTracksOnlyRowsBelowViewport() {
    let ids = ["a", "b", "c", "d", "e"]
    let frames: [String: CGRect] = [
        "a": CGRect(x: 0, y: -40, width: 300, height: 30),
        "b": CGRect(x: 0, y: 20, width: 300, height: 30),
        "c": CGRect(x: 0, y: 90, width: 300, height: 30),
        "d": CGRect(x: 0, y: 110, width: 300, height: 30),
        "e": CGRect(x: 0, y: 160, width: 300, height: 30)
    ]
    #expect(TerminalScrollMetrics.hiddenBelowViewportIDs(orderedIDs: ids, frames: frames, viewportHeight: 100) == ["d", "e"])
    #expect(TerminalScrollMetrics.remainingBelowViewportCount(orderedIDs: ids, frames: frames, viewportHeight: 100) == 2)
    let scrolled = frames.mapValues { CGRect(x: $0.minX, y: $0.minY - 50, width: $0.width, height: $0.height) }
    #expect(TerminalScrollMetrics.remainingBelowViewportCount(orderedIDs: ids, frames: scrolled, viewportHeight: 100) == 1)
    let atEnd = frames.mapValues { CGRect(x: $0.minX, y: $0.minY - 100, width: $0.width, height: $0.height) }
    #expect(TerminalScrollMetrics.remainingBelowViewportCount(orderedIDs: ids, frames: atEnd, viewportHeight: 100) == 0)
    let globalFrames = frames.mapValues { CGRect(x: $0.minX, y: $0.minY + 300, width: $0.width, height: $0.height) }
    #expect(TerminalScrollMetrics.remainingBelowViewportCount(
        orderedIDs: ids, frames: globalFrames, viewportHeight: 100, viewportMinY: 300
    ) == 2)
}
