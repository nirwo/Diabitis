import PhotosUI
import SwiftUI

/// Where the meal photo comes from.
enum MealPhotoSource {
    /// The camera, or the photo library on a device without one.
    case camera
    case library
}

extension View {
    /// Photo → "איך הכנת?" → a `.pending` meal for today, queued for analysis.
    /// Swiping the note sheet away counts as skipping it.
    func mealPhotoCapture(isPresented: Binding<Bool>, source: MealPhotoSource = .camera, slotName: String?,
                          onCreated: @escaping (UUID) -> Void) -> some View {
        modifier(MealPhotoCaptureModifier(isPresented: isPresented, source: source, slotName: slotName,
                                          onCreated: onCreated))
    }
}

private struct MealPhotoCaptureModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var analysisQueue: AnalysisQueue
    @Binding var isPresented: Bool
    let source: MealPhotoSource
    let slotName: String?
    let onCreated: (UUID) -> Void

    @State private var pickedItem: PhotosPickerItem?
    /// A saved photo's meal, held back until the cooking-note sheet closes.
    @State private var capturedEntry: FoodEntry?
    @State private var chosenCookingNote: String?
    @State private var askingCookingNote = false
    @State private var errorMessage: String?
    private let photos = PhotoStore()

    func body(content: Content) -> some View {
        picker(on: content)
            .sheet(isPresented: $askingCookingNote, onDismiss: finishCapture) {
                CookingNoteSheet { chosenCookingNote = $0 }
                    .environment(\.layoutDirection, .rightToLeft)
            }
            .alert("שגיאה", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("אישור", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private func picker(on content: Content) -> some View {
        switch source {
        case .camera:
            // The camera sheet must be gone before the note sheet can be presented.
            content.sheet(isPresented: $isPresented, onDismiss: { if capturedEntry != nil { askingCookingNote = true } }) {
                CameraPicker { image in handleCaptured(image) }.ignoresSafeArea()
            }
        case .library:
            content
                .photosPicker(isPresented: $isPresented, selection: $pickedItem, matching: .images)
                .onChange(of: pickedItem) { _, item in
                    guard let item else { return }
                    Task { await loadPicked(item) }
                }
        }
    }

    private func handleCaptured(_ image: UIImage) {
        do {
            let fileName = try photos.save(image)
            capturedEntry = FoodEntry(date: Date(), slotName: slotName, photoFileName: fileName, status: .pending)
            chosenCookingNote = nil
            // The library picker is already closed here; the camera sheet asks from its onDismiss.
            if source == .library || !isPresented { askingCookingNote = true }
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
        onCreated(entry.id)
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
