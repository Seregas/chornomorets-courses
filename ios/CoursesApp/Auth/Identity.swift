import Foundation
import Observation

/// Анонімний ідентифікатор пристрою (для підписок). Identity-ready: згодом
/// замінюється на реального користувача без зміни моделей.
enum DeviceID {
    private static let key = "device_id"
    static var current: String {
        if let v = UserDefaults.standard.string(forKey: key) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: key)
        return v
    }
}

/// Токени. `bearer` йде в Authorization (dev: email; прод: Google ID-token).
/// `driveAccessToken` — для звернень до Google Drive API. Бекінг — UserDefaults,
/// щоб APIClient читав токен без прив'язки до акторів.
enum AuthTokenStore {
    private static let bearerKey = "auth_bearer"
    private static let driveKey = "drive_access_token"

    static var bearer: String? {
        get { UserDefaults.standard.string(forKey: bearerKey) }
        set { set(newValue, bearerKey) }
    }
    static var driveAccessToken: String? {
        get { UserDefaults.standard.string(forKey: driveKey) }
        set { set(newValue, driveKey) }
    }
    private static func set(_ value: String?, _ key: String) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
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

    /// Реальний Google-вхід через SDK: Bearer = ID-token, окремо зберігаємо Drive-токен.
    func connectGoogle(email: String, idToken: String, accessToken: String) {
        AuthTokenStore.bearer = idToken
        AuthTokenStore.driveAccessToken = accessToken
        setEmail(email.lowercased())
    }

    func disconnect() {
        AuthTokenStore.bearer = nil
        AuthTokenStore.driveAccessToken = nil
        // Відповіді Drive про доступ після виходу нічого не варті.
        DriveAccess.reset()
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
