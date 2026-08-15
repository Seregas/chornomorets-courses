import Foundation

/// Найближче заняття у вигляді, достатньому для віджета.
struct SharedSession: Codable, Hashable {
    let title: String
    let courseTitle: String
    let startAt: Date
    let joinURL: String?
}

/**
 Місток «застосунок → віджет». Розширення живе в окремому процесі з власним
 контейнером, тож єдиний спосіб поділитися даними — App Group.

 Кладемо саме готовий зріз (одне найближче заняття), а не токени й deviceId:
 віджету не потрібно ходити в мережу, а нам — тягнути в нього пів застосунку.
 */
enum SharedSchedule {
    static let appGroup = "group.com.chornomorets.courses"
    private static let key = "next_session"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func save(_ session: SharedSession?) {
        guard let defaults else { return }
        guard let session, let data = try? JSONEncoder().encode(session) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    static func load() -> SharedSession? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SharedSession.self, from: data)
    }
}
