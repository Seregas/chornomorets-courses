import Foundation

// Codable-моделі — дзеркало DTO бекенду (server/src/types.ts).
// Жодних сирих videoRef: відео представлене ознакою hasVideo + provider.

enum CourseFormat: String, Codable { case online, offline, hybrid }
enum PaymentStatus: String, Codable { case unpaid, paid, free }
enum StreamStatus: String, Codable { case upcoming, ongoing, finished }
enum VideoProvider: String, Codable { case drive, youtube, other }
enum AccessState: String, Codable { case granted, denied, unknown }

struct StreamBrief: Codable, Hashable {
    let id: String
    let title: String
    let startDate: String?
    let status: StreamStatus
}

struct CourseCard: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let format: CourseFormat
    let coverImageURL: String?
    let nextStream: StreamBrief?
}

struct ResolvedStream: Codable, Identifiable, Hashable {
    let id: String
    let courseId: String
    let title: String
    let startDate: String?
    let status: StreamStatus
    let telegramGroupURL: String?
    let priceFull: Int?
    let pricePerSession: Int?
    let summary: String
    let description: String
    let program: String?
    let coverImageURL: String?
}

struct MaterialDTO: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let typeId: String?
    let description: String?
    let url: String?
    let dueAt: String?
    let order: Int
    let hasVideo: Bool
    let videoProvider: VideoProvider?
    let durationMinutes: Int?
}

struct CourseDetail: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let description: String
    let program: String?
    let format: CourseFormat
    let coverImageURL: String?
    let streams: [ResolvedStream]
    let materials: [MaterialDTO]
}

struct CourseSession: Codable, Identifiable, Hashable {
    let id: String
    let streamId: String
    let title: String
    let startAt: String
    let durationMinutes: Int
    let format: CourseFormat
    let joinURL: String?
    let paymentStatus: PaymentStatus
    let order: Int
}

/// Заняття разом зі своїми матеріалами: записом, конспектом, домашкою.
struct SessionWithMaterials: Codable, Identifiable, Hashable {
    var id: String { session.id }
    let session: CourseSession
    let materials: [MaterialDTO]

    /// Що є всередині — для іконок у рядку заняття.
    var hasVideo: Bool { materials.contains { $0.hasVideo } }
    var hasHomework: Bool { materials.contains { $0.dueAt != nil } }
    var hasDocuments: Bool {
        materials.contains { $0.url != nil && !$0.hasVideo && $0.dueAt == nil }
    }
}

struct StreamDetail: Codable, Identifiable, Hashable {
    let id: String
    let courseId: String
    let title: String
    let startDate: String?
    let status: StreamStatus
    let telegramGroupURL: String?
    let priceFull: Int?
    let pricePerSession: Int?
    let summary: String
    let description: String
    let program: String?
    let coverImageURL: String?
    let sessions: [SessionWithMaterials]
    let materials: [MaterialDTO]
    // Сирі override-значення (для адмін-редагування; null = успадковано з курсу).
    let summaryOverride: String?
    let descriptionOverride: String?
    let programOverride: String?
    let coverImageOverride: String?
}

/// Сирий матеріал (із videoRef) — приходить лише адмінам для префілу форми.
struct AdminMaterial: Decodable {
    let id: String
    let ownerType: String
    let ownerId: String
    let typeId: String?
    let title: String
    let description: String?
    let videoProvider: VideoProvider?
    let videoRef: String?
    let durationMinutes: Int?
    let url: String?
    let dueAt: String?
    let order: Int
}

struct ScheduleItem: Codable, Identifiable, Hashable {
    var id: String { session.id }
    let session: CourseSession
    let streamId: String
    let streamTitle: String
    let courseId: String
    let courseTitle: String
}

enum ApplicationStatus: String, Codable {
    case new, waitingPayment, enrolled, declined

