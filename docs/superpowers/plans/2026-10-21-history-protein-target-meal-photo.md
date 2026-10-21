# History, Protein Target & Meal-Tab Photo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Day-by-day eating history, a weight-based daily protein target, and a "צלם את המנה" button on the Meal tab that returns items, protein and 1–3 improvement tips.

**Architecture:** Pure, unit-tested logic units (`ProteinTarget`, `DayHistory`) feed new SwiftUI screens; the effective goal is read through one `AppStore.proteinGoal` accessor. The bridge gains context headers (stage, protein eaten/goal) and returns an optional `advice` array that the app stores on `FoodEntry`. The existing camera → "איך הכנת?" → pending entry flow is extracted from `NutritionView` into a reusable modifier and reused on the Meal tab.

**Tech Stack:** Swift 5 / SwiftUI / iOS 17, XCTest, XcodeGen; Python 3 stdlib bridge + unittest.

**Spec:** `docs/superpowers/specs/2026-10-21-history-protein-target-meal-photo-design.md`

## Global Constraints

- iOS 17.0, Swift 5 language mode, no third-party packages; `project.yml` is the source of truth — run `xcodegen generate` after adding files, never hand-edit `project.pbxproj`.
- Every Codable change decodes old data: new fields go through `decodeIfPresent` (Models.swift extensions for `AppSettings`/`DayLog`; custom `init(from:)` wherever a non-optional field with a default is added to a synthesized type).
- Bridge: Python stdlib only; `claude` keeps `--tools Read` scoped to the temp dir; user text never goes through `str.format`; header values are ASCII.
- UI Hebrew + RTL; icon-only buttons get accessibility labels; touch targets ≥44pt.
- AI advice is labelled `הצעת AI` and accompanied by `המידע כללי ואינו מחליף את הדיאטנית.`
- Protein formula: IBW = 25 × height(m)²; adjusted = IBW + factor × (weight − IBW), and the current weight when weight < IBW; target = max(floor, basis × g/kg) rounded. Defaults: basis adjusted, factor 0.25, 1.2 g/kg, floor 90. Ranges: factor ∈ {0.25, 0.4}; g/kg 1.0–2.1 step 0.1; floor 60–120 step 5; height 120–220 cm; weight 35–300 kg. Marked `לבדיקת הדיאטנית`.
- Slot states: eaten = in `completedSlots` OR a same-day `FoodEntry` with that `slotName`; skipped = not eaten and now ≥ slot time + 60 min; upcoming = not eaten and earlier (today only).
- Commands: Swift `xcodebuild test -project BariatricHabits.xcodeproj -scheme BariatricHabits -destination 'platform=iOS Simulator,name=iPhone 17'`; Python `python3 -m unittest discover -s bridge -p 'test_*.py' -v`.
- Commits: conventional, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (a subagent may name its own model).

## Review Focus

1. Upgrading with existing saved state (no profile, no new keys) — goal stays exactly the old manual value and nothing is lost → `test_legacy_settings_keep_manual_goal` (Task 1).
2. A past day viewed after the goal changed — shows its own snapshot, not today's goal → `test_past_day_uses_snapshot_goal` (Task 3).
3. A meal photographed for a slot whose name was later renamed/deleted — entry still shown in the timeline, slot just not matched → `test_entry_with_unknown_slot_is_listed` (Task 3).
4. Bridge reply with absurd/malicious advice (10 items, 2 KB strings, non-strings) — trimmed to ≤3 × ≤140 chars or dropped, never a 500 → `test_advice_is_trimmed_and_filtered` (Task 4).
5. Weight below IBW or missing height — no negative/zero target; falls back to manual goal when profile incomplete → `test_underweight_uses_current_weight` / `test_incomplete_profile_falls_back` (Task 1).

---

### Task 1: Protein target model + effective goal

**Files:**
- Create: `BariatricHabits/Nutrition/ProteinTarget.swift`
- Modify: `BariatricHabits/Models.swift` (`AppSettings` + its decoding extension; `DayLog` + its decoding extension)
- Modify: `BariatricHabits/Nutrition/AppStore+Food.swift`
- Modify (read sites → `store.proteinGoal`): `BariatricHabits/Views/TodayView.swift:90`, `BariatricHabits/Views/Nutrition/NutritionView.swift:27`, `BariatricHabits/Views/Nutrition/RecipeSuggestionView.swift:11`
- Test: `BariatricHabitsTests/ProteinTargetTests.swift`

