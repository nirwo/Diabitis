import SwiftUI

struct ProteinProgressView: View {
    let total: Double
    let goal: Int

    private var fraction: Double { goal > 0 ? min(total / Double(goal), 1) : 0 }
    private var remaining: Double { max(0, Double(goal) - total) }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((fraction * 100).rounded()))%").font(.caption.bold())
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(formatGrams(total)) / \(goal) גר' חלבון").font(.headline)
                Text(remaining == 0 ? "הגעת ליעד היום" : "נשארו \(formatGrams(remaining)) גר'")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
