import AppKit

@MainActor
final class AndroidView: NSView {
    private let connection: SocketConnection
    private let display: H264Display
    private let androidWidth: CGFloat
    private let androidHeight: CGFloat
    private var previousMouse: NSPoint?

    init(frame: NSRect, connection: SocketConnection, display: H264Display,
         androidWidth: Int, androidHeight: Int) {
        self.connection = connection
        self.display = display
        self.androidWidth = CGFloat(androidWidth)
        self.androidHeight = CGFloat(androidHeight)
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(display.layer)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                      owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func layout() { super.layout(); display.layer.frame = bounds }

    private func point(_ event: NSEvent) -> (CGFloat, CGFloat) {
        let local = convert(event.locationInWindow, from: nil)
        let x = max(0, min(androidWidth - 1, local.x / max(bounds.width, 1) * androidWidth))
        let y = max(0, min(androidHeight - 1, (bounds.height - local.y) / max(bounds.height, 1) * androidHeight))
        return (x, y)
    }

    override func mouseDown(with event: NSEvent) { sendTouch(0, event) }
    override func mouseDragged(with event: NSEvent) { sendTouch(2, event) }
    override func mouseUp(with event: NSEvent) { sendTouch(1, event) }
    private func sendTouch(_ action: Int, _ event: NSEvent) {
        let (x, y) = point(event)
        connection.sendLine("TOUCH \(action) \(x) \(y) 0")
    }

    override func rightMouseDown(with event: NSEvent) { connection.sendLine("MOUSE_BUTTON 11 2") }
    override func rightMouseUp(with event: NSEvent) { connection.sendLine("MOUSE_BUTTON 12 2") }
    override func mouseMoved(with event: NSEvent) { sendMouseMove(event) }
    override func rightMouseDragged(with event: NSEvent) { sendMouseMove(event) }
    private func sendMouseMove(_ event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        if let previousMouse {
            connection.sendLine("MOUSE_MOVE \(current.x - previousMouse.x) \(previousMouse.y - current.y)")
        }
        previousMouse = current
    }
    override func scrollWheel(with event: NSEvent) {
        connection.sendLine("SCROLL \(event.scrollingDeltaX / 10) \(-event.scrollingDeltaY / 10)")
    }
    override func keyDown(with event: NSEvent) {
        if let code = AndroidKeys[event.keyCode] { connection.sendLine("KEY 0 \(code)") }
    }
    override func keyUp(with event: NSEvent) {
        if let code = AndroidKeys[event.keyCode] { connection.sendLine("KEY 1 \(code)") }
    }
}

private let AndroidKeys: [UInt16: Int] = [
    0: 29, 1: 47, 2: 32, 3: 33, 4: 35, 5: 34, 6: 54, 7: 52,
    8: 31, 9: 50, 11: 48, 12: 45, 13: 46, 14: 37, 15: 38, 16: 36,
    17: 51, 18: 8, 19: 9, 20: 10, 21: 11, 22: 13, 23: 12, 24: 69,
    25: 7, 26: 70, 27: 71, 28: 72, 29: 73, 30: 74, 31: 75, 32: 76,
    33: 77, 34: 78, 35: 79, 36: 66, 37: 49, 38: 41, 39: 40, 40: 44,
    41: 43, 42: 42, 43: 39, 44: 55, 45: 56, 46: 53, 47: 74, 48: 62,
    49: 62, 51: 67, 53: 111, 123: 21, 124: 22, 125: 20, 126: 19
]
