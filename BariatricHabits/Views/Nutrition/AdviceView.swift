import SwiftUI

/// The analysis' improvement tips, marked as AI output and as no substitute for the dietitian.
struct AdviceView: View {
    let advice: [String]

    var body: some View {
        if !advice.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("הצעת AI", systemImage: "sparkles")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.15), in: Capsule())
                    .foregroundStyle(.purple)
                ForEach(Array(advice.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").accessibilityHidden(true)
                        Text(tip).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                }
                Text("המידע כללי ואינו מחליף את הדיאטנית.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
