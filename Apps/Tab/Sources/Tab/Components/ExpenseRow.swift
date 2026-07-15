import SwiftUI

struct ExpenseRow: View {
    let item: ExpenseRowItem

    private var tone: Color {
        guard let id = item.categoryID else { return Sage.text }
        return DefaultCategories.tone(for: id)
    }

    private var balanceTone: Color {
        switch item.balanceSemantic {
        case .lent: Sage.accentStrong
        case .borrowed: Sage.warning
        case .neutral: Sage.textSecondary
        }
    }

    private var captionLabel: String {
        guard item.netAmount != nil else { return "your share" }
        switch item.balanceSemantic {
        case .lent: return "you lent"
        case .borrowed: return "you borrowed"
        case .neutral: return "your share"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            phosphorIcon(named: item.icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(tone)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.expenseName)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.text)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let sourceName = item.sourceName {
                        Text(sourceName)
                        Text("·")
                    }
                    Text("Paid by \(item.payerName)")
                    Text("·")
                    Text(item.totalAmount)
                }
                    .font(.expenseMeta)
                    .tracking(-0.07)
                    .foregroundStyle(Sage.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.netAmount ?? item.yourShare)
                    .font(.expenseAmount)
                    .tracking(-0.07)
                    .foregroundStyle(item.netAmount == nil ? Sage.text : balanceTone)
                    .monospacedDigit()
                Text(captionLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Sage.textSecondary)
            }
            Chevron(size: 12)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

#Preview("Expense rows") {
    VStack(spacing: 0) {
        ExpenseRow(item: ExpenseRowItem(
            id: UUID(), categoryID: nil, icon: "ForkKnife",
            name: "Pizza dinner", payerName: "Alex",
            totalAmount: "€25.00",
            yourShare: "€12.50", netAmount: "€12.50", balanceSemantic: .borrowed
        ))
        RowDivider()
        ExpenseRow(item: ExpenseRowItem(
            id: UUID(), categoryID: nil, icon: "Car",
            name: "Airport taxi", payerName: "You",
            totalAmount: "€32.00",
            yourShare: "€8.00", netAmount: "€24.00", balanceSemantic: .lent
        ))
    }
    .background(Sage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}
