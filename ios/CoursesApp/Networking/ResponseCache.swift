import Foundation
import Observation

/// Останні успішні відповіді GET-ів на диску. Без цього застосунок без мережі
/// просто порожній: каталог, розклад і «Навчання» — це читання, яке рідко
/// змінюється, тож показати вчорашні дані краще, ніж білий екран.
///
/// Кешуємо на рівні HTTP-шляху, а не окремих методів репозиторію: один шов
/// замість двох десятків прокидувань.
struct ResponseCache {
    private let directory: URL
    private let fm = FileManager.default

    init(name: String = "api-cache") {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func data(for path: String) -> (data: Data, savedAt: Date)? {
        let url = fileURL(for: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let savedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date.distantPast
        return (data, savedAt)
    }

    func store(_ data: Data, for path: String) {
        try? data.write(to: fileURL(for: path), options: .atomic)
    }

    /// Після будь-якого запису на сервері кеш застарів увесь одразу: створення
    /// потоку міняє і каталог, і деталь курсу, і розклад.
    func clear() {
        try? fm.removeItem(at: directory)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Шлях може містити query й слеші — беремо стабільний однорядковий ключ.
    private func fileURL(for path: String) -> URL {
        let key = path.unicodeScalars.reduce(into: "") { acc, scalar in
            acc += CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }
        return directory.appendingPathComponent("\(key).json")
    }
}

/// Чи показуємо зараз збережені дані замість свіжих. Один прапорець на
/// застосунок — банер угорі, а не по банеру на кожен екран.
@MainActor
@Observable
final class OfflineStatus {
    static let shared = OfflineStatus()
    private init() {}

    private(set) var servingFromCacheSince: Date?
    var isOffline: Bool { servingFromCacheSince != nil }

    func markServedFromCache(savedAt: Date) {
        servingFromCacheSince = savedAt
    }
    func markOnline() {
        servingFromCacheSince = nil
    }
}
