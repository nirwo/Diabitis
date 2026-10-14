import Combine
import SwiftUI

struct MealReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var entry: FoodEntry
    @State private var showingLibraryPicker = false
    @State private var photo: UIImage?
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
                if let photo {
                    Section {
                        Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 220)
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
            .task {
                if let name = entry.photoFileName { photo = photos.image(for: name) }
            }
            .navigationTitle(entry.slotName ?? "ארוחה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { save() }.disabled(!canSave)
                }
                // The decimal pad has no return key.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("סיום") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
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

/// Text-backed number fields: `TextField(value:format:)` only commits on return or focus loss,
/// and the decimal pad has no return key, so typed amounts never reached the meal.
struct FoodItemEditor: View {
    /// Below this difference a re-typed value is just the displayed rounding of the stored one.
    private static let roundingTolerance = 0.05

    @Binding var item: FoodItem
    @State private var gramsText = ""
    @State private var proteinText = ""

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
                TextField("גרם", text: $gramsText)
                    .keyboardType(.decimalPad)
                    .frame(minWidth: 60)
                    .onChange(of: gramsText) { _, text in applyGrams(text) }
                Spacer()
                Text("חלבון")
                TextField("חלבון", text: $proteinText)
                    .keyboardType(.decimalPad)
                    .frame(minWidth: 50)
                    .onChange(of: proteinText) { _, text in applyProtein(text) }
                Text("גר'")
            }
            .font(.subheadline)
        }
        .onAppear {
            gramsText = formatGrams(item.grams)
            proteinText = formatGrams(item.proteinG)
        }
        // Typing should replace the old amount, not append to it.
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            guard let field = note.object as? UITextField, field.keyboardType == .decimalPad else { return }
            DispatchQueue.main.async { field.selectAll(nil) }
        }
    }

    private func applyGrams(_ text: String) {
        guard let grams = parseDecimal(text), abs(grams - item.grams) >= Self.roundingTolerance else { return }
        item = item.withGrams(grams)
        proteinText = formatGrams(item.proteinG)
    }

    private func applyProtein(_ text: String) {
        guard let protein = parseDecimal(text), abs(protein - item.proteinG) >= Self.roundingTolerance else { return }
        item.proteinG = protein
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
