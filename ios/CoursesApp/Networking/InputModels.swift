import Foundation

// Тіла запитів для адмін-CRUD. JSONEncoder опускає nil-опціонали, тож той самий
// тип годиться і для create (заповнюємо потрібне), і для update (часткове).

struct CourseInput: Encodable {
    var title: String?
    var summary: String?
    var description: String?
    var program: String?
    var format: String?
    var coverImageURL: String?
    var order: Int?
}

struct StreamInput: Encodable {
    var courseId: String?
    var title: String?
    var startDate: String?
    var status: String?
    var telegramGroupURL: String?
    var priceFull: Int?
    var pricePerSession: Int?
    var summaryOverride: String?
    var descriptionOverride: String?
    var programOverride: String?
    var coverImageOverride: String?
    var order: Int?
}

struct SessionInput: Encodable {
    var streamId: String?
    var title: String?
    var startAt: String?
    var durationMinutes: Int?
    var format: String?
    var joinURL: String?
    var paymentStatus: String?
    var order: Int?
}

struct MaterialInput: Encodable {
    var ownerType: String?
    var ownerId: String?
    var typeId: String?
    var title: String?
    var description: String?
    var videoProvider: String?
    var videoRef: String?
    var durationMinutes: Int?
    var url: String?
    var dueAt: String?
    var order: Int?
}

struct MaterialTypeInput: Encodable {
    var name: String?
    var icon: String?
    var color: String?
    var order: Int?
}

/// Порожній рядок → nil (щоб не слати "" у поля з url-валідацією на бекенді).
func nilIfEmpty(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}
