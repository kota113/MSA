import XCTest
@testable import MSAAppHost

final class ClipboardWireTests: XCTestCase {
    func testTextCommandUsesUTF8Base64() {
        let content = ClipboardContent.text(Data("こんにちは".utf8))
        XCTAssertEqual(ClipboardWire.command(for: content),
                       "CLIPBOARD text/plain 44GT44KT44Gr44Gh44Gv")
    }

    func testImagePayloadRoundTrip() {
        let bytes = Data([0x89, 0x50, 0x4e, 0x47])
        let payload = Data("image/png\n".utf8) + bytes
        XCTAssertEqual(ClipboardWire.decode(payload),
                       .image(mimeType: "image/png", data: bytes))
    }

    func testUnsupportedPayloadIsRejected() {
        XCTAssertNil(ClipboardWire.decode(Data("application/pdf\ndata".utf8)))
    }

    func testOversizedContentIsRejected() {
        let bytes = Data(count: ClipboardWire.maximumBytes + 1)
        XCTAssertNil(ClipboardWire.command(for: .image(mimeType: "image/png", data: bytes)))
    }
}