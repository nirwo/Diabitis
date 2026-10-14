import SwiftUI

struct MealReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var entry: FoodEntry
    @State private var showingLibraryPicker = false
    private let photos = PhotoStore()

    init(entry: FoodEntry) {
        _entry = State(initialValue: entry)
    }

    private var canSave: Bool {
        !entry.items.isEmpty && entry.items.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let name = entry.photoFileName, let image = photos.image(for: name) {
                    Section {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("תמונת הארוחה")
                    }
                }
                if let statusText { Section { Text(statusText).foregroundStyle(.secondary) } }
                Section {
                    ForEach($entry.items) { $item in FoodItemEditor(item: $item) }
                        .onDelete { entry.items.remove(atOffsets: $0) }
                    Button {
                        entry.items.append(FoodItem(name: "", grams: 100, proteinG: 0))
                    } label: { Label("הוספת מאכל", systemImage: "plus") }
                    Button { showingLibraryPicker = true } label: { Label("מהספרייה", systemImage: "book.closed") }
                } header: {
                    Text("מה יש בצלחת")
                } footer: {
                    Text("סה\"כ חלבון: \(formatGrams(entry.proteinG)) גר'")
                }
                if let notes = entry.notes, !notes.isEmpty {
                    Section("הערה מהזיהוי") { Text(notes) }
                }
            }
            .navigationTitle(entry.slotName ?? "ארוחה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { save() }.disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingLibraryPicker) {
                LibraryPickerView { source in
                    entry.items.append(FoodItem(name: source.nameHe, grams: source.servingGrams,
                                                proteinG: source.proteinPerServing))
                }
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }

    private var statusText: String? {
        switch entry.status {
        case .pending, .analyzing: "ממתין לזיהוי במק. אפשר גם להזין ידנית."
        case .needsReview: "זה מה שזיהיתי — בדקו ותקנו לפני שמירה."
        case .failed(.unauthorized): BridgeError.unauthorized.messageHe
        case .failed(.unreadable): BridgeError.badModelOutput.messageHe
        case .failed(.missingPhoto): "התמונה לא נמצאה. אפשר להזין ידנית."
        case .confirmed, .manual: nil
        }
    }

    /// A saved entry always counts toward the goal: photo entries become confirmed, others manual.
    private func save() {
        entry.status = entry.photoFileName == nil ? .manual : .confirmed
        store.upsertFoodEntry(entry)
        dismiss()
    }
}

struct FoodItemEditor: View {
    @Binding var item: FoodItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("שם המאכל", text: $item.name)
                if item.confidence == .low {
                    Text("הערכה לא בטוחה").font(.caption).foregroundStyle(.orange)
                }
            }
            HStack {
                Text("גרם")
                TextField("גרם", value: $item.grams, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).frame(width: 70)
                Spacer()
                Text("חלבון")
                TextField("חלבון", value: $item.proteinG, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).frame(width: 60)
                Text("גר'")
            }
            .font(.subheadline)
        }
    }
}

struct LibraryPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var onPick: (ProteinSource) -> Void

    private var sources: [ProteinSource] {
        let all = FoodLibrary.bundled.sources(for: store.dietStage())
        return query.isEmpty ? all : all.filter { $0.nameHe.contains(query) }
    }

    var body: some View {
        NavigationStack {
            List(sources) { source in
                Button {
                    onPick(source)
                    dismiss()
                } label: {
                    HStack {
                        Text(source.nameHe)
                        Spacer()
                        Text("\(source.servingText) · \(formatGrams(source.proteinPerServing)) גר'")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "חיפוש")
            .navigationTitle("בחירה מהספרייה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } } }
        }
    }
}
