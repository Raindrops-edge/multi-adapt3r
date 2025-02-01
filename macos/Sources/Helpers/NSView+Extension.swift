import AppKit

extension NSView {
    /// Recursively finds and returns the first descendant view that has the given class name.
    func firstDescendant(withClassName name: String) -> NSView? {
        for subview in subviews {
            if String(describing: type(of: subview)) == name {
                return subview
            } else if let found = subview.firstDescendant(withClassName: name) {
                return found
            }
        }

        return nil
    }

    /// Recursively finds and returns descendant views that have the given class name.
    func descendants(withClassName name: String) -> [NSView] {
        var result = [NSView]()

        for subview in subviews {
            if String(describing: type(of: subview)) == name {
                result.append(subview)
            }

            result += subview.descendants(withClassName: name)
        }

        return result
    }

	/// Recursively finds and returns the first descendant view that has the given identifier.
	func firstDescendant(withID id: String) -> NSView? {
		for subview in subviews {
			if subview.identifier == NSUserInterfaceItemIdentifier(id) {
				return subview
			} else if let found = subview.firstDescendant(withID: id) {
				return found
			}
		}

		return nil
	}
}
