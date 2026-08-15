import GoogleSignIn
import SwiftUI

@main
struct CoursesApp: App {
    @State private var auth = AuthStore()
    private let env = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .injecting(env, auth: auth)
                .tint(.sea)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task {
                    // Відновити попередній Google-вхід (якщо налаштований реальний клієнт).
                    if GoogleAuthConfig.isConfigured, let s = await GoogleSignInService().restore() {
                        auth.connectGoogle(email: s.email, idToken: s.idToken, accessToken: s.accessToken)
                    }
                    if ProcessInfo.processInfo.environment["SKIP_NOTIF_PROMPT"] == nil {
                        await env.notifications.requestAuthorization()
                    }
                    await auth.refreshAdmin(using: env.repository)
                    // Звірити нагадування з розкладом на старті: вкладку «Розклад»
                    // могли й не відкривати, а заняття тим часом перенесли.
                    if let items = try? await env.repository.schedule() {
                        await env.notifications.sync(with: items)
                        WidgetSync.update(nextSession: items.first)
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @State private var offline = OfflineStatus.shared
    // Стартова вкладка (для демо/скриншотів через env START_TAB=0|1|2|3).
    // За замовчуванням «Навчання»: у нього ж вбудований порожній стан, який
    // веде новачка в каталог, тож окремої перевірки підписок на старті не треба.
    @State private var selection = Int(ProcessInfo.processInfo.environment["START_TAB"] ?? "0") ?? 0

    var body: some View {
        VStack(spacing: 0) {
            offlineBanner
            tabs
        }
    }

    /// Показані дані можуть бути вчорашніми — про це чесніше сказати одним
    /// рядком угорі, ніж малювати позначку на кожному екрані.
    @ViewBuilder private var offlineBanner: some View {
        if let since = offline.servingFromCacheSince {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                Text("Немає звʼязку · дані від \(Fmt.dayTime(ISO8601DateFormatter().string(from: since)))")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            HomeView(openCatalog: { selection = 2 })
                .tabItem { Label("Навчання", systemImage: "graduationcap") }.tag(0)
            ScheduleView()
                .tabItem { Label("Розклад", systemImage: "calendar") }.tag(1)
            CatalogView()
                .tabItem { Label("Курси", systemImage: "book") }.tag(2)
            SettingsView()
                .tabItem { Label("Налаштування", systemImage: "gearshape") }.tag(3)
        }
    }
}

#Preview {
    RootView().injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
                         auth: AuthStore())
}
