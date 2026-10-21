import SwiftUI

struct RecipeSuggestionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var haveText = ""
    @State private var suggestion: RecipeSuggestion?
    @State private var message: String?
    @State private var isLoading = false

    private var remaining: Double {
        ProteinCalculator.remaining(goal: store.proteinGoal, entries: store.today.foodEntries)
    }

    /// Without a known stage, assume soft food so Claude never suggests late-stage foods by default.
    private var requestStage: DietStage { store.dietStage() ?? .soft }
    private var stageText: String { store.dietStage()?.title ?? "לא הוגדר (מניח מזון רך)" }

    var body: some View {
        Form {
            Section {
                Text("נשארו היום \(formatGrams(remaining)) גר' חלבון · שלב: \(stageText)")
                TextField("מה יש בבית? (מופרד בפסיקים)", text: $haveText)
                Button {
                    Task { await ask() }
                } label: {
                    HStack {
                        Text("תציע לי מתכון")
                        if isLoading { Spacer(); ProgressView() }
                    }
                }
                .disabled(isLoading)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            if let suggestion {
                Section {
                    Text("הצעת AI — לא נבדק").font(.caption.bold()).foregroundStyle(.orange)
                    Text(suggestion.name).font(.headline)
                    Text("\(formatGrams(suggestion.proteinPerPortion)) גר' חלבון · \(suggestion.portionText)")
                }
                Section("מצרכים") { ForEach(suggestion.ingredients, id: \.self) { Text($0) } }
                Section("הכנה") {
                    ForEach(Array(suggestion.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
            }
        }
        .navigationTitle("מתכון מ-Claude")
    }

    private func ask() async {
        isLoading = true
        defer { isLoading = false }
        guard let client = BridgeConfig.makeClient(settings: store.state.settings) else {
            message = "צריך להגדיר את החיבור למק בהגדרות."
            return
        }
        let have = haveText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.prefix(20).map { String($0.prefix(40)) }
        do {
            suggestion = try await client.recipe(RecipeRequest(remainingG: min(remaining, 300),
                                                               stage: requestStage,
                                                               have: Array(have)))
            message = nil
        } catch {
            message = ((error as? BridgeError) ?? .unreachable).messageHe
        }
    }
}
