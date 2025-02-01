import SwiftUI
import GhosttyKit

extension Ghostty {
    /// Render a terminal for the active app in the environment.
    struct Terminal: View {
        @Environment(\.ghosttyApp) private var app
        @FocusedValue(\.ghosttySurfaceTitle) private var surfaceTitle: String?

        var body: some View {
            if let app = self.app {
                SurfaceForApp(app) { surfaceView in
                    SurfaceWrapper(surfaceView: surfaceView)
                }
                .navigationTitle(surfaceTitle ?? "Ghostty")
            }
        }
    }

    /// Yields a SurfaceView for a ghostty app that can then be used however you want.
    struct SurfaceForApp<Content: View>: View {
        let content: ((SurfaceView) -> Content)

        @StateObject private var surfaceView: SurfaceView

        init(_ app: ghostty_app_t, @ViewBuilder content: @escaping ((SurfaceView) -> Content)) {
            _surfaceView = StateObject(wrappedValue: SurfaceView(app, nil))
            self.content = content
        }

        var body: some View {
            content(surfaceView)
        }
    }

    struct SurfaceWrapper: View {
        // The surface to create a view for. This must be created upstream. As long as this
        // remains the same, the surface that is being rendered remains the same.
        @ObservedObject var surfaceView: SurfaceView

        // True if this surface is part of a split view. This is important to know so
        // we know whether to dim the surface out of focus.
        var isSplit: Bool = false

        // Maintain whether our view has focus or not
        @FocusState private var surfaceFocus: Bool

        // Maintain whether our window has focus (is key) or not
        @State private var windowFocus: Bool = true

        @Environment(\.ghosttyConfig) private var ghostty_config

        // This is true if the terminal is considered "focused". The terminal is focused if
        // it is both individually focused and the containing window is key.
        private var hasFocus: Bool { surfaceFocus && windowFocus }

        // The opacity of the rectangle when unfocused.
        private var unfocusedOpacity: Double {
            var opacity: Double = 0.85
            let key = "unfocused-split-opacity"
            _ = ghostty_config_get(ghostty_config, &opacity, key, UInt(key.count))
            return 1 - opacity
        }

        var body: some View {
            ZStack {
                // We use a GeometryReader to get the frame bounds so that our metal surface
                // is up to date. See TerminalSurfaceView for why we don't use the NSView
                // resize callback.
                GeometryReader { geo in
                    // We use these notifications to determine when the window our surface is
                    // attached to is or is not focused.
                    let pubBecomeFocused = NotificationCenter.default.publisher(for: Notification.didBecomeFocusedSurface, object: surfaceView)
                    let pubBecomeKey = NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
                    let pubResign = NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)

                    Surface(view: surfaceView, hasFocus: hasFocus, size: geo.size)
                        .focused($surfaceFocus)
                        .focusedValue(\.ghosttySurfaceTitle, surfaceView.title)
                        .focusedValue(\.ghosttySurfaceView, surfaceView)
                        .onReceive(pubBecomeKey) { notification in
                            guard let window = notification.object as? NSWindow else { return }
                            guard let surfaceWindow = surfaceView.window else { return }
                            windowFocus = surfaceWindow == window
                        }
                        .onReceive(pubResign) { notification in
                            guard let window = notification.object as? NSWindow else { return }
                            guard let surfaceWindow = surfaceView.window else { return }
                            if (surfaceWindow == window) {
                                windowFocus = false
                            }
                        }
                        .onReceive(pubBecomeFocused) { notification in
                            // We only want to run this on older macOS versions where the .focused
                            // method doesn't work properly. See the dispatch of this notification
                            // for more information.
                            if #available(macOS 13, *) { return }

                            DispatchQueue.main.async {
                                surfaceFocus = true
                            }
                        }
                        .onAppear() {
                            // Welcome to the SwiftUI bug house of horrors. On macOS 12 (at least
                            // 12.5.1, didn't test other versions), the order in which the view
                            // is added to the window hierarchy is such that $surfaceFocus is
                            // not set to true for the first surface in a window. As a result,
                            // new windows are key (they have window focus) but the terminal surface
                            // does not have surface until the user clicks. Bad!
                            //
                            // There is a very real chance that I am doing something wrong, but it
                            // works great as-is on macOS 13, so I've instead decided to make the
                            // older macOS hacky. A workaround is on initial appearance to "steal
                            // focus" under certain conditions that seem to imply we're in the
                            // screwy state.
                            if #available(macOS 13, *) {
                                // If we're on a more modern version of macOS, do nothing.
                                return
                            }
                            if #available(macOS 12, *) {
                                // On macOS 13, the view is attached to a window at this point,
                                // so this is one extra check that we're a new view and behaving odd.
                                guard surfaceView.window == nil else { return }
                                DispatchQueue.main.async {
                                    surfaceFocus = true
                                }
                            }

                            // I don't know how older macOS versions behave but Ghostty only
                            // supports back to macOS 12 so its moot.
                        }
                }
                .ghosttySurfaceView(surfaceView)

