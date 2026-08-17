import Foundation

/// Контракт доступу до даних. ViewModels залежать від цього протоколу, не від
/// конкретної реалізації — легко підкласти мок/прев'ю.
protocol CourseRepository {
    func me() async throws -> Me
    /// Видалити свій акаунт разом з усім, що на ньому висить.
    func deleteAccount() async throws
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
    /// Усі нерозглянуті заявки з усіх потоків — для викладача.
    func pendingApplications() async throws -> [ApplicationInContext]
    func setApplicationStatus(id: String, status: ApplicationStatus) async throws

    // — Оплата заняття —
    func payment(sessionId: String) async throws -> Payment?
    func declarePayment(sessionId: String, amount: Int?, receiptURL: String?, note: String?) async throws
    func uploadReceipt(paymentId: String, image: Data, facts: ReceiptFacts) async throws -> Payment
    /// Адреса картинки квитанції — показуємо її прямо із сервера.
    func receiptURL(paymentId: String) -> URL?
    func payments(sessionId: String) async throws -> [Payment]
    func setPaymentStatus(id: String, status: PaymentStatus) async throws

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

/// Реалізація поверх REST API. Ховає формат запитів.
///
/// Особисті дані сервер бере з акаунта у Google-токені, який ставить APIClient,
/// — тут їх передавати не треба й не можна. Раніше цю роль грав deviceId, і
/// зміна телефона стирала людині підписки, оплати й домашки.
final class RemoteCourseRepository: CourseRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    private struct SubBody: Encodable { let streamId: String }

    func me() async throws -> Me { try await api.get("me", cached: false) }
    func deleteAccount() async throws { try await api.mutate("DELETE", "me") }
    func courses() async throws -> [CourseCard] { try await api.get("courses") }
    func course(id: String) async throws -> CourseDetail { try await api.get("courses/\(id)") }
    func stream(id: String) async throws -> StreamDetail { try await api.get("streams/\(id)") }
    func schedule() async throws -> [ScheduleItem] { try await api.get("schedule") }
    func home() async throws -> HomeDigest { try await api.get("home") }
    func subscriptions() async throws -> [ResolvedStream] { try await api.get("subscriptions") }
    func materialTypes() async throws -> [MaterialType] { try await api.get("material-types") }

    func subscribe(streamId: String) async throws {
        try await api.mutate("POST", "subscriptions", body: SubBody(streamId: streamId))
    }
    func unsubscribe(streamId: String) async throws {
        try await api.mutate("DELETE", "subscriptions", body: SubBody(streamId: streamId))
    }

    private struct ApplyBody: Encodable {
        let name: String; let contact: String; let comment: String?
    }
    private struct StatusBody: Encodable { let status: String }

    func application(streamId: String) async throws -> Application? {
        try await api.get("streams/\(streamId)/application")
    }
    func apply(streamId: String, name: String, contact: String, comment: String?) async throws {
        try await api.mutate("POST", "streams/\(streamId)/application",
                             body: ApplyBody(name: name, contact: contact, comment: comment))
    }
    func applications(streamId: String) async throws -> [Application] {
        try await api.get("admin/streams/\(streamId)/applications")
    }
    func pendingApplications() async throws -> [ApplicationInContext] {
        try await api.get("admin/applications", cached: false)
    }
    func setApplicationStatus(id: String, status: ApplicationStatus) async throws {
        try await api.mutate("POST", "admin/applications/\(id)/status",
                             body: StatusBody(status: status.rawValue))
    }

    private struct DeclareBody: Encodable {
        let amount: Int?; let receiptURL: String?; let note: String?
    }
    private struct PaymentStatusBody: Encodable { let status: String }

    func payment(sessionId: String) async throws -> Payment? {
        try await api.get("sessions/\(sessionId)/payment", cached: false)
    }
    func declarePayment(sessionId: String, amount: Int?, receiptURL: String?, note: String?) async throws {
        try await api.mutate("POST", "sessions/\(sessionId)/payment",
                             body: DeclareBody(amount: amount, receiptURL: receiptURL, note: note))
    }
    func uploadReceipt(paymentId: String, image: Data, facts: ReceiptFacts) async throws -> Payment {
        let parsed = (try? JSONEncoder().encode(facts)).map { String(decoding: $0, as: UTF8.self) }
        return try await api.upload(
            "payments/\(paymentId)/receipt",
            image: image,
            fields: ["parsed": parsed ?? ""])
    }

    /// Токен у query, а не в заголовку: URL іде в AsyncImage, а той заголовків
    /// не ставить. Сервер приймає обидва шляхи.
    func receiptURL(paymentId: String) -> URL? {
        guard let token = AuthTokenStore.bearer else { return nil }
        let escaped = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        return URL(string: "payments/\(paymentId)/receipt?token=\(escaped)", relativeTo: api.baseURL)
    }

    func payments(sessionId: String) async throws -> [Payment] {
        try await api.get("admin/sessions/\(sessionId)/payments", cached: false)
    }
    func setPaymentStatus(id: String, status: PaymentStatus) async throws {
        try await api.mutate("POST", "admin/payments/\(id)/status",
                             body: PaymentStatusBody(status: status.rawValue))
    }

    private struct PulseBody: Encodable { let rating: Int; let comment: String? }

    func pulse(sessionId: String) async throws -> Pulse? {
        try await api.get("sessions/\(sessionId)/pulse")
    }
    func ratePulse(sessionId: String, rating: Int, comment: String?) async throws {
        try await api.mutate("POST", "sessions/\(sessionId)/pulse",
                             body: PulseBody(rating: rating, comment: comment))
    }
    func pulseSummary(sessionId: String) async throws -> PulseSummary {
        try await api.get("admin/sessions/\(sessionId)/pulses")
    }

    private struct SubmitBody: Encodable { let text: String }
    private struct FeedbackBody: Encodable { let feedback: String }

    /// Бекенд віддає `null`, якщо здачі ще немає — тому Optional.
    func submission(materialId: String) async throws -> Submission? {
        try await api.get("materials/\(materialId)/submission")
    }
    func submitHomework(materialId: String, text: String) async throws {
        try await api.mutate("POST", "materials/\(materialId)/submission",
                             body: SubmitBody(text: text))
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

    private struct AskBody: Encodable { let text: String; let isAnonymous: Bool }
    private struct AnsweredBody: Encodable { let answered: Bool }

    func questions(sessionId: String) async throws -> [Question] {
        try await api.get("sessions/\(sessionId)/questions")
    }
    func ask(sessionId: String, text: String, isAnonymous: Bool) async throws {
        try await api.mutate("POST", "sessions/\(sessionId)/questions",
                             body: AskBody(text: text, isAnonymous: isAnonymous))
    }
    func deleteQuestion(id: String) async throws {
        try await api.mutate("DELETE", "questions/\(id)")
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
