import SwiftUI

/// Settings section: manual protein goal, or one calculated from height and weight. For the dietitian to review.
struct ProteinTargetSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var heightText: String
    @State private var weightText: String
    @FocusState private var focus: MeasurementField?

    private enum MeasurementField: Hashable { case height, weight }

    private static let heightRange = 120.0...220.0
    private static let weightRange = 35.0...300.0
    private static let gramsPerKgStep = 0.1

    init(initial: ProteinTargetSettings) {
        _heightText = State(initialValue: initial.heightCm.map(formatGrams) ?? "")
        _weightText = State(initialValue: initial.weightKg.map(formatGrams) ?? "")
    }

    private var target: Binding<ProteinTargetSettings> { $store.state.settings.proteinTarget }

    private var gramsPerKg: Binding<Double> {
        Binding(
            get: { store.state.settings.proteinTarget.gramsPerKg },
            set: { store.state.settings.proteinTarget.gramsPerKg = ($0 * 10).rounded() / 10 }
        )
    }

    var body: some View {
        Section {
            Picker("אופן חישוב היעד", selection: target.mode) {
                Text("לפי משקל").tag(ProteinTargetMode.automatic)
                Text("ידני").tag(ProteinTargetMode.manual)
            }
            if store.state.settings.proteinTarget.mode == .manual {
                Stepper("יעד חלבון: \(store.state.settings.proteinGoalGrams) גר'",
                        value: $store.state.settings.proteinGoalGrams, in: 60...160, step: 5)
            } else {
                automaticRows
            }
        } footer: {
            if store.state.settings.proteinTarget.mode == .automatic {
                Text("הנוסחה לבדיקת הדיאטנית. מקור: ASMBS (עד 1.5 גר'/ק\"ג ממשקל אידיאלי), ERAS (לפחות 90 גר' אחרי מעקף).")
            }
        }
        .onChange(of: store.state.settings.proteinTarget) { _, _ in store.refreshTodayGoalSnapshot() }
        .onChange(of: store.state.settings.proteinGoalGrams) { _, _ in store.refreshTodayGoalSnapshot() }
        // Typing should replace the old number, not append to it.
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            guard let field = note.object as? UITextField, field.keyboardType == .decimalPad else { return }
            DispatchQueue.main.async { field.selectAll(nil) }
        }
    }

    @ViewBuilder private var automaticRows: some View {
        measurementRow(.height, title: "גובה (ס\"מ)", text: $heightText, range: Self.heightRange)
        measurementRow(.weight, title: "משקל (ק\"ג)", text: $weightText, range: Self.weightRange)
        Picker("בסיס", selection: target.basis) {
            Text("משקל מתוקנן").tag(ProteinWeightBasis.adjusted)
            Text("משקל אידיאלי").tag(ProteinWeightBasis.ideal)
        }
        if store.state.settings.proteinTarget.basis == .adjusted {
            Picker("מקדם תיקון", selection: target.adjustmentFactor) {
                Text("0.25").tag(0.25)
                Text("0.4").tag(0.4)
            }
        }
        Stepper("גר' חלבון לק\"ג: \(formatGrams(store.state.settings.proteinTarget.gramsPerKg))",
                value: gramsPerKg, in: 1.0...2.1, step: Self.gramsPerKgStep)
        Stepper("מינימום יומי: \(store.state.settings.proteinTarget.floorGrams) גר'",
                value: target.floorGrams, in: 60...120, step: 5)
        Text(resultText)
            .font(.subheadline.bold())
            .accessibilityLabel(resultText)
    }

    private func measurementRow(_ field: MeasurementField, title: String, text: Binding<String>,
                                range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focus, equals: field)
                // While typing, only values already in range are stored; partial input like "1" is ignored.
                .onChange(of: text.wrappedValue) { _, newText in
                    guard let value = parseDecimal(newText), range.contains(value) else { return }
                    store(value, for: field)
                }
        }
        .onChange(of: focus) { oldFocus, newFocus in
            if oldFocus == field && newFocus != field { commit(field, text: text, range: range) }
        }
    }

    /// On focus loss: clamp, store once, and show the stored value (an empty or invalid field restores it).
    private func commit(_ field: MeasurementField, text: Binding<String>, range: ClosedRange<Double>) {
        if let value = parseDecimal(text.wrappedValue) {
            store(min(max(value, range.lowerBound), range.upperBound), for: field)
        }
        let stored = field == .height ? store.state.settings.proteinTarget.heightCm
                                      : store.state.settings.proteinTarget.weightKg
        text.wrappedValue = stored.map(formatGrams) ?? ""
    }

    private func store(_ value: Double, for field: MeasurementField) {
        switch field {
        case .height:
            guard value != store.state.settings.proteinTarget.heightCm else { return }
            store.state.settings.proteinTarget.heightCm = value
        case .weight:
            guard value != store.state.settings.proteinTarget.weightKg else { return }
            store.state.settings.proteinTarget.weightKg = value
            store.state.settings.proteinTarget.weightUpdated = Date()
        }
    }

    private var resultText: String {
        let settings = store.state.settings.proteinTarget
        guard let result = ProteinTarget.calculate(settings) else { return "הזינו גובה ומשקל" }
        let ideal = "אידיאלי \(formatGrams(result.idealKg)) ק\"ג"
        let basis = settings.basis == .adjusted ? " · מתוקנן \(formatGrams(result.basisKg)) ק\"ג" : ""
        return "\(ideal)\(basis) × \(formatGrams(settings.gramsPerKg)) = \(result.grams) גר'"
    }
}
