import PhotosUI
import SwiftUI

struct NutritionView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var analysisQueue: AnalysisQueue
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var reviewing: FoodEntry?
    @State private var errorMessage: String?
    /// A saved photo's meal, held back until the cooking-note sheet closes.
    @State private var capturedEntry: FoodEntry?
    @State private var chosenCookingNote: String?
    @State private var askingCookingNote = false
    private let photos = PhotoStore()

    private var todaysEntries: [FoodEntry] { store.today.foodEntries.sorted { $0.date > $1.date } }
    private var waitingCount: Int { store.foodEntries(withStatus: .pending).count }
    /// Needs review or failed (any day), then earlier days' meals still waiting for analysis.
    private var attentionEntries: [FoodEntry] { store.entriesNeedingAttention + store.queuedEntriesFromEarlierDays() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProteinProgressView(total: store.proteinToday, goal: store.state.settings.proteinGoalGrams)
                }
                if waitingCount > 0 || analysisQueue.isRunning { queueSection }
                if !attentionEntries.isEmpty { attentionSection }
                Section("ארוחות היום") {
                    if todaysEntries.isEmpty {
                        Text("עוד לא תועדו ארוחות היום").foregroundStyle(.secondary)
                    }
                    ForEach(todaysEntries) { entry in
                        Button { reviewing = entry } label: { FoodEntryRow(entry: entry, photos: photos) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { todaysEntries[$0].id }
                        for id in ids {
                            if let photo = store.deleteFoodEntry(id: id) { photos.delete(photo) }
                        }
                    }
                }
                Section {
                    NavigationLink { LibraryView() } label: {
                        Label("מקורות חלבון, מתכונים וכללים", systemImage: "book.closed")
                    }
                }
            }
            .navigationTitle("תזונה")
            .toolbar { ToolbarItem(placement: .primaryAction) { addMenu } }
            .refreshable { await analysisQueue.kick().value }
            .task { analysisQueue.kick() }
            // The camera sheet must be gone before the note sheet can be presented.
            .sheet(isPresented: $showingCamera, onDismiss: { if capturedEntry != nil { askingCookingNote = true } }) {
                CameraPicker { image in handleCaptured(image) }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task { await loadPicked(item) }
            }
            .sheet(isPresented: $askingCookingNote, onDismiss: finishCapture) {
                CookingNoteSheet { chosenCookingNote = $0 }
                    .environment(\.layoutDirection, .rightToLeft)
            }
            .sheet(item: $reviewing) { entry in
                MealReviewView(entry: entry)
                    .environmentObject(store)
                    .environmentObject(analysisQueue)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            .alert("שגיאה", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("אישור", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button { showingCamera = true } label: { Label("צילום ארוחה", systemImage: "camera") }
            Button { showingPhotoPicker = true } label: { Label("תמונה מהגלריה", systemImage: "photo") }
            Button {
                reviewing = FoodEntry(date: Date(), slotName: store.suggestedSlot()?.name, status: .manual)
            } label: { Label("הזנה ידנית", systemImage: "square.and.pencil") }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title2)
        }
        .accessibilityLabel("הוספת ארוחה")
    }

    private var queueSection: some View {
        Section {
            HStack {
                if analysisQueue.isRunning { ProgressView() }
                Text(analysisQueue.isRunning ? "מזהה ארוחות במק…" : (waitingCount == 1 ? "ארוחה אחת ממתינה לזיהוי" : "\(waitingCount) ארוחות ממתינות לזיהוי"))
                Spacer()
                if !analysisQueue.isRunning {
                    Button("נסה עכשיו") { analysisQueue.kick() }
                }
            }
            if let error = analysisQueue.lastError, !analysisQueue.isRunning {
                Text(error.messageHe).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var attentionSection: some View {
        Section {
            ForEach(attentionEntries) { entry in
                Button { reviewing = entry } label: { FoodEntryRow(entry: entry, photos: photos, showsDay: true) }
                    .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let ids = offsets.map { attentionEntries[$0].id }
                for id in ids {
                    if let photo = store.deleteFoodEntry(id: id) { photos.delete(photo) }
                }
            }
        } header: {
            Text("לאישור")
        } footer: {
            Text("ארוחות שמחכות לאישור, שהזיהוי שלהן נכשל, או שעדיין ממתינות מימים קודמים.")
        }
    }

    private func handleCaptured(_ image: UIImage) {
        do {
            let fileName = try photos.save(image)
            capturedEntry = FoodEntry(date: Date(), slotName: store.suggestedSlot()?.name,
                                      photoFileName: fileName, status: .pending)
            chosenCookingNote = nil
            if !showingCamera { askingCookingNote = true }
        } catch {
            errorMessage = "לא הצלחנו לשמור את התמונה."
        }
    }

    /// Runs for "המשך", "דלג" and a swipe-down alike (a swipe leaves the note nil).
    private func finishCapture() {
        guard var entry = capturedEntry else { return }
        entry.cookingNote = chosenCookingNote
        store.upsertFoodEntry(entry)
        capturedEntry = nil
        chosenCookingNote = nil
        analysisQueue.kick()
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                errorMessage = "לא הצלחנו לפתוח את התמונה."
                return
            }
            handleCaptured(image)
        } catch {
            errorMessage = "לא הצלחנו לפתוח את התמונה."
        }
    }
}

struct FoodEntryRow: View {
    let entry: FoodEntry
    let photos: PhotoStore
    var showsDay = false

    private var title: String {
        let base = entry.slotName ?? entry.date.timeText
        guard showsDay, !Calendar.current.isDateInToday(entry.date) else { return base }
        return "\(entry.date.formatted(.dateTime.day().month(.abbreviated))) · \(base)"
    }

    private var subtitle: String {
        let base = entry.items.isEmpty ? entry.date.timeText : entry.items.map(\.name).joined(separator: ", ")
        guard let note = entry.cookingNote, !note.isEmpty else { return base }
        return "\(base) · \(note)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let name = entry.photoFileName, let image = photos.thumbnail(for: name) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "fork.knife").foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if entry.status.labelHe.isEmpty {
                Text("\(formatGrams(entry.proteinG)) גר'").font(.subheadline.bold())
            } else {
                Text(entry.status.labelHe).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