                // If we're part of a split view and don't have focus, we put a semi-transparent
                // rectangle above our view to make it look unfocused. We use "surfaceFocus"
                // because we want to keep our focused surface dark even if we don't have window
                // focus.
                if (isSplit && !surfaceFocus) {
                    Rectangle()
                        .fill(.white)
                        .allowsHitTesting(false)
                        .opacity(unfocusedOpacity)
                }
            }
        }
    }

    /// A surface is terminology in Ghostty for a terminal surface, or a place where a terminal is actually drawn
    /// and interacted with. The word "surface" is used because a surface may represent a window, a tab,
    /// a split, a small preview pane, etc. It is ANYTHING that has a terminal drawn to it.
    ///
    /// We just wrap an AppKit NSView here at the moment so that we can behave as low level as possible
    /// since that is what the Metal renderer in Ghostty expects. In the future, it may make more sense to
    /// wrap an MTKView and use that, but for legacy reasons we didn't do that to begin with.
    struct Surface: NSViewRepresentable {
        /// The view to render for the terminal surface.
        let view: SurfaceView

        /// This should be set to true when the surface has focus. This is up to the parent because
        /// focus is also defined by window focus. It is important this is set correctly since if it is
        /// false then the surface will idle at almost 0% CPU.
        let hasFocus: Bool

        /// The size of the frame containing this view. We use this to update the the underlying
        /// surface. This does not actually SET the size of our frame, this only sets the size
        /// of our Metal surface for drawing.
        ///
        /// Note: we do NOT use the NSView.resize function because SwiftUI on macOS 12
        /// does not call this callback (macOS 13+ does).
        ///
        /// The best approach is to wrap this view in a GeometryReader and pass in the geo.size.
        let size: CGSize

        func makeNSView(context: Context) -> SurfaceView {
            // We need the view as part of the state to be created previously because
            // the view is sent to the Ghostty API so that it can manipulate it
            // directly since we draw on a render thread.
            return view;
        }

        func updateNSView(_ view: SurfaceView, context: Context) {
            view.focusDidChange(hasFocus)
            view.sizeDidChange(size)
        }
    }

    /// The NSView implementation for a terminal surface.
    class SurfaceView: NSView, NSTextInputClient, ObservableObject {
        // The current title of the surface as defined by the pty. This can be
        // changed with escape codes. This is public because the callbacks go
        // to the app level and it is set from there.
        @Published var title: String = "👻"

        private(set) var surface: ghostty_surface_t?
        var error: Error? = nil

        private var markedText: NSMutableAttributedString
        private var mouseEntered: Bool = false
        private var focused: Bool = true
        private var cursor: NSCursor = .iBeam
        private var cursorVisible: CursorVisibility = .visible

        // We need to support being a first responder so that we can get input events
        override var acceptsFirstResponder: Bool { return true }

        // I don't think we need this but this lets us know we should redraw our layer
        // so we'll use that to tell ghostty to refresh.
        override var wantsUpdateLayer: Bool { return true }

        // State machine for mouse cursor visibility because every call to
        // NSCursor.hide/unhide must be balanced.
        enum CursorVisibility {
            case visible
            case hidden
            case pendingVisible
            case pendingHidden
        }

        init(_ app: ghostty_app_t, _ baseConfig: ghostty_surface_config_s?) {
            self.markedText = NSMutableAttributedString()

            // Initialize with some default frame size. The important thing is that this
            // is non-zero so that our layer bounds are non-zero so that our renderer
            // can do SOMETHING.
            super.init(frame: NSMakeRect(0, 0, 800, 600))

            // Setup our surface. This will also initialize all the terminal IO.
            var surface_cfg = baseConfig ?? ghostty_surface_config_new()
            surface_cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
            surface_cfg.nsview = Unmanaged.passUnretained(self).toOpaque()
            surface_cfg.scale_factor = NSScreen.main!.backingScaleFactor

            guard let surface = ghostty_surface_new(app, &surface_cfg) else {
                self.error = AppError.surfaceCreateError
                return
            }
            self.surface = surface;

            // Setup our tracking area so we get mouse moved events
            updateTrackingAreas()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported for this view")
        }

        deinit {
            trackingAreas.forEach { removeTrackingArea($0) }
            
            // mouseExited is not called by AppKit one last time when the view
            // closes so we do it manually to ensure our NSCursor state remains
            // accurate.
            if (mouseEntered) {
                mouseExited(with: NSEvent())
            }
            
            guard let surface = self.surface else { return }
            ghostty_surface_free(surface)
        }

        /// Close the surface early. This will free the associated Ghostty surface and the view will
        /// no longer render. The view can never be used again. This is a way for us to free the
        /// Ghostty resources while references may still be held to this view. I've found that SwiftUI
        /// tends to hold this view longer than it should so we free the expensive stuff explicitly.
        func close() {
            guard let surface = self.surface else { return }
            ghostty_surface_free(surface)
            self.surface = nil
        }

        func focusDidChange(_ focused: Bool) {
            guard let surface = self.surface else { return }
            ghostty_surface_set_focus(surface, focused)
        }

        func sizeDidChange(_ size: CGSize) {
            guard let surface = self.surface else { return }

            // Ghostty wants to know the actual framebuffer size... It is very important
            // here that we use "size" and NOT the view frame. If we're in the middle of
            // an animation (i.e. a fullscreen animation), the frame will not yet be updated.
            // The size represents our final size we're going for.
            let scaledSize = self.convertToBacking(size)
            ghostty_surface_set_size(surface, UInt32(scaledSize.width), UInt32(scaledSize.height))
        }

        func setCursorShape(_ shape: ghostty_mouse_shape_e) {
            switch (shape) {
            case GHOSTTY_MOUSE_SHAPE_DEFAULT:
                cursor = .arrow

            case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU:
                cursor = .contextualMenu

            case GHOSTTY_MOUSE_SHAPE_TEXT:
                cursor = .iBeam

            case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
                cursor = .crosshair

            case GHOSTTY_MOUSE_SHAPE_GRAB:
                cursor = .openHand

            case GHOSTTY_MOUSE_SHAPE_GRABBING:
                cursor = .closedHand

            case GHOSTTY_MOUSE_SHAPE_POINTER:
                cursor = .pointingHand

            case GHOSTTY_MOUSE_SHAPE_W_RESIZE:
                cursor = .resizeLeft

            case GHOSTTY_MOUSE_SHAPE_E_RESIZE:
                cursor = .resizeRight

            case GHOSTTY_MOUSE_SHAPE_N_RESIZE:
                cursor = .resizeUp

            case GHOSTTY_MOUSE_SHAPE_S_RESIZE:
                cursor = .resizeDown

            case GHOSTTY_MOUSE_SHAPE_NS_RESIZE:
                cursor = .resizeUpDown

            case GHOSTTY_MOUSE_SHAPE_EW_RESIZE:
                cursor = .resizeLeftRight

            case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT:
                cursor = .iBeamCursorForVerticalLayout

            case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED:
                cursor = .operationNotAllowed

            default:
                // We ignore unknown shapes.
                return
            }

            // Set our cursor immediately if our mouse is over our window
            if (mouseEntered) { cursorUpdate(with: NSEvent()) }
            if let window = self.window {
                window.invalidateCursorRects(for: self)
            }
        }
        
        func setCursorVisibility(_ visible: Bool) {
            switch (cursorVisible) {
            case .visible:
                // If we want to be visible, do nothing. If we want to be hidden
                // enter the pending state.
                if (visible) { return }
                cursorVisible = .pendingHidden
                
            case .hidden:
                // If we want to be hidden, do nothing. If we want to be visible
                // enter the pending state.
                if (!visible) { return }
                cursorVisible = .pendingVisible
                
            case .pendingVisible:
                // If we want to be visible, do nothing because we're already pending.
                // If we want to be hidden, we're already hidden so reset state.
                if (visible) { return }
                cursorVisible = .hidden
                
            case .pendingHidden:
                // If we want to be hidden, do nothing because we're pending that switch.
                // If we want to be visible, we're already visible so reset state.
                if (!visible) { return }
                cursorVisible = .visible
            }

            if (mouseEntered) {
                cursorUpdate(with: NSEvent())
            }
        }

        override func viewDidMoveToWindow() {
            guard let window = self.window else { return }
            guard let surface = self.surface else { return }
            guard ghostty_surface_transparent(surface) else { return }

            // Set the window transparency settings
            window.isOpaque = false
            window.hasShadow = false
            window.backgroundColor = .clear

            // If we have a blur, set the blur
            ghostty_set_window_background_blur(surface, Unmanaged.passUnretained(window).toOpaque())
        }
        
        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if (result) { focused = true }
            return result
        }

        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()

            // We sometimes call this manually (see SplitView) as a way to force us to
            // yield our focus state.
            if (result) {
                focusDidChange(false)
                focused = false
            }

            return result
        }

        override func updateTrackingAreas() {
            // To update our tracking area we just recreate it all.
            trackingAreas.forEach { removeTrackingArea($0) }

            // This tracking area is across the entire frame to notify us of mouse movements.
            addTrackingArea(NSTrackingArea(
                rect: frame,
                options: [
                    .mouseEnteredAndExited,
                    .mouseMoved,
                    .inVisibleRect,

                    // It is possible this is incorrect when we have splits. This will make
                    // mouse events only happen while the terminal is focused. Is that what
                    // we want?
                    .activeWhenFirstResponder,
                ],
                owner: self,
                userInfo: nil))
        }

        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(frame, cursor: self.cursor)
        }

        override func viewDidChangeBackingProperties() {
            guard let surface = self.surface else { return }

            // Detect our X/Y scale factor so we can update our surface
            let fbFrame = self.convertToBacking(self.frame)
            let xScale = fbFrame.size.width / self.frame.size.width
            let yScale = fbFrame.size.height / self.frame.size.height
            ghostty_surface_set_content_scale(surface, xScale, yScale)

            // When our scale factor changes, so does our fb size so we send that too
            ghostty_surface_set_size(surface, UInt32(fbFrame.size.width), UInt32(fbFrame.size.height))
        }

        override func updateLayer() {
            guard let surface = self.surface else { return }
            ghostty_surface_refresh(surface);
        }

        override func mouseDown(with event: NSEvent) {
            guard let surface = self.surface else { return }
            let mods = Self.translateFlags(event.modifierFlags)
            ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
        }

        override func mouseUp(with event: NSEvent) {
            guard let surface = self.surface else { return }
            let mods = Self.translateFlags(event.modifierFlags)
            ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let surface = self.surface else { return }
            let mods = Self.translateFlags(event.modifierFlags)
            ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
        }

        override func rightMouseUp(with event: NSEvent) {
            guard let surface = self.surface else { return }
            let mods = Self.translateFlags(event.modifierFlags)
            ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods)
        }

        override func mouseMoved(with event: NSEvent) {
            guard let surface = self.surface else { return }
            
            // Convert window position to view position. Note (0, 0) is bottom left.
            let pos = self.convert(event.locationInWindow, from: nil)
            ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y)

        }

        override func mouseDragged(with event: NSEvent) {
            self.mouseMoved(with: event)
        }

        override func mouseEntered(with event: NSEvent) {
            mouseEntered = true
            
            // If our cursor is hidden, we hide it on upon entry and we unhide
            // it on exit (mouseExited)
            if (cursorVisible == .hidden) {
                NSCursor.hide()
            }
        }

        override func mouseExited(with event: NSEvent) {
            mouseEntered = false
            
            if (cursorVisible == .hidden) {
                NSCursor.unhide()
            }
        }

        override func scrollWheel(with event: NSEvent) {
            guard let surface = self.surface else { return }

            // Builds up the "input.ScrollMods" bitmask
            var mods: Int32 = 0

            var x = event.scrollingDeltaX
            var y = event.scrollingDeltaY
            if event.hasPreciseScrollingDeltas {
                mods = 1

                // We do a 2x speed multiplier. This is subjective, it "feels" better to me.
                x *= 2;
                y *= 2;

                // TODO(mitchellh): do we have to scale the x/y here by window scale factor?
            }

            // Determine our momentum value
            var momentum: ghostty_input_mouse_momentum_e = GHOSTTY_MOUSE_MOMENTUM_NONE
            switch (event.momentumPhase) {
            case .began:
                momentum = GHOSTTY_MOUSE_MOMENTUM_BEGAN
            case .stationary:
                momentum = GHOSTTY_MOUSE_MOMENTUM_STATIONARY
            case .changed:
                momentum = GHOSTTY_MOUSE_MOMENTUM_CHANGED
            case .ended:
                momentum = GHOSTTY_MOUSE_MOMENTUM_ENDED
            case .cancelled:
                momentum = GHOSTTY_MOUSE_MOMENTUM_CANCELLED
            case .mayBegin:
                momentum = GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
            default:
                break
            }

            // Pack our momentum value into the mods bitmask
            mods |= Int32(momentum.rawValue) << 1

            ghostty_surface_mouse_scroll(surface, x, y, mods)
        }

        override func cursorUpdate(with event: NSEvent) {
            if (focused) {
                switch (cursorVisible) {
                case .visible, .hidden:
                    // Do nothing, stable state
                    break
                    
                case .pendingHidden:
                    NSCursor.hide()
                    cursorVisible = .hidden
                    
                case .pendingVisible:
                    NSCursor.unhide()
                    cursorVisible = .visible
                }
            }
            
            cursor.set()
        }

        override func keyDown(with event: NSEvent) {
            let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
            keyAction(action, event: event)

            // We specifically DO NOT call interpretKeyEvents because ghostty_surface_key
            // automatically handles all key translation, and we don't handle any commands
            // currently.
            //
            // It is possible that in the future we'll have to modify ghostty_surface_key
            // and the embedding API so that we can call this because macOS needs to do
            // some things with certain keys. I'm not sure. For now this works.
            //
            // self.interpretKeyEvents([event])
        }

        override func keyUp(with event: NSEvent) {
            keyAction(GHOSTTY_ACTION_RELEASE, event: event)
        }

        override func flagsChanged(with event: NSEvent) {
            let mod: UInt32;
            switch (event.keyCode) {
            case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
            case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
            case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
            case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
            case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
            default: return
            }

            // The keyAction function will do this AGAIN below which sucks to repeat
            // but this is super cheap and flagsChanged isn't that common.
            let mods = Self.translateFlags(event.modifierFlags)

            // If the key that pressed this is active, its a press, else release
            var action = GHOSTTY_ACTION_RELEASE
            if (mods.rawValue & mod != 0) { action = GHOSTTY_ACTION_PRESS }

            keyAction(action, event: event)
        }

        private func keyAction(_ action: ghostty_input_action_e, event: NSEvent) {
            guard let surface = self.surface else { return }
            let mods = Self.translateFlags(event.modifierFlags)
            ghostty_surface_key(surface, action, UInt32(event.keyCode), mods)
        }

        // MARK: Menu Handlers

        @IBAction func copy(_ sender: Any?) {
            guard let surface = self.surface else { return }
            let action = "copy_to_clipboard"
            if (!ghostty_surface_binding_action(surface, action, UInt(action.count))) {
                AppDelegate.logger.warning("action failed action=\(action)")
            }
        }

        @IBAction func paste(_ sender: Any?) {
            guard let surface = self.surface else { return }
            let action = "paste_from_clipboard"
            if (!ghostty_surface_binding_action(surface, action, UInt(action.count))) {
                AppDelegate.logger.warning("action failed action=\(action)")
            }
        }

        @IBAction func pasteAsPlainText(_ sender: Any?) {
            guard let surface = self.surface else { return }
            let action = "paste_from_clipboard"
            if (!ghostty_surface_binding_action(surface, action, UInt(action.count))) {
                AppDelegate.logger.warning("action failed action=\(action)")
            }
        }

        // MARK: NSTextInputClient

        func hasMarkedText() -> Bool {
            return markedText.length > 0
        }

        func markedRange() -> NSRange {
            guard markedText.length > 0 else { return NSRange() }
            return NSRange(0...(markedText.length-1))
        }

        func selectedRange() -> NSRange {
            return NSRange()
        }

        func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            switch string {
            case let v as NSAttributedString:
                self.markedText = NSMutableAttributedString(attributedString: v)

            case let v as String:
                self.markedText = NSMutableAttributedString(string: v)

            default:
                print("unknown marked text: \(string)")
            }
        }

        func unmarkText() {
            self.markedText.mutableString.setString("")
        }

        func validAttributesForMarkedText() -> [NSAttributedString.Key] {
            return []
        }

        func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
            return nil
        }

        func characterIndex(for point: NSPoint) -> Int {
            return 0
        }

        func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
            guard let surface = self.surface else {
                return NSMakeRect(frame.origin.x, frame.origin.y, 0, 0)
            }

            // Ghostty will tell us where it thinks an IME keyboard should render.
            var x: Double = 0;
            var y: Double = 0;
            ghostty_surface_ime_point(surface, &x, &y)

            // Ghostty coordinates are in top-left (0, 0) so we have to convert to
            // bottom-left since that is what UIKit expects
            let rect = NSMakeRect(x, frame.size.height - y, 0, 0)

            // Convert from view to screen coordinates
            guard let window = self.window else { return rect }
            return window.convertToScreen(rect)
        }

        func insertText(_ string: Any, replacementRange: NSRange) {
            // We must have an associated event
            guard NSApp.currentEvent != nil else { return }
            guard let surface = self.surface else { return }

            // We want the string view of the any value
            var chars = ""
            switch (string) {
            case let v as NSAttributedString:
                chars = v.string
            case let v as String:
                chars = v
            default:
                return
            }

            for codepoint in chars.unicodeScalars {
                ghostty_surface_char(surface, codepoint.value)
            }
        }

        override func doCommand(by selector: Selector) {
            // This currently just prevents NSBeep from interpretKeyEvents but in the future
            // we may want to make some of this work.

            print("SEL: \(selector)")
        }

        private static func translateFlags(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
            var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue

            if (flags.contains(.shift)) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
            if (flags.contains(.control)) { mods |= GHOSTTY_MODS_CTRL.rawValue }
            if (flags.contains(.option)) { mods |= GHOSTTY_MODS_ALT.rawValue }
            if (flags.contains(.command)) { mods |= GHOSTTY_MODS_SUPER.rawValue }
            if (flags.contains(.capsLock)) { mods |= GHOSTTY_MODS_CAPS.rawValue }

            // Handle sided input. We can't tell that both are pressed in the
            // Ghostty structure but thats okay -- we don't use that information.
            let rawFlags = flags.rawValue
            if (rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0) { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
            if (rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0) { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
            if (rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0) { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
            if (rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0) { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

            return ghostty_input_mods_e(mods)
        }

        // Mapping of event keyCode to ghostty input key values. This is cribbed from
        // glfw mostly since we started as a glfw-based app way back in the day!
        static let keycodes: [UInt16 : ghostty_input_key_e] = [
            0x1D: GHOSTTY_KEY_ZERO,
            0x12: GHOSTTY_KEY_ONE,
            0x13: GHOSTTY_KEY_TWO,
            0x14: GHOSTTY_KEY_THREE,
            0x15: GHOSTTY_KEY_FOUR,
            0x17: GHOSTTY_KEY_FIVE,
            0x16: GHOSTTY_KEY_SIX,
            0x1A: GHOSTTY_KEY_SEVEN,
            0x1C: GHOSTTY_KEY_EIGHT,
            0x19: GHOSTTY_KEY_NINE,
            0x00: GHOSTTY_KEY_A,
            0x0B: GHOSTTY_KEY_B,
            0x08: GHOSTTY_KEY_C,
            0x02: GHOSTTY_KEY_D,
            0x0E: GHOSTTY_KEY_E,
            0x03: GHOSTTY_KEY_F,
            0x05: GHOSTTY_KEY_G,
            0x04: GHOSTTY_KEY_H,
            0x22: GHOSTTY_KEY_I,
            0x26: GHOSTTY_KEY_J,
            0x28: GHOSTTY_KEY_K,
            0x25: GHOSTTY_KEY_L,
            0x2E: GHOSTTY_KEY_M,
            0x2D: GHOSTTY_KEY_N,
            0x1F: GHOSTTY_KEY_O,
            0x23: GHOSTTY_KEY_P,
            0x0C: GHOSTTY_KEY_Q,
            0x0F: GHOSTTY_KEY_R,
            0x01: GHOSTTY_KEY_S,
            0x11: GHOSTTY_KEY_T,
            0x20: GHOSTTY_KEY_U,
            0x09: GHOSTTY_KEY_V,
            0x0D: GHOSTTY_KEY_W,
            0x07: GHOSTTY_KEY_X,
            0x10: GHOSTTY_KEY_Y,
            0x06: GHOSTTY_KEY_Z,

            0x27: GHOSTTY_KEY_APOSTROPHE,
            0x2A: GHOSTTY_KEY_BACKSLASH,
            0x2B: GHOSTTY_KEY_COMMA,
            0x18: GHOSTTY_KEY_EQUAL,
            0x32: GHOSTTY_KEY_GRAVE_ACCENT,
            0x21: GHOSTTY_KEY_LEFT_BRACKET,
            0x1B: GHOSTTY_KEY_MINUS,
            0x2F: GHOSTTY_KEY_PERIOD,
            0x1E: GHOSTTY_KEY_RIGHT_BRACKET,
            0x29: GHOSTTY_KEY_SEMICOLON,
            0x2C: GHOSTTY_KEY_SLASH,

            0x33: GHOSTTY_KEY_BACKSPACE,
            0x39: GHOSTTY_KEY_CAPS_LOCK,
            0x75: GHOSTTY_KEY_DELETE,
            0x7D: GHOSTTY_KEY_DOWN,
            0x77: GHOSTTY_KEY_END,
            0x24: GHOSTTY_KEY_ENTER,
            0x35: GHOSTTY_KEY_ESCAPE,
            0x7A: GHOSTTY_KEY_F1,
            0x78: GHOSTTY_KEY_F2,
            0x63: GHOSTTY_KEY_F3,
            0x76: GHOSTTY_KEY_F4,
            0x60: GHOSTTY_KEY_F5,
            0x61: GHOSTTY_KEY_F6,
            0x62: GHOSTTY_KEY_F7,
            0x64: GHOSTTY_KEY_F8,
            0x65: GHOSTTY_KEY_F9,
            0x6D: GHOSTTY_KEY_F10,
            0x67: GHOSTTY_KEY_F11,
            0x6F: GHOSTTY_KEY_F12,
            0x69: GHOSTTY_KEY_PRINT_SCREEN,
            0x6B: GHOSTTY_KEY_F14,
            0x71: GHOSTTY_KEY_F15,
            0x6A: GHOSTTY_KEY_F16,
            0x40: GHOSTTY_KEY_F17,
            0x4F: GHOSTTY_KEY_F18,
            0x50: GHOSTTY_KEY_F19,
            0x5A: GHOSTTY_KEY_F20,
            0x73: GHOSTTY_KEY_HOME,
            0x72: GHOSTTY_KEY_INSERT,
            0x7B: GHOSTTY_KEY_LEFT,
            0x3A: GHOSTTY_KEY_LEFT_ALT,
            0x3B: GHOSTTY_KEY_LEFT_CONTROL,
            0x38: GHOSTTY_KEY_LEFT_SHIFT,
            0x37: GHOSTTY_KEY_LEFT_SUPER,
            0x47: GHOSTTY_KEY_NUM_LOCK,
            0x79: GHOSTTY_KEY_PAGE_DOWN,
            0x74: GHOSTTY_KEY_PAGE_UP,
            0x7C: GHOSTTY_KEY_RIGHT,
            0x3D: GHOSTTY_KEY_RIGHT_ALT,
            0x3E: GHOSTTY_KEY_RIGHT_CONTROL,
            0x3C: GHOSTTY_KEY_RIGHT_SHIFT,
            0x36: GHOSTTY_KEY_RIGHT_SUPER,
            0x31: GHOSTTY_KEY_SPACE,
            0x30: GHOSTTY_KEY_TAB,
            0x7E: GHOSTTY_KEY_UP,

            0x52: GHOSTTY_KEY_KP_0,
            0x53: GHOSTTY_KEY_KP_1,
            0x54: GHOSTTY_KEY_KP_2,
            0x55: GHOSTTY_KEY_KP_3,
            0x56: GHOSTTY_KEY_KP_4,
            0x57: GHOSTTY_KEY_KP_5,
            0x58: GHOSTTY_KEY_KP_6,
            0x59: GHOSTTY_KEY_KP_7,
            0x5B: GHOSTTY_KEY_KP_8,
            0x5C: GHOSTTY_KEY_KP_9,
            0x45: GHOSTTY_KEY_KP_ADD,
            0x41: GHOSTTY_KEY_KP_DECIMAL,
            0x4B: GHOSTTY_KEY_KP_DIVIDE,
            0x4C: GHOSTTY_KEY_KP_ENTER,
            0x51: GHOSTTY_KEY_KP_EQUAL,
            0x43: GHOSTTY_KEY_KP_MULTIPLY,
            0x4E: GHOSTTY_KEY_KP_SUBTRACT,
        ];
    }
}

// MARK: Surface Environment Keys

private struct GhosttySurfaceViewKey: EnvironmentKey {
    static let defaultValue: Ghostty.SurfaceView? = nil
}

extension EnvironmentValues {
    var ghosttySurfaceView: Ghostty.SurfaceView? {
        get { self[GhosttySurfaceViewKey.self] }
        set { self[GhosttySurfaceViewKey.self] = newValue }
    }
}

extension View {
    func ghosttySurfaceView(_ surfaceView: Ghostty.SurfaceView?) -> some View {
        environment(\.ghosttySurfaceView, surfaceView)
    }
}

// MARK: Surface Focus Keys

extension FocusedValues {
    var ghosttySurfaceView: Ghostty.SurfaceView? {
        get { self[FocusedGhosttySurface.self] }
        set { self[FocusedGhosttySurface.self] = newValue }
    }

    struct FocusedGhosttySurface: FocusedValueKey {
        typealias Value = Ghostty.SurfaceView
    }
}

extension FocusedValues {
    var ghosttySurfaceTitle: String? {
        get { self[FocusedGhosttySurfaceTitle.self] }
        set { self[FocusedGhosttySurfaceTitle.self] = newValue }
    }

    struct FocusedGhosttySurfaceTitle: FocusedValueKey {
        typealias Value = String
    }
}

extension FocusedValues {
    var ghosttySurfaceZoomed: Bool? {
        get { self[FocusedGhosttySurfaceZoomed.self] }
        set { self[FocusedGhosttySurfaceZoomed.self] = newValue }
    }

    struct FocusedGhosttySurfaceZoomed: FocusedValueKey {
        typealias Value = Bool
    }
}
