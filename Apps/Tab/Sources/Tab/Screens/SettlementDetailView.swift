import SwiftUI
import SwiftData

struct SettlementDetailView: View {
    let settlementID: UUID
    let onEditSettlement: (UUID, UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query private var settlements: [SettlementEntity]

    @State private var confirmDelete = false

    init(settlementID: UUID, onEditSettlement: @escaping (UUID, UUID) -> Void = { _, _ in }) {
        self.settlementID = settlementID
        self.onEditSettlement = onEditSettlement
        _settlements = Query(filter: #Predicate<SettlementEntity> { $0.id == settlementID })
    }

    private var settlement: SettlementEntity? { settlements.first }

    var body: some View {
        Group {
            if let settlement, settlement.deletedAt == nil {
                content(for: settlement)
            } else {
                MissingSettlementView { dismiss() }
            }
        }
        .background(Sage.bg.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if let settlement, let tripID = settlement.trip?.id {
                            onEditSettlement(tripID, settlement.id)
                        }
                    } label: {
                        Label("Edit settlement", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete settlement", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Sage.accent)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Delete this settlement?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It will be removed from balances.")
        }
    }

    @ViewBuilder
    private func content(for settlement: SettlementEntity) -> some View {
        let userID = auth.currentUser?.id
        let peopleByID = Dictionary(uniqueKeysWithValues: (settlement.trip?.people ?? []).map { ($0.id, $0) })
        let currentPersonID = userID.flatMap { id in
            settlement.trip?.people.first(where: { $0.userID == id })?.id
        }

        let fromName: String = {
            if settlement.fromPersonID == currentPersonID { return "You" }
            return peopleByID[settlement.fromPersonID]?.displayName ?? "Member"
        }()
        let toName: String = {
            if settlement.toPersonID == currentPersonID { return "You" }
            return peopleByID[settlement.toPersonID]?.displayName ?? "Member"
        }()

        let recorderIsYou = userID.map { $0 == settlement.createdByID } ?? false
        let recorderName = recorderIsYou
            ? "You"
            : (settlement.trip?.people.first(where: { $0.userID == settlement.createdByID })?.displayName ?? "Member")

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                amountBlock(settlement: settlement)
                fromToCard(settlement: settlement, fromName: fromName, toName: toName, currentPersonID: currentPersonID)

                sectionLabel("Details")
                detailsCard(settlement: settlement, recorderName: recorderName)

                Spacer(minLength: 28)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func amountBlock(settlement: SettlementEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SETTLEMENT")
                .font(.balanceLabel)
                .tracking(1.10)
                .foregroundStyle(Sage.Avatar.slate.opacity(0.85))
            Text(MoneyFormatter.format(settlement.amount, currency: settlement.currency))
                .font(.balanceAmount)
                .tracking(-0.85)
                .foregroundStyle(Sage.Avatar.slate)
                .monospacedDigit()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Sage.Avatar.slate.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Sage.Avatar.slate.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private func fromToCard(
        settlement: SettlementEntity,
        fromName: String,
        toName: String,
        currentPersonID: UUID?
    ) -> some View {
        VStack(spacing: 0) {
            personDetailRow(
                label: "FROM",
                personID: settlement.fromPersonID,
                name: fromName,
                currentPersonID: currentPersonID
            )
            RowDivider()
            HStack {
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Sage.Avatar.slate)
                    .frame(width: 28, height: 28)
                    .background(Sage.surface2, in: Circle())
                    .overlay(Circle().stroke(Sage.surface, lineWidth: 2))
                Spacer()
            }
            .frame(height: 1)
            personDetailRow(
                label: "TO",
                personID: settlement.toPersonID,
                name: toName,
                currentPersonID: currentPersonID
            )
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func personDetailRow(label: String, personID: UUID, name: String, currentPersonID: UUID?) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.32)
                .foregroundStyle(Sage.textSecondary)
                .frame(width: 38, alignment: .leading)
            Avatar(
                initial: AvatarInitial.from(
                    personID == currentPersonID
                        ? (auth.currentUser?.displayName ?? name)
                        : name
                ),
                tone: AvatarTone.deterministic(for: personID),
                size: 28,
                borderWidth: 2
            )
            Text(name)
                .font(.system(size: 14.5, weight: .medium))
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func detailsCard(settlement: SettlementEntity, recorderName: String) -> some View {
        VStack(spacing: 0) {
            detailRow(label: "Date", value: Self.fullDateFormatter.string(from: settlement.settledAt))
            if let note = settlement.note, !note.isEmpty {
                RowDivider()
                detailRow(label: "Note", value: note)
            }
            RowDivider()
            detailRow(label: "Recorded by", value: recorderName)
            RowDivider()
            detailRow(label: "Recorded at", value: Self.timestampFormatter.string(from: settlement.createdAt))
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.formRowLabel)
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            Text(value)
                .font(.formRowValue)
                .tracking(-0.07)
                .foregroundStyle(Sage.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func performDelete() {
        guard let settlement else { return }
        Deletion.softDelete(settlement: settlement, in: context)
        Haptics.success()
        dismiss()
        Task { await sync.pushPending() }
    }

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

private struct MissingSettlementView: View {
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Sage.textSecondary)
            Text("Settlement not found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Sage.text)
            Button("Back") { onBack() }
                .font(.system(size: 15))
                .foregroundStyle(Sage.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
