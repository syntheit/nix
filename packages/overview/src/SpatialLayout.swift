import SwiftUI

// MARK: - Spatial window area

struct SpatialWindowArea: View {
    @ObservedObject var state: OverviewState
    var spaceFrames: [Int: CGRect]

    var body: some View {
        GeometryReader { geo in
            let wins = state.currentSpaceWindows
            let screen = state.screenSize
            let padding: CGFloat = 24
            let progress = state.progress

            // Overview layout dimensions
            let usable = CGSize(
                width: geo.size.width - padding * 2,
                height: geo.size.height - padding * 2
            )
            let scaleX = usable.width / screen.width
            let scaleY = usable.height / screen.height
            let overviewScale = min(scaleX, scaleY)

            let scaledW = screen.width * overviewScale
            let scaledH = screen.height * overviewScale
            let originX = padding + (usable.width - scaledW) / 2
            let originY = padding + (usable.height - scaledH) / 2

            ForEach(wins) { window in
                // Real position (progress=0): window at actual screen position, full size
                let realW = window.frame.width
                let realH = window.frame.height
                let realCX = window.frame.origin.x + realW / 2
                let realCY = window.frame.origin.y + realH / 2

                // Overview position (progress=1): scaled down in overview area
                let ovW = realW * overviewScale
                let ovH = realH * overviewScale
                let ovCX = originX + (window.frame.origin.x + realW / 2) * overviewScale
                let ovCY = originY + (window.frame.origin.y + realH / 2) * overviewScale

                // Interpolate between real and overview positions
                let curW = lerp(realW, ovW, progress)
                let curH = lerp(realH, ovH, progress)
                let curCX = lerp(realCX, ovCX, progress)
                let curCY = lerp(realCY, ovCY, progress)

                DraggableWindowThumbnail(
                    window: window,
                    state: state,
                    spaceFrames: spaceFrames
                )
                .frame(width: curW, height: curH)
                .position(x: curCX, y: curCY)
            }
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}

// MARK: - Draggable window thumbnail

struct DraggableWindowThumbnail: View {
    let window: WindowInfo
    @ObservedObject var state: OverviewState
    let spaceFrames: [Int: CGRect]

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    private var isSelected: Bool { state.selectedWindowID == window.id }

    var body: some View {
        Group {
            if let image = window.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Rectangle().fill(.gray.opacity(0.3))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accent : .white.opacity(0.12), lineWidth: isSelected ? 2.5 : 0.5)
        )
        .shadow(color: .black.opacity(isDragging ? 0.6 : 0.3), radius: isDragging ? 20 : 8, y: isDragging ? 8 : 3)
        .opacity(isDragging ? 0.85 : 1.0)
        .offset(dragOffset)
        .zIndex(isDragging ? 100 : 0)
        .onHover { hovering in
            if hovering { state.selectedWindowID = window.id }
            else if state.selectedWindowID == window.id { state.selectedWindowID = nil }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .highPriorityGesture(TapGesture().onEnded { state.onSelect?(window.id) })
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .named("overview"))
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation
                    state.draggedWindowID = window.id
                    let pos = value.location
                    state.dropTargetSpaceIndex = nil
                    for (spaceIdx, frame) in spaceFrames {
                        if frame.contains(pos) && spaceIdx != window.space {
                            state.dropTargetSpaceIndex = spaceIdx
                            break
                        }
                    }
                }
                .onEnded { _ in
                    if let target = state.dropTargetSpaceIndex {
                        state.onMoveWindow?(window.id, target)
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDragging = false
                        dragOffset = .zero
                    }
                    state.draggedWindowID = nil
                    state.dropTargetSpaceIndex = nil
                }
        )
    }
}
