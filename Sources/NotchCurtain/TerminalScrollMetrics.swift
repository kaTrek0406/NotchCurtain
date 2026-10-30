import CoreGraphics

enum TerminalScrollMetrics {
    static func hiddenBelowViewportIDs(
        orderedIDs: [String],
        frames: [String: CGRect],
        viewportHeight: CGFloat,
        viewportMinY: CGFloat = 0
    ) -> [String] {
        guard viewportHeight > 0 else { return [] }
        return orderedIDs.filter { id in
            guard let frame = frames[id] else { return false }
            return frame.minY >= viewportMinY + viewportHeight
        }
    }

    static func remainingBelowViewportCount(
        orderedIDs: [String],
        frames: [String: CGRect],
        viewportHeight: CGFloat,
        viewportMinY: CGFloat = 0
    ) -> Int {
        hiddenBelowViewportIDs(
            orderedIDs: orderedIDs,
            frames: frames,
            viewportHeight: viewportHeight,
            viewportMinY: viewportMinY
        ).count
    }
}
