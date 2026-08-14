import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    var subscriptions: [ResolvedStream] = []

    func load(_ repo: CourseRepository) async {
        subscriptions = (try? await repo.subscriptions()) ?? []
    }

    func unsubscribe(_ repo: CourseRepository, notifications: NotificationScheduler, stream: ResolvedStream) async {
        try? await repo.unsubscribe(streamId: stream.id)
        notifications.cancelReminders(streamId: stream.id)
        subscriptions.removeAll { $0.id == stream.id }
    }
}

struct SettingsView: View {
    @Environment(\.repository) private var repo
    @Environment(\.notifications) private var notifications
    @Environment(AuthStore.self) private var auth
    @State private var vm = SettingsViewModel()
    @State private var showConnect = false
    @State private var google = GoogleSignInService()
    @State private var googleError: String?

    @AppStorage("reminders_enabled") private var remindersEnabled = true
    @AppStorage("reminder_lead") private var reminderLead = 30
    @AppStorage("api_base_url") private var apiBaseURL = ""

    var body: some View {
        NavigationStack {
            Form {
                googleSection
                if auth.isAdmin { adminSection }
                coursesSection
                remindersSection
                downloadsSection
                devSection
            }
            .navigationTitle("Налаштування")
            .sheet(isPresented: $showConnect) {
                ConnectGoogleSheet { email in
                    auth.connectDev(email: email)
                    await auth.refreshAdmin(using: repo)
                }
            }
        }
        .task { await vm.load(repo) }
    }

    private var googleSection: some View {
        Section("Google-акаунт") {
            if let email = auth.email {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(email).font(.subheadline.weight(.medium))
                        Label("доступ до відео активний", systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                    Button("Вийти", role: .destructive) {
                        google.signOut()
                        auth.disconnect()
                    }
                    .font(.subheadline)
                }
            } else if GoogleAuthConfig.isConfigured {
                Button { Task { await signInWithGoogle() } } label: {
                    Label("Увійти через Google", systemImage: "person.crop.circle.badge.plus")
                }
            } else {
                Button { showConnect = true } label: {
                    Label("Підключити (dev: email)", systemImage: "person.crop.circle.badge.plus")
                }
            }
            if let googleError {
                Text(googleError).font(.caption).foregroundStyle(.red)
            }
            Text("Потрібен, щоб відкривати відео з обмеженим доступом.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func signInWithGoogle() async {
        googleError = nil
        do {
            let s = try await google.signIn()
            auth.connectGoogle(email: s.email, idToken: s.idToken, accessToken: s.accessToken)
            await auth.refreshAdmin(using: repo)
        } catch is CancellationError {
            // користувач скасував — мовчки
        } catch {
            googleError = error.localizedDescription
        }
    }

    private var adminSection: some View {
        Section("Адміністрування") {
            NavigationLink {
                MaterialTypesView()
            } label: {
                Label("Типи матеріалів", systemImage: "tag")
            }
            Text("Курси, потоки, заняття й матеріали редагуються прямо на їхніх сторінках.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var coursesSection: some View {
        Section("Мої курси") {
            if vm.subscriptions.isEmpty {
                Text("Ви ще не підписані на жоден потік.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(vm.subscriptions) { stream in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stream.title).font(.subheadline.weight(.medium))
                            Text(Fmt.statusLabel(stream.status)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Відписатися", role: .destructive) {
                            Task { await vm.unsubscribe(repo, notifications: notifications, stream: stream) }
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var remindersSection: some View {
        Section("Нагадування") {
            Toggle("Нагадувати про заняття", isOn: $remindersEnabled)
            Picker("За скільки до початку", selection: $reminderLead) {
                ForEach([10, 15, 30, 60], id: \.self) { Text("\($0) хв").tag($0) }
            }
        }
    }

    private var downloadsSection: some View {
        Section("Завантаження") {
            HStack {
                Text("Завантажені відео")
                Spacer()
                Text("скоро (Фаза 2)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var devSection: some View {
        Section {
            TextField("http://192.168.0.50:3000", text: $apiBaseURL)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        } header: {
            Text("Сервер (розробка)")
        } footer: {
            Text("Адреса API. На реальному телефоні вкажіть IP вашого Mac у локальній мережі. "
                 + "Порожнє = http://localhost:3000. Після зміни перезапустіть застосунок.")
        }
    }
}

/// Прототип-заглушка Google-входу: вводимо email (== токен у dev-режимі бекенду).
/// Прод: тут запускається ASWebAuthenticationSession з реальним OAuth.
struct ConnectGoogleSheet: View {
    let onConnect: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("you@gmail.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Google-акаунт")
                } footer: {
                    Text("Прототип: вводимо email напряму. У релізі тут буде вхід через Google (OAuth).")
                }
            }
            .navigationTitle("Підключити Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Підключити") {
                        Task { await onConnect(email); dismiss() }
                    }
                    .disabled(!email.contains("@"))
                }
            }
        }
    }
}

#Preview {
    SettingsView().injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
                             auth: AuthStore())
}
