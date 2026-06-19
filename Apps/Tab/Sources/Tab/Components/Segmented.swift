import SwiftUI

struct Segmented: View {
    let options: [String]
    @Binding var selection: Int
    var mini: Bool = false
    var horizontalPadding: CGFloat = 18

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                let isActive = index == selection
                Button {
                    if selection != index { selection = index }
                } label: {
                    Text(label)
                        .font(mini ? .segmentTextMini : .segmentText)
                        .tracking(-0.07)
                        .foregroundStyle(isActive ? Sage.text : Sage.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, mini ? 6 : 8)
                        .background {
                            if isActive {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Sage.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
                            }
                        }
                        .fontWeight(isActive ? .semibold : .medium)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Sage.segmentedBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, horizontalPadding)
    }
}
