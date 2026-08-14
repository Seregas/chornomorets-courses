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
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var auth
    // Стартова вкладка (для демо/скриншотів через env START_TAB=0|1|2).
    @State private var selection = Int(ProcessInfo.processInfo.environment["START_TAB"] ?? "1") ?? 1

    var body: some View {
        TabView(selection: $selection) {
            ScheduleView()
                .tabItem { Label("Розклад", systemImage: "calendar") }.tag(0)
            CatalogView()
                .tabItem { Label("Курси", systemImage: "book") }.tag(1)
            SettingsView()
                .tabItem { Label("Налаштування", systemImage: "gearshape") }.tag(2)
        }
    }
}

#Preview {
    RootView().injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
                         auth: AuthStore())
}
