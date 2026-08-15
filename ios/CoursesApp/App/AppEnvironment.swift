import SwiftUI

/// Конфіг адреси API, у порядку пріоритету:
///  1) UserDefaults-ключ `api_base_url` — ручне перевизначення в Налаштуваннях;
///  2) `APIBaseURL` з Info.plist — вшивається зі змінної збірки `API_BASE_URL`
///     (Debug = localhost, Release = адреса, передана під час архівування);
///  3) локальний сервер — щоб прев'ю й свіжий клон працювали без налаштувань.
enum Config {
    static var baseURL: URL {
        if let s = UserDefaults.standard.string(forKey: "api_base_url"),
           !s.isEmpty, let u = URL(string: s) {
            return u
        }
        if let s = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
           !s.isEmpty, let u = URL(string: s) {
            return u
        }
        return URL(string: "http://localhost:3000")!
    }
}

/// Контейнер залежностей (репозиторій + сервіси). Збирається у точці входу.
final class AppEnvironment {
    let repository: CourseRepository
    let notifications: NotificationScheduler

    init(repository: CourseRepository, notifications: NotificationScheduler) {
        self.repository = repository
        self.notifications = notifications
    }

    static func live() -> AppEnvironment {
        let api = APIClient(baseURL: Config.baseURL)
        return AppEnvironment(
            repository: RemoteCourseRepository(api: api),
            notifications: NotificationScheduler())
    }
}

// Інʼєкція через environment.
private struct RepositoryKey: EnvironmentKey {
    static let defaultValue: CourseRepository = PreviewRepository()
}
private struct NotificationsKey: EnvironmentKey {
    static let defaultValue = NotificationScheduler()
}

extension EnvironmentValues {
    var repository: CourseRepository {
        get { self[RepositoryKey.self] }
        set { self[RepositoryKey.self] = newValue }
    }
    var notifications: NotificationScheduler {
        get { self[NotificationsKey.self] }
        set { self[NotificationsKey.self] = newValue }
    }
}

extension Color {
    /// Морський акцент (#0E7C86) — тема «Чорноморець».
    static let sea = Color(red: 0.055, green: 0.486, blue: 0.525)
    static let seaDeep = Color(red: 0.039, green: 0.333, blue: 0.376)
}

extension View {
    func injecting(_ env: AppEnvironment, auth: AuthStore) -> some View {
        self.environment(\.repository, env.repository)
            .environment(\.notifications, env.notifications)
            .environment(auth)
    }
}
