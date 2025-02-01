import Foundation
import Cocoa
import SwiftUI
import Combine

class ConfigurationErrorsController: NSWindowController, NSWindowDelegate {
    /// Singleton for the errors view.
    static let sharedInstance = ConfigurationErrorsController()
    
    override var windowNibName: NSNib.Name? { "ConfigurationErrors" }
    
    /// The data model for this view. Update this directly and the associated view will be updated, too.
    let model = ConfigurationErrorsView.Model()
    
    private var cancellable: AnyCancellable?
    
    //MARK: - NSWindowController
    
    override func windowWillLoad() {
        shouldCascadeWindows = false
        
        if let c = cancellable { c.cancel() }
        cancellable = model.$errors.sink { newValue in
            if (newValue.count == 0) {
                self.window?.close()
            }
        }
    }
    
    override func windowDidLoad() {
        guard let window = window else { return }
        window.center()
        window.level = .popUpMenu
        window.contentView = NSHostingView(rootView: ConfigurationErrorsView(model: model))
    }
    
    //MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        if let cancellable = cancellable {
            cancellable.cancel()
            self.cancellable = nil
        }
    }
}
