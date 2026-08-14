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

    init(baseURL: URL,
         tokenProvider: @escaping () -> String? = { AuthTokenStore.bearer },
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    private struct Empty: Encodable {}

    /// GET + декодування.
    func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await performRaw(method: "GET", path: path, body: Optional<Empty>.none)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Запис із тілом (POST/PUT/DELETE), відповідь ігнорується.
    func mutate<Body: Encodable>(_ method: String, _ path: String, body: Body) async throws {
        _ = try await performRaw(method: method, path: path, body: body)
    }

    /// Запис без тіла (DELETE).
    func mutate(_ method: String, _ path: String) async throws {
        _ = try await performRaw(method: method, path: path, body: Optional<Empty>.none)
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
