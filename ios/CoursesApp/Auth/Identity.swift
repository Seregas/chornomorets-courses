import Foundation
import Observation

/// Анонімний ідентифікатор пристрою — лишився тільки для логів із телефона:
/// вони пишуться ще до входу й саме тоді, коли ламається вхід. Усе особисте
/// (підписки, оплати, домашки) висить на Google-акаунті, а не на пристрої.
enum DeviceID {
    private static let key = "device_id"
    static var current: String {
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: key)
        return v
    }
}

/// Токен для Authorization (dev: email; прод: Google ID-token). Бекінг —
/// UserDefaults, щоб APIClient читав його без прив'язки до акторів.
enum AuthTokenStore {
    private static let bearerKey = "auth_bearer"

    static var bearer: String? {
        get { UserDefaults.standard.string(forKey: bearerKey) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: bearerKey) }
            else { UserDefaults.standard.removeObject(forKey: bearerKey) }
        }
    }
}

/**
 Оновлення протухлого токена.

 Google видає ID-token на годину. Оскільки на ньому тепер тримається все
 особисте, без оновлення застосунок через годину виглядав би залогіненим, а
 сервер відповідав би 401 на розклад, оплати й домашки. Хук ставить застосунок
 на старті; APIClient смикає його, коли отримав 401, і повторює запит.
 */
enum TokenRefresher {
    /// Повертає true, якщо вдалося оновити токен і запит варто повторити.
    nonisolated(unsafe) static var refresh: (() async -> Bool)?
}

/// Спостережуваний стан Google-входу для UI.
@MainActor
@Observable
final class AuthStore {
    private(set) var email: String?
    private(set) var isAdmin = false

    private static let emailKey = "display_email"

    var isConnected: Bool { email != nil }

    init() { email = UserDefaults.standard.string(forKey: Self.emailKey) }

    /// Dev-вхід: email одночасно і Bearer, і відображувана адреса (поки немає реального OAuth).
    func connectDev(email: String) {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        AuthTokenStore.bearer = normalized
        setEmail(normalized)
    }

    /// Реальний Google-вхід через SDK: Bearer = ID-token.
    func connectGoogle(email: String, idToken: String) {
        AuthTokenStore.bearer = idToken
        setEmail(email.lowercased())
    }

    func disconnect() {
        AuthTokenStore.bearer = nil
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        email = nil
        isAdmin = false
    }

    func refreshAdmin(using repo: CourseRepository) async {
        guard isConnected else { isAdmin = false; return }
        if let me = try? await repo.me() { isAdmin = me.isAdmin }
    }

    private func setEmail(_ value: String) {
        UserDefaults.standard.set(value, forKey: Self.emailKey)
        email = value
    }
}
