import XCTest
@testable import MSAHostCore

final class ArgumentsTests: XCTestCase {
    func testBundleMetadataSelectsAndroidApp() {
        let arguments = Arguments.parse(
            ["MSAHost"],
            bundlePackageName: "com.example.android",
            bundleDisplayName: "Example Android App",
            bundleIsEmulatorManager: false,
            bundleEmulatorSerial: "emulator-5558",
            bundleAVDName: "msa-gms-api36",
            bundleWritableSystem: false,
            bundleSDKRoot: "/opt/android-sdk"
        )

        XCTAssertEqual(arguments.packageName, "com.example.android")
        XCTAssertFalse(arguments.isEmulatorManager)
        XCTAssertEqual(arguments.windowTitle, "Example Android App")
        XCTAssertEqual(arguments.emulatorSerial, "emulator-5558")
        XCTAssertEqual(arguments.avdName, "msa-gms-api36")
        XCTAssertFalse(arguments.writableSystem)
        XCTAssertEqual(arguments.sdkRoot, "/opt/android-sdk")
    }

    func testBundleMetadataSelectsEmulatorManager() {
        let arguments = Arguments.parse(
            ["MSAHost"],
            bundlePackageName: nil,
            bundleDisplayName: "MSA Emulator",
            bundleIsEmulatorManager: true
        )

        XCTAssertTrue(arguments.isEmulatorManager)
    }

    func testCommandLineOverridesBundleMetadata() {
        let arguments = Arguments.parse(
            ["MSAHost", "--package", "com.example.override", "--name", "Override"],
            bundlePackageName: "com.example.bundle",
            bundleDisplayName: "Bundle",
            bundleEmulatorSerial: nil,
            bundleAVDName: nil,
            bundleWritableSystem: nil
        )

        XCTAssertEqual(arguments.packageName, "com.example.override")
        XCTAssertEqual(arguments.windowTitle, "Override")
    }

    func testCommandLineOverridesEmulatorConfiguration() {
        let arguments = Arguments.parse(
            ["MSAHost", "--serial", "emulator-5560", "--avd", "custom-avd", "--writable-system", "false"],
            bundlePackageName: nil,
            bundleDisplayName: nil,
            bundleEmulatorSerial: "emulator-5558",
            bundleAVDName: "bundle-avd",
            bundleWritableSystem: true
        )

        XCTAssertEqual(arguments.emulatorSerial, "emulator-5560")
        XCTAssertEqual(arguments.avdName, "custom-avd")
        XCTAssertFalse(arguments.writableSystem)
    }
}
