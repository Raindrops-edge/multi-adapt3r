import Sparkle

class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        // Eventually w want to support multiple channels. Sparkle itself supports
        // channels but we probably don't want some appcasts in the same file (i.e.
        // tip) so this would be the place to change that. For now, we hardcode the
        // tip appcast URL since it is all we support.
        return "https://tip.files.ghostty.dev/appcast.xml"
    }
}
