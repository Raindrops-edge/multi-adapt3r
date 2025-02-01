import SwiftUI
import GhosttyKit

struct Ghostty {
    // All the notifications that will be emitted will be put here.
    struct Notification {}
}

// MARK: Surface Notifications

extension Ghostty {
    /// An enum that is used for the directions that a split focus event can change.
    enum SplitFocusDirection {
        case previous, next, top, bottom, left, right
        
        /// Initialize from a Ghostty API enum.
        static func from(direction: ghostty_split_focus_direction_e) -> Self? {
            switch (direction) {
            case GHOSTTY_SPLIT_FOCUS_PREVIOUS:
                return .previous
                
            case GHOSTTY_SPLIT_FOCUS_NEXT:
                return .next
                
            case GHOSTTY_SPLIT_FOCUS_TOP:
                return .top
                
            case GHOSTTY_SPLIT_FOCUS_BOTTOM:
                return .bottom
                
            case GHOSTTY_SPLIT_FOCUS_LEFT:
                return .left
                
            case GHOSTTY_SPLIT_FOCUS_RIGHT:
                return .right
                
            default:
                return nil
            }
        }
        
        func toNative() -> ghostty_split_focus_direction_e {
            switch (self) {
            case .previous:
                return GHOSTTY_SPLIT_FOCUS_PREVIOUS
                
            case .next:
                return GHOSTTY_SPLIT_FOCUS_NEXT
                
            case .top:
                return GHOSTTY_SPLIT_FOCUS_TOP
                
            case .bottom:
                return GHOSTTY_SPLIT_FOCUS_BOTTOM
                
            case .left:
                return GHOSTTY_SPLIT_FOCUS_LEFT
                
            case .right:
                return GHOSTTY_SPLIT_FOCUS_RIGHT
            }
        }
    }
}

extension Ghostty.Notification {
    /// Used to pass a configuration along when creating a new tab/window/split.
    static let NewSurfaceConfigKey = "com.mitchellh.ghostty.newSurfaceConfig"
    
    /// Posted when a new split is requested. The sending object will be the surface that had focus. The
    /// userdata has one key "direction" with the direction to split to.
    static let ghosttyNewSplit = Notification.Name("com.mitchellh.ghostty.newSplit")
    
    /// Close the calling surface.
    static let ghosttyCloseSurface = Notification.Name("com.mitchellh.ghostty.closeSurface")
    
    /// Focus previous/next split. Has a SplitFocusDirection in the userinfo.
    static let ghosttyFocusSplit = Notification.Name("com.mitchellh.ghostty.focusSplit")
    static let SplitDirectionKey = ghosttyFocusSplit.rawValue
    
    /// Goto tab. Has tab index in the userinfo.
    static let ghosttyGotoTab = Notification.Name("com.mitchellh.ghostty.gotoTab")
    static let GotoTabKey = ghosttyGotoTab.rawValue
    
    /// New tab. Has base surface config requested in userinfo.
    static let ghosttyNewTab = Notification.Name("com.mitchellh.ghostty.newTab")
    
    /// New window. Has base surface config requested in userinfo.
    static let ghosttyNewWindow = Notification.Name("com.mitchellh.ghostty.newWindow")

    /// Toggle fullscreen of current window
    static let ghosttyToggleFullscreen = Notification.Name("com.mitchellh.ghostty.toggleFullscreen")
    static let NonNativeFullscreenKey = ghosttyToggleFullscreen.rawValue
    
    /// Notification that a surface is becoming focused. This is only sent on macOS 12 to
    /// work around bugs. macOS 13+ should use the ".focused()" attribute.
    static let didBecomeFocusedSurface = Notification.Name("com.mitchellh.ghostty.didBecomeFocusedSurface")
    
    /// Notification sent to toggle split maximize/unmaximize.
    static let didToggleSplitZoom = Notification.Name("com.mitchellh.ghostty.didToggleSplitZoom")
}

// Make the input enum hashable.
extension ghostty_input_key_e : Hashable {}
