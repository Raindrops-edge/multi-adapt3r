import SwiftUI

extension View {
    /// Returns the ghostty icon to use for views.
    func ghosttyIconImage() -> Image {
        #if os(macOS)
        if let delegate = NSApplication.shared.delegate as? AppDelegate,
           let nsImage = delegate.appIcon {
            return Image(nsImage: nsImage)
        }
        #endif

        return Image("AppIconImage")
    }
}
