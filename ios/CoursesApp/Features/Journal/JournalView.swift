import SwiftUI

/// Щоденник практик: чек-ін стану за тиждень і власні нотатки.
/// Усе локально — записи не залишають пристрій.
struct JournalView: View {
    @State private var journal = PracticeJournal.shared
    @State private var draft = ""
    @State private var reminderOn = JournalReminder.hour != nil
    @FocusState private var writing: Bool

    var body: some View {
        List {
            weekSection
            todaySection
            noteSection
            entriesSection
            settingsSection
        }
        .navigationTitle("Щоденник")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Тиждень

    private var weekSection: some View {
        Section("Енергія за тиждень") {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(journal.lastWeekEnergy, id: \.day) { day, energy in
                    VStack(spacing: 6) {
                        // Порожній день лишається порожнім стовпчиком: пропуск —
                        // теж інформація, підмальовувати його нулем нечесно.
                        RoundedRectangle(cornerRadius: 4)
                            .fill(energy == nil ? Color.secondary.opacity(0.15) : Color.sea)
                            .frame(width: 22, height: CGFloat(energy ?? 1) * 14)
                        Text(shortDay(day)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)
            .padding(.vertical, 6)
        }
    }

    private func shortDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "uk_UA")
        f.dateFormat = "EE"
        return f.string(from: date)
    }

    // MARK: - Чек-ін

    private var todaySection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        journal.checkIn(energy: level)
                    } label: {
                        Text("\(level)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                (journal.todayCheckIn?.energy ?? 0) == level
                                    ? Color.sea : Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(
                                (journal.todayCheckIn?.energy ?? 0) == level ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Як сьогодні з енергією?")
        } footer: {
            Text(journal.todayCheckIn == nil
                 ? "1 — на нулі, 5 — повний бак."
                 : "Записано. Можна змінити — за день лишається одна оцінка.")
        }
    }

    // MARK: - Нотатка

    private var noteSection: some View {
        Section {
            TextField("Що помітили сьогодні?", text: $draft, axis: .vertical)
                .lineLimit(2...6)
                .focused($writing)
            Button("Записати") {
                journal.addNote(draft)
                draft = ""
                writing = false
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Нотатка")
        } footer: {
            Text("Записи зберігаються лише на цьому пристрої — ні викладач, ні сервер їх не бачать.")
        }
    }

    @ViewBuilder private var entriesSection: some View {
        if !journal.entries.isEmpty {
            Section("Записи") {
                ForEach(journal.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if let energy = entry.energy {
                                Text("енергія \(energy)/5")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.sea.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color.sea)
                            }
                            Text(Fmt.dayTime(ISO8601DateFormatter().string(from: entry.createdAt)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if !entry.text.isEmpty {
                            Text(entry.text).font(.subheadline)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { journal.delete(entry) } label: {
                            Label("Видалити", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        Section {
            Toggle("Нагадувати ввечері", isOn: $reminderOn)
                .onChange(of: reminderOn) { _, on in
                    JournalReminder.hour = on ? 21 : nil
                }
        } footer: {
            Text("Щодня о 21:00 нагадаємо зробити чек-ін.")
        }
    }
}

#Preview {
    NavigationStack { JournalView() }
}
