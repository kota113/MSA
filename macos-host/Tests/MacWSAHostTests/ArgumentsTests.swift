import XCTest
@testable import MacWSAHost

final class ArgumentsTests: XCTestCase {
    func testBundleMetadataSelectsAndroidApp() {
        let arguments = Arguments.parse(
            ["MacWSAHost"],
            bundlePackageName: "com.example.android",
            bundleDisplayName: "Example Android App"
        )

        XCTAssertEqual(arguments.packageName, "com.example.android")
        XCTAssertEqual(arguments.windowTitle, "Example Android App")
    }

    func testCommandLineOverridesBundleMetadata() {
        let arguments = Arguments.parse(
            ["MacWSAHost", "--package", "com.example.override", "--name", "Override"],
            bundlePackageName: "com.example.bundle",
            bundleDisplayName: "Bundle"
        )

        XCTAssertEqual(arguments.packageName, "com.example.override")
        XCTAssertEqual(arguments.windowTitle, "Override")
    }
}
