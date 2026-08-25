import XCTest
@testable import MacWSAHost

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
}
