import Foundation

struct APIError: LocalizedError {
    let status: Int
    let body: String
    var errorDescription: String? { "HTTP \(status): \(body)" }
}

/// Тонкий HTTP-клієнт. Авторизація — Bearer-токеном від AuthTokenStore
/// (прототип: email). База — з Config.
final class APIClient {
    let baseURL: URL
    private let tokenProvider: () -> String?
    private let session: URLSession
    private let cache: ResponseCache

    init(baseURL: URL,
         tokenProvider: @escaping () -> String? = { AuthTokenStore.bearer },
         session: URLSession = .shared,
         cache: ResponseCache = ResponseCache()) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.cache = cache
    }

    private struct Empty: Encodable {}

    /// GET + декодування. Успішну відповідь кладемо в кеш; якщо мережі немає —
    /// віддаємо збережену копію, а не помилку. Помилки сервера (4xx/5xx) із
    /// кешу не рятуємо: 403 на відео має лишитися 403, а не показати старе.
    func get<T: Decodable>(_ path: String) async throws -> T {
        do {
            let data = try await performRaw(method: "GET", path: path, body: Optional<Empty>.none)
            cache.store(data, for: path)
            await OfflineStatus.shared.markOnline()
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as APIError {
            throw error
        } catch {
            guard let cached = cache.data(for: path),
                  let value = try? JSONDecoder().decode(T.self, from: cached.data)
            else { throw error }
            await OfflineStatus.shared.markServedFromCache(savedAt: cached.savedAt)
            return value
        }
    }

    /// Запис із тілом (POST/PUT/DELETE), відповідь ігнорується.
    func mutate<Body: Encodable>(_ method: String, _ path: String, body: Body) async throws {
        _ = try await performRaw(method: method, path: path, body: body)
        cache.clear()
    }

    /// Запис без тіла (DELETE).
    func mutate(_ method: String, _ path: String) async throws {
        _ = try await performRaw(method: method, path: path, body: Optional<Empty>.none)
        cache.clear()
    }

    private func performRaw<Body: Encodable>(method: String, path: String, body: Body?) async throws -> Data {
        // URL(string:relativeTo:) зберігає query-рядок (appendingPathComponent його екранує).
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError(status: -1, body: "невалідний шлях: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }
}
