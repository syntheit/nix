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

            // The GeometryReader is offset from screen origin (workspace bar + padding above it)
            // We need to know where THIS view sits on screen to calculate real positions
            let geoFrame = geo.frame(in: .named("overview"))

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
                // Real position (progress=0): window at actual screen coords,
                // but adjusted for GeometryReader's offset within the overlay
                let realW = window.frame.width
                let realH = window.frame.height
                let realCX = window.frame.origin.x + realW / 2 - geoFrame.origin.x
                let realCY = window.frame.origin.y + realH / 2 - geoFrame.origin.y

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
                    spaceFrames: spaceFrames,
                    viewCenter: CGPoint(x: curCX + geoFrame.origin.x, y: curCY + geoFrame.origin.y)
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
    let viewCenter: CGPoint  // center of this view in "overview" coordinate space

    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var dragScale: CGFloat = 1.0
    @State private var grabOffset: CGSize = .zero  // grab point relative to view center

    private var isSelected: Bool { state.progress >= 0.99 && state.selectedWindowID == window.id }
    private let minDragScale: CGFloat = 0.15

    var body: some View {
        Group {
            if let image = window.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .transition(.opacity)
            } else {
                Color.clear
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accent : .white.opacity(0.12), lineWidth: isSelected ? 2.5 : 0.5)
        )
        .shadow(color: .black.opacity(isDragging ? 0.6 : 0.3), radius: isDragging ? 20 : 8, y: isDragging ? 8 : 3)
        .opacity(isDragging ? 0.85 : 1.0)
        .scaleEffect(isDragging ? dragScale : 1.0)
        .offset(dragOffset)
        .zIndex(isDragging ? 100 : 0)
        .onHover { hovering in
            if hovering { state.selectedWindowID = window.id }
            else if state.selectedWindowID == window.id { state.selectedWindowID = nil }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .highPriorityGesture(TapGesture().onEnded { state.onSelect?(window.id) })
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .named("overview"))
                .onChanged { value in
                    if !isDragging {
                        // Where the user grabbed relative to view center
                        grabOffset = CGSize(
                            width: value.startLocation.x - viewCenter.x,
                            height: value.startLocation.y - viewCenter.y
                        )
                    }
                    isDragging = true
                    state.draggedWindowID = window.id

                    // Calculate scale based on proximity to workspace bar
                    let pos = value.location
                    state.dropTargetSpaceIndex = nil
                    var nearestDist: CGFloat = .infinity
                    for (spaceIdx, frame) in spaceFrames {
                        let dist = distToRect(pos, frame)
                        if frame.contains(pos) && spaceIdx != window.space {
                            state.dropTargetSpaceIndex = spaceIdx
                        }
                        if dist < nearestDist { nearestDist = dist }
                    }
                    let t = max(0, min(1, 1 - nearestDist / 200))
                    dragScale = 1.0 - t * (1.0 - minDragScale)

                    // Offset so the grab point stays under the cursor:
                    // After scale, grab point moves to: viewCenter + grabOffset * scale
                    // We want it at: cursor = viewCenter + translation + grabOffset
                    // So offset = translation + grabOffset * (1 - scale)
                    dragOffset = CGSize(
                        width: value.translation.width + grabOffset.width * (1 - dragScale),
                        height: value.translation.height + grabOffset.height * (1 - dragScale)
                    )
                }
                .onEnded { _ in
                    if let target = state.dropTargetSpaceIndex {
                        state.onMoveWindow?(window.id, target)
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDragging = false
                        dragOffset = .zero
                        dragScale = 1.0
                    }
                    state.draggedWindowID = nil
                    state.dropTargetSpaceIndex = nil
                }
        )
    }

    private func distToRect(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let cx = max(r.minX, min(p.x, r.maxX))
        let cy = max(r.minY, min(p.y, r.maxY))
        return sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy))
    }
}
