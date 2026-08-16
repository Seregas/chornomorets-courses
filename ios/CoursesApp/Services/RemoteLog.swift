import Foundation

/**
 Надсилає діагностичні події на наш бекенд.

 Причина проста: застосунок живе в TestFlight, і кожна перевірка гіпотези
 коштує збірки, вивантаження й чужого часу. Без зворотного каналу залишається
 просити людину переказувати, що вона бачить на екрані.

 Що НЕ шлемо: токени, вміст щоденника, тексти домашок і питань. Лише те, що
 сталося і з якою помилкою.
 */
enum RemoteLog {
    static func send(_ event: String, _ detail: String? = nil) {
        // Спеціально не через APIClient: логи не мають чистити офлайн-кеш
        // і не мають залежати від решти мережевого шару.
        guard let url = URL(string: "logs", relativeTo: Config.baseURL) else { return }

        let payload: [String: Any?] = [
            "deviceId": DeviceID.current,
            "appVersion": appVersion,
            "event": event,
            "detail": detail,
        ]
        guard let body = try? JSONSerialization.data(
            withJSONObject: payload.compactMapValues { $0 }) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10

        // Fire-and-forget: діагностика не має гальмувати екран і не має
        // ламатися, якщо сервера немає.
        URLSession.shared.dataTask(with: request).resume()
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
