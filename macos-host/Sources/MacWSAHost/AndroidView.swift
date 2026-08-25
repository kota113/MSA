import AppKit

@MainActor
final class AndroidView: NSView {
    private let connection: SocketConnection
    private let display: H264Display
    private var androidWidth: CGFloat
    private var androidHeight: CGFloat
    private var androidDensityDpi: Int
    private let initialAndroidWidth: CGFloat
    private let initialViewWidth: CGFloat
    private let initialDensityDpi: CGFloat
    private let initialPixelArea: CGFloat
    private var resizeWorkItem: DispatchWorkItem?
    private var acceptsResizeEvents = false
    private var modifierKeyState = ModifierKeyState()

    init(frame: NSRect, connection: SocketConnection, display: H264Display,
         androidWidth: Int, androidHeight: Int, densityDpi: Int) {
        self.connection = connection
        self.display = display
        self.androidWidth = CGFloat(androidWidth)
        self.androidHeight = CGFloat(androidHeight)
        self.androidDensityDpi = densityDpi
        self.initialAndroidWidth = CGFloat(androidWidth)
        self.initialViewWidth = frame.width
        self.initialDensityDpi = CGFloat(densityDpi)
        self.initialPixelArea = CGFloat(androidWidth * androidHeight)
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        display.layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        display.layer.needsDisplayOnBoundsChange = true
        layer?.addSublayer(display.layer)
        updateDisplayLayerFrame()
        acceptsResizeEvents = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDisplayLayerFrame()
        needsDisplay = true
        scheduleAndroidResize()
    }

    override func layout() {
        super.layout()
        updateDisplayLayerFrame()
    }

    private func updateDisplayLayerFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display.layer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        scheduleAndroidResize(delay: 0)
    }

    private func scheduleAndroidResize(delay: TimeInterval = 0.25) {
        guard acceptsResizeEvents, bounds.width >= 64, bounds.height >= 64 else { return }
        resizeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendAndroidResize() }
        resizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func sendAndroidResize() {
        let aspect = bounds.width / bounds.height
        var width = sqrt(initialPixelArea * aspect)
        var height = sqrt(initialPixelArea / aspect)
        let longest = max(width, height)
        if longest > 1920 {
            let scale = 1920 / longest
            width *= scale
            height *= scale
        }
        let targetWidth = max(64, Int(width) & ~1)
        let targetHeight = max(64, Int(height) & ~1)
        let pixelScale = CGFloat(targetWidth) / initialAndroidWidth
        let pointScale = bounds.width / initialViewWidth
        let targetDensity = max(160, min(640,
            Int((initialDensityDpi * pixelScale / pointScale).rounded())))
        guard abs(CGFloat(targetWidth) - androidWidth) >= 8
                || abs(CGFloat(targetHeight) - androidHeight) >= 8
                || abs(targetDensity - androidDensityDpi) >= 2 else { return }

        androidWidth = CGFloat(targetWidth)
        androidHeight = CGFloat(targetHeight)
        androidDensityDpi = targetDensity
        display.prepareForStreamResize()
        connection.sendLine("RESIZE \(targetWidth) \(targetHeight) \(targetDensity)")
    }

    private var videoRect: NSRect {
        let scale = min(bounds.width / androidWidth, bounds.height / androidHeight)
        let size = NSSize(width: androidWidth * scale, height: androidHeight * scale)
        return NSRect(x: (bounds.width - size.width) / 2,
                      y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func point(_ event: NSEvent) -> (CGFloat, CGFloat) {
        let local = convert(event.locationInWindow, from: nil)
        let image = videoRect
        let x = max(0, min(androidWidth - 1,
                           (local.x - image.minX) / max(image.width, 1) * androidWidth))
        let y = max(0, min(androidHeight - 1,
                           (image.maxY - local.y) / max(image.height, 1) * androidHeight))
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
    override func scrollWheel(with event: NSEvent) {
        let x = normalizedScroll(event.scrollingDeltaX)
        let y = normalizedScroll(-event.scrollingDeltaY)
        guard x != 0 || y != 0 else { return }
        connection.sendLine("SCROLL \(x) \(y)")
    }

    private func normalizedScroll(_ delta: CGFloat) -> CGFloat {
        max(-1, min(1, delta / 10))
    }
    override func keyDown(with event: NSEvent) {
        if let code = AndroidKeys[event.keyCode] { connection.sendLine("KEY 0 \(code)") }
    }
    override func keyUp(with event: NSEvent) {
        if let code = AndroidKeys[event.keyCode] { connection.sendLine("KEY 1 \(code)") }
    }

    override func flagsChanged(with event: NSEvent) {
        guard let transition = modifierKeyState.toggle(macKeyCode: event.keyCode) else {
            super.flagsChanged(with: event)
            return
        }
        connection.sendLine("KEY \(transition.action) \(transition.androidKeyCode)")
    }

    func releaseModifierKeys() {
        for transition in modifierKeyState.releaseAll() {
            connection.sendLine("KEY \(transition.action) \(transition.androidKeyCode)")
        }
    }
}

struct AndroidKeyTransition: Equatable {
    let action: Int
    let androidKeyCode: Int
}

struct ModifierKeyState {
    private var pressedMacKeyCodes: Set<UInt16> = []

    mutating func toggle(macKeyCode: UInt16) -> AndroidKeyTransition? {
        guard let androidKeyCode = AndroidModifierKeys[macKeyCode] else { return nil }
        if pressedMacKeyCodes.remove(macKeyCode) != nil {
            return AndroidKeyTransition(action: 1, androidKeyCode: androidKeyCode)
        }
        pressedMacKeyCodes.insert(macKeyCode)
        return AndroidKeyTransition(action: 0, androidKeyCode: androidKeyCode)
    }

    mutating func releaseAll() -> [AndroidKeyTransition] {
        let transitions = pressedMacKeyCodes.sorted().compactMap { macKeyCode in
            AndroidModifierKeys[macKeyCode].map {
                AndroidKeyTransition(action: 1, androidKeyCode: $0)
            }
        }
        pressedMacKeyCodes.removeAll()
        return transitions
    }
}

let AndroidModifierKeys: [UInt16: Int] = [
    56: 59, // Left Shift -> KEYCODE_SHIFT_LEFT
    60: 60, // Right Shift -> KEYCODE_SHIFT_RIGHT
]

let AndroidKeys: [UInt16: Int] = [
    // ANSI letters
    0: 29, 1: 47, 2: 32, 3: 34, 4: 36, 5: 35, 6: 54, 7: 52,
    8: 31, 9: 50, 11: 30, 12: 45, 13: 51, 14: 33, 15: 46, 16: 53,
    17: 48, 31: 43, 32: 49, 34: 37, 35: 44, 37: 40, 38: 38,
    40: 39, 45: 42, 46: 41,

    // ANSI number row and punctuation
    18: 8, 19: 9, 20: 10, 21: 11, 22: 13, 23: 12, 24: 70,
    25: 16, 26: 14, 27: 69, 28: 15, 29: 7, 30: 72, 33: 71,
    39: 75, 41: 74, 42: 73, 43: 55, 44: 76, 47: 56, 50: 68,

    // Editing and navigation
    36: 66, 48: 61, 49: 62, 51: 67, 53: 111,
    114: 124, 115: 122, 116: 92, 117: 112, 119: 123, 121: 93,
    123: 21, 124: 22, 125: 20, 126: 19
]
