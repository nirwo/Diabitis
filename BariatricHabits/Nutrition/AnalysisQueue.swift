import Foundation

/// Sends pending meal photos to the Mac bridge whenever it is reachable.
@MainActor
final class AnalysisQueue: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: BridgeError?

    private let store: AppStore
    private let photos: PhotoStore
    private let makeClient: @MainActor () -> BridgeClienting?
    /// Owned by the queue, not by a view, so leaving a screen never cancels a running analysis.
    private var runTask: Task<Void, Never>?
    /// Set by a kick during a run: a meal re-queued mid-run was already skipped this round.
    private var isRerunRequested = false

    init(store: AppStore, photos: PhotoStore, makeClient: @escaping @MainActor () -> BridgeClienting?) {
        self.store = store
        self.photos = photos
        self.makeClient = makeClient
        store.resetStaleAnalyses()
    }

    /// Starts processing in a task the queue owns. While a run is in progress it asks that run
    /// to go once more when it finishes. Returns the running task so callers can await it.
    @discardableResult
    func kick() -> Task<Void, Never> {
        if let runTask {
            isRerunRequested = true
            return runTask
        }
        let task = Task { [weak self] in
            var shouldRun = true
            while shouldRun {
                self?.isRerunRequested = false
                await self?.processPending()
                shouldRun = self?.isRerunRequested ?? false
            }
            self?.runTask = nil
        }
        runTask = task
        return task
    }

    func processPending() async {
        guard !isRunning, let client = makeClient() else { return }
        isRunning = true
        defer { isRunning = false }

        var attempted = Set<UUID>()
        // Re-read each round so meals added mid-run are picked up and edited ones skipped.
        while let entry = store.foodEntries(withStatus: .pending).first(where: { !attempted.contains($0.id) }) {
            attempted.insert(entry.id)
            guard let fileName = entry.photoFileName, let jpeg = photos.data(for: fileName) else {
                store.updateFoodEntry(id: entry.id) { $0.status = .failed(.missingPhoto) }
                continue
            }
            store.updateFoodEntry(id: entry.id) { $0.status = .analyzing }
            do {
                let cookingNote = entry.cookingNote
                let result = try await client.analyze(jpeg: jpeg, cookingNote: cookingNote, context: context(for: entry))
                store.updateFoodEntry(id: entry.id) {
                    guard $0.status == .analyzing else { return }
                    $0.items = result.items.map {
                        FoodItem(name: $0.name, grams: $0.grams, proteinG: $0.proteinG, confidence: $0.confidence).sanitized
                    }
                    $0.notes = result.notes.isEmpty ? nil : result.notes
                    $0.advice = result.advice.isEmpty ? nil : result.advice
                    $0.analyzedCookingNote = cookingNote
                    $0.status = .needsReview
                }
                lastError = nil
            } catch is CancellationError {
                markIfStillAnalyzing(entry.id, as: .pending)
                return
            } catch BridgeError.badModelOutput {
                markIfStillAnalyzing(entry.id, as: .failed(.unreadable))
            } catch BridgeError.unauthorized {
                markIfStillAnalyzing(entry.id, as: .failed(.unauthorized))
                lastError = .unauthorized
                return
            } catch {
                // Mac asleep, offline, Claude logged out, timeout: retry later, stop hammering now.
                markIfStillAnalyzing(entry.id, as: .pending)
                lastError = (error as? BridgeError) ?? .unreachable
                return
            }
        }
    }

    private static let maxContextGrams = 1000

    /// Protein already confirmed on the meal's own day (not counting the meal itself) and that day's goal,
    /// clamped to the bridge's range.
    private func context(for entry: FoodEntry) -> AnalysisContext {
        let log = store.log(for: entry.date)
        let others = log.foodEntries.filter { $0.id != entry.id }
        let eaten = Int(ProteinCalculator.total(others).rounded())
        let goal = log.proteinGoalGrams ?? store.proteinGoal
        return AnalysisContext(stage: store.dietStage(now: entry.date),
                               proteinEatenG: min(max(eaten, 0), Self.maxContextGrams),
                               proteinGoalG: min(max(goal, 0), Self.maxContextGrams))
    }

    /// A late result must never overwrite a meal the user confirmed or edited meanwhile.
    private func markIfStillAnalyzing(_ id: UUID, as status: FoodEntryStatus) {
        store.updateFoodEntry(id: id) {
            guard $0.status == .analyzing else { return }
            $0.status = status
        }
    }
}
