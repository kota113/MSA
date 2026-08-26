import XCTest
@testable import MSAHost

final class EmulatorConfigurationTests: XCTestCase {
    func testQuickBootLaunchArgumentsUseSerialPortAndHeadlessMode() throws {
        let configuration = try EmulatorConfiguration(
            sdkRoot: "/tmp/android-sdk",
            serial: "emulator-5558",
            avdName: "msa-gms-api36",
            writableSystem: false
        )

        XCTAssertEqual(configuration.port, 5558)
        XCTAssertEqual(configuration.launchArguments(coldBoot: false), [
            "-avd", "msa-gms-api36", "-port", "5558", "-no-window",
            "-no-boot-anim", "-gpu", "host",
        ])
    }

    func testColdBootOnlyDisablesSnapshotLoading() throws {
        let configuration = try EmulatorConfiguration(
            sdkRoot: "/tmp/android-sdk",
            serial: "emulator-5558",
            avdName: "msa-gms-api36",
            writableSystem: false
        )

        XCTAssertEqual(configuration.launchArguments(coldBoot: true), [
            "-avd", "msa-gms-api36", "-port", "5558", "-no-window",
            "-no-boot-anim", "-gpu", "host", "-no-snapshot-load",
        ])
    }

    func testWritableSystemArgumentIsAddedForAOSPImage() throws {
        let configuration = try EmulatorConfiguration(
            sdkRoot: "/tmp/android-sdk",
            serial: "emulator-5556",
            avdName: "msa-api36",
            writableSystem: true
        )

        XCTAssertTrue(configuration.launchArguments(coldBoot: false).contains("-writable-system"))
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

    func testEmulatorConsoleStateDetectsPausedVM() {
        XCTAssertTrue(EmulatorState.isPaused(
            output: "virtual device is stopped\nOK\n", terminationStatus: 0
        ))
        XCTAssertFalse(EmulatorState.isPaused(
            output: "virtual device is running\nOK\n", terminationStatus: 0
        ))
        XCTAssertFalse(EmulatorState.isPaused(
            output: "virtual device is stopped\nKO\n", terminationStatus: 1
        ))
    }

    func testClientRegistryExpiresMissingHeartbeats() {
        let start = Date(timeIntervalSince1970: 1_000)
        var registry = EmulatorClientRegistry(leaseDuration: 90)
        registry.touch("active", at: start.addingTimeInterval(30))
        registry.touch("expired", at: start)

        registry.removeExpired(at: start.addingTimeInterval(90))

        XCTAssertTrue(registry.contains("active"))
        XCTAssertFalse(registry.contains("expired"))
    }

    func testClientRegistryReleaseRemovesLease() {
        var registry = EmulatorClientRegistry(leaseDuration: 90)
        registry.touch("client")

        registry.release("client")

        XCTAssertTrue(registry.isEmpty)
    }

}