**Interfaces:**
- Produces:
  - `enum ProteinTargetMode: String, Codable { case automatic, manual }`
  - `enum ProteinWeightBasis: String, Codable, CaseIterable { case ideal, adjusted }`
  - `struct ProteinTargetSettings: Codable, Hashable { var mode: ProteinTargetMode = .automatic; var heightCm: Double?; var weightKg: Double?; var weightUpdated: Date?; var basis: ProteinWeightBasis = .adjusted; var adjustmentFactor: Double = 0.25; var gramsPerKg: Double = 1.2; var floorGrams: Int = 90 }` (custom `init(from:)` with `decodeIfPresent` for every field)
  - `struct ProteinTargetResult: Equatable { let idealKg: Double; let basisKg: Double; let grams: Int }`
  - `enum ProteinTarget { static func calculate(_ s: ProteinTargetSettings) -> ProteinTargetResult? }` — nil when height or weight missing.
  - `AppSettings.proteinTarget: ProteinTargetSettings` (default `.init()`); existing `proteinGoalGrams` stays as the manual value.
  - `DayLog.proteinGoalGrams: Int?`
  - `extension AppStore { var proteinGoal: Int; func refreshTodayGoalSnapshot() }` — `proteinGoal` = calculated grams when mode automatic and calculable, else `settings.proteinGoalGrams`. `refreshTodayGoalSnapshot()` writes `proteinGoal` into today's `DayLog` (only if it differs). `upsertFoodEntry` calls it for entries dated today.

- [ ] **Step 1: Write failing tests** in `ProteinTargetTests.swift`:
  - `test_adjusted_default`: height 180, weight 130 → idealKg 81.0, basisKg 93.25, grams 112.
  - `test_ideal_basis`: same, basis `.ideal`, 1.5 g/kg → grams 122 (81 × 1.5 = 121.5 → 122).
  - `test_floor_applies`: height 160, weight 70, 1.0 g/kg → grams 90.
  - `test_underweight_uses_current_weight`: height 180, weight 70 (< IBW 81) → basisKg 70.
  - `test_incomplete_profile_falls_back`: `calculate` with no height → nil; `AppStore.proteinGoal` with mode automatic, no height, `proteinGoalGrams` 100 → 100.
  - `test_manual_mode_ignores_profile`: profile complete, mode manual, `proteinGoalGrams` 105 → `proteinGoal` 105.
  - `test_legacy_settings_keep_manual_goal`: decode the legacy settings JSON used in `StateDecodingTests` (no `proteinTarget` key) → `proteinTarget == ProteinTargetSettings()` and `proteinGoal == 100`.
  - `test_snapshot_written_on_today_upsert`: profile complete; upsert a today entry → `store.today.proteinGoalGrams == store.proteinGoal`.
- [ ] **Step 2: Run** `xcodegen generate` then the Swift command with `-only-testing:BariatricHabitsTests/ProteinTargetTests` → FAIL (types missing).
- [ ] **Step 3: Implement** the interfaces above. Rounding: `Int((basisKg * gramsPerKg).rounded())`, then `max(floorGrams, …)`. Replace the three read sites with `store.proteinGoal`.
- [ ] **Step 4: Run** focused tests → PASS; then the full Swift suite → all pass.
- [ ] **Step 5: Commit** `feat(nutrition): weight-based protein target with manual fallback`.

### Task 2: Settings — profile and calculation

**Files:**
- Create: `BariatricHabits/Views/Nutrition/ProteinTargetSection.swift`
- Modify: `BariatricHabits/Views/SettingsView.swift:33-36` (replace the protein Stepper with `ProteinTargetSection()`)

**Interfaces:**
- Consumes: Task 1 (`ProteinTargetSettings`, `ProteinTarget.calculate`, `AppStore.proteinGoal`, `refreshTodayGoalSnapshot()`).
- Produces: `struct ProteinTargetSection: View` (uses `@EnvironmentObject AppStore`).

