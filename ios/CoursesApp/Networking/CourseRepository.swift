import Foundation

/// Контракт доступу до даних. ViewModels залежать від цього протоколу, не від
/// конкретної реалізації — легко підкласти мок/прев'ю.
protocol CourseRepository {
    func me() async throws -> Me
    func courses() async throws -> [CourseCard]
    func course(id: String) async throws -> CourseDetail
    func stream(id: String) async throws -> StreamDetail
    func schedule() async throws -> [ScheduleItem]
    func home() async throws -> HomeDigest
    func subscriptions() async throws -> [ResolvedStream]
    func materialTypes() async throws -> [MaterialType]

    func subscribe(streamId: String) async throws
    func unsubscribe(streamId: String) async throws

    // — Заявки на потік —
    func application(streamId: String) async throws -> Application?
    func apply(streamId: String, name: String, contact: String, comment: String?) async throws
    func applications(streamId: String) async throws -> [Application]
    func setApplicationStatus(id: String, status: ApplicationStatus) async throws

    // — Пульс після заняття —
    func pulse(sessionId: String) async throws -> Pulse?
    func ratePulse(sessionId: String, rating: Int, comment: String?) async throws
    func pulseSummary(sessionId: String) async throws -> PulseSummary

    // — Здача домашки —
    func submission(materialId: String) async throws -> Submission?
    func submitHomework(materialId: String, text: String) async throws
    func submissions(materialId: String) async throws -> [Submission]
    func reviewSubmission(id: String, feedback: String) async throws

    // — Оголошення на потік —
    func announcements(streamId: String) async throws -> [Announcement]
    func createAnnouncement(streamId: String, text: String) async throws
    func deleteAnnouncement(id: String) async throws

    // — Питання до заняття —
    func questions(sessionId: String) async throws -> [Question]
    func ask(sessionId: String, text: String, isAnonymous: Bool) async throws
    func deleteQuestion(id: String) async throws
    func markQuestionAnswered(id: String, answered: Bool) async throws

    func playback(materialId: String) async throws -> PlaybackResponse
    func access(materialId: String) async throws -> AccessResponse

    // — Адмін (за Google-allowlist на бекенді) —
    func adminMaterial(id: String) async throws -> AdminMaterial

    func createCourse(_ input: CourseInput) async throws
    func updateCourse(id: String, _ input: CourseInput) async throws
    func deleteCourse(id: String) async throws

    func createStream(_ input: StreamInput) async throws
    func updateStream(id: String, _ input: StreamInput) async throws
    func deleteStream(id: String) async throws

    /// Копія потоку зі зсувом розкладу — потоки повторюються щосезону.
    func cloneStream(id: String, _ input: CloneStreamInput) async throws

    func createSession(_ input: SessionInput) async throws
    /// Серія занять одним кроком замість N однакових форм.
    func createSessionsBatch(_ input: SessionsBatchInput) async throws
    func updateSession(id: String, _ input: SessionInput) async throws
    func deleteSession(id: String) async throws

    func createMaterial(_ input: MaterialInput) async throws
    func updateMaterial(id: String, _ input: MaterialInput) async throws
    func deleteMaterial(id: String) async throws

    func createMaterialType(_ input: MaterialTypeInput) async throws
    func updateMaterialType(id: String, _ input: MaterialTypeInput) async throws
    func deleteMaterialType(id: String) async throws
}

/// Реалізація поверх REST API. Знає deviceId; ховає формат запитів.
final class RemoteCourseRepository: CourseRepository {
    private let api: APIClient
    private let deviceId: String

    init(api: APIClient, deviceId: String = DeviceID.current) {
        self.api = api
        self.deviceId = deviceId
    }

    private struct SubBody: Encodable { let deviceId: String; let streamId: String }

    func me() async throws -> Me { try await api.get("me?deviceId=\(deviceId)", cached: false) }
    func courses() async throws -> [CourseCard] { try await api.get("courses") }
    func course(id: String) async throws -> CourseDetail { try await api.get("courses/\(id)") }
    func stream(id: String) async throws -> StreamDetail { try await api.get("streams/\(id)") }
    func schedule() async throws -> [ScheduleItem] { try await api.get("schedule?deviceId=\(deviceId)") }
    func home() async throws -> HomeDigest { try await api.get("home?deviceId=\(deviceId)") }
    func subscriptions() async throws -> [ResolvedStream] { try await api.get("subscriptions?deviceId=\(deviceId)") }
    func materialTypes() async throws -> [MaterialType] { try await api.get("material-types") }

    func subscribe(streamId: String) async throws {
        try await api.mutate("POST", "subscriptions", body: SubBody(deviceId: deviceId, streamId: streamId))
    }
    func unsubscribe(streamId: String) async throws {
        try await api.mutate("DELETE", "subscriptions", body: SubBody(deviceId: deviceId, streamId: streamId))
    }

    private struct ApplyBody: Encodable {
        let deviceId: String; let name: String; let contact: String; let comment: String?
    }
    private struct StatusBody: Encodable { let status: String }

    func application(streamId: String) async throws -> Application? {
        try await api.get("streams/\(streamId)/application?deviceId=\(deviceId)")
    }
    func apply(streamId: String, name: String, contact: String, comment: String?) async throws {
        try await api.mutate("POST", "streams/\(streamId)/application",
                             body: ApplyBody(deviceId: deviceId, name: name, contact: contact, comment: comment))
    }
    func applications(streamId: String) async throws -> [Application] {
        try await api.get("admin/streams/\(streamId)/applications")
    }
    func setApplicationStatus(id: String, status: ApplicationStatus) async throws {
        try await api.mutate("POST", "admin/applications/\(id)/status",
                             body: StatusBody(status: status.rawValue))
    }

