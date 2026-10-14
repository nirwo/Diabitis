import Foundation

/// Sends pending meal photos to the Mac bridge whenever it is reachable.
@MainActor
final class AnalysisQueue: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: BridgeError?

    private let store: AppStore
    private let photos: PhotoStore
    private let makeClient: @MainActor () -> BridgeClienting?

    init(store: AppStore, photos: PhotoStore, makeClient: @escaping @MainActor () -> BridgeClienting?) {
        self.store = store
        self.photos = photos
        self.makeClient = makeClient
        store.resetStaleAnalyses()
    }

    func processPending() async {
        guard !isRunning, let client = makeClient() else { return }
        isRunning = true
        defer { isRunning = false }

        for entry in store.foodEntries(withStatus: .pending) {
            guard let fileName = entry.photoFileName, let jpeg = photos.data(for: fileName) else {
                store.updateFoodEntry(id: entry.id) { $0.status = .failed(.missingPhoto) }
                continue
            }
            store.updateFoodEntry(id: entry.id) { $0.status = .analyzing }
            do {
                let result = try await client.analyze(jpeg: jpeg)
                store.updateFoodEntry(id: entry.id) {
                    $0.items = result.items.map {
                        FoodItem(name: $0.name, grams: $0.grams, proteinG: $0.proteinG, confidence: $0.confidence)
                    }
                    $0.notes = result.notes.isEmpty ? nil : result.notes
                    $0.status = .needsReview
                }
                lastError = nil
            } catch BridgeError.badModelOutput {
                store.updateFoodEntry(id: entry.id) { $0.status = .failed(.unreadable) }
            } catch BridgeError.unauthorized {
                store.updateFoodEntry(id: entry.id) { $0.status = .failed(.unauthorized) }
                lastError = .unauthorized
                return
            } catch {
                // Mac asleep, offline, Claude logged out, timeout: retry later, stop hammering now.
                store.updateFoodEntry(id: entry.id) { $0.status = .pending }
                lastError = (error as? BridgeError) ?? .unreachable
                return
            }
        }
    }
}
