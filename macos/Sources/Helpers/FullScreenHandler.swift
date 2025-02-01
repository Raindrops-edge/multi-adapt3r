import SwiftUI
import GhosttyKit

class FullScreenHandler {
    var previousTabGroup: NSWindowTabGroup?
    var previousTabGroupIndex: Int?
    var previousContentFrame: NSRect?
    
    // We keep track of whether we entered non-native fullscreen in case
    // a user goes to fullscreen, changes the config to disable non-native fullscreen
    // and then wants to toggle it off
    var isInNonNativeFullscreen: Bool = false
    var processingScreenChange: Bool = false
    
    func toggleFullscreen(window: NSWindow, nonNativeFullscreen: ghostty_non_native_fullscreen_e) {
        if isInNonNativeFullscreen {
            leaveFullscreen(window: window)
            isInNonNativeFullscreen = false
        } else if nonNativeFullscreen != GHOSTTY_NON_NATIVE_FULLSCREEN_FALSE {
            let hideMenu = nonNativeFullscreen != GHOSTTY_NON_NATIVE_FULLSCREEN_VISIBLE_MENU
            enterFullscreen(window: window, hideMenu: hideMenu)
            isInNonNativeFullscreen = true
        } else {
            window.toggleFullScreen(nil)
        }
    }
    
