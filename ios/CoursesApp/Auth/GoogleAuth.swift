import Foundation
import GoogleSignIn
import UIKit

/// Конфіг Google-входу. clientID береться з Info.plist (GIDClientID).
/// Поки там плейсхолдер — застосунок працює у dev-режимі (вхід через email).
enum GoogleAuthConfig {
    static var clientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }
    static var isConfigured: Bool {
        guard let id = clientID else { return false }
        return !id.hasPrefix("REPLACE_WITH") && id.contains(".apps.googleusercontent.com")
    }
}

enum GoogleAuthError: LocalizedError {
    case noPresenter, missingIdToken
    var errorDescription: String? {
        switch self {
        case .noPresenter: return "Немає вікна для показу входу."
        case .missingIdToken: return "Google не повернув ID-token."
        }
    }
}

/**
 Обгортка над GoogleSignIn SDK. SDK сам робить PKCE, оновлення токенів і Keychain.

 Просимо лише базові дані (пошта, ім'я) — жодних scope до Drive. Записи
 відкриваються плеєром самого Drive у Safari-контролері, під тим Google-акаунтом,
 яким людина вже залогінена в браузері, тож наш токен для перегляду не потрібен.
 Раніше тут стояв `drive.readonly` — читання ВСЬОГО диска — заради єдиного
 бейджа «є доступ / немає». Ціна: екран згоди, який лякає, і restricted scope,
 що вимагає щорічного зовнішнього аудиту безпеки для публікації.
 */
@MainActor
final class GoogleSignInService {
    struct Session {
        let email: String
        let idToken: String  // → Authorization Bearer на бекенд
    }

    init() {
        if GoogleAuthConfig.isConfigured, let id = GoogleAuthConfig.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: id)
        }
    }

    func signIn() async throws -> Session {
        guard let presenter = Self.topViewController() else { throw GoogleAuthError.noPresenter }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        return try session(from: result.user)
    }

    func restore() async -> Session? {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return nil }
        guard let user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn() else { return nil }
        return try? session(from: user)
    }

    func signOut() { GIDSignIn.sharedInstance.signOut() }

    /// Оновлює ID-token, якщо той протух (SDK тримає refresh-token у Keychain).
    /// Повертає nil, якщо входу немає або оновити не вдалося — тоді потрібен
    /// справжній повторний вхід.
    func refreshIfNeeded() async -> Session? {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return nil }
        guard let refreshed = try? await user.refreshTokensIfNeeded() else { return nil }
        return try? session(from: refreshed)
    }

    private func session(from user: GIDGoogleUser) throws -> Session {
        guard let idToken = user.idToken?.tokenString else { throw GoogleAuthError.missingIdToken }
        return Session(email: user.profile?.email ?? "", idToken: idToken)
    }

    static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var top = windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
