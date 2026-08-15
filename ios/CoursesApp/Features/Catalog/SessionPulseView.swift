import SwiftUI

@MainActor
@Observable
final class SessionPulseViewModel {
    var rating = 0
    var comment = ""
    var existing: Pulse?
    var summary: PulseSummary?
    var saving = false
    var saved = false
    var error: String?

    func load(_ repo: CourseRepository, sessionId: String, isAdmin: Bool) async {
        existing = try? await repo.pulse(sessionId: sessionId)
        if let existing {
            rating = existing.rating
            comment = existing.comment ?? ""
            saved = true
        }
        if isAdmin { summary = try? await repo.pulseSummary(sessionId: sessionId) }
    }

    func send(_ repo: CourseRepository, sessionId: String, isAdmin: Bool) async {
        guard rating > 0 else { return }
        saving = true
        defer { saving = false }
        do {
            try await repo.ratePulse(
                sessionId: sessionId, rating: rating,
                comment: comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : comment)
            saved = true
            await load(repo, sessionId: sessionId, isAdmin: isAdmin)
        } catch { self.error = error.localizedDescription }
    }
}

/// «Як зайшло заняття» — оцінка 1–5 і необовʼязковий коментар.
/// Викладачу це зворотний звʼязок, студенту — хвилина рефлексії.
struct SessionPulseView: View {
    let session: CourseSession
    @Environment(\.repository) private var repo
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var vm = SessionPulseViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section(session.title) {
                    Text(Fmt.dayTime(session.startAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
                rateSection
                if auth.isAdmin, let summary = vm.summary { summarySection(summary) }
            }
            .navigationTitle("Як зайшло?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
        .task { await vm.load(repo, sessionId: session.id, isAdmin: auth.isAdmin) }
    }

    private var rateSection: some View {
        Section {
            HStack(spacing: 10) {
                Spacer()
                ForEach(1...5, id: \.self) { star in
                    Button {
                        vm.rating = star
                    } label: {
                        Image(systemName: star <= vm.rating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(star <= vm.rating ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            TextField("Що допомогло, а що ні? (не обовʼязково)", text: $vm.comment, axis: .vertical)
                .lineLimit(2...6)

            if vm.saving {
                ProgressView()
            } else {
                Button(vm.existing == nil ? "Надіслати" : "Оновити оцінку") {
                    Task { await vm.send(repo, sessionId: session.id, isAdmin: auth.isAdmin) }
                }
                .disabled(vm.rating == 0)
            }
            if let error = vm.error { Text(error).font(.caption).foregroundStyle(.red) }
        } header: {
            Text("Ваша оцінка")
        } footer: {
            Text(vm.saved
                 ? "Дякуємо. Оцінку можна змінити — збережеться остання."
                 : "Оцінку бачить лише викладач, і без імені.")
        }
    }

    private func summarySection(_ s: PulseSummary) -> some View {
        Section("Відгуки (\(s.count))") {
            if s.count == 0 {
                Text("Поки ніхто не оцінив.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(String(format: "%.1f", s.average))
                        .font(.title2.bold()).foregroundStyle(.orange)
                    Text("середня").font(.caption).foregroundStyle(.secondary)
                }
                // Гістограма зверху вниз: «5 зірок» першими — так читається швидше.
                ForEach(Array(s.histogram.enumerated()).reversed(), id: \.offset) { index, count in
                    HStack(spacing: 8) {
                        Text("\(index + 1)★").font(.caption).frame(width: 28, alignment: .leading)
                        ProgressView(value: s.count > 0 ? Double(count) / Double(s.count) : 0)
                            .tint(.orange)
                        Text("\(count)").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
                ForEach(Array(s.comments.enumerated()), id: \.offset) { _, comment in
                    Text(comment).font(.subheadline)
                }
            }
        }
    }
}

#Preview {
    SessionPulseView(session: CourseSession(
        id: "ses-s4-1", streamId: "s-stress-4", title: "Заняття 1",
        startAt: "2026-04-08T17:00:00Z", durationMinutes: 120, format: .online,
        joinURL: nil, paymentStatus: .paid, order: 1))
    .injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
               auth: AuthStore())
}
