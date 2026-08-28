import Foundation
import XCTest
@testable import MSAEmulatorManager

final class AppBundleBuilderTests: XCTestCase {
    func testBuildCreatesAndReplacesAppUsingPackagedHost() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("msa-builder-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("host")
        try Data("host-v1".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let output = root.appendingPathComponent("Applications", isDirectory: true)
        let builder = AppBundleBuilder(hostExecutableURL: executable, outputDirectoryURL: output,
                                       signer: { _ in })
        let request = AppBundleRequest(packageName: "com.example_app.demo", displayName: "Example/App",
                                       emulatorSerial: "emulator-5558", avdName: "msa-gms-api36",
                                       sdkRoot: "/sdk", writableSystem: false, iconData: nil)

        let firstURL = try builder.build(request)
        XCTAssertEqual(firstURL.lastPathComponent, "Example-App.app")
        let firstInfo = try XCTUnwrap(Bundle(url: firstURL)?.infoDictionary)
        XCTAssertEqual(firstInfo["MSAPackageName"] as? String, "com.example_app.demo")
        XCTAssertEqual(firstInfo["CFBundleExecutable"] as? String, "MSAAppHost")

        try Data("host-v2".utf8).write(to: executable)
        let secondURL = try builder.build(request)
        let bundledHost = secondURL.appendingPathComponent("Contents/MacOS/MSAAppHost")
        XCTAssertEqual(try Data(contentsOf: bundledHost), Data("host-v2".utf8))
    }

    func testPackageEventProtocolRejectsCommandsDisguisedAsPackageNames() {
        XCTAssertTrue(PackageEventProtocol.isValidPackageName("com.example_app.demo"))
        XCTAssertFalse(PackageEventProtocol.isValidPackageName("com.example;rm -rf"))
        XCTAssertEqual(PackageEventProtocol.parsePending("PACKAGE com.example.good\nPACKAGE bad value\nEND\n"),
                       ["com.example.good"])
    }

    func testManagedAppRegistryWaitsBeforeReportingRemovedAppAndTracksRename() throws {
        let suiteName = "msa-registry-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = ManagedAppRegistry(defaults: defaults, graceInterval: 5)
        let start = Date(timeIntervalSince1970: 1_000)
        let original = ManagedApp(packageName: "com.example.demo", displayName: "Demo",
                                  path: "/Applications/Demo.app")

        XCTAssertEqual(registry.reconcile(discovered: [original], now: start), [])
        XCTAssertEqual(registry.reconcile(discovered: [], now: start.addingTimeInterval(1)), [])
        XCTAssertEqual(registry.reconcile(discovered: [], now: start.addingTimeInterval(6)), [original])

        let renamed = ManagedApp(packageName: "com.example.demo", displayName: "Demo",
                                 path: "/Applications/Renamed.app")
        XCTAssertEqual(registry.reconcile(discovered: [renamed], now: start.addingTimeInterval(7)), [])
        XCTAssertEqual(registry.reconcile(discovered: [], now: start.addingTimeInterval(8)), [])
        XCTAssertEqual(registry.reconcile(discovered: [], now: start.addingTimeInterval(13)), [renamed])

        registry.remove(packageName: renamed.packageName)
        XCTAssertEqual(registry.reconcile(discovered: [], now: start.addingTimeInterval(20)), [])
    }
}