- [ ] **Step 1: Build the section** (UI-only; logic is tested in Task 1). Contents, in order:
  - Picker `אופן חישוב היעד`: `לפי משקל` (automatic) / `ידני` (manual).
  - Manual: the existing Stepper (`יעד חלבון: N גר'`, 60…160 step 5).
  - Automatic: גובה (ס"מ) and משקל (ק"ג) as decimal fields using the same text-backed pattern as `FoodItemEditor` (`parseDecimal`), clamped to the ranges in Global Constraints; editing weight sets `weightUpdated = Date()`. Picker `בסיס`: `משקל מתוקנן` / `משקל אידיאלי`; Picker `מקדם תיקון`: 0.25 / 0.4 (only for adjusted); Stepper `גר' חלבון לק"ג` 1.0–2.1 step 0.1; Stepper `מינימום יומי` 60–120 step 5.
  - Result row: `אידיאלי X ק"ג · מתוקנן Y ק"ג × Z = N גר'` (omit the adjusted part for basis ideal), or `הזינו גובה ומשקל` when incomplete.
  - Footer: `הנוסחה לבדיקת הדיאטנית. מקור: ASMBS (עד 1.5 גר'/ק"ג ממשקל אידיאלי), ERAS (לפחות 90 גר' אחרי מעקף).`
  - Any change calls `store.refreshTodayGoalSnapshot()`.
- [ ] **Step 2: Verify** build + full suite pass; simulator: enter 180 / 130 → result row shows `112 גר'`; Today and Nutrition rings show 112. Screenshot.
- [ ] **Step 3: Commit** `feat(settings): protein target profile and calculation`.

### Task 3: Day history model

**Files:**
- Create: `BariatricHabits/Nutrition/DayHistory.swift`
- Test: `BariatricHabitsTests/DayHistoryTests.swift`

**Interfaces:**
- Consumes: `DayLog`, `MealSlot` (`id`, `name`, `hour`, `minute`, `date(on:)`), `FoodEntry`, `ProteinCalculator.total`.
- Produces:
  - `enum PlannedSlotState: Equatable { case eaten, skipped, upcoming }`
  - `enum DayTimelineRow: Identifiable, Equatable { case meal(FoodEntry), planned(MealSlot, PlannedSlotState) }` — `id`: entry id / slot id string.
  - `struct DaySummary: Equatable { let date: Date; let proteinG: Double; let goal: Int; let isGoalSnapshot: Bool; let eatenSlots: Int; let plannedSlots: Int; let rows: [DayTimelineRow] }`
  - `enum DayHistory { static func summary(for date: Date, log: DayLog, slots: [MealSlot], currentGoal: Int, now: Date, calendar: Calendar = .current) -> DaySummary }`
  - Rules: rows sorted by time (entry `date`; slot `date(on:)`); a planned row is emitted only for slots **not** eaten (eaten slots are represented by their meal rows; a slot eaten only via `completedSlots` with no entry gets `.planned(slot, .eaten)`); goal = `log.proteinGoalGrams` (snapshot) else `currentGoal` with `isGoalSnapshot == false`; for today, goal is always `currentGoal`.

- [ ] **Step 1: Write failing tests** (fixed calendar `Asia/Jerusalem`, slots 08:00 בוקר, 10:30 ביניים, 13:00 צהריים):
  - `test_big_breakfast_then_skipped_lunch`: entry at 08:10 slotName `בוקר`, now = same day 15:00 → rows: meal(בוקר), planned(ביניים, .skipped), planned(צהריים, .skipped); eatenSlots 1, plannedSlots 3.
  - `test_upcoming_today`: now 12:30 → צהריים `.upcoming`; ביניים (10:30, +60 = 11:30 < 12:30) `.skipped`.
  - `test_completed_slot_without_entry_counts_as_eaten`: `completedSlots` contains ביניים, no entry → `.planned(ביניים, .eaten)`, eatenSlots counts it.
  - `test_past_day_uses_snapshot_goal`: yesterday log with `proteinGoalGrams` 95, currentGoal 112 → goal 95, isGoalSnapshot true.
  - `test_past_day_without_snapshot_uses_current_goal`: → goal 112, isGoalSnapshot false.
  - `test_entry_with_unknown_slot_is_listed`: entry slotName `ארוחה ישנה` → present as `.meal`, no slot marked eaten by it.
  - `test_protein_counts_only_confirmed_and_manual`: one confirmed 20 g, one needsReview 30 g → proteinG 20.
- [ ] **Step 2: Run** focused → FAIL. **Step 3: Implement.** **Step 4: Run** focused + full → PASS.
- [ ] **Step 5: Commit** `feat(nutrition): day history model with planned-meal states`.

### Task 4: Bridge — context headers and advice

**Files:**
- Modify: `bridge/server.py` (`ANALYZE_PROMPT` schema line, `build_analyze_prompt`, `validate_analysis`, `_analyze`)
- Test: `bridge/test_server.py`

