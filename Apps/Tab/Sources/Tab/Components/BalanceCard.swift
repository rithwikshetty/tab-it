import SwiftUI

struct BalanceCard: View {
    let summary: BalanceSummary

    private var tone: Color {
        summary.semantic == .borrowed ? Sage.warning : Sage.accentStrong
    }

    private var tint: Color {
        summary.semantic == .borrowed ? Sage.warning.opacity(0.08) : Sage.accentTint
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(summary.label.uppercased())
                    .font(.balanceLabel)
                    .tracking(1.10)
                    .foregroundStyle(tone.opacity(0.85))
                Text(summary.amount)
                    .font(.balanceAmount)
                    .tracking(-0.85)
                    .foregroundStyle(tone)
                    .padding(.top, 4)
                    .monospacedDigit()

                if !summary.details.isEmpty {
                    Rectangle()
                        .fill(tone.opacity(0.25))
                        .frame(height: 1)
                        .padding(.top, 10)

                    VStack(spacing: 4) {
                        ForEach(summary.details) { detail in
                            HStack {
                                Text(detail.counterparty)
                                    .font(.balanceDetail)
                                    .foregroundStyle(Sage.text.opacity(0.78))
                                Spacer()
                                Text(detail.amount)
                                    .font(.balanceDetail.weight(.semibold))
                                    .foregroundStyle(detail.semantic == .borrowed ? Sage.warning : Sage.accentStrong)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [tone.opacity(0.25), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)
                .offset(x: 40, y: -40)
                .allowsHitTesting(false)
        }
        .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tone.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

struct EmptyBalanceCard: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("All settled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Sage.text)
            Text("Add an expense to start tracking")
                .font(.system(size: 13))
                .foregroundStyle(Sage.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Sage.accentTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Sage.accentSoft, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

#Preview("Balance cards") {
    ScrollView {
        VStack(spacing: 0) {
            BalanceCard(summary: BalanceSummary(
                label: "You're owed",
                amount: "€42.50",
                details: [
                    BalanceDetailItem(id: UUID(), counterparty: "Alex owes you", amount: "€20.00", semantic: .lent),
                    BalanceDetailItem(id: UUID(), counterparty: "Jess owes you", amount: "€22.50", semantic: .lent),
                ],
                semantic: .lent
            ))
            BalanceCard(summary: BalanceSummary(
                label: "You owe",
                amount: "$18.00",
                details: [
                    BalanceDetailItem(id: UUID(), counterparty: "You owe Sam", amount: "$18.00", semantic: .borrowed),
                ],
                semantic: .borrowed
            ))
            BalanceCard(summary: BalanceSummary(
                label: "You're owed",
                amount: "£12.00",
                details: [],
                semantic: .lent
            ))
            EmptyBalanceCard()
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Sage.bg)
}
