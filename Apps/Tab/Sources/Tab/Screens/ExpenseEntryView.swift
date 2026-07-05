import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import TabCore

struct ExpenseEntryView: View {
    let tripID: UUID
    let editingExpenseID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query private var trips: [TripEntity]
    @Query private var editingExpenses: [ExpenseEntity]

    @Query(filter: #Predicate<CategoryEntity> { $0.isDefault && $0.deletedAt == nil })
    private var categories: [CategoryEntity]

    private var orderedCategories: [CategoryEntity] {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return DefaultCategories.all.compactMap { byID[$0.id] }
    }

    @State private var amountText: String = ""
    @State private var description: String = ""
    @State private var selectedCategoryID: UUID = DefaultCategories.food.id
    @State private var splitMode: Int = 0    // 0=equal, 1=exact, 2=shares, 3=percentage
    @State private var exactAmountTextByPersonID: [UUID: String] = [:]
    @State private var shareTextByPersonID: [UUID: String] = [:]
    @State private var percentTextByPersonID: [UUID: String] = [:]
    @State private var participantSet: Set<UUID> = []
    @State private var currency: String = CurrencyDefaults.initialCurrency
    @State private var isCurrencyPickerPresented = false
    @State private var expenseDate: Date = .now
    @State private var isDatePickerPresented = false
    @State private var paymentMethodIndex: Int = 1 // 0=cash, 1=card, 2=bank_transfer

    /// Empty = single-payer with the recorder paying the full amount (default).
    /// Non-empty = explicit ledger from PaymentSplitView. Sum must equal totalAmount.
    @State private var paymentEntries: [Payment] = []

    @State private var receiptPickerItem: PhotosPickerItem?
    @State private var receiptThumbnail: UIImage?
    @State private var receiptJPEG: Data?
    @State private var receiptError: String?
    @State private var isPreparingReceipt = false
    @State private var isSaving = false
    @State private var receiptLoadID = UUID()

    @State private var hasPrePopulated = false
    @State private var existingReceiptPath: String?
    @State private var existingReceiptURL: URL?

    @FocusState private var descriptionFocused: Bool
    @FocusState private var splitFieldFocused: UUID?

    private var isEditing: Bool { editingExpenseID != nil }
    private var editingExpense: ExpenseEntity? { editingExpenses.first }

    private enum Layout {
        static let hPad: CGFloat = 18
        static let cardHPad: CGFloat = 18
        static let cardInnerHPad: CGFloat = 16
        static let rowVPad: CGFloat = 14
        static let sectionGap: CGFloat = 22
        static let sectionLabelTop: CGFloat = 8
        static let sectionLabelBottom: CGFloat = 10
    }

    init(tripID: UUID, editingExpenseID: UUID? = nil) {
        self.tripID = tripID
        self.editingExpenseID = editingExpenseID
        _trips = Query(filter: #Predicate<TripEntity> { $0.id == tripID })
        let eid = editingExpenseID ?? UUID()
        _editingExpenses = Query(filter: #Predicate<ExpenseEntity> { $0.id == eid })
    }

    private var trip: TripEntity? { trips.first }

    private var totalAmount: Decimal {
        MoneyFormatter.decimal(from: amountText) ?? 0
    }

    private var selectedSplitType: SplitType {
        switch splitMode {
        case 0: .equal
        case 2: .shares
        case 3: .percentage
        default: .exact
        }
    }

    private static let paymentMethodOrder: [PaymentMethod] = [.cash, .card, .bankTransfer]

    private var selectedPaymentMethod: PaymentMethod {
        Self.paymentMethodOrder[paymentMethodIndex]
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
            && !description.trimmingCharacters(in: .whitespaces).isEmpty
            && !participantSet.isEmpty
            && auth.currentUser != nil
            && computedSplits != nil
            && paymentLedgerValid
            && !isPreparingReceipt
            && !isSaving
    }

    /// Empty ledger = OK (defaults to single-payer at save time).
    /// Non-empty ledger = sum must equal totalAmount.
    private var paymentLedgerValid: Bool {
        if paymentEntries.isEmpty { return true }
        let sum = paymentEntries.reduce(Decimal(0)) { $0 + $1.amountPaid }
        return sum == totalAmount
    }

    private var computedSplits: [ExpenseSplit]? {
        guard totalAmount > 0, !participantSet.isEmpty else { return nil }
        let participants = Array(participantSet)
        switch selectedSplitType {
        case .equal:
            return try? SplitCalculator.calculate(
                totalAmount: totalAmount,
                currency: currency,
                participants: participants,
                splitType: .equal
            )
        case .exact:
            guard let exactAmounts else { return nil }
            return try? SplitCalculator.calculate(
                totalAmount: totalAmount,
                currency: currency,
                participants: participants,
                splitType: .exact,
                exactAmounts: exactAmounts
            )
        case .shares:
            guard let shareAmounts else { return nil }
            return try? SplitCalculator.calculate(
                totalAmount: totalAmount,
                currency: currency,
                participants: participants,
                splitType: .shares,
                shares: shareAmounts
            )
        case .percentage:
            guard let percentAmounts else { return nil }
            return try? SplitCalculator.calculate(
                totalAmount: totalAmount,
                currency: currency,
                participants: participants,
                splitType: .percentage,
                percentages: percentAmounts
            )
        case .adjustment:
            return nil
        }
    }

    private var shareAmounts: [UUID: Decimal]? {
        guard selectedSplitType == .shares else { return nil }
        var shares: [UUID: Decimal] = [:]
        for personID in participantSet {
            let raw = shareTextByPersonID[personID, default: ""].trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, let share = MoneyFormatter.decimal(from: raw), share > 0 else { return nil }
            shares[personID] = share
        }
        return shares
    }

    private var percentAmounts: [UUID: Decimal]? {
        guard selectedSplitType == .percentage else { return nil }
        var percentages: [UUID: Decimal] = [:]
        for personID in participantSet {
            let raw = percentTextByPersonID[personID, default: ""].trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, let percent = MoneyFormatter.decimal(from: raw), percent > 0 else { return nil }
            percentages[personID] = percent
        }
        return percentages
    }

    private var percentEnteredTotal: Decimal {
        participantSet.reduce(Decimal(0)) { total, personID in
            total + (MoneyFormatter.decimal(from: percentTextByPersonID[personID, default: ""]) ?? 0)
        }
    }

    private var exactAmounts: [UUID: Decimal]? {
        guard selectedSplitType == .exact else { return nil }
        var amounts: [UUID: Decimal] = [:]
        for personID in participantSet {
            let raw = exactAmountTextByPersonID[personID, default: ""].trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty, let amount = decimalAmount(from: raw) else { return nil }
            amounts[personID] = amount
        }
        return amounts
    }

    private var exactEnteredTotal: Decimal {
        participantSet.reduce(Decimal(0)) { total, personID in
            total + (decimalAmount(from: exactAmountTextByPersonID[personID, default: ""]) ?? 0)
        }
    }

    private var exactSplitFooter: (text: String, isValid: Bool)? {
        guard selectedSplitType == .exact, totalAmount > 0 else { return nil }
        let remaining = totalAmount - exactEnteredTotal
        if computedSplits != nil {
            return ("Exact total \(MoneyFormatter.format(exactEnteredTotal, currency: currency))", true)
        } else if remaining >= 0 {
            return ("Remaining \(MoneyFormatter.format(remaining, currency: currency))", false)
        } else {
            return ("Over by \(MoneyFormatter.format(-remaining, currency: currency))", false)
        }
    }

    private var sharesFooter: (text: String, isValid: Bool)? {
        guard selectedSplitType == .shares, totalAmount > 0, !participantSet.isEmpty else { return nil }
        guard let shares = shareAmounts else {
            return ("Every participant needs a share", false)
        }
        let total = shares.values.reduce(Decimal(0), +)
        return ("\(MoneyFormatter.shareString(total)) shares total", true)
    }

    private var percentFooter: (text: String, isValid: Bool)? {
        guard selectedSplitType == .percentage, totalAmount > 0, !participantSet.isEmpty else { return nil }
        if computedSplits != nil {
            return ("Total 100%", true)
        }
        let remaining = Decimal(100) - percentEnteredTotal
        if remaining >= 0 {
            return ("\(MoneyFormatter.shareString(remaining))% left", false)
        }
        return ("Over by \(MoneyFormatter.shareString(-remaining))%", false)
    }

    /// People offered in pickers: active members, plus removed people already
    /// on the expense being edited, so an edit never drops them silently.
    private var selectablePeople: [TripPersonEntity] {
        guard let trip else { return [] }
        var referenced: Set<UUID> = []
        if let expense = editingExpense {
            referenced.formUnion(expense.payments.map(\.tripPersonID))
            referenced.formUnion(expense.splits.map(\.tripPersonID))
        }
        return trip.people.filter { $0.removedAt == nil || referenced.contains($0.id) }
    }

    private var participantRows: [ParticipantRow] {
        guard let trip else { return [] }
        let currentPersonID = auth.currentUser.flatMap { user in
            trip.people.first(where: { $0.userID == user.id })?.id
        }
        let splits = computedSplits ?? []
        return selectablePeople.sortedForDisplay(currentPersonID: currentPersonID).map { person in
            let name = person.id == currentPersonID ? "You" : person.displayName
            let isOn = participantSet.contains(person.id)
            let share = splits.first(where: { $0.participantID == person.id })?.amountOwed ?? 0
            let shareText = isOn ? MoneyFormatter.format(share, currency: currency) : "—"
            return ParticipantRow(personID: person.id, name: name, share: shareText, isOn: isOn)
        }
    }

    var body: some View {
        Group {
            if trip == nil {
                Color.clear.onAppear { dismiss() }
            } else if isEditing, editingExpense == nil || editingExpense?.deletedAt != nil {
                Color.clear.onAppear { dismiss() }
            } else {
                form
            }
        }
        .background(Sage.bg.ignoresSafeArea())
        .navigationTitle(isEditing ? "Edit expense" : "New expense")
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
        .onAppear {
            prepopulate()
        }
        .onChange(of: splitMode) { _, newValue in
            if newValue == 1 {
                seedMissingExactAmountsFromEqual()
            } else if newValue == 2 {
                seedMissingShares()
            } else if newValue == 3 {
                seedMissingPercentages()
            }
        }
        .onChange(of: participantSet) {
            if selectedSplitType == .exact {
                seedMissingExactAmountsFromEqual()
            } else if selectedSplitType == .shares {
                seedMissingShares()
            } else if selectedSplitType == .percentage {
                seedMissingPercentages()
            }
        }
        .onChange(of: currency) {
            normalizeAmountTextForCurrency()
        }
        .onChange(of: receiptPickerItem) { _, newItem in
            guard let newItem else { return }
            loadReceipt(from: newItem)
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 0) {
                amountBlock
                hairline
                descriptionRow

                categoryChips
                    .padding(.top, Layout.sectionGap)

                Card(horizontalPadding: Layout.cardHPad) {
                    paymentSplitRow
                    RowDivider()
                    dateRow
                    RowDivider()
                    paymentMethodRow
                }
                .padding(.top, Layout.sectionGap)

                sectionLabel("Split between")
                participantsCard

                receiptSection

                Spacer(minLength: 24)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture { descriptionFocused = false }
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
                accessibilityIdentifier: "expense.amountField"
            )
            .frame(height: 62)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: amountText) { _, new in
                let sanitized = sanitizeAmount(new)
                if sanitized != new {
                    amountText = sanitized
                } else {
                    refreshEqualPaymentsForCurrentTotal()
                }
            }

            CurrencyPill(code: currency, symbol: MoneyFormatter.currencySymbol(currency)) {
                isCurrencyPickerPresented = true
            }
            .sheet(isPresented: $isCurrencyPickerPresented) {
                CurrencyPickerSheet(selection: currencySelection)
            }
        }
        .padding(.horizontal, Layout.hPad)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private func prepopulate() {
        if !hasPrePopulated {
            hasPrePopulated = true

            if let expense = editingExpense {
                currency = expense.currency
                amountText = plainAmountString(expense.amount)
                description = expense.descriptionText
                selectedCategoryID = expense.categoryID ?? DefaultCategories.food.id
                expenseDate = expense.expenseDate

                let splitType = expense.splits.first?.splitType ?? .equal
                switch splitType {
                case .equal: splitMode = 0
                case .shares: splitMode = 2
                case .percentage: splitMode = 3
                default: splitMode = 1
                }
                participantSet = Set(expense.splits.map(\.tripPersonID))

                if splitType == .exact {
                    for split in expense.splits {
                        exactAmountTextByPersonID[split.tripPersonID] = plainAmountString(split.amountOwed)
                    }
                } else if splitType == .shares {
                    for split in expense.splits {
                        shareTextByPersonID[split.tripPersonID] = split.shareUnits.map { MoneyFormatter.shareString($0) } ?? "1"
                    }
                } else if splitType == .percentage {
                    for split in expense.splits {
                        percentTextByPersonID[split.tripPersonID] = split.percentage.map { MoneyFormatter.shareString($0) } ?? ""
                    }
                }

                paymentMethodIndex = Self.paymentMethodOrder.firstIndex(of: expense.paymentMethod) ?? 1
                paymentEntries = expense.payments.map { $0.toCorePayment() }
                existingReceiptPath = expense.receiptStoragePath
            } else {
                currency = CurrencyDefaults.defaultCurrency(for: trip)
            }
        }

        if participantSet.isEmpty, let trip {
            participantSet = Set(trip.activePeople.map(\.id))
        }
        if selectedSplitType == .exact {
            seedMissingExactAmountsFromEqual()
        } else if selectedSplitType == .shares {
            seedMissingShares()
        } else if selectedSplitType == .percentage {
            seedMissingPercentages()
        }
    }

    private func sanitizeAmount(_ input: String) -> String {
        MoneyFormatter.sanitizeAmountInput(input, currency: currency)
    }

    private func decimalAmount(from input: String) -> Decimal? {
        MoneyFormatter.decimal(from: input)
    }

    private func plainAmountString(_ amount: Decimal) -> String {
        MoneyFormatter.plainAmountString(amount, currency: currency)
    }

    private func normalizeAmountTextForCurrency() {
        // Preserve the entered value at the new currency's precision rather than
        // re-sanitizing digits (which would turn "123.45" into "12345" for JPY).
        amountText = MoneyFormatter.convertAmountText(amountText, to: currency)
        exactAmountTextByPersonID = exactAmountTextByPersonID.mapValues {
            MoneyFormatter.convertAmountText($0, to: currency)
        }
        refreshEqualPaymentsForCurrentTotal()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .tracking(1.32)
            .foregroundStyle(Sage.textSecondary)
            .padding(.horizontal, Layout.hPad)
            .padding(.top, Layout.sectionLabelTop)
            .padding(.bottom, Layout.sectionLabelBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var descriptionRow: some View {
        TextField("Description", text: $description)
            .focused($descriptionFocused)
            .accessibilityIdentifier("expense.descriptionField")
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .onSubmit { descriptionFocused = false }
            .font(.formRow)
            .tracking(-0.07)
            .foregroundStyle(Sage.text)
            .padding(.horizontal, Layout.hPad)
            .padding(.vertical, Layout.rowVPad)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(orderedCategories) { category in
                    let isActive = category.id == selectedCategoryID
                    CategoryChip(
                        category: category.asOption,
                        isActive: isActive,
                        emojiOnly: !isActive
                    ) {
                        Haptics.light()
                        withAnimation(.snappy(duration: 0.22)) {
                            selectedCategoryID = category.id
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.hPad)
            .padding(.bottom, 4)
        }
    }

    private var paymentSplitRow: some View {
        NavigationLink {
            PaymentSplitView(
                tripID: tripID,
                totalAmount: totalAmount,
                currency: currency,
                payments: $paymentEntries,
                splitMode: $splitMode,
                participantSet: $participantSet,
                exactSplitAmountText: $exactAmountTextByPersonID,
                shareSplitText: $shareTextByPersonID,
                percentSplitText: $percentTextByPersonID
            )
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {
                        Text(paidByShortLabel)
                            .font(.formRow.weight(.semibold))
                            .tracking(-0.07)
                            .foregroundStyle(paymentLedgerValid ? Sage.accentStrong : Sage.warning)
                            .accessibilityIdentifier("expense.paidBySummary")
                        Text(" \u{00B7} ")
                            .font(.system(size: 13))
                            .foregroundStyle(Sage.textSecondary)
                        Text(splitTypeLabel)
                            .font(.formRow.weight(.medium))
                            .tracking(-0.07)
                            .foregroundStyle(Sage.text)
                    }
                    Text(splitSummarySubtitle)
                        .font(.system(size: 12.5))
                        .tracking(-0.07)
                        .foregroundStyle(Sage.textSecondary)
                }
                Spacer()
                Chevron(size: 9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Layout.rowVPad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("expense.paidByRow")
        .disabled(totalAmount <= 0)
        .opacity(totalAmount > 0 ? 1 : 0.5)
    }

    private var paidByShortLabel: String {
        if paymentEntries.isEmpty { return "You" }
        if paymentEntries.count == 1, let only = paymentEntries.first {
            let currentPersonID = auth.currentUser.flatMap { user in
                trip?.people.first(where: { $0.userID == user.id })?.id
            }
            return only.payerID == currentPersonID
                ? "You"
                : (trip?.people.first(where: { $0.id == only.payerID })?.displayName ?? "Member")
        }
        return "\(paymentEntries.count) people"
    }

    private var splitTypeLabel: String {
        switch splitMode {
        case 0: "Equal split"
        case 2: "Split by shares"
        case 3: "Split by percentages"
        default: "Exact split"
        }
    }

    private var splitSummarySubtitle: String {
        let count = participantSet.count
        let payer = paidByShortLabel
        if !paymentLedgerValid {
            return "\(payer) paid \u{00B7} doesn't reconcile"
        }
        return "Split between \(count) \(count == 1 ? "person" : "people")"
    }

    private var dateRow: some View {
        Button {
            descriptionFocused = false
            isDatePickerPresented = true
        } label: {
            HStack(spacing: 12) {
                Text("Date")
                    .font(.formRowLabel)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                Spacer()
                Text(Self.expenseDateFormatter.string(from: expenseDate))
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
        .padding(.vertical, Layout.rowVPad)
        .contentShape(Rectangle())
        .popover(isPresented: $isDatePickerPresented) {
            InlineDatePicker(selection: $expenseDate, tintColor: UIColor(Sage.accent)) {
                isDatePickerPresented = false
            }
            .frame(width: 320, height: 324)
            .padding(12)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var paymentMethodRow: some View {
        HStack(spacing: 12) {
            Text("Paid via")
                .font(.formRowLabel)
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            Menu {
                ForEach(Array(Self.paymentMethodOrder.enumerated()), id: \.element) { index, method in
                    Button(method.displayName) {
                        paymentMethodIndex = index
                    }
                }
            } label: {
                DropdownPill(title: selectedPaymentMethod.displayName)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("expense.paymentMethodMenu")
            .accessibilityLabel(selectedPaymentMethod.displayName)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Layout.rowVPad)
    }

    private var participantsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(participantRows.enumerated()), id: \.element.personID) { index, row in
                participantRow(row)
                if index < participantRows.count - 1 { RowDivider() }
            }

            if let footer = exactSplitFooter ?? sharesFooter ?? percentFooter {
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
        .padding(.bottom, 14)
        .animation(.snappy(duration: 0.2), value: selectedSplitType)
    }

    private var receiptSection: some View {
        VStack(spacing: 6) {
            if let thumb = receiptThumbnail {
                receiptThumbnailCard(thumb)
            } else if let existingPath = existingReceiptPath {
                existingReceiptCard(path: existingPath)
            } else {
                receiptPlaceholder
            }
            if let receiptError {
                Text(receiptError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Sage.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Layout.cardHPad)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .animation(.snappy(duration: 0.2), value: receiptThumbnail != nil)
        .animation(.snappy(duration: 0.2), value: existingReceiptPath)
    }

    private func existingReceiptCard(path: String) -> some View {
        HStack(spacing: 12) {
            if let url = existingReceiptURL {
                DownsampledAsyncImage(url: url, maxPointSize: 120) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ProgressView().controlSize(.small).tint(Sage.accent)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Sage.surface2)
                    .frame(width: 56, height: 56)
                    .overlay(ProgressView().controlSize(.small).tint(Sage.accent))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt attached")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
            }

            Spacer(minLength: 8)

            PhotosPicker(selection: $receiptPickerItem, matching: .images, photoLibrary: .shared()) {
                Text("Replace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Sage.accent)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.light()
                existingReceiptPath = nil
                existingReceiptURL = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Sage.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Sage.surface2, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .task(id: path) {
            do {
                existingReceiptURL = try await ReceiptStorage.signedURL(path: path)
            } catch {
                existingReceiptURL = nil
            }
        }
    }

    private var receiptPlaceholder: some View {
        let preparing = isPreparingReceipt
        return PhotosPicker(selection: $receiptPickerItem, matching: .images, photoLibrary: .shared()) {
            HStack(spacing: 6) {
                if preparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Sage.accent)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(preparing ? "Preparing…" : "Add photo")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.07)
            }
            .foregroundStyle(Sage.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Sage.accentSoft, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
        .disabled(preparing)
    }

    private func receiptThumbnailCard(_ image: UIImage) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt attached")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                if let bytes = receiptJPEG?.count {
                    Text(byteString(bytes))
                        .font(.system(size: 12))
                        .foregroundStyle(Sage.textSecondary)
                }
            }

            Spacer(minLength: 8)

            PhotosPicker(selection: $receiptPickerItem, matching: .images, photoLibrary: .shared()) {
                Text("Replace")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Sage.accent)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.light()
                clearReceipt()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Sage.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Sage.surface2, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
    }

    private func byteString(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    private func loadReceipt(from item: PhotosPickerItem) {
        let loadID = UUID()
        receiptLoadID = loadID
        isPreparingReceipt = true
        receiptError = nil
        Task {
            defer {
                Task { @MainActor in
                    guard receiptLoadID == loadID else { return }
                    isPreparingReceipt = false
                }
            }
            guard let raw = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    guard receiptLoadID == loadID else { return }
                    receiptPickerItem = nil
                    receiptError = "Couldn't read photo."
                }
                return
            }
            do {
                let jpeg = try await Task.detached(priority: .userInitiated) {
                    try ReceiptStorage.prepareJPEG(from: raw)
                }.value
                let preview = UIImage(data: jpeg)
                await MainActor.run {
                    guard receiptLoadID == loadID else { return }
                    receiptJPEG = jpeg
                    receiptThumbnail = preview
                    existingReceiptPath = nil
                    existingReceiptURL = nil
                }
            } catch {
                await MainActor.run {
                    guard receiptLoadID == loadID else { return }
                    receiptPickerItem = nil
                    receiptError = (error as? LocalizedError)?.errorDescription ?? "Couldn't process image."
                    receiptJPEG = nil
                    receiptThumbnail = nil
                }
            }
        }
    }

    private func clearReceipt() {
        receiptLoadID = UUID()
        receiptPickerItem = nil
        receiptThumbnail = nil
        receiptJPEG = nil
        receiptError = nil
        isPreparingReceipt = false
        existingReceiptPath = nil
        existingReceiptURL = nil
    }

    private func participantRow(_ row: ParticipantRow) -> some View {
        let canTapToEdit = row.isOn && selectedSplitType == .equal

        return HStack(spacing: 12) {
            Button {
                Haptics.light()
                withAnimation(.snappy(duration: 0.18)) {
                    toggleParticipant(row.personID)
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        row.isOn ? Sage.accent : Sage.textSecondary.opacity(0.4),
                        in: Circle()
                    )
                    .scaleEffect(row.isOn ? 1.0 : 0.92)
                    .animation(.snappy(duration: 0.18), value: row.isOn)
            }
            .buttonStyle(.plain)

            Text(row.name)
                .font(.formRow.weight(.medium))
                .tracking(-0.07)
                .foregroundStyle(Sage.text)

            Spacer()

            if selectedSplitType == .exact, row.isOn {
                InlineDecimalTextField(
                    text: Binding(
                        get: { exactAmountTextByPersonID[row.personID, default: ""] },
                        set: { exactAmountTextByPersonID[row.personID] = sanitizeAmount($0) }
                    ),
                    placeholder: MoneyFormatter.amountPlaceholder(currency: currency),
                    isFocused: splitFieldFocused == row.personID,
                    onFocus: { splitFieldFocused = row.personID },
                    accessibilityIdentifier: "expense.splitAmount.\(row.personID.uuidString)"
                )
                .frame(width: 88, height: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Sage.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
            } else if selectedSplitType == .shares, row.isOn {
                Text(row.share)
                    .font(.system(size: 13))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                InlineDecimalTextField(
                    text: Binding(
                        get: { shareTextByPersonID[row.personID, default: ""] },
                        set: { shareTextByPersonID[row.personID] = MoneyFormatter.sanitizeShareInput($0) }
                    ),
                    placeholder: "1",
                    isFocused: splitFieldFocused == row.personID,
                    onFocus: { splitFieldFocused = row.personID },
                    accessibilityIdentifier: "expense.shareUnits.\(row.personID.uuidString)"
                )
                .frame(width: 44, height: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Sage.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Sage.cardBorder, lineWidth: 1)
                )
            } else if selectedSplitType == .percentage, row.isOn {
                Text(row.share)
                    .font(.system(size: 13))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                HStack(spacing: 3) {
                    InlineDecimalTextField(
                        text: Binding(
                            get: { percentTextByPersonID[row.personID, default: ""] },
                            set: { percentTextByPersonID[row.personID] = MoneyFormatter.sanitizeShareInput($0) }
                        ),
                        placeholder: "0",
                        isFocused: splitFieldFocused == row.personID,
                        onFocus: { splitFieldFocused = row.personID },
                        accessibilityIdentifier: "expense.percentage.\(row.personID.uuidString)"
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
                Text(row.share)
                    .font(.system(size: 13))
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .onTapGesture {
                        guard canTapToEdit else { return }
                        Haptics.light()
                        descriptionFocused = false
                        splitMode = 1
                        seedMissingExactAmountsFromEqual(overwrite: true)
                        splitFieldFocused = row.personID
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func toggleParticipant(_ personID: UUID) {
        if participantSet.contains(personID) {
            if participantSet.count > 1 {
                participantSet.remove(personID)
            }
        } else {
            participantSet.insert(personID)
        }
    }

    private func seedMissingExactAmountsFromEqual(overwrite: Bool = false) {
        guard totalAmount > 0, !participantSet.isEmpty else { return }
        guard let splits = try? SplitCalculator.calculate(
            totalAmount: totalAmount,
            currency: currency,
            participants: Array(participantSet),
            splitType: .equal
        ) else { return }

        for split in splits {
            let current = exactAmountTextByPersonID[split.participantID, default: ""]
            if overwrite || current.trimmingCharacters(in: .whitespaces).isEmpty {
                exactAmountTextByPersonID[split.participantID] = plainAmountString(split.amountOwed)
            }
        }
    }

    private func seedMissingShares() {
        for personID in participantSet {
            let current = shareTextByPersonID[personID, default: ""].trimmingCharacters(in: .whitespaces)
            if current.isEmpty {
                shareTextByPersonID[personID] = "1"
            }
        }
    }

    private func seedMissingPercentages() {
        let equal = SplitCalculator.equalPercentages(participants: Array(participantSet))
        for personID in participantSet {
            let current = percentTextByPersonID[personID, default: ""].trimmingCharacters(in: .whitespaces)
            if current.isEmpty, let percent = equal[personID] {
                percentTextByPersonID[personID] = MoneyFormatter.shareString(percent)
            }
        }
    }

    private func refreshEqualPaymentsForCurrentTotal() {
        guard totalAmount > 0, !paymentEntries.isEmpty else { return }
        guard paymentEntries.allSatisfy({ $0.paymentMode == .equal }) else { return }

        let payerIDs = paymentEntries.map(\.payerID)
        guard let recalculated = try? PaymentCalculator.calculate(
            totalAmount: totalAmount,
            currency: currency,
            payers: payerIDs,
            paymentMode: .equal
        ) else { return }
        paymentEntries = recalculated
    }

    private func save() {
        // canSave includes !isSaving, so this also rejects a second tap landing
        // during the dismiss transition (each saveNew mints a new UUID).
        guard canSave else { return }
        isSaving = true
        if isEditing {
            guard let expense = editingExpense, expense.deletedAt == nil else {
                isSaving = false
                return
            }
            saveEdit(expense)
        } else {
            saveNew()
        }
    }

    private func saveNew() {
        guard let trip, let user = auth.currentUser,
              let currentPersonID = trip.people.first(where: { $0.userID == user.id })?.id,
              let splits = computedSplits else {
            isSaving = false
            return
        }

        let expenseID = UUID()
        let tripID = trip.id
        let receiptPath: String?
        if let receiptJPEG {
            do {
                receiptPath = try ReceiptStorage.persistPendingUpload(
                    jpeg: receiptJPEG,
                    tripID: tripID,
                    expenseID: expenseID
                )
            } catch {
                receiptError = (error as? LocalizedError)?.errorDescription ?? "Couldn't prepare receipt."
                isSaving = false
                return
            }
        } else {
            receiptPath = nil
        }

        let expense = ExpenseEntity(
            id: expenseID,
            amount: totalAmount,
            currency: currency,
            categoryID: selectedCategoryID,
            descriptionText: description.trimmingCharacters(in: .whitespaces),
            expenseDate: ExpenseDates.utcNoonAnchor(forLocalDay: expenseDate),
            receiptStoragePath: receiptPath,
            paymentMethodRaw: selectedPaymentMethod.rawValue,
            createdByID: user.id,
            trip: trip
        )
        context.insert(expense)

        let payments = paymentEntries.isEmpty
            ? [Payment(payerID: currentPersonID, amountPaid: totalAmount, paymentMode: .equal)]
            : paymentEntries
        for payment in payments {
            let entity = PaymentEntity(
                tripPersonID: payment.payerID,
                amountPaid: payment.amountPaid,
                paymentModeRaw: payment.paymentMode.rawValue,
                expense: expense
            )
            context.insert(entity)
        }

        for split in splits {
            let entity = ExpenseSplitEntity(
                tripPersonID: split.participantID,
                amountOwed: split.amountOwed,
                splitTypeRaw: split.splitType.rawValue,
                shareUnits: split.shareUnits,
                percentage: split.percentage,
                expense: expense
            )
            context.insert(entity)
        }
        trip.lastActivityAt = .now

        try? context.save()
        CurrencyDefaults.remember(currency)
        Haptics.success()

        dismiss()

        Task {
            await sync.pushPending()
        }
    }

    private func saveEdit(_ expense: ExpenseEntity) {
        guard let trip, let user = auth.currentUser,
              let currentPersonID = trip.people.first(where: { $0.userID == user.id })?.id,
              let splits = computedSplits else {
            isSaving = false
            return
        }

        let receiptPath: String?
        if let receiptJPEG {
            do {
                receiptPath = try ReceiptStorage.persistPendingUpload(
                    jpeg: receiptJPEG,
                    tripID: trip.id,
                    expenseID: expense.id
                )
            } catch {
                receiptError = (error as? LocalizedError)?.errorDescription ?? "Couldn't prepare receipt."
                isSaving = false
                return
            }
        } else {
            receiptPath = existingReceiptPath
        }

        expense.amount = totalAmount
        expense.currency = currency
        expense.categoryID = selectedCategoryID
        expense.descriptionText = description.trimmingCharacters(in: .whitespaces)
        expense.expenseDate = ExpenseDates.utcNoonAnchor(forLocalDay: expenseDate)
        expense.receiptStoragePath = receiptPath
        expense.paymentMethodRaw = selectedPaymentMethod.rawValue
        expense.lastEditedByID = user.id
        expense.updatedAt = .now
        expense.writeID = UUID()

        for payment in expense.payments { context.delete(payment) }
        let payments = paymentEntries.isEmpty
            ? [Payment(payerID: currentPersonID, amountPaid: totalAmount, paymentMode: .equal)]
            : paymentEntries
        for payment in payments {
            context.insert(PaymentEntity(
                tripPersonID: payment.payerID,
                amountPaid: payment.amountPaid,
                paymentModeRaw: payment.paymentMode.rawValue,
                expense: expense
            ))
        }

        for split in expense.splits { context.delete(split) }
        for split in splits {
            context.insert(ExpenseSplitEntity(
                tripPersonID: split.participantID,
                amountOwed: split.amountOwed,
                splitTypeRaw: split.splitType.rawValue,
                shareUnits: split.shareUnits,
                percentage: split.percentage,
                expense: expense
            ))
        }

        trip.lastActivityAt = .now

        try? context.save()
        CurrencyDefaults.remember(currency)
        Haptics.success()

        dismiss()

        Task {
            await sync.pushPending()
        }
    }

    private static let expenseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct InlineDatePicker: UIViewRepresentable {
    @Binding var selection: Date
    let tintColor: UIColor
    let onSelection: () -> Void

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.tintColor = tintColor
        picker.setDate(selection, animated: false)
        picker.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        uiView.tintColor = tintColor
        if !Calendar.current.isDate(uiView.date, inSameDayAs: selection) {
            uiView.setDate(selection, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: InlineDatePicker

        init(parent: InlineDatePicker) {
            self.parent = parent
        }

        @MainActor
        @objc func valueChanged(_ picker: UIDatePicker) {
            let previousDate = parent.selection
            parent.selection = picker.date
            guard !Calendar.current.isDate(picker.date, inSameDayAs: previousDate) else { return }
            parent.onSelection()
        }
    }
}

private struct ParticipantRow: Hashable {
    let personID: UUID
    let name: String
    let share: String
    let isOn: Bool
}

struct InlineDecimalTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "0.00"
    let isFocused: Bool
    let onFocus: () -> Void
    let accessibilityIdentifier: String

    func makeUIView(context: Context) -> UITextField {
        let tf = SelectAllInlineTextField()
        tf.accessibilityIdentifier = accessibilityIdentifier
        tf.keyboardType = .decimalPad
        tf.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        tf.textColor = UIColor(Sage.text)
        tf.textAlignment = .right
        tf.tintColor = UIColor(Sage.accent)
        tf.placeholder = placeholder
        tf.delegate = context.coordinator
        tf.selectAllOnTouch = { [weak tf] in
            guard let tf else { return }
            context.coordinator.selectAll(in: tf)
        }
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.accessibilityIdentifier = accessibilityIdentifier
        uiView.placeholder = placeholder
        if uiView.text != text {
            uiView.text = text
        }

        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
                context.coordinator.selectAll(in: uiView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: InlineDecimalTextField

        init(parent: InlineDecimalTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocus()
            selectAll(in: textField)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func selectAll(in textField: UITextField) {
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }
    }
}

private final class SelectAllInlineTextField: UITextField {
    var selectAllOnTouch: (() -> Void)?

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        selectAllOnTouch?()
    }
}

struct DecimalTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: UIFont
    var textColor: UIColor
    var placeholderColor: UIColor
    var alignment: NSTextAlignment = .left
    var tintColor: UIColor
    var becomeFirstResponderOnAppear: Bool = false
    var accessibilityIdentifier: String? = nil

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.accessibilityIdentifier = accessibilityIdentifier
        tf.keyboardType = .decimalPad
        tf.font = font
        tf.textColor = textColor
        tf.textAlignment = alignment
        tf.tintColor = tintColor
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor, .font: font]
        )
        tf.delegate = context.coordinator
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )

        if becomeFirstResponderOnAppear {
            DispatchQueue.main.async {
                tf.becomeFirstResponder()
            }
        }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.accessibilityIdentifier = accessibilityIdentifier
        if uiView.text != text {
            uiView.text = text
        }
        uiView.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor, .font: font]
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DecimalTextField

        init(parent: DecimalTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ tf: UITextField) {
            parent.text = tf.text ?? ""
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
    }
}
