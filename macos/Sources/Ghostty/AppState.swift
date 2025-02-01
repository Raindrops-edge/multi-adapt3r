import SwiftUI
import GhosttyKit

protocol GhosttyAppStateDelegate: AnyObject {
    /// Called when the configuration did finish reloading.
    func configDidReload(_ state: Ghostty.AppState)
}

extension Ghostty {
    enum AppReadiness {
        case loading, error, ready
    }
    
    struct Info {
        var mode: ghostty_build_mode_e
        var version: String
    }
    
    /// The AppState is the global state that is associated with the Swift app. This handles initially
    /// initializing Ghostty, loading the configuration, etc.
    class AppState: ObservableObject {
        /// The readiness value of the state.
        @Published var readiness: AppReadiness = .loading
        
        /// Optional delegate
        weak var delegate: GhosttyAppStateDelegate?
        
        /// The ghostty global configuration. This should only be changed when it is definitely
        /// safe to change. It is definite safe to change only when the embedded app runtime
        /// in Ghostty says so (usually, only in a reload configuration callback).
        @Published var config: ghostty_config_t? = nil {
            didSet {
                // Free the old value whenever we change
                guard let old = oldValue else { return }
                ghostty_config_free(old)
            }
        }
        
        /// The ghostty app instance. We only have one of these for the entire app, although I guess
        /// in theory you can have multiple... I don't know why you would...
        @Published var app: ghostty_app_t? = nil {
            didSet {
                guard let old = oldValue else { return }
                ghostty_app_free(old)
            }
        }
        
        /// True if we need to confirm before quitting.
        var needsConfirmQuit: Bool {
            guard let app = app else { return false }
            return ghostty_app_needs_confirm_quit(app)
        }
        
        /// Build information
        var info: Info {
            let raw = ghostty_info()
            let version = NSString(
                bytes: raw.version,
                length: Int(raw.version_len),
                encoding: NSUTF8StringEncoding
            ) ?? "unknown"
            
            return Info(mode: raw.build_mode, version: String(version))
        }
        
        /// Cached clipboard string for `read_clipboard` callback.
        private var cached_clipboard_string: String? = nil

        init() {
            // Initialize ghostty global state. This happens once per process.
            guard ghostty_init() == GHOSTTY_SUCCESS else {
                AppDelegate.logger.critical("ghostty_init failed")
                readiness = .error
                return
            }
            
            // Initialize the global configuration.
            guard let cfg = Self.loadConfig() else {
                readiness = .error
                return
            }
            self.config = cfg;
            
            // Create our "runtime" config. The "runtime" is the configuration that ghostty
            // uses to interface with the application runtime environment.
            var runtime_cfg = ghostty_runtime_config_s(
                userdata: Unmanaged.passUnretained(self).toOpaque(),
                supports_selection_clipboard: false,
                wakeup_cb: { userdata in AppState.wakeup(userdata) },
                reload_config_cb: { userdata in AppState.reloadConfig(userdata) },
                set_title_cb: { userdata, title in AppState.setTitle(userdata, title: title) },
                set_mouse_shape_cb: { userdata, shape in AppState.setMouseShape(userdata, shape: shape) },
                set_mouse_visibility_cb: { userdata, visible in AppState.setMouseVisibility(userdata, visible: visible) },
                read_clipboard_cb: { userdata, loc in AppState.readClipboard(userdata, location: loc) },
                write_clipboard_cb: { userdata, str, loc in AppState.writeClipboard(userdata, string: str, location: loc) },
                new_split_cb: { userdata, direction, surfaceConfig in AppState.newSplit(userdata, direction: direction, config: surfaceConfig) },
                new_tab_cb: { userdata, surfaceConfig in AppState.newTab(userdata, config: surfaceConfig) },
                new_window_cb: { userdata, surfaceConfig in AppState.newWindow(userdata, config: surfaceConfig) },
                close_surface_cb: { userdata, processAlive in AppState.closeSurface(userdata, processAlive: processAlive) },
                focus_split_cb: { userdata, direction in AppState.focusSplit(userdata, direction: direction) },
                toggle_split_zoom_cb: { userdata in AppState.toggleSplitZoom(userdata) },
                goto_tab_cb: { userdata, n in AppState.gotoTab(userdata, n: n) },
                toggle_fullscreen_cb: { userdata, nonNativeFullscreen in AppState.toggleFullscreen(userdata, nonNativeFullscreen: nonNativeFullscreen) }
            )

            // Create the ghostty app.
            guard let app = ghostty_app_new(&runtime_cfg, cfg) else {
                AppDelegate.logger.critical("ghostty_app_new failed")
                readiness = .error
                return
            }
            self.app = app
            
            // Subscribe to notifications for keyboard layout change so that we can update Ghostty.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.keyboardSelectionDidChange(notification:)),
                name: NSTextInputContext.keyboardSelectionDidChangeNotification,
                object: nil)

