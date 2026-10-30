import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]) else {
    fputs("Usage: move_cursor <x> <y>\n", stderr)
    exit(2)
}
let point = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(point)
let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
event?.post(tap: .cghidEventTap)
