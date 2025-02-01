import SwiftUI
import GhosttyKit

extension Ghostty {
    /// A spittable terminal view is one where the terminal allows for "splits" (vertical and horizontal) within the
    /// view. The terminal starts in the unsplit state (a plain ol' TerminalView) but responds to changes to the
    /// split direction by splitting the terminal.
    struct TerminalSplit: View {
        let onClose: (() -> Void)?
        let baseConfig: ghostty_surface_config_s?

        @Environment(\.ghosttyApp) private var app

        /// Non-nil if one of the surfaces in the split tree is currently "zoomed." A zoomed surface
        /// becomes "full screen" on the split tree.
        @State private var zoomedSurface: SurfaceView? = nil

        var body: some View {
            if let app = app {
                ZStack {
                    TerminalSplitRoot(
                        app: app,
                        zoomedSurface: $zoomedSurface,
                        onClose: onClose,
                        baseConfig: baseConfig
                    )

                    // If we have a zoomed surface, we overlay that on top of our split
                    // root. Our split root will become clear when there is a zoomed
                    // surface. We need to keep the split root around so that we don't
                    // lose all of the surface state so this must be a ZStack.
                    if let surfaceView = zoomedSurface {
                        SurfaceWrapper(surfaceView: surfaceView)
                    }
                }
                .focusedValue(\.ghosttySurfaceZoomed, zoomedSurface != nil)
            }
        }
    }

    /// This enum represents the possible states that a node in the split tree can be in. It is either:
    ///
    ///   - noSplit - This is an unsplit, single pane. This contains only a "leaf" which has a single
    ///   terminal surface to render.
    ///   - horizontal/vertical - This is split into the horizontal or vertical direction. This contains a
    ///   "container" which has a recursive top/left SplitNode and bottom/right SplitNode. These
    ///   values can further be split infinitely.
    ///
    enum SplitNode {
        case noSplit(Leaf)
        case horizontal(Container)
        case vertical(Container)

        /// Returns the view that would prefer receiving focus in this tree. This is always the
        /// top-left-most view. This is used when creating a split or closing a split to find the
        /// next view to send focus to.
        func preferredFocus(_ direction: SplitFocusDirection = .top) -> SurfaceView {
            let container: Container
            switch (self) {
            case .noSplit(let leaf):
                // noSplit is easy because there is only one thing to focus
                return leaf.surface

            case .horizontal(let c):
                container = c

            case .vertical(let c):
                container = c
            }
            
            let node: SplitNode
            switch (direction) {
            case .previous, .bottom, .left:
                node = container.bottomRight
                
            case .next, .top, .right:
                node = container.topLeft
            }
            
            return node.preferredFocus(direction)
        }

        /// Close the surface associated with this node. This will likely deinitialize the
        /// surface. At this point, the surface view in this node tree can never be used again.
        func close() {
            switch (self) {
            case .noSplit(let leaf):
                leaf.surface.close()

            case .horizontal(let container):
                container.topLeft.close()
                container.bottomRight.close()

            case .vertical(let container):
                container.topLeft.close()
                container.bottomRight.close()
            }
        }

        /// Returns true if the split tree contains the given view.
        func contains(view: SurfaceView) -> Bool {
            switch (self) {
            case .noSplit(let leaf):
                return leaf.surface == view

            case .horizontal(let container):
                return container.topLeft.contains(view: view) ||
                    container.bottomRight.contains(view: view)

            case .vertical(let container):
                return container.topLeft.contains(view: view) ||
                    container.bottomRight.contains(view: view)
            }
        }

        class Leaf: ObservableObject {
            let app: ghostty_app_t
            @Published var surface: SurfaceView

            /// Initialize a new leaf which creates a new terminal surface.
            init(_ app: ghostty_app_t, _ baseConfig: ghostty_surface_config_s?) {
                self.app = app
                self.surface = SurfaceView(app, baseConfig)
            }
        }

        class Container: ObservableObject {
            let app: ghostty_app_t
            @Published var topLeft: SplitNode
            @Published var bottomRight: SplitNode

            /// A container is always initialized from some prior leaf because a split has to originate
            /// from a non-split value. When initializing, we inherit the leaf's surface and then
            /// initialize a new surface for the new pane.
            init(from: Leaf, baseConfig: ghostty_surface_config_s? = nil) {
                self.app = from.app

                // Initially, both topLeft and bottomRight are in the "nosplit"
                // state since this is a new split.
                self.topLeft = .noSplit(from)
                self.bottomRight = .noSplit(.init(app, baseConfig))
            }
        }

