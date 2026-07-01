import SwiftUI
import SwiftData
import TabCore

struct PaymentSplitView: View {
    let tripID: UUID
    let totalAmount: Decimal
    let currency: String
    @Binding var payments: [Payment]
    @Binding var splitMode: Int
    @Binding var participantSet: Set<UUID>
    @Binding var exactSplitAmountText: [UUID: String]
    @Binding var shareSplitText: [UUID: String]
    @Binding var percentSplitText: [UUID: String]

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    @Query private var trips: [TripEntity]

    @State private var draft = PaymentSplitDraft()

    private enum FocusField: Hashable {
        case payer(UUID)
        case split(UUID)
    }
    @FocusState private var focused: FocusField?

    private enum Layout {
        static let hPad: CGFloat = 18
        static let cardHPad: CGFloat = 18
    }

    init(tripID: UUID, totalAmount: Decimal, currency: String,
         payments: Binding<[Payment]>, splitMode: Binding<Int>,
         participantSet: Binding<Set<UUID>>, exactSplitAmountText: Binding<[UUID: String]>,
         shareSplitText: Binding<[UUID: String]>, percentSplitText: Binding<[UUID: String]>) {
        self.tripID = tripID
        self.totalAmount = totalAmount
        self.currency = currency
        _payments = payments
        _splitMode = splitMode
        _participantSet = participantSet
        _exactSplitAmountText = exactSplitAmountText
        _shareSplitText = shareSplitText
        _percentSplitText = percentSplitText
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
    }

    private var trip: TripEntity? { trips.first }

    private var currentPersonID: UUID? {
        guard let trip, let userID = auth.currentUser?.id else { return nil }
        return trip.people.first(where: { $0.userID == userID })?.id
    }

    private var members: [TripPersonEntity] {
        trip?.people.sortedForDisplay(currentPersonID: currentPersonID) ?? []
    }

    private var computedPayments: [Payment]? {
        draft.computedPayments(totalAmount: totalAmount, currency: currency)
    }

    private var computedSplits: [ExpenseSplit]? {
        draft.computedSplits(totalAmount: totalAmount, currency: currency)
    }

    private var canSave: Bool {
        computedPayments != nil && computedSplits != nil
    }

    // MARK: - Body

