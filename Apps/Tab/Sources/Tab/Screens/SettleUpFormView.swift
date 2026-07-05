import SwiftUI
import SwiftData
import TabCore

struct SettleUpFormView: View {
    let tripID: UUID
    let editingSettlementID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]
    @Query private var editingSettlements: [SettlementEntity]

    @State private var amountText: String = ""
    @State private var isSaving = false
    @State private var fromPersonID: UUID?
    @State private var toPersonID: UUID?
    @State private var currency: String = CurrencyDefaults.initialCurrency
    @State private var isCurrencyPickerPresented = false
    @State private var settledAt: Date = .now
    @State private var isDatePickerPresented = false
    @State private var note: String = ""
    @State private var hasPrePopulated = false

    private var isEditing: Bool { editingSettlementID != nil }
    private var editingSettlement: SettlementEntity? { editingSettlements.first }

    init(tripID: UUID, editingSettlementID: UUID? = nil) {
        self.tripID = tripID
        self.editingSettlementID = editingSettlementID
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
        let eid = editingSettlementID ?? UUID()
        _editingSettlements = Query(filter: #Predicate<SettlementEntity> { $0.id == eid })
    }

    private var trip: TripEntity? { trips.first }

    private var totalAmount: Decimal {
        MoneyFormatter.decimal(from: amountText) ?? 0
    }

    private var currencySelection: Binding<String> {
        Binding(
            get: { currency },
            set: { newValue in
                currency = newValue
                CurrencyDefaults.remember(newValue)
            }
        )
    }

    private var canSave: Bool {
        totalAmount > 0
            && CurrencyCatalog.hasValidPrecision(totalAmount, currency: currency)
            && fromPersonID != nil
            && toPersonID != nil
            && fromPersonID != toPersonID
            && auth.currentUser != nil
            && !isSaving
    }

    private var currentPersonID: UUID? {
        guard let trip, let user = auth.currentUser else { return nil }
        return trip.people.first(where: { $0.userID == user.id })?.id
    }

    private var currentBalances: [UserBalance] {
        guard let trip else { return [] }
        let coreExpenses = trip.expenses.filter { $0.deletedAt == nil }.map { $0.toCoreExpense() }
        let coreSettlements = trip.settlements
            .filter { settlement in
                guard settlement.deletedAt == nil else { return false }
                if let editingSettlementID, settlement.id == editingSettlementID { return false }
                return true
            }
            .map { $0.toCoreSettlement() }
        return BalanceEngine.compute(expenses: coreExpenses, settlements: coreSettlements)
    }

    private var pairBalance: Decimal? {
        guard let from = fromPersonID, let to = toPersonID else { return nil }
        return currentBalances.first(where: { $0.forUser == from && $0.withUser == to && $0.currency == currency })?.amount
    }

    private func displayName(for personID: UUID) -> String {
        if personID == currentPersonID { return "You" }
        return trip?.people.first(where: { $0.id == personID })?.displayName ?? "Member"
    }

    /// Active members, plus removed people who still owe or are owed something
    /// (debts survive removal and must stay settleable), plus anyone already
    /// selected on this form.
    private var selectablePeople: [TripPersonEntity] {
        guard let trip else { return [] }
        var keep = Set<UUID>()
        for balance in currentBalances where balance.amount != 0 {
            keep.insert(balance.forUser)
        }
        if let fromPersonID { keep.insert(fromPersonID) }
        if let toPersonID { keep.insert(toPersonID) }
        return trip.people.filter { $0.removedAt == nil || keep.contains($0.id) }
    }

    var body: some View {
        Group {
            if trip == nil {
                Color.clear.onAppear { dismiss() }
            } else if isEditing, editingSettlement == nil || editingSettlement?.deletedAt != nil {
                Color.clear.onAppear { dismiss() }
            } else {
                form
            }
        }
        .background(Sage.bg.ignoresSafeArea())
        .navigationTitle(isEditing ? "Edit settlement" : "Settle up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .font(.navLinkBold)
                    .foregroundStyle(canSave ? Sage.accent : Sage.accent.opacity(0.4))
                    .disabled(!canSave)
                    .animation(.snappy(duration: 0.15), value: canSave)
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { prepopulate() }
        .onChange(of: currency) {
            amountText = MoneyFormatter.convertAmountText(amountText, to: currency)
            updateAmountForPair()
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 0) {
                amountBlock
                hairline

                sectionLabel("Payment")
                paymentCard

                if let contextText = balanceContextText {
                    balanceContextBanner(contextText)
                }

                sectionLabel("Details")
                Card(horizontalPadding: 18) {
                    dateRow
                    RowDivider()
                    noteRow
                }

                Spacer(minLength: 24)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Sage.rowDivider)
            .frame(height: 1)
    }

    private var amountBlock: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            DecimalTextField(
                text: $amountText,
                placeholder: MoneyFormatter.amountPlaceholder(currency: currency),
                font: .systemFont(ofSize: 52, weight: .light),
                textColor: UIColor(Sage.text),
                placeholderColor: UIColor(Sage.textSecondary.opacity(0.55)),
                alignment: .left,
                tintColor: UIColor(Sage.accent),
                becomeFirstResponderOnAppear: !isEditing,
                accessibilityIdentifier: "settlement.amountField"
            )
            .frame(height: 62)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: amountText) { _, new in
                let sanitized = sanitizeAmount(new)
                if sanitized != new { amountText = sanitized }
            }

            CurrencyPill(code: currency, symbol: MoneyFormatter.currencySymbol(currency)) {
                isCurrencyPickerPresented = true
            }
            .sheet(isPresented: $isCurrencyPickerPresented) {
                CurrencyPickerSheet(selection: currencySelection)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var paymentCard: some View {
        VStack(spacing: 0) {
            personRow(label: "From", personID: fromPersonID, excludeID: toPersonID) { id in
                withAnimation(.snappy(duration: 0.18)) {
                    fromPersonID = id
                    updateAmountForPair()
                }
            }
            RowDivider()
            HStack {
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Sage.Avatar.slate)
                    .frame(width: 28, height: 28)
                    .background(Sage.surface2, in: Circle())
                    .overlay(Circle().stroke(Sage.surface, lineWidth: 2))
                    .offset(y: -1)
                Spacer()
            }
            .frame(height: 1)
            personRow(label: "To", personID: toPersonID, excludeID: fromPersonID) { id in
                withAnimation(.snappy(duration: 0.18)) {
                    toPersonID = id
                    updateAmountForPair()
                }
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .shadow(color: Sage.shadow, radius: 1, x: 0, y: 1)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func personRow(
        label: String,
        personID: UUID?,
        excludeID: UUID?,
        onSelect: @escaping (UUID) -> Void
    ) -> some View {
        let members = selectablePeople.sortedForDisplay(currentPersonID: currentPersonID)
        Menu {
            ForEach(members, id: \.id) { person in
                if person.id != excludeID {
                    Button {
                        onSelect(person.id)
                    } label: {
                        let name = person.id == currentPersonID ? "You" : person.displayName
                        Label(name, systemImage: person.id == personID ? "checkmark" : "")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Sage.textSecondary)
                    .frame(width: 38, alignment: .leading)

                if let personID {
                    let tone = AvatarTone.deterministic(for: personID)
                    let name = displayName(for: personID)
                    Avatar(
                        initial: AvatarInitial.from(
                            personID == currentPersonID
                                ? (auth.currentUser?.displayName ?? name)
                                : name
                        ),
                        tone: tone,
                        size: 28,
                        borderWidth: 2
                    )
                    Text(name)
                        .font(.formRow.weight(.medium))
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                }

                Spacer()
                Chevron(size: 9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var balanceContextText: String? {
        guard let from = fromPersonID, let to = toPersonID, from != to else { return nil }
        let fromName = displayName(for: from)
        let toName = displayName(for: to)

        guard let balance = pairBalance else { return nil }

        if balance == 0 { return nil }

        if balance < 0 {
            let amount = -balance
            let formatted = MoneyFormatter.format(amount, currency: currency)
            let remaining = amount - totalAmount
            if remaining > 0 {
                let remainFormatted = MoneyFormatter.format(remaining, currency: currency)
                return "\(fromName) owes \(toName) \(formatted). After this, \(remainFormatted) will remain."
            }
            if remaining == 0 {
                return "\(fromName) owes \(toName) \(formatted). This will settle the full balance."
            }
            let overpaid = -remaining
            let overpaidFormatted = MoneyFormatter.format(overpaid, currency: currency)
            return "\(fromName) owes \(toName) \(formatted). This overpays by \(overpaidFormatted), so \(toName) will owe \(fromName) \(overpaidFormatted)."
        }

        let formatted = MoneyFormatter.format(balance, currency: currency)
        let increased = balance + totalAmount
        let increasedFormatted = MoneyFormatter.format(increased, currency: currency)
        return "\(toName) already owes \(fromName) \(formatted). This payment is opposite that balance; after this, \(toName) will owe \(fromName) \(increasedFormatted)."
    }

    private func balanceContextBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Sage.Avatar.slate)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Sage.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Sage.Avatar.slate.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Sage.Avatar.slate.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var dateRow: some View {
        Button {
            isDatePickerPresented = true
        } label: {
            HStack(spacing: 12) {
                Text("Date")
                    .font(.formRowLabel)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                Spacer()
                Text(Self.dateFormatter.string(from: settledAt))
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Sage.accent)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .popover(isPresented: $isDatePickerPresented) {
            InlineDatePicker(selection: $settledAt, tintColor: UIColor(Sage.accent)) {
                isDatePickerPresented = false
            }
            .frame(width: 320, height: 324)
            .padding(12)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var noteRow: some View {
        TextField("Add a note (optional)", text: $note)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .font(.formRow)
            .tracking(-0.07)
            .foregroundStyle(Sage.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pre-population

    private func prepopulate() {
        guard !hasPrePopulated else { return }
        hasPrePopulated = true

        if let settlement = editingSettlement {
            currency = settlement.currency
            amountText = plainAmountString(settlement.amount)
            fromPersonID = settlement.fromPersonID
            toPersonID = settlement.toPersonID
            settledAt = settlement.settledAt
            note = settlement.note ?? ""
            return
        }

        currency = CurrencyDefaults.defaultCurrency(for: trip)

        guard let trip, let cpID = currentPersonID else { return }
        fromPersonID = cpID

        if let suggestion = SettleUpPresenter.suggestedPayment(
            balances: currentBalances,
            currentPersonID: cpID
        ) {
            fromPersonID = suggestion.fromPersonID
            toPersonID = suggestion.toPersonID
            currency = suggestion.currency
            amountText = plainAmountString(suggestion.amount)
        } else if let firstOther = trip.activePeople.first(where: { $0.id != cpID }) {
            toPersonID = firstOther.id
        }
    }

    private func updateAmountForPair() {
        guard !isEditing, let from = fromPersonID, let to = toPersonID else { return }
        if let entry = currentBalances.first(where: { $0.forUser == from && $0.withUser == to && $0.currency == currency }) {
            let owed = abs(entry.amount)
            if owed > 0 {
                amountText = plainAmountString(owed)
            }
        }
    }

    // MARK: - Save

    private func save() {
        // canSave includes !isSaving, so this also rejects a second tap during dismiss.
        guard canSave else { return }
        isSaving = true
        if isEditing {
            guard let settlement = editingSettlement, settlement.deletedAt == nil else {
                isSaving = false
                return
            }
            saveEdit(settlement)
        } else {
            saveNew()
        }
    }

    private func saveNew() {
        guard let trip, let user = auth.currentUser,
              let from = fromPersonID, let to = toPersonID else {
            isSaving = false
            return
        }

        let settlement = SettlementEntity(
            id: UUID(),
            fromPersonID: from,
            toPersonID: to,
            amount: totalAmount,
            currency: currency,
            note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces),
            settledAt: settledAt,
            createdByID: user.id,
            trip: trip
        )
        context.insert(settlement)

        trip.lastActivityAt = .now

        try? context.save()
        CurrencyDefaults.remember(currency)
        Haptics.success()
        dismiss()
        Task { await sync.pushPending() }
    }

    private func saveEdit(_ settlement: SettlementEntity) {
        guard let trip, let from = fromPersonID, let to = toPersonID else {
            isSaving = false
            return
        }

        settlement.fromPersonID = from
        settlement.toPersonID = to
        settlement.amount = totalAmount
        settlement.currency = currency
        settlement.note = note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces)
        settlement.settledAt = settledAt
        settlement.updatedAt = .now
        settlement.writeID = UUID()

        trip.lastActivityAt = .now

        try? context.save()
        CurrencyDefaults.remember(currency)
        Haptics.success()
        dismiss()
        Task { await sync.pushPending() }
    }

    // MARK: - Helpers

    private func sanitizeAmount(_ input: String) -> String {
        MoneyFormatter.sanitizeAmountInput(input, currency: currency)
    }

    private func plainAmountString(_ amount: Decimal) -> String {
        MoneyFormatter.plainAmountString(amount, currency: currency)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
