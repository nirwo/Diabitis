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
    private let photos = PhotoStore()

    private var todaysEntries: [FoodEntry] { store.today.foodEntries.sorted { $0.date > $1.date } }
    private var waitingCount: Int { store.foodEntries(withStatus: .pending).count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProteinProgressView(total: store.proteinToday, goal: store.state.settings.proteinGoalGrams)
                }
                if waitingCount > 0 || analysisQueue.isRunning { queueSection }
                Section("ארוחות היום") {
                    if todaysEntries.isEmpty {
                        Text("עוד לא תועדו ארוחות היום").foregroundStyle(.secondary)
                    }
                    ForEach(todaysEntries) { entry in
                        Button { reviewing = entry } label: { FoodEntryRow(entry: entry, photos: photos) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            if let photo = store.deleteFoodEntry(id: todaysEntries[index].id) { photos.delete(photo) }
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
            .refreshable { await analysisQueue.processPending() }
            .task { await analysisQueue.processPending() }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { image in handleCaptured(image) }.ignoresSafeArea()
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task { await loadPicked(item) }
            }
            .sheet(item: $reviewing) { entry in
                MealReviewView(entry: entry)
                    .environmentObject(store)
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
                Text(analysisQueue.isRunning ? "מזהה ארוחות במק…" : "\(waitingCount) ארוחות ממתינות לזיהוי")
                Spacer()
                if !analysisQueue.isRunning {
                    Button("נסה עכשיו") { Task { await analysisQueue.processPending() } }
                }
            }
            if let error = analysisQueue.lastError, !analysisQueue.isRunning {
                Text(error.messageHe).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func handleCaptured(_ image: UIImage) {
        do {
            let fileName = try photos.save(image)
            store.upsertFoodEntry(FoodEntry(date: Date(), slotName: store.suggestedSlot()?.name,
                                            photoFileName: fileName, status: .pending))
            Task { await analysisQueue.processPending() }
        } catch {
            errorMessage = "לא הצלחנו לשמור את התמונה."
        }
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

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let name = entry.photoFileName, let image = photos.image(for: name) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "fork.knife").foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.slotName ?? entry.date.timeText).font(.headline)
                Text(entry.items.isEmpty ? entry.date.timeText : entry.items.map(\.name).joined(separator: ", "))
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
