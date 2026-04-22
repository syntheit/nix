import SwiftUI

struct WorkspaceBar: View {
    @ObservedObject var state: OverviewState

    var body: some View {
        HStack(spacing: 12) {
            ForEach(state.spaces) { space in
                let wins = state.windows(forSpace: space.index)
                let isCurrent = space.index == state.currentSpaceIndex
                let isDropTarget = state.dropTargetSpaceIndex == space.index

                DraggableSpaceThumbnail(
                    spaceIndex: space.index,
                    windows: wins,
                    isCurrent: isCurrent,
                    isDropTarget: isDropTarget,
                    screenSize: state.screenSize,
                    state: state
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SpaceFrameKey.self,
                            value: [space.index: geo.frame(in: .named("overview"))]
                        )
                    }
                )
            }
        }
    }
}

// MARK: - Draggable space thumbnail (supports reordering + window drop)

struct DraggableSpaceThumbnail: View {
    let spaceIndex: Int
    let windows: [WindowInfo]
    let isCurrent: Bool
    let isDropTarget: Bool
    let screenSize: CGSize
    @ObservedObject var state: OverviewState

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    private let thumbWidth: CGFloat = 180
    private var thumbHeight: CGFloat { thumbWidth * (screenSize.height / screenSize.width) }

    var body: some View {
        SpaceThumbnailContent(
            windows: windows,
            isCurrent: isCurrent,
            isDropTarget: isDropTarget,
            screenSize: screenSize,
            thumbWidth: thumbWidth,
            thumbHeight: thumbHeight
        )
        .offset(isDragging ? dragOffset : .zero)
        .zIndex(isDragging ? 100 : 0)
        .opacity(isDragging ? 0.8 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .highPriorityGesture(TapGesture().onEnded { state.onSelectSpace?(spaceIndex) })
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .named("overview"))
                .onChanged { value in
                    isDragging = true
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                }
                .onEnded { value in
                    let dropPos = value.location
                    for s in state.spaces where s.index != spaceIndex {
                        if let frame = state.spaceFrames[s.index], frame.contains(dropPos) {
                            state.onReorderSpace?(spaceIndex, s.index)
                            break
                        }
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDragging = false
                        dragOffset = .zero
                    }
                }
        )
    }
}

// MARK: - Space thumbnail appearance (shared between draggable wrapper)

private struct SpaceThumbnailContent: View {
    let windows: [WindowInfo]
    let isCurrent: Bool
    let isDropTarget: Bool
    let screenSize: CGSize
    let thumbWidth: CGFloat
    let thumbHeight: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.black.opacity(0.5))

            if isDropTarget {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accent.opacity(0.25))
            }

            if !windows.isEmpty {
                miniatureLayout
            }
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isCurrent ? .white.opacity(0.6) :
                    isDropTarget ? Color.accent.opacity(0.5) :
                    .white.opacity(0.15),
                    lineWidth: isCurrent ? 2 : 1
                )
        )
    }

    private var miniatureLayout: some View {
        GeometryReader { geo in
            let padding: CGFloat = 3
            let usable = CGSize(width: geo.size.width - padding * 2, height: geo.size.height - padding * 2)
            let scale = min(usable.width / screenSize.width, usable.height / screenSize.height)
            let offsetX = padding + (usable.width - screenSize.width * scale) / 2
            let offsetY = padding + (usable.height - screenSize.height * scale) / 2

            ForEach(windows) { win in
                let w = win.frame.width * scale
                let h = win.frame.height * scale
                let x = offsetX + (win.frame.origin.x + win.frame.width / 2) * scale
                let y = offsetY + (win.frame.origin.y + win.frame.height / 2) * scale

                Group {
                    if let image = win.image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else {
                        Rectangle().fill(.white.opacity(0.15))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .frame(width: max(4, w), height: max(4, h))
                .position(x: x, y: y)
            }
        }
    }
}
