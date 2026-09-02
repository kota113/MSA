import XCTest
@testable import MSAAppHost

final class AndroidKeysTests: XCTestCase {
    func testUSLetterKeysMapToAndroidLetters() {
        let macKeyCodes: [UInt16] = [
            0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
            45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6,
        ]

        for (offset, macKeyCode) in macKeyCodes.enumerated() {
            XCTAssertEqual(AndroidKeys[macKeyCode], 29 + offset)
        }
    }

    func testUSASDFGSequence() {
        XCTAssertEqual([0, 1, 2, 3, 5].map { AndroidKeys[UInt16($0)] },
                       [29, 47, 32, 34, 35])
    }

    func testUSNumberRowAndPunctuation() {
        XCTAssertEqual(AndroidKeys[18], 8)   // 1
        XCTAssertEqual(AndroidKeys[25], 16)  // 9
        XCTAssertEqual(AndroidKeys[29], 7)   // 0
        XCTAssertEqual(AndroidKeys[24], 70)  // =
        XCTAssertEqual(AndroidKeys[27], 69)  // -
        XCTAssertEqual(AndroidKeys[50], 68)  // `
        XCTAssertEqual(AndroidKeys[48], 61)  // Tab
    }

    func testLeftAndRightShiftToggleIndependently() {
        var state = ModifierKeyState()

        XCTAssertEqual(state.toggle(macKeyCode: 56),
                       AndroidKeyTransition(action: 0, androidKeyCode: 59))
        XCTAssertEqual(state.toggle(macKeyCode: 60),
                       AndroidKeyTransition(action: 0, androidKeyCode: 60))
        XCTAssertEqual(state.toggle(macKeyCode: 56),
                       AndroidKeyTransition(action: 1, androidKeyCode: 59))
        XCTAssertEqual(state.toggle(macKeyCode: 60),
                       AndroidKeyTransition(action: 1, androidKeyCode: 60))
    }

    func testModifierKeysReleaseWhenWindowLosesFocus() {
        var state = ModifierKeyState()
        _ = state.toggle(macKeyCode: 60)
        _ = state.toggle(macKeyCode: 56)

        XCTAssertEqual(state.releaseAll(), [
            AndroidKeyTransition(action: 1, androidKeyCode: 59),
            AndroidKeyTransition(action: 1, androidKeyCode: 60),
        ])
        XCTAssertTrue(state.releaseAll().isEmpty)
    }

    func testCommandVPastesWithAndroidControlV() {
        XCTAssertEqual(AndroidShortcuts.command(9), [
            AndroidKeyTransition(action: 0, androidKeyCode: 113),
            AndroidKeyTransition(action: 0, androidKeyCode: 50),
            AndroidKeyTransition(action: 1, androidKeyCode: 50),
            AndroidKeyTransition(action: 1, androidKeyCode: 113),
        ])
        XCTAssertNil(AndroidShortcuts.command(8))
    }
}