    var body: some View {
        Group {
            if trip != nil { formContent }
            else { Color.clear.onAppear { dismiss() } }
        }
        .background(Sage.bg.ignoresSafeArea())
        .navigationTitle("Payment & Split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { commit() }
                    .font(.navLinkBold)
                    .foregroundStyle(canSave ? Sage.accent : Sage.accent.opacity(0.4))
                    .disabled(!canSave)
                    .animation(.snappy(duration: 0.15), value: canSave)
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            draft.seed(
                payments: payments,
                splitMode: splitMode,
                participantSet: participantSet,
                exactSplitAmountText: exactSplitAmountText,
                shareSplitText: shareSplitText,
                percentSplitText: percentSplitText,
                currency: currency,
                currentPersonID: currentPersonID,
                members: members.map(\.id)
            )
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                totalRow
                hairline

                whoPaidSection
                splitBetweenSection

                Spacer(minLength: 24)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Total

    private var totalRow: some View {
        HStack {
            Text("Total")
                .font(.formRowLabel)
                .foregroundStyle(Sage.textSecondary)
            Spacer()
            Text(MoneyFormatter.format(totalAmount, currency: currency))
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Sage.text)
                .monospacedDigit()
        }
        .padding(.horizontal, Layout.hPad)
        .padding(.vertical, 16)
    }

    private var hairline: some View {
        Rectangle().fill(Sage.rowDivider).frame(height: 1)
    }

    // MARK: - Who Paid

    private var whoPaidSection: some View {
        VStack(spacing: 0) {
            whoPaidHeader
            payerCard
        }
    }

    private var whoPaidHeader: some View {
        HStack {
            Text("WHO PAID")
                .font(.sectionLabel)
                .tracking(1.32)
                .foregroundStyle(Sage.textSecondary)
            Spacer()
            if draft.selectedPayerIDs.count > 1 {
                payerModeMenu
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            }
        }
        .padding(.horizontal, Layout.hPad + 4)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.22), value: draft.selectedPayerIDs.count > 1)
    }

    private var payerModeMenu: some View {
        Menu {
            Button {
                draft.setPayerMode(.equal, totalAmount: totalAmount, currency: currency)
                focused = nil
            } label: {
                Label("Equal", systemImage: draft.payerMode == .equal ? "checkmark" : "")
            }
            Button {
                draft.setPayerMode(.exact, totalAmount: totalAmount, currency: currency)
            } label: {
                Label("Exact amounts", systemImage: draft.payerMode == .exact ? "checkmark" : "")
            }
        } label: {
            TypePill(title: draft.payerMode == .equal ? "Equal" : "Exact")
        }
        .accessibilityIdentifier("paymentSplit.payerModePill")
    }

    private var payerCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, person in
                payerRow(person: person)
                if index < members.count - 1 { RowDivider() }
            }
            if let footer = payerReconcileFooter {
                RowDivider()
                Text(footer.text)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.07)
                    .foregroundStyle(footer.isValid ? Sage.textSecondary : Sage.warning)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .transition(.opacity)
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, Layout.cardHPad)
        .animation(.snappy(duration: 0.2), value: draft.payerMode)
    }

    private func payerRow(person: TripPersonEntity) -> some View {
        let personID = person.id
        let isOn = draft.selectedPayerIDs.contains(personID)
        let isYou = personID == currentPersonID
        let name = isYou ? "You" : person.displayName
        let payment = computedPayments?.first { $0.payerID == personID }
        let displayShare = isOn
            ? MoneyFormatter.format(payment?.amountPaid ?? 0, currency: currency)
            : "—"
        let canTapToEdit = isOn && draft.payerMode == .equal && draft.selectedPayerIDs.count > 1

        return HStack(spacing: 12) {
            Button {
                Haptics.light()
                withAnimation(.snappy(duration: 0.18)) {
                    draft.togglePayer(personID, totalAmount: totalAmount, currency: currency)
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(isOn ? Sage.accent : Sage.textSecondary.opacity(0.4), in: Circle())
                    .scaleEffect(isOn ? 1.0 : 0.92)
                    .animation(.snappy(duration: 0.18), value: isOn)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paidBy.toggle.\(personID.uuidString)")
            .accessibilityLabel("Toggle payer \(name)")

            Text(name)
                .font(.formRow.weight(.medium))
                .tracking(-0.07)
                .foregroundStyle(isOn ? Sage.text : Sage.textSecondary)

            Spacer()

            if draft.payerMode == .exact, isOn, draft.selectedPayerIDs.count > 1 {
                InlineDecimalTextField(
                    text: Binding(
                        get: { draft.exactPayerAmountText[personID, default: ""] },
                        set: { draft.setExactPayerAmount($0, for: personID, currency: currency) }
                    ),
                    placeholder: MoneyFormatter.amountPlaceholder(currency: currency),
                    isFocused: focused == .payer(personID),
                    onFocus: { focused = .payer(personID) },
                    accessibilityIdentifier: "paidBy.exactAmount.\(personID.uuidString)"
                )
                .frame(width: 88, height: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Sage.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
            } else {
                Text(displayShare)
                    .font(.system(size: 13))
                    .tracking(-0.07)
                    .foregroundStyle(isOn ? Sage.textSecondary : Sage.textSecondary.opacity(0.5))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .onTapGesture {
                        guard canTapToEdit else { return }
                        Haptics.light()
                        draft.setPayerMode(.exact, totalAmount: totalAmount, currency: currency)
                        focused = .payer(personID)
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var payerReconcileFooter: (text: String, isValid: Bool)? {
        guard draft.selectedPayerIDs.count > 1, totalAmount > 0 else { return nil }
        switch draft.payerMode {
        case .equal:
            guard let payments = computedPayments else { return nil }
            let amounts = Set(payments.map(\.amountPaid))
            if amounts.count == 1, let amount = amounts.first {
                return ("Each pays \(MoneyFormatter.format(amount, currency: currency))", true)
            }
            return ("Equal total \(MoneyFormatter.format(totalAmount, currency: currency))", true)
        case .exact:
            let remaining = totalAmount - draft.enteredPayerTotal
            if computedPayments != nil {
                return ("Exact total \(MoneyFormatter.format(draft.enteredPayerTotal, currency: currency))", true)
            }
            if remaining >= 0 {
                return ("Remaining \(MoneyFormatter.format(remaining, currency: currency))", false)
            }
            return ("Over by \(MoneyFormatter.format(-remaining, currency: currency))", false)
        default:
            return nil
        }
    }

    // MARK: - Split Between

    private var splitBetweenSection: some View {
        VStack(spacing: 0) {
            splitHeader
            splitCard
        }
    }

    private var splitHeader: some View {
        HStack {
            Text("SPLIT BETWEEN")
                .font(.sectionLabel)
                .tracking(1.32)
                .foregroundStyle(Sage.textSecondary)
            Spacer()
            splitModeMenu
        }
        .padding(.horizontal, Layout.hPad + 4)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var splitModeMenu: some View {
        Menu {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    draft.setSplitMode(0, totalAmount: totalAmount, currency: currency)
                }
                focused = nil
            } label: {
                Label("Equal", systemImage: draft.splitMode == 0 ? "checkmark" : "")
            }
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    draft.setSplitMode(1, totalAmount: totalAmount, currency: currency)
                }
            } label: {
                Label("Exact amounts", systemImage: draft.splitMode == 1 ? "checkmark" : "")
            }
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    draft.setSplitMode(2, totalAmount: totalAmount, currency: currency)
                }
            } label: {
                Label("Shares", systemImage: draft.splitMode == 2 ? "checkmark" : "")
            }
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    draft.setSplitMode(3, totalAmount: totalAmount, currency: currency)
                }
            } label: {
                Label("Percentages", systemImage: draft.splitMode == 3 ? "checkmark" : "")
            }
        } label: {
            TypePill(title: splitModePillTitle)
        }
        .accessibilityIdentifier("paymentSplit.splitModePill")
    }

    private var splitModePillTitle: String {
        switch draft.splitMode {
        case 0: "Equal"
        case 2: "Shares"
        case 3: "Percent"
        default: "Exact"
        }
    }

    private var splitCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, person in
                splitRow(person: person)
                if index < members.count - 1 { RowDivider() }
            }
            if let footer = splitReconcileFooter {
                RowDivider()
                Text(footer.text)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.07)
                    .foregroundStyle(footer.isValid ? Sage.textSecondary : Sage.warning)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .transition(.opacity)
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, Layout.cardHPad)
        .animation(.snappy(duration: 0.2), value: draft.selectedSplitType)
    }

    private func splitRow(person: TripPersonEntity) -> some View {
        let personID = person.id
        let isOn = draft.selectedParticipants.contains(personID)
        let isYou = personID == currentPersonID
        let name = isYou ? "You" : person.displayName
        let split = computedSplits?.first { $0.participantID == personID }
        let displayShare = isOn
            ? MoneyFormatter.format(split?.amountOwed ?? 0, currency: currency)
            : "—"
        let canTapToEdit = isOn && draft.selectedSplitType == .equal

        return HStack(spacing: 12) {
            Button {
                Haptics.light()
                withAnimation(.snappy(duration: 0.18)) {
                    draft.toggleParticipant(personID, totalAmount: totalAmount, currency: currency)
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(isOn ? Sage.accent : Sage.textSecondary.opacity(0.4), in: Circle())
                    .scaleEffect(isOn ? 1.0 : 0.92)
                    .animation(.snappy(duration: 0.18), value: isOn)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("split.toggle.\(personID.uuidString)")

            Text(name)
                .font(.formRow.weight(.medium))
                .tracking(-0.07)
                .foregroundStyle(isOn ? Sage.text : Sage.textSecondary)

            Spacer()

            if draft.selectedSplitType == .exact, isOn {
                InlineDecimalTextField(
                    text: Binding(
                        get: { draft.exactSplitAmountText[personID, default: ""] },
                        set: { draft.setExactSplitAmount($0, for: personID, currency: currency) }
                    ),
                    placeholder: MoneyFormatter.amountPlaceholder(currency: currency),
                    isFocused: focused == .split(personID),
                    onFocus: { focused = .split(personID) },
                    accessibilityIdentifier: "split.exactAmount.\(personID.uuidString)"
                )
                .frame(width: 88, height: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Sage.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
            } else if draft.selectedSplitType == .shares, isOn {
                Text(displayShare)
                    .font(.system(size: 13))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                InlineDecimalTextField(
                    text: Binding(
                        get: { draft.shareSplitText[personID, default: ""] },
                        set: { draft.setShareSplitText($0, for: personID) }
                    ),
                    placeholder: "1",
                    isFocused: focused == .split(personID),
                    onFocus: { focused = .split(personID) },
                    accessibilityIdentifier: "split.shareUnits.\(personID.uuidString)"
                )
                .frame(width: 44, height: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Sage.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
            } else if draft.selectedSplitType == .percentage, isOn {
                Text(displayShare)
                    .font(.system(size: 13))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                HStack(spacing: 3) {
                    InlineDecimalTextField(
                        text: Binding(
                            get: { draft.percentSplitText[personID, default: ""] },
                            set: { draft.setPercentSplitText($0, for: personID) }
                        ),
                        placeholder: "0",
                        isFocused: focused == .split(personID),
                        onFocus: { focused = .split(personID) },
                        accessibilityIdentifier: "split.percentage.\(personID.uuidString)"
                    )
                    .frame(width: 48, height: 28)
                    Text("%")
                        .font(.system(size: 12))
                        .foregroundStyle(Sage.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Sage.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
            } else {
                Text(displayShare)
                    .font(.system(size: 13))
                    .tracking(-0.07)
                    .foregroundStyle(isOn ? Sage.textSecondary : Sage.textSecondary.opacity(0.5))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .onTapGesture {
                        guard canTapToEdit else { return }
                        Haptics.light()
                        draft.setSplitMode(
                            1,
                            totalAmount: totalAmount,
                            currency: currency,
                            overwriteExactAmounts: true
                        )
                        focused = .split(personID)
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var splitReconcileFooter: (text: String, isValid: Bool)? {
        guard totalAmount > 0, !draft.selectedParticipants.isEmpty else { return nil }
        switch draft.selectedSplitType {
        case .exact:
            let remaining = totalAmount - draft.enteredSplitTotal
            if computedSplits != nil {
                return ("Exact total \(MoneyFormatter.format(draft.enteredSplitTotal, currency: currency))", true)
            }
            if remaining >= 0 {
                return ("Remaining \(MoneyFormatter.format(remaining, currency: currency))", false)
            }
            return ("Over by \(MoneyFormatter.format(-remaining, currency: currency))", false)
        case .shares:
            if computedSplits != nil {
                return ("\(MoneyFormatter.shareString(draft.enteredShareTotal)) shares total", true)
            }
            return ("Every participant needs a share", false)
        case .percentage:
            if computedSplits != nil {
                return ("Total 100%", true)
            }
            let remaining = Decimal(100) - draft.enteredPercentTotal
            if remaining >= 0 {
                return ("\(MoneyFormatter.shareString(remaining))% left", false)
            }
            return ("Over by \(MoneyFormatter.shareString(-remaining))%", false)
        default:
            return nil
        }
    }

    // MARK: - Commit

    private func commit() {
        guard let payments = computedPayments else { return }
        self.payments = payments
        splitMode = draft.splitMode
        participantSet = draft.selectedParticipants
        exactSplitAmountText = draft.exactSplitAmountText
        shareSplitText = draft.shareSplitText
        percentSplitText = draft.percentSplitText
        Haptics.light()
        dismiss()
    }
}

// MARK: - Type Pill

private struct TypePill: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .tracking(-0.07)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .medium))
                .opacity(0.45)
        }
        .foregroundStyle(Sage.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Sage.surface2, in: Capsule())
        .overlay(Capsule().stroke(Sage.cardBorder, lineWidth: 1))
    }
}

// MARK: - Draft

@Observable
final class PaymentSplitDraft: @unchecked Sendable {
    var payerMode: PaymentMode = .equal
    var selectedPayerIDs: Set<UUID> = []
    var exactPayerAmountText: [UUID: String] = [:]
    private var payerEdited = false

    var splitMode: Int = 0    // 0=equal, 1=exact, 2=shares, 3=percentage
    var selectedParticipants: Set<UUID> = []
    var exactSplitAmountText: [UUID: String] = [:]
    var shareSplitText: [UUID: String] = [:]
    var percentSplitText: [UUID: String] = [:]

    private var hasSeeded = false

    var selectedSplitType: SplitType {
        switch splitMode {
        case 0: .equal
        case 2: .shares
        case 3: .percentage
        default: .exact
        }
    }

    var enteredPayerTotal: Decimal {
        selectedPayerIDs.reduce(Decimal(0)) { $0 + (Self.decimal(from: exactPayerAmountText[$1, default: ""]) ?? 0) }
    }

    var enteredSplitTotal: Decimal {
        selectedParticipants.reduce(Decimal(0)) { $0 + (Self.decimal(from: exactSplitAmountText[$1, default: ""]) ?? 0) }
    }

    var enteredShareTotal: Decimal {
        selectedParticipants.reduce(Decimal(0)) { $0 + (Self.decimal(from: shareSplitText[$1, default: ""]) ?? 0) }
    }

    var enteredPercentTotal: Decimal {
        selectedParticipants.reduce(Decimal(0)) { $0 + (Self.decimal(from: percentSplitText[$1, default: ""]) ?? 0) }
    }

    // MARK: Seed

    func seed(payments: [Payment], splitMode: Int, participantSet: Set<UUID>,
              exactSplitAmountText: [UUID: String], shareSplitText: [UUID: String],
              percentSplitText: [UUID: String],
              currency: String, currentPersonID: UUID?, members: [UUID]) {
        guard !hasSeeded else { return }
        hasSeeded = true

        if payments.isEmpty {
            selectedPayerIDs = Set([currentPersonID ?? members.first].compactMap { $0 })
            payerMode = .equal
        } else {
            selectedPayerIDs = Set(payments.map(\.payerID))
            payerMode = payments.first?.paymentMode ?? .equal
            if payerMode == .exact {
                payerEdited = true
                for p in payments {
                    exactPayerAmountText[p.payerID] = Self.plainAmountString(p.amountPaid, currency: currency)
                }
            }
        }

        self.splitMode = splitMode
        self.selectedParticipants = participantSet
        self.exactSplitAmountText = exactSplitAmountText.mapValues { Self.sanitize($0, currency: currency) }
        self.shareSplitText = shareSplitText.mapValues { MoneyFormatter.sanitizeShareInput($0) }
        self.percentSplitText = percentSplitText.mapValues { MoneyFormatter.sanitizeShareInput($0) }
        if selectedSplitType == .shares {
            seedMissingShares()
        } else if selectedSplitType == .percentage {
            seedMissingPercentages()
        }
    }

    // MARK: Payer methods

    func setPayerMode(_ mode: PaymentMode, totalAmount: Decimal, currency: String) {
        payerMode = mode
        if mode == .exact {
            payerEdited = false
            seedPayerExact(totalAmount: totalAmount, currency: currency, overwrite: true)
        }
    }

    func togglePayer(_ uid: UUID, totalAmount: Decimal, currency: String) {
        if selectedPayerIDs.contains(uid) {
            guard selectedPayerIDs.count > 1 else { return }
            selectedPayerIDs.remove(uid)
            exactPayerAmountText.removeValue(forKey: uid)
            if payerMode == .exact {
                // Down to one payer, the exact-amount field/footer/mode pill are
                // all hidden, so the user can't fix a stale total — reseed the
                // lone payer to the full amount even if they had edited values.
                let overwrite = !payerEdited || selectedPayerIDs.count == 1
                seedPayerExact(totalAmount: totalAmount, currency: currency, overwrite: overwrite)
            }
        } else {
            selectedPayerIDs.insert(uid)
            if payerMode == .exact {
                seedPayerExact(totalAmount: totalAmount, currency: currency, overwrite: !payerEdited)
            }
        }
    }

    func setExactPayerAmount(_ input: String, for uid: UUID, currency: String) {
        payerEdited = true
        exactPayerAmountText[uid] = Self.sanitize(input, currency: currency)
    }

    func computedPayments(totalAmount: Decimal, currency: String) -> [Payment]? {
        guard !selectedPayerIDs.isEmpty, totalAmount > 0 else { return nil }
        let payers = Array(selectedPayerIDs)
        switch payerMode {
        case .equal:
            return try? PaymentCalculator.calculate(totalAmount: totalAmount, currency: currency, payers: payers, paymentMode: .equal)
        case .exact:
            var amounts: [UUID: Decimal] = [:]
            for id in selectedPayerIDs {
                let raw = exactPayerAmountText[id, default: ""].trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, let amt = Self.decimal(from: raw) else { return nil }
                amounts[id] = amt
            }
            return try? PaymentCalculator.calculate(totalAmount: totalAmount, currency: currency, payers: payers, paymentMode: .exact, exactAmounts: amounts)
        default:
            return nil
        }
    }

    // MARK: Split methods

    func setSplitMode(
        _ newMode: Int,
        totalAmount: Decimal,
        currency: String,
        overwriteExactAmounts: Bool = false
    ) {
        splitMode = newMode
        if newMode == 1 {
            seedSplitExact(
                totalAmount: totalAmount,
                currency: currency,
                overwrite: overwriteExactAmounts
            )
        } else if newMode == 2 {
            seedMissingShares()
        } else if newMode == 3 {
            seedMissingPercentages()
        }
    }

    func toggleParticipant(_ uid: UUID, totalAmount: Decimal, currency: String) {
        if selectedParticipants.contains(uid) {
            guard selectedParticipants.count > 1 else { return }
            selectedParticipants.remove(uid)
        } else {
            selectedParticipants.insert(uid)
        }
        if selectedSplitType == .exact {
            seedSplitExact(totalAmount: totalAmount, currency: currency)
        } else if selectedSplitType == .shares {
            seedMissingShares()
        } else if selectedSplitType == .percentage {
            seedMissingPercentages()
        }
    }

    func setExactSplitAmount(_ input: String, for uid: UUID, currency: String) {
        exactSplitAmountText[uid] = Self.sanitize(input, currency: currency)
    }

    func setShareSplitText(_ input: String, for uid: UUID) {
        shareSplitText[uid] = MoneyFormatter.sanitizeShareInput(input)
    }

    func setPercentSplitText(_ input: String, for uid: UUID) {
        percentSplitText[uid] = MoneyFormatter.sanitizeShareInput(input)
    }

    func computedSplits(totalAmount: Decimal, currency: String) -> [ExpenseSplit]? {
        guard !selectedParticipants.isEmpty, totalAmount > 0 else { return nil }
        let parts = Array(selectedParticipants)
        switch selectedSplitType {
        case .equal:
            return try? SplitCalculator.calculate(totalAmount: totalAmount, currency: currency, participants: parts, splitType: .equal)
        case .exact:
            var amounts: [UUID: Decimal] = [:]
            for id in selectedParticipants {
                let raw = exactSplitAmountText[id, default: ""].trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, let amt = Self.decimal(from: raw) else { return nil }
                amounts[id] = amt
            }
            return try? SplitCalculator.calculate(totalAmount: totalAmount, currency: currency, participants: parts, splitType: .exact, exactAmounts: amounts)
        case .shares:
            var shares: [UUID: Decimal] = [:]
            for id in selectedParticipants {
                let raw = shareSplitText[id, default: ""].trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, let share = Self.decimal(from: raw), share > 0 else { return nil }
                shares[id] = share
            }
            return try? SplitCalculator.calculate(totalAmount: totalAmount, currency: currency, participants: parts, splitType: .shares, shares: shares)
        case .percentage:
            var percentages: [UUID: Decimal] = [:]
            for id in selectedParticipants {
                let raw = percentSplitText[id, default: ""].trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty, let percent = Self.decimal(from: raw), percent > 0 else { return nil }
                percentages[id] = percent
            }
            return try? SplitCalculator.calculate(totalAmount: totalAmount, currency: currency, participants: parts, splitType: .percentage, percentages: percentages)
        default:
            return nil
        }
    }

    // MARK: Private helpers

    private func seedPayerExact(totalAmount: Decimal, currency: String, overwrite: Bool) {
        guard !selectedPayerIDs.isEmpty, totalAmount > 0 else { return }
        guard let computed = try? PaymentCalculator.calculate(
            totalAmount: totalAmount, currency: currency,
            payers: Array(selectedPayerIDs), paymentMode: .equal
        ) else { return }
        exactPayerAmountText = exactPayerAmountText.filter { selectedPayerIDs.contains($0.key) }
        for p in computed {
            let existing = exactPayerAmountText[p.payerID, default: ""].trimmingCharacters(in: .whitespaces)
            if overwrite || existing.isEmpty {
                exactPayerAmountText[p.payerID] = Self.plainAmountString(p.amountPaid, currency: currency)
            }
        }
    }

    private func seedMissingShares() {
        for id in selectedParticipants {
            let existing = shareSplitText[id, default: ""].trimmingCharacters(in: .whitespaces)
            if existing.isEmpty {
                shareSplitText[id] = "1"
            }
        }
    }

    private func seedMissingPercentages() {
        let equal = SplitCalculator.equalPercentages(participants: Array(selectedParticipants))
        for id in selectedParticipants {
            let existing = percentSplitText[id, default: ""].trimmingCharacters(in: .whitespaces)
            if existing.isEmpty, let percent = equal[id] {
                percentSplitText[id] = MoneyFormatter.shareString(percent)
            }
        }
    }

    private func seedSplitExact(totalAmount: Decimal, currency: String, overwrite: Bool = false) {
        guard !selectedParticipants.isEmpty, totalAmount > 0 else { return }
        guard let splits = try? SplitCalculator.calculate(
            totalAmount: totalAmount, currency: currency,
            participants: Array(selectedParticipants), splitType: .equal
        ) else { return }
        for s in splits {
            let existing = exactSplitAmountText[s.participantID, default: ""].trimmingCharacters(in: .whitespaces)
            if overwrite || existing.isEmpty {
                exactSplitAmountText[s.participantID] = Self.plainAmountString(s.amountOwed, currency: currency)
            }
        }
    }

    static func sanitize(_ input: String, currency: String) -> String {
        MoneyFormatter.sanitizeAmountInput(input, currency: currency)
    }

    static func decimal(from input: String) -> Decimal? {
        MoneyFormatter.decimal(from: input)
    }

    static func plainAmountString(_ amount: Decimal, currency: String) -> String {
        MoneyFormatter.plainAmountString(amount, currency: currency)
    }
}