**Interfaces:**
- Produces (HTTP): `/analyze` accepts optional headers `X-Diet-Stage` (one of `preSurgery|liquid|puree|soft|regular|unknown`, else treated as `unknown`), `X-Protein-Eaten`, `X-Protein-Goal` (integers 0–1000, else ignored). Response gains `"advice": [str]` (≤3 items, each stripped, ≤140 chars, non-strings/empty dropped; missing → `[]`).
  - `def clean_context(headers) -> dict` (keys `stage`, `eaten`, `goal`; values validated).
  - `def build_analyze_prompt(image_path, cooking_note=None, context=None) -> str` — appends a context line and advice rules by concatenation (never `format` on header text).
- Advice rules text (in the prompt, English, answer in Hebrew): up to 3 short Hebrew tips to improve this meal for a patient at stage `<stage>` who has eaten `<eaten>` of `<goal>` g protein today: portion size for the stage (after surgery small portions, roughly 60–200 g); protein first; for stages before `regular` suggest postponing red meat, legumes, rice/bread/pasta; flag added sugar and fried/fatty food; what to add to reach the goal; before surgery frame tips as habits to practise; no medical diagnoses.

- [ ] **Step 1: Write failing tests:**
  - `test_context_headers_reach_prompt`: headers stage `soft`, eaten `40`, goal `112` → prompt contains `soft`, `40`, `112`.
  - `test_bad_context_headers_are_ignored`: stage `"{x}"`, eaten `"-5"`, goal `"abc"` → prompt contains `unknown`, no `{x}`, no `-5`.
  - `test_advice_is_returned`: runner output has `"advice": ["להתחיל מהחלבון"]` → response advice equals it.
  - `test_advice_is_trimmed_and_filtered`: advice of 10 items incl. `5`, `""`, a 2000-char string → ≤3 items, each ≤140 chars, all non-empty strings; status 200.
  - `test_missing_advice_defaults_to_empty`: → `"advice": []`.
- [ ] **Step 2: Run** Python suite → new tests FAIL. **Step 3: Implement.** **Step 4: Run** → all pass (existing 28 + new).
- [ ] **Step 5: Commit** `feat(bridge): meal context and improvement advice in analysis`.

### Task 5: App — advice in models, client and queue

**Files:**
- Modify: `BariatricHabits/Bridge/BridgeClient.swift`
- Modify: `BariatricHabits/Nutrition/FoodModels.swift` (`FoodEntry`)
- Modify: `BariatricHabits/Nutrition/AnalysisQueue.swift`
- Modify: `BariatricHabitsTests/BridgeClientTests.swift`, `BariatricHabitsTests/AnalysisQueueTests.swift` (FakeBridgeClient signature)