    func enterFullscreen(window: NSWindow, hideMenu: Bool) {
        guard let screen = window.screen else { return }
        guard let contentView = window.contentView else { return }
        
        previousTabGroup = window.tabGroup
        previousTabGroupIndex = window.tabGroup?.windows.firstIndex(of: window)
        
        // Save previous contentViewFrame and screen
        previousContentFrame = window.convertToScreen(contentView.frame)
        
        // Change presentation style to hide menu bar and dock if needed
        // It's important to do this in two calls, because setting them in a single call guarantees
        // that the menu bar will also be hidden on any additional displays (why? nobody knows!)
        // When these options are set separately, the menu bar hiding problem will only occur in
        // specific scenarios. More invesitgation is needed to pin these scenarios down precisely,
        // but it seems to have something to do with which app had focus last.
        // Furthermore, it's much easier to figure out which screen the dock is on if the menubar
        // has not yet been hidden, so the order matters here!
        if (shouldHideDock(screen: screen)) {
            self.hideDock()
            
            // Ensure that we always hide the dock bar for this window, but not for non fullscreen ones
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.hideDock),
                name: NSWindow.didBecomeMainNotification,
                object: window)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.unHideDock),
                name: NSWindow.didResignMainNotification,
                object: window)
        }
        if (hideMenu) {
            self.hideMenu()
            
            // Ensure that we always hide the menu bar for this window, but not for non fullscreen ones
            // This is not the best way to do this, not least because it causes the menu to stay visible
            // for a brief moment before being hidden in some cases (e.g. when switching spaces).
            // If we end up adding a NSWindowDelegate to PrimaryWindow, then we may be better off
            // handling this there.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.hideMenu),
                name: NSWindow.didBecomeMainNotification,
                object: window)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.unHideMenu),
                name: NSWindow.didResignMainNotification,
                object: window)
        }
        
        // This is important: it gives us the full screen, including the
        // notch area on MacBooks.
        window.styleMask.remove(.titled)
        
        // Set frame to screen size, accounting for the menu bar if needed
        let frame = calculateFullscreenFrame(screenFrame: screen.frame, subtractMenu: !hideMenu)
        window.setFrame(frame, display: true)
        
        // If the window gets moved to another display (via a window manager or the Window menu) then
        // we may need to update the frame to the size of the new screen and update dock visibility
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.windowChangedScreen(notification:)),
            name: NSWindow.didChangeScreenNotification,
            object: window)
        
        // Focus window
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func hideMenu() {
        NSApp.presentationOptions.insert(.autoHideMenuBar)
    }
    
    @objc func unHideMenu() {
        NSApp.presentationOptions.remove(.autoHideMenuBar)
    }
    
    @objc func hideDock() {
        NSApp.presentationOptions.insert(.autoHideDock)
    }
    
    @objc func unHideDock() {
        NSApp.presentationOptions.remove(.autoHideDock)
    }
    
    @objc func windowChangedScreen(notification: NSNotification) {
        // This notification can fire spriously and repeatedly in some situations.
        // It's best if we're only handling one at a time.
        // IMPORTANT: don't forget to set processingScreenChange to false before any
        // early returns!
        if processingScreenChange { return }
        processingScreenChange = true

        guard let window = notification.object as? NSWindow else {
            self.processingScreenChange = false
            return
        }

        // Window size updates must be done on the main thread. We also do the
        // frame calculation there because otherwise we get the menu bar size
        // from the old display rather than the new one.
        DispatchQueue.main.async(execute: {
            guard let screen = window.screen else {
                self.processingScreenChange = false
                return
            }
            let subtractMenu = !NSApp.presentationOptions.contains(.autoHideMenuBar);
            let frame = self.calculateFullscreenFrame(screenFrame: screen.frame, subtractMenu: subtractMenu)
            window.setFrame(frame, display: true)

            print("done")
        })
        self.processingScreenChange = false
        // TODO: check whether this retain cycle is an issue
    }
    
    func calculateFullscreenFrame(screenFrame: NSRect, subtractMenu: Bool)->NSRect {
        if (subtractMenu) {
            let menuHeight = NSApp.mainMenu?.menuBarHeight ?? 0
            return NSMakeRect(screenFrame.minX, screenFrame.minY, screenFrame.width, screenFrame.height - menuHeight)
        }
        return screenFrame
    }
    
    func leaveFullscreen(window: NSWindow) {
        guard let previousFrame = previousContentFrame else { return }
        
        // Restore title bar
        window.styleMask.insert(.titled)
        
        // Restore previous presentation options
        NSApp.presentationOptions = []
        
        // Stop handling any kind of notification since we're leaving fullscreen mode
        NotificationCenter.default.removeObserver(self)
        
        // Restore frame
        window.setFrame(window.frameRect(forContentRect: previousFrame), display: true)
        
        // If the window was previously in a tab group that isn't empty now, we re-add it
        if let group = previousTabGroup, let tabIndex = previousTabGroupIndex, !group.windows.isEmpty {
            var tabWindow: NSWindow?
            var order: NSWindow.OrderingMode = .below
            
            // Index of the window before `window`
            let tabIndexBefore = tabIndex-1
            if tabIndexBefore < 0 {
                // If we were the first tab, we add the window *before* (.below) the first one.
                tabWindow = group.windows.first
            } else if tabIndexBefore < group.windows.count {
                // If we weren't the first tab in the group, we add our window after
                // the tab that was before it.
                tabWindow = group.windows[tabIndexBefore]
                order = .above
            } else {
                // If index is after group, add it after last window
                tabWindow = group.windows.last
            }
            
            // Add the window
            tabWindow?.addTabbedWindow(window, ordered: order)
        }
        
        // Focus window
        window.makeKeyAndOrderFront(nil)
    }
    
    // We only want to hide the dock if it's not already going to be hidden automatically, and if
    // it's on the same display as the ghostty window that we want to make fullscreen.
    func shouldHideDock(screen: NSScreen) -> Bool {
        if let dockAutohide = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["autohide"] as? Bool {
            if (dockAutohide) { return false }
        }

        // There is no public API to directly ask about dock visibility, so we have to figure it out
        // by comparing the sizes of visibleFrame (the currently usable area of the screen) and
        // frame (the full screen size). We also need to account for the menubar, any inset caused
        // by the notch on macbooks, and a little extra padding to compensate for the boundary area
        // which triggers showing the dock.
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuHeight = NSApp.mainMenu?.menuBarHeight ?? 0
        var notchInset = 0.0
        if #available(macOS 12, *) {
            notchInset = screen.safeAreaInsets.top
        }
        let boundaryAreaPadding = 5.0

        return visibleFrame.height < (frame.height - max(menuHeight, notchInset) - boundaryAreaPadding) || visibleFrame.width < frame.width
    }
}
