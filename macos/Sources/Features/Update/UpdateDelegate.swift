import Sparkle
import Cocoa

class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        // Eventually w want to support multiple channels. Sparkle itself supports
        // channels but we probably don't want some appcasts in the same file (i.e.
        // tip) so this would be the place to change that. For now, we hardcode the
        // tip appcast URL since it is all we support.
        return "https://tip.files.ghostty.dev/appcast.xml"
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // When the updater is relaunching the application we want to get macOS
        // to invalidate and re-encode all of our restorable state so that when
        // we relaunch it uses it.
        NSApp.invalidateRestorableState()
        for window in NSApp.windows { window.invalidateRestorableState() }
    }
}
