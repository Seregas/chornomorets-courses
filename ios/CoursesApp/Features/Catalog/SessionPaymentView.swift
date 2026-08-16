import SwiftUI

@MainActor
@Observable
final class SessionPaymentViewModel {
    var mine: Payment?
    var all: [Payment] = []
    var amount = ""
    var receipt = ""
    var note = ""
    var saving = false
    var loaded = false
    var error: String?

    func load(_ repo: CourseRepository, sessionId: String, isAdmin: Bool) async {
        mine = try? await repo.payment(sessionId: sessionId)
        if let mine {
            amount = mine.amount.map(String.init) ?? ""
            receipt = mine.receiptURL ?? ""
            note = mine.note ?? ""
        }
        if isAdmin { all = (try? await repo.payments(sessionId: sessionId)) ?? [] }
        loaded = true
    }

    func declare(_ repo: CourseRepository, sessionId: String, isAdmin: Bool) async {
        saving = true
        defer { saving = false }
        do {
            try await repo.declarePayment(
                sessionId: sessionId,
                amount: Int(amount),
                receiptURL: receipt.trimmingCharacters(in: .whitespaces).isEmpty ? nil : receipt,
                note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note)
            await load(repo, sessionId: sessionId, isAdmin: isAdmin)
        } catch { self.error = error.localizedDescription }
    }
}

/// Оплата за конкретне заняття конкретною людиною.
///
/// Гроші приходять на картку поза застосунком, тож застосунок лише веде облік:
/// студент каже «оплатив» і лишає квитанцію, викладач звіряє з випискою й
/// підтверджує. Автоматичного звіряння немає й не планується.
struct SessionPaymentView: View {
    let session: CourseSession
    /// Ціна за заняття з потоку — щоб не змушувати згадувати суму.
    let suggestedAmount: Int?

    @Environment(\.repository) private var repo
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var vm = SessionPaymentViewModel()

    var body: some View {
        NavigationStack {
            Form {
                if auth.isAdmin { adminSection }
                mySection
            }
            .navigationTitle("Оплата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
        .task {
            await vm.load(repo, sessionId: session.id, isAdmin: auth.isAdmin)
            if vm.amount.isEmpty, let suggestedAmount { vm.amount = String(suggestedAmount) }
        }
    }

    // MARK: - Студент

    @ViewBuilder private var mySection: some View {
        Section {
            if let mine = vm.mine {
                HStack {
                    Text("Стан")
                    Spacer()
                    Text(mine.status.label).foregroundStyle(.secondary)
                }
            }
            TextField("Сума, ₴", text: $vm.amount).keyboardType(.numberPad)
            TextField("Посилання на квитанцію", text: $vm.receipt)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Коментар (не обовʼязково)", text: $vm.note, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Ваша оплата")
        } footer: {
            Text("Скріншот поки що не завантажується — покладіть його в Drive чи "
                 + "Телеграм і вставте посилання. Викладач звірить із випискою й підтвердить.")
        }

        Section {
            if vm.saving {
                ProgressView()
            } else if vm.mine?.status == .confirmed || vm.mine?.status == .free {
                Label("Підтверджено — змінювати нічого не треба", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.subheadline)
            } else {
                Button(vm.mine == nil ? "Я оплатив" : "Оновити заявку") {
                    Task { await vm.declare(repo, sessionId: session.id, isAdmin: auth.isAdmin) }
                }
                .disabled(Int(vm.amount) == nil)
            }
            if let error = vm.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    // MARK: - Викладач

    @ViewBuilder private var adminSection: some View {
        Section("Заявки (\(vm.all.count))") {
            if vm.loaded && vm.all.isEmpty {
                Text("Поки ніхто не заявляв оплату.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(vm.all) { payment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(payment.authorEmail ?? payment.deviceId ?? "—")
                            .font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(payment.amount.map { "\($0) ₴" } ?? "—")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let note = payment.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    if let receipt = payment.receiptURL, let url = URL(string: receipt) {
                        Button("Квитанція") { openURL(url) }.font(.caption)
                    }
                    Picker("Стан", selection: Binding(
                        get: { payment.status },
                        set: { newStatus in
                            Task {
                                try? await repo.setPaymentStatus(id: payment.id, status: newStatus)
                                await vm.load(repo, sessionId: session.id, isAdmin: true)
                            }
                        })) {
                        Text("заявлено").tag(PaymentStatus.declared)
                        Text("підтверджено").tag(PaymentStatus.confirmed)
                        Text("безкоштовно").tag(PaymentStatus.free)
                        Text("відхилено").tag(PaymentStatus.rejected)
                    }
                    .pickerStyle(.menu)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
