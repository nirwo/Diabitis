import SwiftUI

struct NutritionView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                ProteinProgressView(total: store.proteinToday, goal: store.state.settings.proteinGoalGrams)
            }
            .navigationTitle("תזונה")
        }
    }
}