        /// This keeps track of the "neighbors" of a split: the immediately above/below/left/right
        /// nodes. This is purposely weak so we don't have to worry about memory management
        /// with this (although, it should always be correct).
        struct Neighbors {
            var left: SplitNode?
            var right: SplitNode?
            var top: SplitNode?
            var bottom: SplitNode?

            /// These are the previous/next nodes. It will certainly be one of the above as well
            /// but we keep track of these separately because depending on the split direction
            /// of the containing node, previous may be left OR top (same for next).
            var previous: SplitNode?
            var next: SplitNode?

            /// No neighbors, used by the root node.
            static let empty: Self = .init()

            /// Get the node for a given direction.
            func get(direction: SplitFocusDirection) -> SplitNode? {
                let map: [SplitFocusDirection : KeyPath<Self, SplitNode?>] = [
                    .previous: \.previous,
                    .next: \.next,
                    .top: \.top,
                    .bottom: \.bottom,
                    .left: \.left,
                    .right: \.right,
                ]

                guard let path = map[direction] else { return nil }
                return self[keyPath: path]
            }

            /// Update multiple keys and return a new copy.
            func update(_ attrs: [WritableKeyPath<Self, SplitNode?>: SplitNode?]) -> Self {
                var clone = self
                attrs.forEach { (key, value) in
                    clone[keyPath: key] = value
                }
                return clone
            }
            
            /// True if there are no neighbors
            func isEmpty() -> Bool {
                return self.previous == nil && self.next == nil
            }
        }
    }

    /// The root of a split tree. This sets up the initial SplitNode state and renders. There is only ever
    /// one of these in a split tree.
    private struct TerminalSplitRoot: View {
        @State private var node: SplitNode
        @State private var requestClose: Bool = false
        let onClose: (() -> Void)?
        let baseConfig: ghostty_surface_config_s?

        /// Keeps track of whether we're in a zoomed split state or not. If one of the splits we own
        /// is in the zoomed state, we clear our body since we expect a zoomed split to overlay
        /// this one.
        @Binding var zoomedSurface: SurfaceView?

        @FocusedValue(\.ghosttySurfaceTitle) private var surfaceTitle: String?

        init(app: ghostty_app_t,
             zoomedSurface: Binding<SurfaceView?>,
             onClose: (() ->Void)? = nil,
             baseConfig: ghostty_surface_config_s? = nil) {
            self.onClose = onClose
            self.baseConfig = baseConfig
            self._zoomedSurface = zoomedSurface
            _node = State(wrappedValue: SplitNode.noSplit(.init(app, baseConfig)))
        }

        var body: some View {
            let center = NotificationCenter.default
            let pubZoom = center.publisher(for: Notification.didToggleSplitZoom)

            // If we're zoomed, we don't render anything, we are transparent. This
            // ensures that the View stays around so we don't lose our state, but
            // also that the zoomed view on top can see through if background transparency
            // is enabled.
            if (zoomedSurface == nil) {
                ZStack {
                    switch (node) {
                    case .noSplit(let leaf):
                        TerminalSplitLeaf(
                            leaf: leaf,
                            neighbors: .empty,
                            node: $node,
                            requestClose: $requestClose
                        )
                        .onChange(of: requestClose) { value in
                            guard value else { return }

                            // Free any resources associated with this root, we're closing.
                            node.close()

                            // Call our callback
                            guard let onClose = self.onClose else { return }
                            onClose()
                        }

                    case .horizontal(let container):
                        TerminalSplitContainer(
                            direction: .horizontal,
                            neighbors: .empty,
                            node: $node,
                            container: container
                        )
                        .onReceive(pubZoom) { onZoom(notification: $0) }

                    case .vertical(let container):
                        TerminalSplitContainer(
                            direction: .vertical,
                            neighbors: .empty,
                            node: $node,
                            container: container
                        )
                        .onReceive(pubZoom) { onZoom(notification: $0) }
                    }
                }
                .navigationTitle(surfaceTitle ?? "Ghostty")
            } else {
                // On these events we want to reset the split state and call it.
                let pubSplit = center.publisher(for: Notification.ghosttyNewSplit, object: zoomedSurface!)
                let pubClose = center.publisher(for: Notification.ghosttyCloseSurface, object: zoomedSurface!)
                let pubFocus = center.publisher(for: Notification.ghosttyFocusSplit, object: zoomedSurface!)

                ZStack {}
                    .onReceive(pubZoom) { onZoomReset(notification: $0) }
                    .onReceive(pubSplit) { onZoomReset(notification: $0) }
                    .onReceive(pubClose) { onZoomReset(notification: $0) }
                    .onReceive(pubFocus) { onZoomReset(notification: $0) }
            }
        }

