import SwiftUI

// MARK: - Colors

extension Color {
    static let accent  = Color(red: 0.48, green: 0.63, blue: 0.97)  // #7aa2f7
    static let subtle  = Color.white.opacity(0.5)
    static let dimmed  = Color.white.opacity(0.3)
}

// MARK: - Root view

struct OverviewView: View {
    @ObservedObject var state: OverviewState

    var body: some View {
        ZStack {
            // Desktop background
            Group {
                if let wp = state.wallpaper {
                    Image(nsImage: wp)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    Color.black
                }
            }
            .allowsHitTesting(false)

            // Content fades/slides in with progress
            VStack(spacing: 0) {
                // Workspace bar slides down from top
                WorkspaceBar(state: state)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 50)
                    .padding(.horizontal, 40)
                    .offset(y: -120 * (1 - state.progress))
                    .opacity(state.progress)

                // Spatial window layout
                SpatialWindowArea(state: state, spaceFrames: state.spaceFrames)
                    .padding(32)
            }
        }
        // Tap empty space to dismiss (only when fully open)
        .onTapGesture {
            if state.progress >= 1.0 { state.onDismiss?() }
        }
        .coordinateSpace(name: "overview")
        .onPreferenceChange(SpaceFrameKey.self) { state.spaceFrames = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onContinuousHover { _ in NSCursor.arrow.set() }
    }

}

// MARK: - Preference key for workspace bar frame tracking

struct SpaceFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
