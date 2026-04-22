import SwiftUI

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search...", text: $model.query)
                    .font(.system(size: 24, weight: .light))
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onChange(of: model.query) { _, _ in
                        model.updateResults()
                    }

                if !model.query.isEmpty {
                    Button(action: { model.query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)

            if model.hasResults {
                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ResultRow(
                            item: item,
                            selected: model.selectedIndex == index,
                            showCopied: model.copiedFlash && model.selectedIndex == index,
                            action: {
                                model.selectedIndex = index
                                model.launchSelected()
                            }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .frame(width: 680)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
    }
}

struct ResultRow: View {
    let item: SearchItem
    let selected: Bool
    let showCopied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconView.frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: selected ? .medium : .regular))
                        .foregroundStyle(.primary)
                    if let sub = item.subtitle {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if selected {
                    if showCopied {
                        Text("Copied")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Accent.green)
                    } else {
                        Text("\u{21B5}")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Accent.subtext)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(selected ? 0.1 : 0))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.iconType {
        case .app(let image):
            Image(nsImage: image)
                .interpolation(.high)
                .resizable()
                .frame(width: 32, height: 32)
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 22))
                .foregroundStyle(color)
        case .emoji(let char):
            Text(char)
                .font(.system(size: 26))
        }
    }
}
