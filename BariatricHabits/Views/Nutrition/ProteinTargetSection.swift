import SwiftUI

/// Settings section: manual protein goal, or one calculated from height and weight. For the dietitian to review.
struct ProteinTargetSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var heightText: String
    @State private var weightText: String

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
        measurementRow(title: "גובה (ס\"מ)", text: $heightText, range: Self.heightRange) { value in
            store.state.settings.proteinTarget.heightCm = value
        }
        measurementRow(title: "משקל (ק\"ג)", text: $weightText, range: Self.weightRange) { value in
            store.state.settings.proteinTarget.weightKg = value
            store.state.settings.proteinTarget.weightUpdated = Date()
        }
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

    private func measurementRow(title: String, text: Binding<String>, range: ClosedRange<Double>,
                                apply: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text.wrappedValue) { _, newText in
                    guard let value = parseDecimal(newText) else { return }
                    apply(min(max(value, range.lowerBound), range.upperBound))
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in
            normalize()
        }
    }

    /// Shows the stored, clamped values once editing ends.
    private func normalize() {
        let stored = store.state.settings.proteinTarget
        heightText = stored.heightCm.map(formatGrams) ?? ""
        weightText = stored.weightKg.map(formatGrams) ?? ""
    }

    private var resultText: String {
        let settings = store.state.settings.proteinTarget
        guard let result = ProteinTarget.calculate(settings) else { return "הזינו גובה ומשקל" }
        let ideal = "אידיאלי \(formatGrams(result.idealKg)) ק\"ג"
        let basis = settings.basis == .adjusted ? " · מתוקנן \(formatGrams(result.basisKg)) ק\"ג" : ""
        return "\(ideal)\(basis) × \(formatGrams(settings.gramsPerKg)) = \(result.grams) גר'"
    }
}
