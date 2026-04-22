import SwiftUI

// MARK: - Color theme (Tokyo Night)

private extension Color {
    static let accent  = Color(red: 0.48, green: 0.63, blue: 0.97)  // #7aa2f7
    static let subtle  = Color.white.opacity(0.5)
    static let dimmed  = Color.white.opacity(0.3)
}

// MARK: - Root view

struct OverviewView: View {
    @ObservedObject var state: OverviewState

    var body: some View {
        ZStack {
            // Dimmed backdrop — click to dismiss
            Color.black.opacity(0.35)
                .onTapGesture { state.onDismiss?() }

            VStack(spacing: 24) {
                windowGrid
            }
            .padding(48)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: maxGridWidth)
            .scaleEffect(state.appeared ? 1.0 : 0.96)
            .opacity(state.appeared ? 1.0 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onContinuousHover { _ in NSCursor.arrow.set() }
        .onAppear {
            NSCursor.arrow.set()
            withAnimation(.easeOut(duration: 0.15)) {
                state.appeared = true
            }
        }
    }

    private var windowGrid: some View {
        let cols = state.columns
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: cols),
            spacing: 20
        ) {
            ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, window in
                WindowThumbnail(
                    window: window,
                    isSelected: state.selectedIndex == index
                )
                .onTapGesture { state.onSelect?(window.id) }
                .onHover { hovering in
                    if hovering {
                        state.selectedIndex = index
                    } else if state.selectedIndex == index {
                        state.selectedIndex = nil
                    }
                }
            }
        }
    }

    private var maxGridWidth: CGFloat {
        guard let screen = NSScreen.main else { return 1200 }
        return screen.frame.width * 0.8
    }
}

// MARK: - Window thumbnail

private struct WindowThumbnail: View {
    let window: WindowInfo
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                if let image = window.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.06))
                        .aspectRatio(16.0 / 10.0, contentMode: .fit)
                        .overlay {
                            Image(nsImage: window.icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 64, height: 64)
                        }
                }

                // App icon badge
                Image(nsImage: window.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accent : .clear, lineWidth: 3)
            )

            Text(window.app)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
    }
}
