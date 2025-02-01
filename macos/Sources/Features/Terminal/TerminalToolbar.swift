import Cocoa

// Custom NSToolbar subclass that displays a centered window title,
// in order to accommodate the titlebar tabs feature.
class TerminalToolbar: NSToolbar, NSToolbarDelegate {
    private let titleTextField = CenteredDynamicLabel(labelWithString: "👻 Ghostty")

    var titleText: String {
        get {
            titleTextField.stringValue
        }

        set {
            titleTextField.stringValue = newValue
        }
    }

    var titleFont: NSFont? {
        get {
            titleTextField.font
        }

        set {
            titleTextField.font = newValue
        }
    }

    override init(identifier: NSToolbar.Identifier) {
        super.init(identifier: identifier)

        delegate = self
        centeredItemIdentifiers.insert(.titleText)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        var item: NSToolbarItem

        switch itemIdentifier {
        case .titleText:
            item = NSToolbarItem(itemIdentifier: .titleText)
            item.view = self.titleTextField
            item.visibilityPriority = .user

            // NSToolbarItem.minSize and NSToolbarItem.maxSize are deprecated, and make big ugly
            // warnings in Xcode when you use them, but I cannot for the life of me figure out
            // how to get this to work with constraints. The behavior isn't the same, instead of
            // shrinking the item and clipping the subview, it hides the item as soon as the
            // intrinsic size of the subview gets too big for the toolbar width, regardless of
            // whether I have constraints set on its width, height, or both :/
            //
            // If someone can fix this so we don't have to use deprecated properties: Please do.
            item.minSize = NSSize(width: 32, height: 1)
            item.maxSize = NSSize(width: 1024, height: self.titleTextField.intrinsicContentSize.height)

            item.isEnabled = true
        case .resetZoom:
            item = NSToolbarItem(itemIdentifier: .resetZoom)
        default:
            item = NSToolbarItem(itemIdentifier: itemIdentifier)
        }

        return item
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.titleText, .flexibleSpace, .space, .resetZoom]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // These space items are here to ensure that the title remains centered when it starts
        // getting smaller than the max size so starts clipping. Lucky for us, two of the
        // built-in spacers plus the un-zoom button item seems to exactly match the space
        // on the left that's reserved for the window buttons.
		return [.titleText, .flexibleSpace, .space, .space, .resetZoom]
    }
}

/// A label that expands to fit whatever text you put in it and horizontally centers itself in the current window.
fileprivate class CenteredDynamicLabel: NSTextField {
    override func viewDidMoveToSuperview() {
        // Truncate the title when it gets too long, cutting it off with an ellipsis.
        cell?.truncatesLastVisibleLine = true
        cell?.lineBreakMode = .byCharWrapping

        // Make the text field as small as possible while fitting its text.
        setContentHuggingPriority(.required, for: .horizontal)
        cell?.alignment = .center

        // We've changed some alignment settings, make sure the layout is updated immediately.
        needsLayout = true
    }
}

extension NSToolbarItem.Identifier {
    static let resetZoom = NSToolbarItem.Identifier("ResetZoom")
    static let titleText = NSToolbarItem.Identifier("TitleText")
}
