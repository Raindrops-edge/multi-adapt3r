import SwiftUI

/// A split view shows a left and right (or top and bottom) view with a divider in the middle to do resizing.
/// The terminlogy "left" and "right" is always used but for vertical splits "left" is "top" and "right" is "bottom".
///
/// This view is purpose built for our use case and I imagine we'll continue to make it more configurable
/// as time goes on. For example, the splitter divider size and styling is all hardcoded.
struct SplitView<L: View, R: View>: View {
    /// Direction of the split
    let direction: SplitViewDirection
    
    /// The left and right views to render.
    let left: L
    let right: R
    
    /// The current fractional width of the split view. 0.5 means L/R are equally sized, for example.
    @State var split: CGFloat = 0.5
    
    /// The visible size of the splitter, in points. The invisible size is a transparent hitbox that can still
    /// be used for getting a resize handle. The total width/height of the splitter is the sum of both.
    private let splitterVisibleSize: CGFloat = 1
    private let splitterInvisibleSize: CGFloat = 6
    
    var body: some View {
        GeometryReader { geo in
            let leftRect = self.leftRect(for: geo.size)
            let rightRect = self.rightRect(for: geo.size, leftRect: leftRect)
            let splitterPoint = self.splitterPoint(for: geo.size, leftRect: leftRect)
            
            ZStack(alignment: .topLeading) {
                left
                    .frame(width: leftRect.size.width, height: leftRect.size.height)
                    .offset(x: leftRect.origin.x, y: leftRect.origin.y)
                right
                    .frame(width: rightRect.size.width, height: rightRect.size.height)
                    .offset(x: rightRect.origin.x, y: rightRect.origin.y)
                Divider(direction: direction, visibleSize: splitterVisibleSize, invisibleSize: splitterInvisibleSize)
                    .position(splitterPoint)
                    .gesture(dragGesture(geo.size, splitterPoint: splitterPoint))
            }
        }
    }
    
    init(_ direction: SplitViewDirection, @ViewBuilder left: (() -> L), @ViewBuilder right: (() -> R)) {
        self.direction = direction
        self.left = left()
        self.right = right()
    }
    
    private func dragGesture(_ size: CGSize, splitterPoint: CGPoint) -> some Gesture {
        return DragGesture()
            .onChanged { gesture in
                let minSize: CGFloat = 10
                
                switch (direction) {
                case .horizontal:
                    let new = min(max(minSize, gesture.location.x), size.width - minSize)
                    split = new / size.width
                    
                case .vertical:
                    let new = min(max(minSize, gesture.location.y), size.height - minSize)
                    split = new / size.height
                }
            }
    }
    
    /// Calculates the bounding rect for the left view.
    private func leftRect(for size: CGSize) -> CGRect {
        // Initially the rect is the full size
        var result = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        switch (direction) {
        case .horizontal:
            result.size.width = result.size.width * split
            result.size.width -= splitterVisibleSize / 2
            
        case .vertical:
            result.size.height = result.size.height * split
            result.size.height -= splitterVisibleSize / 2
        }
        
        return result
    }
    
    /// Calculates the bounding rect for the right view.
    private func rightRect(for size: CGSize, leftRect: CGRect) -> CGRect {
        // Initially the rect is the full size
        var result = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        switch (direction) {
        case .horizontal:
            // For horizontal layouts we offset the starting X by the left rect
            // and make the width fit the remaining space.
            result.origin.x += leftRect.size.width
            result.origin.x += splitterVisibleSize / 2
            result.size.width -= result.origin.x
            
        case .vertical:
            result.origin.y += leftRect.size.height
            result.origin.y += splitterVisibleSize / 2
            result.size.height -= result.origin.y
        }
        
        return result
    }
    
    /// Calculates the point at which the splitter should be rendered.
    private func splitterPoint(for size: CGSize, leftRect: CGRect) -> CGPoint {
        switch (direction) {
        case .horizontal:
            return CGPoint(x: leftRect.size.width, y: size.height / 2)
            
        case .vertical:
            return CGPoint(x: size.width / 2, y: leftRect.size.height)
        }
    }
}

enum SplitViewDirection {
    case horizontal, vertical
}
