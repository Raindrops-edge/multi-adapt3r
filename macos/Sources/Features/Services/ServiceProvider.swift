import Foundation
import AppKit

class ServiceProvider: NSObject {
    static private let errorNoString = NSString(string: "Could not load any text from the clipboard.")
    
    /// The target for an open operation
    enum OpenTarget {
        case tab
        case window
    }
    
    @objc func openTab(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        openTerminalFromPasteboard(pasteboard: pasteboard, target: .tab, error: error)
    }
    
    @objc func openWindow(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        openTerminalFromPasteboard(pasteboard: pasteboard, target: .window, error: error)
    }

    @inline(__always)
    private func openTerminalFromPasteboard(
        pasteboard: NSPasteboard,
        target: OpenTarget,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let objs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL] else {
            error.pointee = Self.errorNoString
            return
        }
        let filePaths = objs.map { $0.path }.compactMap { $0 }
        
        openTerminal(filePaths, target: target)
    }
    
    private func openTerminal(_ paths: [String], target: OpenTarget) {
        guard let delegateRaw = NSApp.delegate else { return }
        guard let delegate = delegateRaw as? AppDelegate else { return }
        let terminalManager = delegate.terminalManager

        for path in paths {
            // We only open in directories.
            var isDirectory = ObjCBool(true)
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else { continue }
            
            // Build our config
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = path

            switch (target) {
            case .window:
                terminalManager.newWindow(withBaseConfig: config)

            case .tab:
                terminalManager.newTab(withBaseConfig: config)
            }
        }

    }
}