    private struct PulseBody: Encodable { let deviceId: String; let rating: Int; let comment: String? }

    func pulse(sessionId: String) async throws -> Pulse? {
        try await api.get("sessions/\(sessionId)/pulse?deviceId=\(deviceId)")
    }
    func ratePulse(sessionId: String, rating: Int, comment: String?) async throws {
        try await api.mutate("POST", "sessions/\(sessionId)/pulse",
                             body: PulseBody(deviceId: deviceId, rating: rating, comment: comment))
    }
    func pulseSummary(sessionId: String) async throws -> PulseSummary {
        try await api.get("admin/sessions/\(sessionId)/pulses")
    }

    private struct SubmitBody: Encodable { let deviceId: String; let text: String }
    private struct FeedbackBody: Encodable { let feedback: String }

    /// Бекенд віддає `null`, якщо здачі ще немає — тому Optional.
    func submission(materialId: String) async throws -> Submission? {
        try await api.get("materials/\(materialId)/submission?deviceId=\(deviceId)")
    }
    func submitHomework(materialId: String, text: String) async throws {
        try await api.mutate("POST", "materials/\(materialId)/submission",
                             body: SubmitBody(deviceId: deviceId, text: text))
    }
    func submissions(materialId: String) async throws -> [Submission] {
        try await api.get("admin/materials/\(materialId)/submissions")
    }
    func reviewSubmission(id: String, feedback: String) async throws {
        try await api.mutate("POST", "admin/submissions/\(id)/feedback",
                             body: FeedbackBody(feedback: feedback))
    }

    private struct AnnouncementBody: Encodable { let streamId: String; let text: String }

    func announcements(streamId: String) async throws -> [Announcement] {
        try await api.get("streams/\(streamId)/announcements")
    }
    func createAnnouncement(streamId: String, text: String) async throws {
        try await api.mutate("POST", "admin/announcements",
                             body: AnnouncementBody(streamId: streamId, text: text))
    }
    func deleteAnnouncement(id: String) async throws {
        try await api.mutate("DELETE", "admin/announcements/\(id)")
    }

    private struct AskBody: Encodable { let deviceId: String; let text: String; let isAnonymous: Bool }
    private struct AnsweredBody: Encodable { let answered: Bool }

    func questions(sessionId: String) async throws -> [Question] {
        try await api.get("sessions/\(sessionId)/questions?deviceId=\(deviceId)")
    }
    func ask(sessionId: String, text: String, isAnonymous: Bool) async throws {
        try await api.mutate("POST", "sessions/\(sessionId)/questions",
                             body: AskBody(deviceId: deviceId, text: text, isAnonymous: isAnonymous))
    }
    func deleteQuestion(id: String) async throws {
        try await api.mutate("DELETE", "questions/\(id)?deviceId=\(deviceId)")
    }
    func markQuestionAnswered(id: String, answered: Bool) async throws {
        try await api.mutate("POST", "admin/questions/\(id)/answered", body: AnsweredBody(answered: answered))
    }

    func playback(materialId: String) async throws -> PlaybackResponse {
        try await api.get("video/\(materialId)/playback")
    }
    func access(materialId: String) async throws -> AccessResponse {
        try await api.get("video/\(materialId)/access")
    }

    // — Адмін —
    func adminMaterial(id: String) async throws -> AdminMaterial { try await api.get("admin/materials/\(id)") }

    func createCourse(_ input: CourseInput) async throws { try await api.mutate("POST", "admin/courses", body: input) }
    func updateCourse(id: String, _ input: CourseInput) async throws { try await api.mutate("PUT", "admin/courses/\(id)", body: input) }
    func deleteCourse(id: String) async throws { try await api.mutate("DELETE", "admin/courses/\(id)") }

    func createStream(_ input: StreamInput) async throws { try await api.mutate("POST", "admin/streams", body: input) }
    func updateStream(id: String, _ input: StreamInput) async throws { try await api.mutate("PUT", "admin/streams/\(id)", body: input) }
    func deleteStream(id: String) async throws { try await api.mutate("DELETE", "admin/streams/\(id)") }

    func cloneStream(id: String, _ input: CloneStreamInput) async throws {
        try await api.mutate("POST", "admin/streams/\(id)/clone", body: input)
    }

    func createSession(_ input: SessionInput) async throws { try await api.mutate("POST", "admin/sessions", body: input) }
    func createSessionsBatch(_ input: SessionsBatchInput) async throws { try await api.mutate("POST", "admin/sessions/batch", body: input) }
    func updateSession(id: String, _ input: SessionInput) async throws { try await api.mutate("PUT", "admin/sessions/\(id)", body: input) }
    func deleteSession(id: String) async throws { try await api.mutate("DELETE", "admin/sessions/\(id)") }

    func createMaterial(_ input: MaterialInput) async throws { try await api.mutate("POST", "admin/materials", body: input) }
    func updateMaterial(id: String, _ input: MaterialInput) async throws { try await api.mutate("PUT", "admin/materials/\(id)", body: input) }
    func deleteMaterial(id: String) async throws { try await api.mutate("DELETE", "admin/materials/\(id)") }

    func createMaterialType(_ input: MaterialTypeInput) async throws { try await api.mutate("POST", "admin/material-types", body: input) }
    func updateMaterialType(id: String, _ input: MaterialTypeInput) async throws { try await api.mutate("PUT", "admin/material-types/\(id)", body: input) }
    func deleteMaterialType(id: String) async throws { try await api.mutate("DELETE", "admin/material-types/\(id)") }
}
