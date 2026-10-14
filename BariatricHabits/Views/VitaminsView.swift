import SwiftUI

struct VitaminsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: Vitamin?

    var body: some View {
        NavigationStack {
            List {
                let taken = store.today.vitaminsTaken
                Section {
                    ForEach(store.sortedVitamins) { vitamin in
                        HStack(spacing: 12) {
                            Button {
                                store.toggleVitamin(vitamin.id)
                            } label: {
                                Image(systemName: taken.contains(vitamin.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(taken.contains(vitamin.id) ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.borderless)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(vitamin.name).font(.headline)
                                if !vitamin.dose.isEmpty {
                                    Text(vitamin.dose).font(.subheadline)
                                }
                                if !vitamin.note.isEmpty {
                                    Text(vitamin.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(vitamin.timeText).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = vitamin }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.sortedVitamins[$0].id }
                        store.state.vitamins.removeAll { ids.contains($0.id) }
                    }
                } header: {
                    Text("היום: \(store.sortedVitamins.filter { taken.contains($0.id) }.count) מתוך \(store.state.vitamins.count)")
                } footer: {
                    Text("לחיצה על העיגול מסמנת שנלקח. לחיצה על השורה לעריכה. הרשימה ההתחלתית היא דוגמה — יש לעדכן לפי ההמלצה האישית של הדיאטנית.")
                }

                Section("חשוב לזכור") {
                    Label("אחרי מיני מעקף לוקחים תוספים לכל החיים", systemImage: "infinity")
                    Label("סידן וברזל — בהפרדה של שעתיים לפחות", systemImage: "arrow.left.arrow.right")
                    Label("בדיקות דם תקופתיות לפי הנחיית הצוות", systemImage: "cross.vial")
                }
                .font(.subheadline)
            }
            .navigationTitle("ויטמינים")
            .toolbar {
                Button {
                    editing = Vitamin(name: "", dose: "", hour: 9, minute: 0, note: "")
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(item: $editing) { vitamin in
                VitaminEditor(vitamin: vitamin) { saved in
                    if let index = store.state.vitamins.firstIndex(where: { $0.id == saved.id }) {
                        store.state.vitamins[index] = saved
                    } else {
                        store.state.vitamins.append(saved)
                    }
                }
            }
        }
    }
}

struct VitaminEditor: View {
    @State var vitamin: Vitamin
    var onSave: (Vitamin) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("שם (למשל: ויטמין B12)", text: $vitamin.name)
                TextField("מינון (לפי הדיאטנית)", text: $vitamin.dose)
                DatePicker("שעה", selection: timeBinding($vitamin.hour, $vitamin.minute), displayedComponents: .hourAndMinute)
                TextField("הערה", text: $vitamin.note, axis: .vertical)
            }
            .navigationTitle(vitamin.name.isEmpty ? "תוסף חדש" : vitamin.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        onSave(vitamin)
                        dismiss()
                    }
                    .disabled(vitamin.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Binds a DatePicker (hour & minute) to separate Int fields.
func timeBinding(_ hour: Binding<Int>, _ minute: Binding<Int>) -> Binding<Date> {
    Binding(
        get: { Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: Date()) ?? Date() },
        set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            hour.wrappedValue = c.hour ?? 0
            minute.wrappedValue = c.minute ?? 0
        }
    )
}
