import AppKit

extension NSPasteboard {
    /// Gets the contents of the pasteboard as a string following a specific set of semantics.
    /// Does these things in order:
    /// - Tries to get the absolute filesystem path of the file in the pasteboard if there is one.
    /// - Tries to get any string from the pasteboard.
    /// If all of the above fail, returns None.
    func getOpinionatedStringContents() -> String? {
        if let file = self.string(forType: .fileURL) {
            if let path = NSURL(string: file)?.path {
                return path
            }
        }
        return self.string(forType: .string)
    }
}
