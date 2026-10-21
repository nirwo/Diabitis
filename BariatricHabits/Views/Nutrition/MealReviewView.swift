import Combine
import SwiftUI

struct MealReviewView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var analysisQueue: AnalysisQueue
    @Environment(\.dismiss) private var dismiss
    @State private var entry: FoodEntry
    @State private var cookingDraft: CookingNoteDraft
    @State private var showingLibraryPicker = false
    @State private var photo: UIImage?
    private let photos = PhotoStore()

    init(entry: FoodEntry) {
        _entry = State(initialValue: entry)
        _cookingDraft = State(initialValue: CookingNoteDraft(note: entry.cookingNote))
    }

    /// The saved meal as it is now; the queue may have moved on since this screen copied it.
    private var liveEntry: FoodEntry { store.allFoodEntries.first { $0.id == entry.id } ?? entry }

    /// The stored estimate was made with a different note than the one now chosen.
    private var canReanalyze: Bool {
        let live = liveEntry
        return live.photoFileName != nil && live.status != .analyzing
            && CookingNoteDraft.isChanged(cookingDraft, from: live.analyzedCookingNote)
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
                // Live, so tips that arrive while this screen is open still show.
                if let advice = liveEntry.advice, !advice.isEmpty {
                    Section { AdviceView(advice: advice) }
                }
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
                Section {
                    CookingNoteEditor(draft: $cookingDraft)
                    if canReanalyze {
                        Button { reanalyze() } label: {
                            Label("זהה מחדש עם אופן ההכנה", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("איך הכנתי")
                } footer: {
                    if canReanalyze && liveEntry.status == .confirmed {
                        Text("הארוחה תחזור לאישור ולא תיספר ביעד עד שתאשרו שוב.")
                    }
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
        entry.cookingNote = cookingDraft.note
        entry.status = entry.photoFileName == nil ? .manual : .confirmed
        store.upsertFoodEntry(entry)
        dismiss()
    }

    /// Sends the photo again with the edited note; the new result replaces the items when it arrives.
    private func reanalyze() {
        entry.cookingNote = cookingDraft.note
        entry.status = .pending
        store.upsertFoodEntry(entry)
        analysisQueue.kick()
        dismiss()
    }
}

/// Text-backed number fields: `TextField(value:format:)` only commits on return or focus loss,
/// and the decimal pad has no return key, so typed amounts never reached the meal.
struct FoodItemEditor: View {
    @Binding var item: FoodItem
    @State private var amounts: FoodAmountEdit
    @State private var gramsText: String
    @State private var proteinText: String
    /// Set when the protein field is rewritten from a grams change, so that echo isn't taken as a user edit.
    @State private var isSyncingProtein = false

    init(item: Binding<FoodItem>) {
        _item = item
        _amounts = State(initialValue: FoodAmountEdit(item: item.wrappedValue))
        _gramsText = State(initialValue: formatGrams(item.wrappedValue.grams))
        _proteinText = State(initialValue: formatGrams(item.wrappedValue.proteinG))
    }

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
        // Typing should replace the old amount, not append to it.
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            guard let field = note.object as? UITextField, field.keyboardType == .decimalPad else { return }
            DispatchQueue.main.async { field.selectAll(nil) }
        }
    }

    private func applyGrams(_ text: String) {
        guard amounts.setGrams(text) else { return }
        item.grams = amounts.grams
        item.proteinG = amounts.proteinG
        let shown = formatGrams(amounts.proteinG)
        if shown != proteinText {
            isSyncingProtein = true
            proteinText = shown
        }
    }

    private func applyProtein(_ text: String) {
        if isSyncingProtein {
            isSyncingProtein = false
            return
        }
        guard amounts.setProtein(text) else { return }
        item.proteinG = amounts.proteinG
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