            self.readiness = .ready
        }
        
        deinit {
            // This will force the didSet callbacks to run which free.
            self.app = nil
            self.config = nil
            
            // Remove our observer
            NotificationCenter.default.removeObserver(
                self,
                name: NSTextInputContext.keyboardSelectionDidChangeNotification,
                object: nil)
        }
        
        /// Initializes a new configuration and loads all the values.
        static func loadConfig() -> ghostty_config_t? {
            // Initialize the global configuration.
            guard let cfg = ghostty_config_new() else {
                AppDelegate.logger.critical("ghostty_config_new failed")
                return nil
            }
            
            // Load our configuration files from the home directory.
            ghostty_config_load_default_files(cfg);
            ghostty_config_load_cli_args(cfg);
            ghostty_config_load_recursive_files(cfg);
            
            // TODO: we'd probably do some config loading here... for now we'd
            // have to do this synchronously. When we support config updating we can do
            // this async and update later.
            
            // Finalize will make our defaults available.
            ghostty_config_finalize(cfg)
            
            // Log any configuration errors. These will be automatically shown in a
            // pop-up window too.
            let errCount = ghostty_config_errors_count(cfg)
            if errCount > 0 {
                AppDelegate.logger.warning("config error: \(errCount) configuration errors on reload")
                var errors: [String] = [];
                for i in 0..<errCount {
                    let err = ghostty_config_get_error(cfg, UInt32(i))
                    let message = String(cString: err.message)
                    errors.append(message)
                    AppDelegate.logger.warning("config error: \(message)")
                }
            }
            
            return cfg
        }
        
        /// Returns the configuration errors (if any).
        func configErrors() -> [String] {
            guard let cfg = self.config else { return [] }
            
            var errors: [String] = [];
            let errCount = ghostty_config_errors_count(cfg)
            for i in 0..<errCount {
                let err = ghostty_config_get_error(cfg, UInt32(i))
                let message = String(cString: err.message)
                errors.append(message)
            }
            
            return errors
        }
        
        func appTick() {
            guard let app = self.app else { return }
            
            // Tick our app, which lets us know if we want to quit
            let exit = ghostty_app_tick(app)
            if (!exit) { return }
                
            // We want to quit, start that process
            NSApplication.shared.terminate(nil)
        }
        
        func reloadConfig() {
            guard let app = self.app else { return }
            ghostty_app_reload_config(app)
        }
        
        /// Request that the given surface is closed. This will trigger the full normal surface close event
        /// cycle which will call our close surface callback.
        func requestClose(surface: ghostty_surface_t) {
            ghostty_surface_request_close(surface)
        }
        
        func newTab(surface: ghostty_surface_t) {
            let action = "new_tab"
            if (!ghostty_surface_binding_action(surface, action, UInt(action.count))) {
                AppDelegate.logger.warning("action failed action=\(action)")
            }
        }
        
        func newWindow(surface: ghostty_surface_t) {
            let action = "new_window"
            if (!ghostty_surface_binding_action(surface, action, UInt(action.count))) {
                AppDelegate.logger.warning("action failed action=\(action)")
            }
        }
        
        func split(surface: ghostty_surface_t, direction: ghostty_split_direction_e) {
            ghostty_surface_split(surface, direction)
        }
        
        func splitMoveFocus(surface: ghostty_surface_t, direction: SplitFocusDirection) {
            ghostty_surface_split_focus(surface, direction.toNative())
        }
        