    var label: String {
        switch self {
        case .new: return "заявку прийнято"
        case .waitingPayment: return "очікує оплати"
        case .enrolled: return "зараховано"
        case .declined: return "відхилено"
        }
    }
}

/// Заявка на потік — заміна Google Forms.
struct Application: Codable, Identifiable, Hashable {
    let id: String
    let streamId: String
    let deviceId: String
    let name: String
    let contact: String
    let comment: String?
    let status: ApplicationStatus
    let createdAt: String
}

/// «Як зайшло заняття»: оцінка 1–5 і необовʼязковий коментар.
struct Pulse: Codable, Identifiable, Hashable {
    let id: String
    let sessionId: String
    let rating: Int
    let comment: String?
}

/// Зведення відгуків по заняттю — для викладача.
struct PulseSummary: Codable, Hashable {
    let sessionId: String
    let count: Int
    let average: Double
    /// Розподіл оцінок: індекс 0 = «1 зірка».
    let histogram: [Int]
    let comments: [String]
}

/// Здана домашка. Одна на матеріал і пристрій: повторна здача перезаписує текст,
/// але не стирає відповідь викладача.
struct Submission: Codable, Identifiable, Hashable {
    let id: String
    let materialId: String
    let deviceId: String
    let authorEmail: String?
    let text: String
    let submittedAt: String
    let feedback: String?
    let reviewedAt: String?
}

/// Оголошення викладача на потік.
struct Announcement: Codable, Identifiable, Hashable {
    let id: String
    let streamId: String
    let streamTitle: String
    let courseTitle: String
    let text: String
    let createdAt: String
}

/// Питання до заняття. `authorEmail` приходить лише адміну (і лише якщо
/// питання не анонімне) — решта бачить питання без імен.
struct Question: Codable, Identifiable, Hashable {
    let id: String
    let sessionId: String
    let text: String
    let createdAt: String
    let answeredAt: String?
    let isMine: Bool
    let authorEmail: String?

    var isAnswered: Bool { answeredAt != nil }
}

/// Матеріал разом із потоком/курсом, звідки він.
struct MaterialInContext: Codable, Identifiable, Hashable {
    var id: String { material.id }
    let material: MaterialDTO
    let streamId: String
    let streamTitle: String
    let courseId: String
    let courseTitle: String
}

/// Зведення для екрана «Моє навчання».
struct HomeDigest: Codable, Hashable {
    let nextSession: ScheduleItem?
    let announcements: [Announcement]
    let upcoming: [ScheduleItem]
    let homework: [MaterialInContext]
    let recordings: [MaterialInContext]

    var isEmpty: Bool {
        nextSession == nil && announcements.isEmpty && upcoming.isEmpty
            && homework.isEmpty && recordings.isEmpty
    }
}

struct MaterialType: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String?
    let color: String?
    let order: Int
}

struct Me: Codable, Hashable {
    let deviceId: String?
    let email: String?
    let isAdmin: Bool
}

struct Enrollment: Codable, Identifiable, Hashable {
    let id: String
    let deviceId: String
    let streamId: String
    let subscribedAt: String
}

// Відео: типізований playback-дескриптор (дзеркало server/src/video.ts).
enum PlaybackDescriptor: Hashable {
    case direct(url: String)
    case youtube(videoId: String)
    case googleDrive(fileId: String)
}

extension PlaybackDescriptor: Decodable {
    private enum CodingKeys: String, CodingKey { case type, url, videoId, fileId }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "direct": self = .direct(url: try c.decode(String.self, forKey: .url))
        case "youtube": self = .youtube(videoId: try c.decode(String.self, forKey: .videoId))
        case "google-drive": self = .googleDrive(fileId: try c.decode(String.self, forKey: .fileId))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "невідомий тип playback")
        }
    }
}

struct PlaybackResponse: Decodable {
    let access: AccessState
    let descriptor: PlaybackDescriptor
}

struct AccessResponse: Decodable {
    let access: AccessState
    let provider: VideoProvider?
}
