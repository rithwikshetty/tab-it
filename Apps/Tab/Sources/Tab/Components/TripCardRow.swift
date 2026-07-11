import SwiftUI

struct TripCardRow: View {
    let trip: TripCard

    private var statusColor: Color {
        switch trip.status {
        case .owed: Sage.accent
        case .owe: Sage.warning
        case .mixed: Sage.textSecondary
        case .settled, .empty: Sage.textSecondary
        }
    }

    private var statusText: String {
        switch trip.status {
        case .owed(let s), .owe(let s), .mixed(let s), .settled(let s): s
        case .empty: "no expenses yet"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name)
                    .font(.tripName)
                    .tracking(-0.15)
                    .foregroundStyle(Sage.text)
                    .lineLimit(1)
                Text(statusText)
                    .font(.tripStatus)
                    .tracking(-0.07)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            AvatarGroup(members: trip.members, size: 28, borderWidth: 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .opacity(trip.isCompleted ? 0.72 : 1)
        .saturation(trip.isCompleted ? 0.7 : 1)
    }
}

#Preview("Trip rows") {
    let members = [
        MemberCard(id: UUID(), displayName: "Alex"),
        MemberCard(id: UUID(), displayName: "Sam"),
        MemberCard(id: UUID(), displayName: "Jess"),
    ]
    return VStack(spacing: 0) {
        TripCardRow(trip: TripCard(
            id: UUID(), name: "Lisbon weekend", members: members,
            status: .owed("you're owed €42.50"), isCompleted: false
        ))
        RowDivider()
        TripCardRow(trip: TripCard(
            id: UUID(), name: "Italy roadtrip", members: members,
            status: .owe("you owe €18.00"), isCompleted: false
        ))
        RowDivider()
        TripCardRow(trip: TripCard(
            id: UUID(), name: "Solo coffee run", members: [members[0]],
            status: .empty, isCompleted: false
        ))
        RowDivider()
        TripCardRow(trip: TripCard(
            id: UUID(), name: "Barcelona 2023", members: members,
            status: .settled("settled · Mar 2023"), isCompleted: true
        ))
    }
    .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}
