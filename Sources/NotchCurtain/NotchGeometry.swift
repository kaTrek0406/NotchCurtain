import CoreGraphics

struct NotchGeometry: Equatable {
    let frame: CGRect

    func containsCursor(_ point: CGPoint) -> Bool { frame.contains(point) }

    static func resolve(screenFrame: CGRect, safeAreaTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) -> NotchGeometry? {
        guard safeAreaTop > 0, let leftArea, let rightArea else { return nil }
        let left = leftArea.maxX
        let right = rightArea.minX
        guard right > left else { return nil }
        return NotchGeometry(frame: CGRect(x: left, y: screenFrame.maxY - safeAreaTop, width: right - left, height: safeAreaTop))
    }
}
