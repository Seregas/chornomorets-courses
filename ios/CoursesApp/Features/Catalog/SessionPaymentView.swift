import PhotosUI
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
    /// Прочитане зі скріншота — заповнює поля й показує розбіжності.
    var facts: ReceiptFacts?
    var problems: [String] = []
    var uploading = false

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

extension SessionPaymentViewModel {
    /// Розпізнає скріншот на пристрої, підставляє суму й одразу відправляє файл.
    ///
    /// Порядок саме такий: спершу заявка (щоб було до чого чіпляти), далі
    /// картинка. Розпізнавання не є доказом оплати — воно лише прибирає ручне
    /// набирання й показує викладачу, де числа не збіглися.
    @MainActor
    func attach(_ repo: CourseRepository, image: UIImage, session: CourseSession,
                expected: Int?, isAdmin: Bool) async {
        uploading = true
        defer { uploading = false }

        let read = await ReceiptScanner.scan(image)
        facts = read
        problems = ReceiptScanner.matches(
            read, expectedAmount: expected, sessionDate: Fmt.date(session.startAt))
        if amount.isEmpty, let found = read.amount { amount = String(found) }

        do {
            if mine == nil {
                try await repo.declarePayment(
                    sessionId: session.id, amount: Int(amount) ?? read.amount,
                    receiptURL: nil, note: note.isEmpty ? nil : note)
                mine = try? await repo.payment(sessionId: session.id)
            }
            guard let paymentId = mine?.id,
                  let data = image.jpegData(compressionQuality: 0.8) else { return }
            mine = try await repo.uploadReceipt(paymentId: paymentId, image: data, facts: read)
            if isAdmin { all = (try? await repo.payments(sessionId: session.id)) ?? [] }
        } catch {
            self.error = error.localizedDescription
        }
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
    @State private var picked: PhotosPickerItem?

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
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await vm.attach(repo, image: image, session: session,
                                expected: suggestedAmount, isAdmin: auth.isAdmin)
            }
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
            PhotosPicker(selection: $picked, matching: .images) {
                Label(vm.mine?.hasReceiptImage == true ? "Замінити скріншот" : "Додати скріншот",
                      systemImage: "photo.badge.plus")
            }
            if vm.uploading { ProgressView() }
            if let facts = vm.facts, !facts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if let a = facts.amount { Text("Прочитано: \(a) ₴").font(.caption) }
                    if let d = facts.date { Text("Дата: \(d)").font(.caption) }
                    ForEach(vm.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            TextField("Або посилання на квитанцію", text: $vm.receipt)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Коментар (не обовʼязково)", text: $vm.note, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Ваша оплата")
        } footer: {
            Text("Скріншот читається на вашому телефоні — сума й дата підставляються самі. "
                 + "Викладач звірить із випискою й підтвердить.")
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

    private func decodeFacts(_ raw: String) -> ReceiptFacts? {
        try? JSONDecoder().decode(ReceiptFacts.self, from: Data(raw.utf8))
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
                        Text(payment.authorEmail ?? payment.accountId ?? "—")
                            .font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(payment.amount.map { "\($0) ₴" } ?? "—")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let note = payment.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    if payment.hasReceiptImage, let url = repo.receiptURL(paymentId: payment.id) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit().frame(maxHeight: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } placeholder: {
                            ProgressView()
                        }
                    } else if let receipt = payment.receiptURL, let url = URL(string: receipt) {
                        Button("Квитанція") { openURL(url) }.font(.caption)
                    }
                    if let parsed = payment.receiptParsed, let read = decodeFacts(parsed) {
                        Text("Прочитано: \(read.amount.map { "\($0) ₴" } ?? "—")"
                             + (read.date.map { " · \($0)" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
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
