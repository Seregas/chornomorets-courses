import Foundation

/// Фаза 2 (заглушка інтерфейсу): офлайн-завантаження відео з орендою.
/// Реалізація — окремим кроком: завантаження потоку в sandbox, шифрування
/// (AES-GCM, ключ у Keychain), відтворення через AVAssetResourceLoaderDelegate
/// з дешифруванням на льоту; lease TTL (expiresAt) із бекенду.
protocol DownloadManaging {
    func isDownloaded(materialId: String) -> Bool
    func download(materialId: String) async throws
    func remove(materialId: String)
    func leaseExpiry(materialId: String) -> Date?
}

/// Поки що — лише заглушка, щоб верхні шари вже могли посилатися на інтерфейс.
final class DownloadManager: DownloadManaging {
    func isDownloaded(materialId: String) -> Bool { false }
    func download(materialId: String) async throws {
        throw NSError(domain: "DownloadManager", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "Завантаження зʼявиться у Фазі 2"])
    }
    func remove(materialId: String) {}
    func leaseExpiry(materialId: String) -> Date? { nil }
}