**Interfaces:**
- Consumes: Task 1 (`AppStore.proteinGoal`, `proteinToday`), `AppStore.dietStage(now:)`.
- Produces:
  - `struct AnalysisContext: Equatable { var stage: DietStage?; var proteinEatenG: Int; var proteinGoalG: Int }`
  - `AnalysisResult.advice: [String]` — custom `init(from:)` decoding `advice` with `decodeIfPresent ?? []` (old bridge).
  - `FoodEntry.advice: [String]? = nil`
  - `BridgeClienting.analyze(jpeg: Data, cookingNote: String?, context: AnalysisContext?) async throws -> AnalysisResult`; headers `X-Diet-Stage` (`stage?.rawValue ?? "unknown"`), `X-Protein-Eaten`, `X-Protein-Goal`.
  - `AnalysisQueue` builds the context per entry from the store at send time (eaten = `ProteinCalculator.total` of that entry's day excluding the entry itself; goal = `proteinGoal`) and stores `result.advice` (empty → nil) on success.

- [ ] **Step 1: Write failing tests:**
  - `test_analyze_sends_context_headers` (StubURLProtocol): context `(.soft, 40, 112)` → headers `soft`, `40`, `112`.
  - `test_analysis_result_without_advice_decodes`: JSON `{"items":[],"notes":""}` → `advice == []`.
  - `test_queue_stores_advice_and_sends_context` (FakeBridgeClient records context): result advice `["א"]` → entry `advice == ["א"]`; recorded context goal == `store.proteinGoal`.
- [ ] **Step 2: Run** focused → FAIL. **Step 3: Implement.** **Step 4: Run** focused + full → PASS.
- [ ] **Step 5: Commit** `feat(nutrition): send meal context and keep improvement advice`.

### Task 6: Reusable capture flow + Meal-tab photo + advice display

**Files:**
- Create: `BariatricHabits/Views/Nutrition/MealPhotoCapture.swift`
- Create: `BariatricHabits/Views/Nutrition/AdviceView.swift`
- Modify: `BariatricHabits/Views/Nutrition/NutritionView.swift` (replace its inline camera → cooking-note → entry code with the modifier)
- Modify: `BariatricHabits/Views/MealTimerView.swift` (button above `מתחילים` at ~line 110, meal card)
- Modify: `BariatricHabits/Views/Nutrition/MealReviewView.swift` (advice section)

**Interfaces:**
- Consumes: Task 5 (`FoodEntry.advice`), existing `CameraPicker`, `CookingNoteSheet`, `PhotoStore`, `AnalysisQueue.kick()`.
- Produces:
  - `extension View { func mealPhotoCapture(isPresented: Binding<Bool>, slotName: String?, onCreated: @escaping (UUID) -> Void) -> some View }` — camera → `CookingNoteSheet` → upsert `.pending` entry (today, given slotName) → `kick()` → `onCreated(entryID)`; identical behavior to today's Nutrition flow (swipe-dismiss of the note sheet = skip).
  - `struct AdviceView: View { let advice: [String] }` — renders bullets, badge `הצעת AI`, footer `המידע כללי ואינו מחליף את הדיאטנית.`; renders nothing for empty.

- [ ] **Step 1: Extract** the flow into `mealPhotoCapture`; switch `NutritionView` to it. Run the full suite → still green (no behavior change).
- [ ] **Step 2: Meal tab:** when the timer is idle show `Button("צלם את המנה", systemImage: "camera")` (prominent, above `מתחילים`), using `slotName: selectedSlot?.name`. Keep the created entry id in `@State`; while it exists show a card for that entry (live from the store): status label / items with grams / `+X גר' → Y/Z היום` / `AdviceView`; tapping opens `MealReviewView`. The timer start button stays enabled regardless of analysis status.
- [ ] **Step 3: MealReviewView:** add a section showing `AdviceView(advice: entry.advice ?? [])` above the items.
- [ ] **Step 4: Verify:** build + full suite green. Simulator (bridge not required): Meal tab → `צלם את המנה` → pick gallery photo → `איך הכנת?` → `דלג` → card shows `ממתין לזיהוי`; `מתחילים` still works. Screenshots.
- [ ] **Step 5: Commit** `feat(meal): photograph the dish from the meal timer with tips`.

### Task 7: History screen

**Files:**
- Create: `BariatricHabits/Views/Nutrition/HistoryView.swift`
- Modify: `BariatricHabits/Views/Nutrition/NutritionView.swift` (toolbar/list entry `היסטוריה`)

**Interfaces:**
- Consumes: Task 3 (`DayHistory.summary`), Task 6 (`AdviceView`), `FoodEntryRow` thumbnail pattern, `MealReviewView`, `AppStore.log(for:)`, `proteinGoal`.
- Produces: `struct HistoryView: View`.

- [ ] **Step 1: Build:** week strip (7 days, swipe/arrows to previous weeks, today marked) + `DatePicker` for jumping; summary card `X / Y גר' חלבון` (append `· יעד נוכחי` when `!isGoalSnapshot` on a past day) and `N/5 ארוחות`; timeline: meal rows (thumbnail, slot/time, items with grams, protein, cooking note, `AdviceView`), planned rows `דולגה` (orange text + icon, not color alone) / `בהמשך` / `סומנה כנאכלה`; tap a meal → `MealReviewView` (edit/delete allowed on any day); empty day → `אין ארוחות ביום הזה`.
- [ ] **Step 2: Verify:** build + suite green; simulator: Nutrition → `היסטוריה` → today and yesterday render; tapping a meal opens review. Screenshots.
- [ ] **Step 3: Commit** `feat(nutrition): day-by-day eating history`.

### Task 8: Ship

- [ ] **Step 1:** Full Swift + Python suites green.
- [ ] **Step 2:** Restart the bridge: `launchctl kickstart -k gui/$(id -u)/com.nirwo.bariatric-bridge`; `/health` → `{"status": "ok", "claude": true}`.
- [ ] **Step 3:** Build for device `00008150-00123D1E0AB9401C` (team `44MM5U2745`), install, `devicectl … process launch --terminate-existing`.
- [ ] **Step 4:** README: add rows for history, protein calculator, meal-tab photo.
- [ ] **Step 5:** Commit `docs: describe history, protein target and meal photo`.
