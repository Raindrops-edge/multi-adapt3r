import SwiftUI

// All backport view/scene modifiers go as an extension on this. We use this
// so we can easily track and centralize all backports.
struct Backport<Content> {
    let content: Content
}

extension View {
    var backport: Backport<Self> { Backport(content: self) }
}

extension Scene {
    var backport: Backport<Self> { Backport(content: self) }
}

extension Backport where Content: Scene {
    func defaultSize(width: CGFloat, height: CGFloat) -> some Scene {
        if #available(macOS 13, *) {
            return content.defaultSize(width: width, height: height)
        } else {
            return content
        }
    }
}
