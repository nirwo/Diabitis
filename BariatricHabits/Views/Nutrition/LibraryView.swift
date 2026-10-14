import SwiftUI

struct LibraryView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case sources = "מקורות חלבון"
        case recipes = "מתכונים"
        case rules = "כללים"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: AppStore
    @State private var tab: Tab = .sources
    @State private var showAllStages = false
    private let library = FoodLibrary.bundled

    var body: some View {
        let currentStage = store.dietStage()
        let stage = showAllStages ? nil : currentStage
        List {
            Section {
                Picker("קטגוריה", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if let currentStage, currentStage != .preSurgery {
                    Toggle("להציג את כל השלבים (כעת: \(currentStage.title))", isOn: $showAllStages)
                }
            }
            switch tab {
            case .sources:
                ForEach(library.sources(for: stage)) { SourceRow(source: $0) }
            case .recipes:
                Section {
                    NavigationLink { RecipeSuggestionView() } label: {
                        Label("תציע לי מתכון (Claude דרך המק)", systemImage: "sparkles")
                    }
                }
                ForEach(library.recipes(for: stage)) { recipe in
                    NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.nameHe).font(.headline)
                            Text("\(formatGrams(recipe.proteinPerPortion)) גר' חלבון \(recipe.portionText)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            case .rules:
                ForEach(library.rules) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.textHe)
                        Link("מקור", destination: rule.sourceURL).font(.caption)
                    }
                }
            }
            Section {
                Text("המידע כללי, נבדק מול מקורות, ואינו מחליף את הדיאטנית.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("ספריית תזונה")
    }
}

private struct SourceRow: View {
    let source: ProteinSource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(source.nameHe).font(.headline)
                Spacer()
                Text("\(formatGrams(source.proteinPerServing)) גר'").bold()
            }
            Text(source.servingText).font(.subheadline).foregroundStyle(.secondary)
            if !source.note.isEmpty { Text(source.note).font(.footnote) }
            HStack {
                Text("משלב: \(source.minStage.title)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Link("מקור", destination: source.sourceURL).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RecipeDetailView: View {
    let recipe: Recipe

    var body: some View {
        List {
            Section {
                Text("\(formatGrams(recipe.proteinPerPortion)) גר' חלבון \(recipe.portionText)").font(.headline)
                Text("משלב: \(recipe.minStage.title)").foregroundStyle(.secondary)
            }
            if !recipe.warnings.isEmpty {
                Section { ForEach(recipe.warnings, id: \.self) { Text($0).foregroundStyle(.orange) } }
            }
            Section("מצרכים") { ForEach(recipe.ingredients, id: \.self) { Text($0) } }
            Section {
                Link("אופן ההכנה המלא בחוברת המקור", destination: recipe.sourceURL)
            }
        }
        .navigationTitle(recipe.nameHe)
    }
}
