import AppKit
import Cocoa
import GhosttyKit

// We put the GHOSTTY_MAC_APP env var into the Info.plist to detect
// whether we launch from the app or not. A user can fake this if
// they want but they're doing so at their own detriment...
let process = ProcessInfo.processInfo
if ((process.environment["GHOSTTY_MAC_APP"] ?? "") == "") {
    ghostty_cli_main(UInt(CommandLine.argc), CommandLine.unsafeArgv)
    exit(1)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