        func splitToggleZoom(surface: ghostty_surface_t) {
            let action = "toggle_split_zoom"
            if (!ghostty_surface_binding_action(surface, action, UInt(action.count))) {
                AppDelegate.logger.warning("action failed action=\(action)")
            }
        }
        
        // Called when the selected keyboard changes. We have to notify Ghostty so that
        // it can reload the keyboard mapping for input.
        @objc private func keyboardSelectionDidChange(notification: NSNotification) {
            guard let app = self.app else { return }
            ghostty_app_keyboard_changed(app)
        }
        
        // MARK: Ghostty Callbacks
        
        static func newSplit(_ userdata: UnsafeMutableRawPointer?, direction: ghostty_split_direction_e, config: ghostty_surface_config_s) {
            guard let surface = self.surfaceUserdata(from: userdata) else { return }
            NotificationCenter.default.post(name: Notification.ghosttyNewSplit, object: surface, userInfo: [
                "direction": direction,
                Notification.NewSurfaceConfigKey: config,
            ])
        }
        
        static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
            guard let surface = self.surfaceUserdata(from: userdata) else { return }
            NotificationCenter.default.post(name: Notification.ghosttyCloseSurface, object: surface, userInfo: [
                "process_alive": processAlive,
            ])
        }
        
        static func focusSplit(_ userdata: UnsafeMutableRawPointer?, direction: ghostty_split_focus_direction_e) {
            guard let surface = self.surfaceUserdata(from: userdata) else { return }
            guard let splitDirection = SplitFocusDirection.from(direction: direction) else { return }
            NotificationCenter.default.post(
                name: Notification.ghosttyFocusSplit,
                object: surface,
                userInfo: [
                    Notification.SplitDirectionKey: splitDirection,
                ]
            )
        }
        
        static func toggleSplitZoom(_ userdata: UnsafeMutableRawPointer?) {
            guard let surface = self.surfaceUserdata(from: userdata) else { return }
            
            NotificationCenter.default.post(
                name: Notification.didToggleSplitZoom,
                object: surface
            )
        }
        
        static func gotoTab(_ userdata: UnsafeMutableRawPointer?, n: Int32) {
            guard let surface = self.surfaceUserdata(from: userdata) else { return }
            NotificationCenter.default.post(
                name: Notification.ghosttyGotoTab,
                object: surface,
                userInfo: [
                    Notification.GotoTabKey: n,
                ]
            )
        }
        
        static func readClipboard(_ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e) -> UnsafePointer<CChar>? {
            // We only support the standard clipboard
            if (location != GHOSTTY_CLIPBOARD_STANDARD) { return nil }
            
            guard let appState = self.appState(fromSurface: userdata) else { return nil }
            guard let str = NSPasteboard.general.string(forType: .string) else { return nil }
            
            // Ghostty requires we cache the string because the pointer we return has to remain
            // stable until the next call to readClipboard.
            appState.cached_clipboard_string = str
            return (str as NSString).utf8String
        }
        
        static func writeClipboard(_ userdata: UnsafeMutableRawPointer?, string: UnsafePointer<CChar>?, location: ghostty_clipboard_e) {
            // We only support the standard clipboard
            if (location != GHOSTTY_CLIPBOARD_STANDARD) { return }
            
            guard let valueStr = String(cString: string!, encoding: .utf8) else { return }
            let pb = NSPasteboard.general
            pb.declareTypes([.string], owner: nil)
            pb.setString(valueStr, forType: .string)
        }
        
        static func reloadConfig(_ userdata: UnsafeMutableRawPointer?) -> ghostty_config_t? {
            guard let newConfig = Self.loadConfig() else {
                AppDelegate.logger.warning("failed to reload configuration")
                return nil
            }
            
            // Assign the new config. This will automatically free the old config.
            // It is safe to free the old config from within this function call.
            let state = Unmanaged<AppState>.fromOpaque(userdata!).takeUnretainedValue()
            state.config = newConfig
            
            // If we have a delegate, notify.
            if let delegate = state.delegate {
                delegate.configDidReload(state)
            }
            
            return newConfig
        }
        
        static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
            let state = Unmanaged<AppState>.fromOpaque(userdata!).takeUnretainedValue()
            
            // Wakeup can be called from any thread so we schedule the app tick
            // from the main thread. There is probably some improvements we can make
            // to coalesce multiple ticks but I don't think it matters from a performance
            // standpoint since we don't do this much.
            DispatchQueue.main.async { state.appTick() }
        }
        
        static func setTitle(_ userdata: UnsafeMutableRawPointer?, title: UnsafePointer<CChar>?) {
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata!).takeUnretainedValue()
            guard let titleStr = String(cString: title!, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                surfaceView.title = titleStr
            }
        }
        
        static func setMouseShape(_ userdata: UnsafeMutableRawPointer?, shape: ghostty_mouse_shape_e) {
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata!).takeUnretainedValue()
            surfaceView.setCursorShape(shape)
        }
        
        static func setMouseVisibility(_ userdata: UnsafeMutableRawPointer?, visible: Bool) {
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata!).takeUnretainedValue()
            surfaceView.setCursorVisibility(visible)
        }

        static func toggleFullscreen(_ userdata: UnsafeMutableRawPointer?, nonNativeFullscreen: ghostty_non_native_fullscreen_e) {
            guard let surface = self.surfaceUserdata(from: userdata) else { return }
            NotificationCenter.default.post(
                name: Notification.ghosttyToggleFullscreen,
                object: surface,
                userInfo: [
                    Notification.NonNativeFullscreenKey: nonNativeFullscreen,
                ]
            )
        }
        
        static func newTab(_ userdata: UnsafeMutableRawPointer?, config: ghostty_surface_config_s) {
            guard let surface = self.surfaceUserdata(from: userdata) else { return }
            
            NotificationCenter.default.post(
                name: Notification.ghosttyNewTab,
                object: surface,
                userInfo: [
                    Notification.NewSurfaceConfigKey: config
                ]
            )
        }
        
        static func newWindow(_ userdata: UnsafeMutableRawPointer?, config: ghostty_surface_config_s) {
            guard let surface = self.surfaceUserdata(from: userdata) else { return }
            
            NotificationCenter.default.post(
                name: Notification.ghosttyNewWindow,
                object: surface,
                userInfo: [
                    Notification.NewSurfaceConfigKey: config
                ]
            )
        }
        
        /// Returns the GhosttyState from the given userdata value.
        static private func appState(fromSurface userdata: UnsafeMutableRawPointer?) -> AppState? {
            let surfaceView = Unmanaged<SurfaceView>.fromOpaque(userdata!).takeUnretainedValue()
            guard let surface = surfaceView.surface else { return nil }
            guard let app = ghostty_surface_app(surface) else { return nil }
            guard let app_ud = ghostty_app_userdata(app) else { return nil }
            return Unmanaged<AppState>.fromOpaque(app_ud).takeUnretainedValue()
        }
        
        /// Returns the surface view from the userdata.
        static private func surfaceUserdata(from userdata: UnsafeMutableRawPointer?) -> SurfaceView? {
            return Unmanaged<SurfaceView>.fromOpaque(userdata!).takeUnretainedValue()
        }
    }
}

// MARK: AppState Environment Keys

private struct GhosttyAppKey: EnvironmentKey {
    static let defaultValue: ghostty_app_t? = nil
}

private struct GhosttyConfigKey: EnvironmentKey {
    static let defaultValue: ghostty_config_t? = nil
}

extension EnvironmentValues {
    var ghosttyApp: ghostty_app_t? {
        get { self[GhosttyAppKey.self] }
        set { self[GhosttyAppKey.self] = newValue }
    }
    
    var ghosttyConfig: ghostty_config_t? {
        get { self[GhosttyConfigKey.self] }
        set { self[GhosttyConfigKey.self] = newValue }
    }
}

extension View {
    func ghosttyApp(_ app: ghostty_app_t?) -> some View {
        environment(\.ghosttyApp, app)
    }
    
    func ghosttyConfig(_ config: ghostty_config_t?) -> some View {
        environment(\.ghosttyConfig, config)
    }
}
