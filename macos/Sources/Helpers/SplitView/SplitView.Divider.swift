import SwiftUI

extension SplitView {
    /// The split divider that is rendered and can be used to resize a split view.
    struct Divider: View {
        let direction: SplitViewDirection
        let visibleSize: CGFloat
        let invisibleSize: CGFloat
        
        private var visibleWidth: CGFloat? {
            switch (direction) {
            case .horizontal:
                return visibleSize
            case .vertical:
                return nil
            }
        }
        
        private var visibleHeight: CGFloat? {
            switch (direction) {
            case .horizontal:
                return nil
            case .vertical:
                return visibleSize
            }
        }
        
        private var invisibleWidth: CGFloat? {
            switch (direction) {
            case .horizontal:
                return visibleSize + invisibleSize
            case .vertical:
                return nil
            }
        }
        
        private var invisibleHeight: CGFloat? {
            switch (direction) {
            case .horizontal:
                return nil
            case .vertical:
                return visibleSize + invisibleSize
            }
        }
        
        var body: some View {
            ZStack {
                Color.clear
                    .frame(width: invisibleWidth, height: invisibleHeight)
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: visibleWidth, height: visibleHeight)
            }
            .onHover { isHovered in
                if (isHovered) {
                    switch (direction) {
                    case .horizontal:
                        NSCursor.resizeLeftRight.push()
                    case .vertical:
                        NSCursor.resizeUpDown.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}
