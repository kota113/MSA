import AppKit
import MSAHostCore

let arguments = Arguments.parse(CommandLine.arguments)
let application = NSApplication.shared
let delegate = AppDelegate(arguments: arguments)
application.delegate = delegate
application.setActivationPolicy(.regular)
application.activate(ignoringOtherApps: true)
application.run()