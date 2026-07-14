import SwiftUI

struct Avatar: View {
    let initial: String
    let tone: AvatarTone
    var size: CGFloat = 28
    var borderWidth: CGFloat = 2

    private var bg: Color {
        switch tone {
        case .terracotta: Sage.Avatar.terracotta
        case .sage: Sage.Avatar.sage
        case .sand: Sage.Avatar.sand
        case .slate: Sage.Avatar.slate
        }
    }

    var body: some View {
        Text(initial)
            .font(size >= 40 ? .avatarLarge : .avatarSmall)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(bg, in: Circle())
            .overlay(Circle().stroke(Sage.surface, lineWidth: borderWidth))
    }
}

struct AvatarAdd: View {
    var size: CGFloat = 44
    var borderWidth: CGFloat = 3

    var body: some View {
        Text("+")
            .font(.system(size: size >= 40 ? 20 : 14, weight: .regular))
            .foregroundStyle(Sage.accent)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(Sage.accentSoft, style: StrokeStyle(lineWidth: borderWidth, dash: [3, 3]))
            )
    }
}

struct AvatarOverflow: View {
    let count: Int
    var size: CGFloat = 28
    var borderWidth: CGFloat = 2

    var body: some View {
        Text("+\(count)")
            .font(size >= 34 ? .avatarLarge : .avatarSmall)
            .foregroundStyle(Sage.textSecondary)
            .frame(width: size, height: size)
            .background(Sage.surface2, in: Circle())
            .overlay(Circle().stroke(Sage.surface, lineWidth: borderWidth))
    }
}

struct AvatarGroup: View {
    let members: [MemberCard]
    var size: CGFloat = 28
    var borderWidth: CGFloat = 2
    var maxVisible: Int? = nil
    var onAddTap: (() -> Void)?

    private var visibleMembers: [MemberCard] {
        guard let max = maxVisible, members.count > max else { return members }
        return Array(members.prefix(max - 1))
    }

    private var overflowCount: Int {
        guard let max = maxVisible, members.count > max else { return 0 }
        return members.count - (max - 1)
    }

    var body: some View {
        // The add button sits outside the overlapping stack: AvatarAdd has no
        // opaque fill, so tucking it under the overflow badge showed the badge
        // through the dashed ring.
        HStack(spacing: 5) {
            HStack(spacing: -8) {
                ForEach(visibleMembers) { member in
                    Avatar(initial: member.initial, tone: member.tone, size: size, borderWidth: borderWidth)
                }
                if overflowCount > 0 {
                    AvatarOverflow(count: overflowCount, size: size, borderWidth: borderWidth)
                }
            }
            if let onAddTap {
                Button {
                    Haptics.light()
                    onAddTap()
                } label: {
                    AvatarAdd(size: size, borderWidth: borderWidth)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add people")
            }
        }
    }
}

#Preview("Avatars") {
    VStack(spacing: 32) {
        HStack(spacing: 12) {
            Avatar(initial: "A", tone: .terracotta, size: 44, borderWidth: 3)
            Avatar(initial: "B", tone: .sage, size: 44, borderWidth: 3)
            Avatar(initial: "C", tone: .sand, size: 44, borderWidth: 3)
            Avatar(initial: "D", tone: .slate, size: 44, borderWidth: 3)
            AvatarAdd(size: 44, borderWidth: 3)
        }
        HStack(spacing: 12) {
            Avatar(initial: "A", tone: .terracotta, size: 28)
            Avatar(initial: "B", tone: .sage, size: 28)
            Avatar(initial: "C", tone: .sand, size: 28)
            Avatar(initial: "D", tone: .slate, size: 28)
        }
        AvatarGroup(
            members: [
                MemberCard(id: UUID(), displayName: "Alex"),
                MemberCard(id: UUID(), displayName: "Sam"),
                MemberCard(id: UUID(), displayName: "Jess"),
            ],
            size: 44,
            borderWidth: 3,
            onAddTap: {}
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}
