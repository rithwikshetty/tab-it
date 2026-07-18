import SwiftUI
import SwiftData
import TabCore

struct ExpenseDetailView: View {
    let expenseID: UUID
    let onEditExpense: (UUID, UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync

    @Query private var expenses: [ExpenseEntity]
    @Query private var categories: [CategoryEntity]

    @State private var confirmDelete = false
    @State private var receiptURL: URL?
    @State private var loadedReceiptForPath: String?
    @State private var receiptLoadFailed = false
    @State private var receiptPreviewPresented = false

    init(expenseID: UUID, onEditExpense: @escaping (UUID, UUID) -> Void = { _, _ in }) {
        self.expenseID = expenseID
        self.onEditExpense = onEditExpense
        _expenses = Query(filter: #Predicate<ExpenseEntity> { $0.id == expenseID })
    }

    private var expense: ExpenseEntity? { expenses.first }

    private var categoriesByID: [UUID: CategoryEntity] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    var body: some View {
        Group {
            if let expense, expense.deletedAt == nil {
                content(for: expense)
            } else {
                MissingExpenseView { dismiss() }
            }
        }
        .background(Sage.bg.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if let expense, let tripID = expense.trip?.id {
                            onEditExpense(tripID, expense.id)
                        }
                    } label: {
                        Label("Edit expense", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("expenseDetail.editButton")
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete expense", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Sage.accent)
                        .frame(width: 32, height: 32)
                }
                .accessibilityIdentifier("expenseDetail.actionsButton")
            }
        }
        .toolbarBackground(Sage.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Delete this expense?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It will be removed from balances.")
        }
    }

    @ViewBuilder
    private func content(for expense: ExpenseEntity) -> some View {
        let userID = auth.currentUser?.id
        let currentPersonID = userID.flatMap { id in
            expense.trip?.people.first(where: { $0.userID == id })?.id
        }
        let category = expense.categoryID.flatMap { categoriesByID[$0] }
        let categoryName = category?.name ?? "Other"
        let categoryTone = expense.categoryID.map { DefaultCategories.tone(for: $0) } ?? Sage.text
        let categoryIcon = category?.icon ?? "tag"

        let paymentRows = buildPaymentRows(expense: expense, currentPersonID: currentPersonID)
        let splitRows = buildSplitRows(expense: expense, currentPersonID: currentPersonID)
        let splitType = expense.splits.first?.splitType ?? .equal
        let participantCount = expense.splits.count

        let loggedByIsYou = userID.map { $0 == expense.createdByID } ?? false
        let loggedByName = loggedByIsYou
            ? "You"
            : (expense.trip?.people.first(where: { $0.userID == expense.createdByID })?.displayName ?? "Member")

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock(
                    categoryName: categoryName,
                    categoryTone: categoryTone,
                    categoryIcon: categoryIcon,
                    description: expense.descriptionText
                )

                amountBlock(
                    amount: expense.amount,
                    currency: expense.currency,
                    date: expense.expenseDate
                )

                sectionLabel("Paid by")
                paidByCard(rows: paymentRows, currency: expense.currency)

                sectionLabel("Split")
                splitCard(rows: splitRows, splitType: splitType, count: participantCount, currency: expense.currency)

                sectionLabel("Details")
                detailsCard(
                    expense: expense,
                    loggedByName: loggedByName,
                    editedByName: editedByName(for: expense, userID: userID)
                )

                if expense.receiptStoragePath != nil {
                    sectionLabel("Receipt")
                    receiptCard(path: expense.receiptStoragePath!)
                }

                Spacer(minLength: 28)
            }
        }
        .scrollIndicators(.hidden)
        .task(id: expense.receiptStoragePath) { await refreshReceiptURL(for: expense.receiptStoragePath) }
        .sheet(isPresented: $receiptPreviewPresented) {
            receiptFullScreen
        }
    }

    private func headerBlock(
        categoryName: String,
        categoryTone: Color,
        categoryIcon: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                phosphorIcon(named: categoryIcon)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(categoryTone)
                    .frame(width: 18, height: 18)
                Text(categoryName.uppercased())
                    .font(.sectionLabel)
                    .tracking(1.32)
                    .foregroundStyle(categoryTone)
            }

            Text(description)
                .font(.largeTitle30)
                .tracking(-0.75)
                .foregroundStyle(Sage.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func amountBlock(amount: Decimal, currency: String, date: Date) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TOTAL")
                    .font(.balanceLabel)
                    .tracking(1.10)
                    .foregroundStyle(Sage.accentStrong.opacity(0.85))
                Text(MoneyFormatter.format(amount, currency: currency))
                    .font(.balanceAmount)
                    .tracking(-0.85)
                    .foregroundStyle(Sage.accentStrong)
                    .monospacedDigit()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text(ExpenseDates.displayString(date, dateFormat: "d"))
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(Sage.text.opacity(0.85))
                Text(ExpenseDates.displayString(date, dateFormat: "MMM yyyy").lowercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.88)
                    .foregroundStyle(Sage.textSecondary)
            }
            .padding(.top, 16)
            .padding(.trailing, 18)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Sage.accentGlow, .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)
                .offset(x: 40, y: -40)
                .allowsHitTesting(false)
        }
        .background(Sage.accentTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Sage.accentSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func paidByCard(rows: [PaymentRowItem], currency: String) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    Avatar(initial: row.member.initial, tone: row.member.tone, size: 26, borderWidth: 2)
                    Text(row.member.displayName)
                        .font(.system(size: 14, weight: row.isYou ? .semibold : .medium))
                        .tracking(-0.07)
                        .foregroundStyle(Sage.text)
                    Spacer()
                    Text(MoneyFormatter.format(row.amount, currency: currency))
                        .font(.system(size: 14, weight: row.isYou ? .semibold : .regular))
                        .tracking(-0.07)
                        .foregroundStyle(row.isYou ? Sage.accentStrong : Sage.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                if index < rows.count - 1 { RowDivider() }
            }
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func splitCard(
        rows: [SplitRowItem],
        splitType: SplitType,
        count: Int,
        currency: String
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                splitRow(row, currency: currency)
                if index < rows.count - 1 { RowDivider() }
            }
            RowDivider()
            HStack {
                Spacer()
                Text("\(splitTypeLabel(splitType)) · \(count) ways")
                    .font(.system(size: 11.5, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Sage.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Sage.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func splitRow(_ row: SplitRowItem, currency: String) -> some View {
        HStack(spacing: 12) {
            Avatar(initial: row.member.initial, tone: row.member.tone, size: 26, borderWidth: 2)
            Text(row.member.displayName)
                .font(.system(size: 14, weight: row.isYou ? .semibold : .medium))
                .tracking(-0.07)
                .foregroundStyle(Sage.text)
            Spacer()
            Text(MoneyFormatter.format(row.amount, currency: currency))
                .font(.system(size: 14, weight: row.isYou ? .semibold : .regular))
                .tracking(-0.07)
                .foregroundStyle(row.isYou ? Sage.text : Sage.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func editedByName(for expense: ExpenseEntity, userID: UUID?) -> String? {
        guard let editorID = expense.lastEditedByID else { return nil }
        if userID == editorID { return "You" }
        return expense.trip?.people.first(where: { $0.userID == editorID })?.displayName ?? "Member"
    }

    private func detailsCard(expense: ExpenseEntity, loggedByName: String, editedByName: String?) -> some View {
        VStack(spacing: 0) {
            detailRow(label: "Date", value: ExpenseDates.displayString(expense.expenseDate, dateStyle: .long))
            RowDivider()
            detailRow(label: "Paid via", value: expense.paymentMethod.displayName)
            RowDivider()
            detailRow(label: "Logged by", value: loggedByName)
            RowDivider()
            detailRow(label: "Logged at", value: Self.timestampFormatter.string(from: expense.createdAt))
            if let editedByName {
                RowDivider()
                detailRow(label: "Edited by", value: editedByName)
                RowDivider()
                detailRow(label: "Edited at", value: Self.timestampFormatter.string(from: expense.updatedAt))
            }
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

    @ViewBuilder
    private func receiptCard(path: String) -> some View {
        Button {
            guard receiptURL != nil else { return }
            Haptics.light()
            receiptPreviewPresented = true
        } label: {
            ZStack {
                if let url = receiptURL {
                    DownsampledAsyncImage(url: url, maxPointSize: 400) { phase in
                        switch phase {
                        case .empty:
                            receiptPlaceholder(isLoading: true)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            receiptPlaceholder(isLoading: false, failed: true)
                        @unknown default:
                            receiptPlaceholder(isLoading: true)
                        }
                    }
                } else if receiptLoadFailed {
                    receiptPlaceholder(isLoading: false, failed: true)
                } else {
                    receiptPlaceholder(isLoading: true)
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Sage.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
        .disabled(receiptURL == nil)
    }

    private func receiptPlaceholder(isLoading: Bool, failed: Bool = false) -> some View {
        ZStack {
            Sage.surface2
            if isLoading {
                ProgressView().tint(Sage.accent)
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 22))
                        .foregroundStyle(Sage.textSecondary)
                    Text("Couldn't load receipt")
                        .font(.system(size: 12))
                        .foregroundStyle(Sage.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var receiptFullScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = receiptURL {
                DownsampledAsyncImage(url: url, maxPointSize: 1024) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Text("Couldn't load receipt").foregroundStyle(.white)
                    default:
                        ProgressView().tint(.white)
                    }
                }
                .padding()
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        receiptPreviewPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.15), in: Circle())
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 16)
                }
                Spacer()
            }
        }
    }

    private func refreshReceiptURL(for path: String?) async {
        guard let path else {
            await MainActor.run {
                receiptURL = nil
                loadedReceiptForPath = nil
                receiptLoadFailed = false
            }
            return
        }
        if loadedReceiptForPath == path, receiptURL != nil { return }
        if let url = ReceiptStorage.pendingUploadURL(for: path) {
            await MainActor.run {
                receiptURL = url
                loadedReceiptForPath = path
                receiptLoadFailed = false
            }
            return
        }
        do {
            let url = try await ReceiptStorage.signedURL(path: path)
            await MainActor.run {
                receiptURL = url
                loadedReceiptForPath = path
                receiptLoadFailed = false
            }
        } catch {
            await MainActor.run {
                receiptURL = nil
                receiptLoadFailed = true
            }
        }
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

    private func splitTypeLabel(_ type: SplitType) -> String {
        switch type {
        case .equal: "equal"
        case .exact: "exact"
        case .percentage: "percentage"
        case .shares: "shares"
        case .adjustment: "adjustment"
        }
    }

    private func buildSplitRows(expense: ExpenseEntity, currentPersonID: UUID?) -> [SplitRowItem] {
        let peopleByID = Dictionary(uniqueKeysWithValues: (expense.trip?.people ?? []).map { ($0.id, $0) })
        return expense.splits
            .map { split -> SplitRowItem in
                let isYou = split.tripPersonID == currentPersonID
                let member = isYou
                    ? MemberCard(
                        id: split.tripPersonID,
                        displayName: "You",
                        avatarName: auth.currentUser?.displayName ?? peopleByID[split.tripPersonID]?.displayName
                    )
                    : MemberCard(id: split.tripPersonID, displayName: peopleByID[split.tripPersonID]?.displayName ?? "Member")
                return SplitRowItem(
                    id: split.tripPersonID,
                    member: member,
                    amount: split.amountOwed,
                    isYou: isYou
                )
            }
            .sorted { lhs, rhs in
                if lhs.isYou != rhs.isYou { return lhs.isYou }
                return lhs.member.displayName.localizedCaseInsensitiveCompare(rhs.member.displayName) == .orderedAscending
            }
    }

    private func buildPaymentRows(expense: ExpenseEntity, currentPersonID: UUID?) -> [PaymentRowItem] {
        let peopleByID = Dictionary(uniqueKeysWithValues: (expense.trip?.people ?? []).map { ($0.id, $0) })
        return expense.payments
            .map { payment -> PaymentRowItem in
                let isYou = payment.tripPersonID == currentPersonID
                let member = isYou
                    ? MemberCard(
                        id: payment.tripPersonID,
                        displayName: "You",
                        avatarName: auth.currentUser?.displayName ?? peopleByID[payment.tripPersonID]?.displayName
                    )
                    : MemberCard(
                        id: payment.tripPersonID,
                        displayName: peopleByID[payment.tripPersonID]?.displayName ?? "Member"
                    )
                return PaymentRowItem(
                    id: payment.tripPersonID,
                    member: member,
                    amount: payment.amountPaid,
                    isYou: isYou
                )
            }
            .sorted { lhs, rhs in
                if lhs.isYou != rhs.isYou { return lhs.isYou }
                return lhs.member.displayName.localizedCaseInsensitiveCompare(rhs.member.displayName) == .orderedAscending
            }
    }

    private func performDelete() {
        guard let expense else { return }
        Deletion.softDelete(expense: expense, in: context)
        Haptics.success()
        dismiss()
        Task { await sync.pushPending() }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

private struct SplitRowItem: Identifiable, Hashable {
    let id: UUID
    let member: MemberCard
    let amount: Decimal
    let isYou: Bool
}

private struct PaymentRowItem: Identifiable, Hashable {
    let id: UUID
    let member: MemberCard
    let amount: Decimal
    let isYou: Bool
}

private struct MissingExpenseView: View {
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Sage.textSecondary)
            Text("Expense not found")
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
