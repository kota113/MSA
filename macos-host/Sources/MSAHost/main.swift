import AppKit

let arguments = Arguments.parse(CommandLine.arguments)
let application = NSApplication.shared
let delegate: any NSApplicationDelegate = arguments.isEmulatorManager
    ? EmulatorManagerAppDelegate(arguments: arguments)
    : AppDelegate(arguments: arguments)
application.delegate = delegate
if !arguments.isEmulatorManager {
    application.setActivationPolicy(.regular)
    application.activate(ignoringOtherApps: true)
}
application.run()
