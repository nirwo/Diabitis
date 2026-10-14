import SwiftUI

/// Quick choices plus free text, joined into one note such as "מטוגן בשמן, בכף שמן זית".
struct CookingNoteDraft: Equatable {
    static let options = ["מבושל", "אפוי בתנור", "מטוגן בשמן", "צלוי/גריל", "מאודה", "טרי/לא מבושל"]
    static let maxLength = 200
    private static let separator = ", "

    private var selected: Set<String> = []
    var text = ""

    /// Parts of an existing note that exactly match a choice become chips; the rest stays text.
    init(note: String?) {
        guard let note else { return }
        var rest: [String] = []
        for part in note.components(separatedBy: Self.separator) {
            if Self.options.contains(part) { selected.insert(part) } else { rest.append(part) }
        }
        text = rest.joined(separator: Self.separator)
    }

    func isSelected(_ option: String) -> Bool { selected.contains(option) }

    mutating func toggle(_ option: String) {
        if selected.remove(option) == nil { selected.insert(option) }
    }

    /// Trimmed, at most 200 characters; nil when nothing was chosen or typed.
    var note: String? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = Self.options.filter(selected.contains) + (typed.isEmpty ? [] : [typed])
        let joined = String(parts.joined(separator: Self.separator).prefix(Self.maxLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}

/// Shared by the capture sheet and the review screen.
struct CookingNoteEditor: View {
    @Binding var draft: CookingNoteDraft
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CookingNoteDraft.options, id: \.self) { option in
                    chip(option)
                }
            }
            TextField("למשל: בכף שמן זית, עם רוטב עגבניות", text: $draft.text, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func chip(_ option: String) -> some View {
        let isOn = draft.isSelected(option)
        return Button { draft.toggle(option) } label: {
            Text(option)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 6)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                .contentShape(Capsule())
        }
        // Plain style keeps each chip its own tap target inside a Form row.
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Asked right after a meal photo, before it is queued for analysis.
struct CookingNoteSheet: View {
    var onFinish: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CookingNoteDraft(note: nil)

    var body: some View {
        NavigationStack {
            ScrollView {
                CookingNoteEditor(draft: $draft).padding()
            }
            .navigationTitle("איך הכנת?")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { finish(with: nil) } label: { Text("דלג").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    Button { finish(with: draft.note) } label: { Text("המשך").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func finish(with note: String?) {
        onFinish(note)
        dismiss()
    }
}
