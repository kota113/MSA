import XCTest
@testable import MSAHost

final class EmulatorConfigurationTests: XCTestCase {
    func testLaunchArgumentsUseSerialPortAndHeadlessMode() throws {
        let configuration = try EmulatorConfiguration(
            sdkRoot: "/tmp/android-sdk",
            serial: "emulator-5558",
            avdName: "msa-gms-api36",
            writableSystem: false
        )

        XCTAssertEqual(configuration.port, 5558)
        XCTAssertEqual(configuration.launchArguments, [
            "-avd", "msa-gms-api36", "-port", "5558", "-no-window",
            "-no-snapshot", "-no-boot-anim", "-gpu", "host",
        ])
    }

    func testWritableSystemArgumentIsAddedForAOSPImage() throws {
        let configuration = try EmulatorConfiguration(
            sdkRoot: "/tmp/android-sdk",
            serial: "emulator-5556",
            avdName: "msa-api36",
            writableSystem: true
        )

        XCTAssertTrue(configuration.launchArguments.contains("-writable-system"))
    }

    func testInvalidSerialIsRejected() {
        XCTAssertThrowsError(try EmulatorConfiguration(
            sdkRoot: "/tmp/android-sdk",
            serial: "device-1234",
            avdName: "msa-api36",
            writableSystem: true
        ))
    }

    func testADBStateRequiresSuccessfulDeviceResponse() {
        XCTAssertTrue(EmulatorState.isRunning(output: "device\n", terminationStatus: 0))
        XCTAssertFalse(EmulatorState.isRunning(output: "offline\n", terminationStatus: 0))
        XCTAssertFalse(EmulatorState.isRunning(output: "device\n", terminationStatus: 1))
        XCTAssertTrue(EmulatorState.isPresent(output: "offline\n", terminationStatus: 0))
        XCTAssertFalse(EmulatorState.isPresent(output: "unknown\n", terminationStatus: 0))
    }

}