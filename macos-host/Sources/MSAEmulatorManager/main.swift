import AppKit
import MSAHostCore

let arguments = Arguments.parse(CommandLine.arguments)
let application = NSApplication.shared
let delegate = EmulatorManagerAppDelegate(arguments: arguments)
application.delegate = delegate
application.run()