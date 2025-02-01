import Cocoa
import SwiftUI
import GhosttyKit

// FocusedSurfaceWrapper is here so that we can pass a reference down
// the view hierarchy and keep track of which surface is focused.
class FocusedSurfaceWrapper {
    var surface: ghostty_surface_t?
}

// PrimaryWindow is the primary window you'd associate with a terminal: the window
// that contains one or more terminals (splits, and such).
//
// We need to subclass NSWindow so that we can override some methods for features
// such as non-native fullscreen.
class PrimaryWindow: NSWindow {
    var focusedSurfaceWrapper: FocusedSurfaceWrapper = FocusedSurfaceWrapper()

    static func create(ghostty: Ghostty.AppState, appDelegate: AppDelegate, baseConfig: ghostty_surface_config_s? = nil) -> PrimaryWindow {
        let window = PrimaryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.center()

        // Terminals typically operate in sRGB color space and macOS defaults
        // to "native" which is typically P3. There is a lot more resources
        // covered in thie GitHub issue: https://github.com/mitchellh/ghostty/pull/376
        window.colorSpace = NSColorSpace.sRGB

        window.contentView = NSHostingView(rootView: PrimaryView(
            ghostty: ghostty,
            appDelegate: appDelegate,
            focusedSurfaceWrapper: window.focusedSurfaceWrapper,
            baseConfig: baseConfig
        ))
        
        // We do want to cascade when new windows are created
        window.windowController?.shouldCascadeWindows = true
        
        // A default title. This should be overwritten quickly by the Ghostty core.
        window.title = "Ghostty 👻"
        
        return window
    }
    
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}
