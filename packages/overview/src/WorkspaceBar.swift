import SwiftUI

struct WorkspaceBar: View {
    @ObservedObject var state: OverviewState

    @State private var draggingSpaceIndex: Int? = nil
    @State private var dragX: CGFloat = 0
    @State private var dragOriginalSlot: Int = 0
    @State private var currentTargetSlot: Int = -1
    @State private var shiftOffsets: [Int: CGFloat] = [:]
    @State private var dragStartCenter: CGPoint = .zero

    private let thumbWidth: CGFloat = 180
    private let spacing: CGFloat = 12
    private var slotWidth: CGFloat { thumbWidth + spacing }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(state.spaces) { space in
                let wins = state.windows(forSpace: space.index)
                let isCurrent = space.index == state.currentSpaceIndex
                let isDropTarget = state.dropTargetSpaceIndex == space.index
                let isBeingDragged = draggingSpaceIndex == space.index

                SpaceThumbnailContent(
                    windows: wins,
                    isCurrent: isCurrent,
                    isDropTarget: isDropTarget,
                    screenSize: state.screenSize
                )
                .opacity(isBeingDragged ? 0 : 1)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SpaceFrameKey.self,
                            value: [space.index: geo.frame(in: .named("overview"))]
                        )
                    }
                )
                .offset(x: isBeingDragged ? 0 : (shiftOffsets[space.index] ?? 0))
                .animation(.easeInOut(duration: 0.2), value: shiftOffsets[space.index] ?? 0)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .highPriorityGesture(TapGesture().onEnded {
                    state.onSelectSpace?(space.index)
                })
                .simultaneousGesture(makeDragGesture(for: space.index))
            }
        }
        // Floating dragged item as overlay — doesn't affect layout
        .overlay {
            if let dragIdx = draggingSpaceIndex,
               let space = state.spaces.first(where: { $0.index == dragIdx }) {
                SpaceThumbnailContent(
                    windows: state.windows(forSpace: space.index),
                    isCurrent: space.index == state.currentSpaceIndex,
                    isDropTarget: false,
                    screenSize: state.screenSize
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                .offset(x: dragX)
            }
        }
    }

    private func makeDragGesture(for spaceIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let indices = state.spaces.map(\.index)
                let slot = indices.firstIndex(of: spaceIndex) ?? 0

                if draggingSpaceIndex == nil {
                    draggingSpaceIndex = spaceIndex
                    dragOriginalSlot = slot
                    currentTargetSlot = slot
                    shiftOffsets = [:]
                    // Calculate start center from slot position
                    if let frame = state.spaceFrames[spaceIndex] {
                        dragStartCenter = CGPoint(x: frame.midX, y: frame.midY)
                    }
                }
                dragX = value.translation.width

                let target = max(0, min(indices.count - 1,
                    dragOriginalSlot + Int(round(dragX / slotWidth))))

                if target != currentTargetSlot {
                    currentTargetSlot = target
                    var newShifts: [Int: CGFloat] = [:]
                    let from = dragOriginalSlot
                    for (i, idx) in indices.enumerated() {
                        if idx == spaceIndex { continue }
                        if from < target && i > from && i <= target {
                            newShifts[idx] = -slotWidth
                        } else if from > target && i >= target && i < from {
                            newShifts[idx] = slotWidth
                        }
                    }
                    shiftOffsets = newShifts
                }
            }
            .onEnded { _ in
                let from = dragOriginalSlot
                let to = currentTargetSlot
                if from != to {
                    let indices = state.spaces.map(\.index)
                    WindowManager.reorderSpace(indices[from], to: indices[to])
                    refreshAfterReorder()
                }
                draggingSpaceIndex = nil
                dragX = 0
                currentTargetSlot = -1
                shiftOffsets = [:]
            }
    }

    private func refreshAfterReorder() {
        let fresh = WindowManager.querySpaces()
        let lastOccupied = fresh.filter({ !$0.windowIDs.isEmpty }).map(\.index).max() ?? 0
        let cutoff = max(lastOccupied, state.currentSpaceIndex) + 1
        state.spaces = fresh.filter { !$0.windowIDs.isEmpty || $0.index <= cutoff }

        // Update window space assignments
        let freshWindows = WindowManager.queryWindowInfo()
        for fw in freshWindows {
            if let idx = state.windows.firstIndex(where: { $0.id == fw.id }), fw.space != state.windows[idx].space {
                let old = state.windows[idx]
                state.windows[idx] = WindowInfo(id: old.id, pid: old.pid, app: old.app, title: old.title,
                                                 space: fw.space, frame: old.frame, image: old.image, icon: old.icon)
            }
        }
    }

}

// MARK: - Space thumbnail appearance

struct SpaceThumbnailContent: View {
    let windows: [WindowInfo]
    let isCurrent: Bool
    let isDropTarget: Bool
    let screenSize: CGSize

    private let thumbWidth: CGFloat = 180
    private var thumbHeight: CGFloat { thumbWidth * (screenSize.height / screenSize.width) }

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
