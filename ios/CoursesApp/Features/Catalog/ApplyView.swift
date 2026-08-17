import SwiftUI

/// Заявка на потік — замість переходу в Google Forms.
/// Оплату застосунок не обробляє: тут лише контакт і статус, за яким веде викладач.
struct ApplyView: View {
    let stream: StreamDetail
    let existing: Application?
    let onDone: () async -> Void

    @Environment(\.repository) private var repo
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var contact: String
    @State private var comment: String
    @State private var saving = false
    @State private var error: String?

    init(stream: StreamDetail, existing: Application?, onDone: @escaping () async -> Void) {
        self.stream = stream
        self.existing = existing
        self.onDone = onDone
        _name = State(initialValue: existing?.name ?? "")
        // Якщо людина вже входила через Google — підставляємо той email, щоб не набирати.
        _contact = State(
            initialValue: existing?.contact
                ?? UserDefaults.standard.string(forKey: "display_email") ?? "")
        _comment = State(initialValue: existing?.comment ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(stream.title) {
                    if let date = stream.startDate {
                        Text("старт \(Fmt.day(date))").font(.caption).foregroundStyle(.secondary)
                    }
                    if let price = Fmt.price(stream.priceFull, perSession: stream.pricePerSession) {
                        Text(price).font(.subheadline.weight(.medium))
                    }
                }

                Section {
                    TextField("Імʼя", text: $name)
                    TextField("Email або телеграм", text: $contact)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Питання чи побажання (не обовʼязково)", text: $comment, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("Викладач звʼяжеться з вами й підтвердить участь. "
                         + "Оплата — поза застосунком, як і раніше.")
                }

                Section {
                    if saving {
                        ProgressView()
                    } else {
                        Button(existing == nil ? "Надіслати заявку" : "Оновити заявку") {
                            Task { await submit() }
                        }
                        .disabled(name.isEmpty || contact.count < 3)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Записатися")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
            }
        }
    }

    private func submit() async {
        saving = true
        defer { saving = false }
        do {
            try await repo.apply(
                streamId: stream.id, name: name, contact: contact,
                comment: comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : comment)
            await onDone()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Заявки на потік очима викладача: контакти, коментарі й статус.
struct ApplicationsView: View {
    let streamId: String
    @Environment(\.repository) private var repo
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Application] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                if loaded && items.isEmpty {
                    Text("Заявок поки немає.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(items) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name).font(.subheadline.weight(.medium))
                        Text(app.contact).font(.caption).foregroundStyle(.secondary)
                        if let comment = app.comment, !comment.isEmpty {
                            Text(comment).font(.caption).foregroundStyle(.secondary)
                        }
                        Picker("Статус", selection: Binding(
                            get: { app.status },
                            set: { newStatus in
                                Task {
                                    try? await repo.setApplicationStatus(id: app.id, status: newStatus)
                                    await load()
                                }
                            })) {
                            Text("нова").tag(ApplicationStatus.new)
                            Text("очікує оплати").tag(ApplicationStatus.waitingPayment)
                            Text("зараховано").tag(ApplicationStatus.enrolled)
                            Text("відхилено").tag(ApplicationStatus.declined)
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Заявки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func load() async {
        items = (try? await repo.applications(streamId: streamId)) ?? []
        loaded = true
    }
}
