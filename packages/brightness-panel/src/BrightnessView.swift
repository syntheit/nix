import SwiftUI

struct BrightnessView: View {
    @ObservedObject var display: BrightnessManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Brightness")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                Image(systemName: "sun.min")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.15))
                        Capsule()
                            .fill(.white)
                            .frame(width: max(4, geo.size.width * CGFloat(display.brightness)))
                    }
                }
                .frame(height: 6)

                Image(systemName: "sun.max")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 340)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
    }
}