        func onZoom(notification: SwiftUI.Notification) {
            // Our node must be split to receive zooms. You can't zoom an unsplit terminal.
            if case .noSplit = node {
                preconditionFailure("TerminalSplitRoom must not be zoom-able if no splits exist")
            }

            // Make sure the notification has a surface and that this window owns the surface.
            guard let surfaceView = notification.object as? SurfaceView else { return }
            guard node.contains(view: surfaceView) else { return }

            // We are in the zoomed state.
            zoomedSurface = surfaceView

            // See onZoomReset, same logic.
            DispatchQueue.main.async { Ghostty.moveFocus(to: surfaceView) }
        }

        func onZoomReset(notification: SwiftUI.Notification) {
            // Make sure the notification has a surface and that this window owns the surface.
            guard let surfaceView = notification.object as? SurfaceView else { return }
            guard zoomedSurface == surfaceView else { return }

            // We are now unzoomed
            zoomedSurface = nil

            // We need to stay focused on this view, but the view is going to change
            // superviews. We need to do this async so it happens on the next event loop
            // tick.
            DispatchQueue.main.async {
                Ghostty.moveFocus(to: surfaceView)

                // If the notification is not a toggle zoom notification, we want to re-publish
                // it after a short delay so that the split tree has a chance to re-establish
                // so the proper view gets this notification.
                if (notification.name != Notification.didToggleSplitZoom) {
                    // We have to wait ANOTHER tick since we just established.
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(notification)
                    }
                }
            }
        }
    }

    /// A noSplit leaf node of a split tree.
    private struct TerminalSplitLeaf: View {
        /// The leaf to draw the surface for.
        let leaf: SplitNode.Leaf

        /// The neighbors, used for navigation.
        let neighbors: SplitNode.Neighbors

        /// The SplitNode that the leaf belongs to.
        @Binding var node: SplitNode

        ///  This will be set to true when the split requests that is become closed.
        @Binding var requestClose: Bool

        /// This controls whether we're actively confirming if we want to close or not.
        @State private var confirmClose: Bool = false

        var body: some View {
            let center = NotificationCenter.default
            let pub = center.publisher(for: Notification.ghosttyNewSplit, object: leaf.surface)
            let pubClose = center.publisher(for: Notification.ghosttyCloseSurface, object: leaf.surface)
            let pubFocus = center.publisher(for: Notification.ghosttyFocusSplit, object: leaf.surface)

            SurfaceWrapper(surfaceView: leaf.surface, isSplit: !neighbors.isEmpty())
                .onReceive(pub) { onNewSplit(notification: $0) }
                .onReceive(pubClose) { onClose(notification: $0) }
                .onReceive(pubFocus) { onMoveFocus(notification: $0) }
                .confirmationDialog(
                    "Close Terminal?",
                    isPresented: $confirmClose) {
                        Button("Close the Terminal") {
                            confirmClose = false
                            requestClose = true
                        }
                        .keyboardShortcut(.defaultAction)
                    } message: {
                        Text("The terminal still has a running process. If you close the terminal " +
                             "the process will be killed.")
                    }
        }

        private func onClose(notification: SwiftUI.Notification) {
            var processAlive = false
            if let valueAny = notification.userInfo?["process_alive"] {
                if let value = valueAny as? Bool {
                    processAlive = value
                }
            }

            // If the child process is not alive, then we exit immediately
            guard processAlive else {
                requestClose = true
                return
            }

            // Child process is alive, so we want to show a confirmation.
            confirmClose = true
        }

        private func onNewSplit(notification: SwiftUI.Notification) {
            let configAny = notification.userInfo?[Ghostty.Notification.NewSurfaceConfigKey]
            let config = configAny as? ghostty_surface_config_s

            // Determine our desired direction
            guard let directionAny = notification.userInfo?["direction"] else { return }
            guard let direction = directionAny as? ghostty_split_direction_e else { return }
            var splitDirection: SplitViewDirection
            switch (direction) {
            case GHOSTTY_SPLIT_RIGHT:
                splitDirection = .horizontal

            case GHOSTTY_SPLIT_DOWN:
                splitDirection = .vertical

            default:
                return
            }

            // Setup our new container since we are now split
            let container = SplitNode.Container(from: leaf, baseConfig: config)

            // Depending on the direction, change the parent node. This will trigger
            // the parent to relayout our views.
            switch (splitDirection) {
            case .horizontal:
                node = .horizontal(container)
            case .vertical:
                node = .vertical(container)
            }

            // See moveFocus comment, we have to run this whenever split changes.
            Ghostty.moveFocus(to: container.bottomRight.preferredFocus(), from: node.preferredFocus())
        }

        /// This handles the event to move the split focus (i.e. previous/next) from a keyboard event.
        private func onMoveFocus(notification: SwiftUI.Notification) {
            // Determine our desired direction
            guard let directionAny = notification.userInfo?[Notification.SplitDirectionKey] else { return }
            guard let direction = directionAny as? SplitFocusDirection else { return }
            guard let next = neighbors.get(direction: direction) else { return }
            Ghostty.moveFocus(
                to: next.preferredFocus(direction),
                from: node.preferredFocus()
            )
        }
    }

    /// This represents a split view that is in the horizontal or vertical split state.
    private struct TerminalSplitContainer: View {
        let direction: SplitViewDirection
        let neighbors: SplitNode.Neighbors
        @Binding var node: SplitNode
        @StateObject var container: SplitNode.Container

        @State private var closeTopLeft: Bool = false
        @State private var closeBottomRight: Bool = false

        var body: some View {
            SplitView(direction, left: {
                let neighborKey: WritableKeyPath<SplitNode.Neighbors, SplitNode?> = direction == .horizontal ? \.right : \.bottom

                TerminalSplitNested(
                    node: $container.topLeft,
                    neighbors: neighbors.update([
                        neighborKey: container.bottomRight,
                        \.next: container.bottomRight,
                    ]),
                    requestClose: $closeTopLeft
                )
                .onChange(of: closeTopLeft) { value in
                    guard value else { return }

                    // Close the top left and release all resources
                    container.topLeft.close()

                    // When closing the topLeft, our parent becomes the bottomRight.
                    node = container.bottomRight
                    Ghostty.moveFocus(to: node.preferredFocus(), from: container.topLeft.preferredFocus())
                }
            }, right: {
                let neighborKey: WritableKeyPath<SplitNode.Neighbors, SplitNode?> = direction == .horizontal ? \.left : \.top

                TerminalSplitNested(
                    node: $container.bottomRight,
                    neighbors: neighbors.update([
                        neighborKey: container.topLeft,
                        \.previous: container.topLeft,
                    ]),
                    requestClose: $closeBottomRight
                )
                .onChange(of: closeBottomRight) { value in
                    guard value else { return }

                    // Close the node and release all resources
                    container.bottomRight.close()

                    // When closing the bottomRight, our parent becomes the topLeft.
                    node = container.topLeft
                    Ghostty.moveFocus(to: node.preferredFocus(), from: container.bottomRight.preferredFocus())
                }
            })
        }
    }

    /// This is like TerminalSplitRoot, but... not the root. This renders a SplitNode in any state but
    /// requires there be a binding to the parent node.
    private struct TerminalSplitNested: View {
        @Binding var node: SplitNode
        let neighbors: SplitNode.Neighbors
        @Binding var requestClose: Bool

        var body: some View {
            switch (node) {
            case .noSplit(let leaf):
                TerminalSplitLeaf(
                    leaf: leaf,
                    neighbors: neighbors,
                    node: $node,
                    requestClose: $requestClose
                )

            case .horizontal(let container):
                TerminalSplitContainer(
                    direction: .horizontal,
                    neighbors: neighbors,
                    node: $node,
                    container: container
                )

            case .vertical(let container):
                TerminalSplitContainer(
                    direction: .vertical,
                    neighbors: neighbors,
                    node: $node,
                    container: container
                )
            }
        }
    }

    /// When changing the split state, or going full screen (native or non), the terminal view
    /// will lose focus. There has to be some nice SwiftUI-native way to fix this but I can't
    /// figure it out so we're going to do this hacky thing to bring focus back to the terminal
    /// that should have it.
    static func moveFocus(to: SurfaceView, from: SurfaceView? = nil) {
        DispatchQueue.main.async {
            // If the callback runs before the surface is attached to a view
            // then the window will be nil. We just reschedule in that case.
            guard let window = to.window else {
                moveFocus(to: to, from: from)
                return
            }

            // If we had a previously focused node and its not where we're sending
            // focus, make sure that we explicitly tell it to lose focus. In theory
            // we should NOT have to do this but the focus callback isn't getting
            // called for some reason.
            if let from = from {
                _ = from.resignFirstResponder()
            }

            window.makeFirstResponder(to)

            // On newer versions of macOS everything above works great so we're done.
            if #available(macOS 13, *) { return }

            // On macOS 12, splits do not properly gain focus. I don't know why, but
            // it seems like the `focused` SwiftUI method doesn't work. We use
            // NotificationCenter as a blunt force instrument to make it work.
            if #available(macOS 12, *) {
                NotificationCenter.default.post(
                    name: Notification.didBecomeFocusedSurface,
                    object: to
                )
            }
        }
    }
}
