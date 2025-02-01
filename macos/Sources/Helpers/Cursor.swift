import Cocoa

/// This helps manage the stateful nature of NSCursor hiding and unhiding. 
class Cursor {
    private static var counter: UInt = 0

    static var isVisible: Bool {
        counter == 0
    }

    static func hide() {
        counter += 1
        NSCursor.hide()
    }

    /// Unhide the cursor. Returns true if the cursor was previously hidden.
    static func unhide() -> Bool {
        // Its always safe to call unhide when the counter is zero because it
        // won't go negative.
        NSCursor.unhide()

        if (counter > 0) {
            counter -= 1
            return true
        }

        return false
    }

    static func unhideCompletely() -> UInt {
        let counter = self.counter
        for _ in 0..<counter {
            assert(unhide())
        }
        assert(self.counter == 0)
        return counter
    }
}
