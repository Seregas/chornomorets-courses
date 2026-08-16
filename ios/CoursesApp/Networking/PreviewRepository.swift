import Foundation

/// Канонічні дані для SwiftUI-прев'ю й офлайн-розробки UI без бекенду.
final class PreviewRepository: CourseRepository {
    static let stressCard = CourseCard(
        id: "c-stress", title: "Стрес, втома і піклування про себе",
        summary: "Міні-курс на 3 заняття про тактики й стратегії життя замість стресу.",
        format: .online, coverImageURL: nil,
        nextStream: StreamBrief(id: "s-stress-5", title: "Потік 5", startDate: "2026-07-08", status: .upcoming))

    static let esteemCard = CourseCard(
        id: "c-esteem", title: "Самооцінка",
        summary: "Міні-курс на 2 заняття про самоцінність і як її підвищити.",
        format: .online, coverImageURL: nil,
        nextStream: StreamBrief(id: "s-esteem-3", title: "Потік 3", startDate: "2026-07-10", status: .upcoming))

    static let stream5 = ResolvedStream(
        id: "s-stress-5", courseId: "c-stress", title: "Потік 5", startDate: "2026-07-08",
        status: .upcoming, telegramGroupURL: "https://t.me/petro_chornomorets",
        priceFull: 900, pricePerSession: 350,
        summary: "Міні-курс на 3 заняття.", description: "Розбираємо стрес із біологічної точки зору.",
        program: "1) Емоції; 2) Дихання; 3) Відновлення.", coverImageURL: nil)

    static let videoMaterial = MaterialDTO(
        id: "m-s4-rec1", title: "Запис заняття 1", typeId: "mt-video",
        description: "Як не заїдати емоції — повний запис.", url: nil, dueAt: nil,
        order: 1, hasVideo: true, videoProvider: .drive, durationMinutes: 118)

    func me() async throws -> Me { Me(deviceId: "preview", email: "admin@test.com", isAdmin: true) }
    func courses() async throws -> [CourseCard] { [Self.stressCard, Self.esteemCard] }
    func course(id: String) async throws -> CourseDetail {
        CourseDetail(id: "c-stress", title: Self.stressCard.title, summary: Self.stressCard.summary,
                     description: "Розбираємо стрес, втому й піклування про себе.",
                     program: "1) Емоції; 2) Дихання; 3) Відновлення.", format: .online,
                     coverImageURL: nil, streams: [Self.stream5], materials: [])
    }
    func stream(id: String) async throws -> StreamDetail {
        StreamDetail(id: Self.stream5.id, courseId: Self.stream5.courseId, title: Self.stream5.title,
                     startDate: Self.stream5.startDate, status: Self.stream5.status,
                     telegramGroupURL: Self.stream5.telegramGroupURL, priceFull: Self.stream5.priceFull,
                     pricePerSession: Self.stream5.pricePerSession, summary: Self.stream5.summary,
                     description: Self.stream5.description, program: Self.stream5.program,
                     coverImageURL: nil,
                     sessions: [SessionWithMaterials(
                        session: CourseSession(id: "ses-s5-1", streamId: "s-stress-5", title: "Заняття 1",
                                               startAt: "2026-07-08T17:00:00Z", durationMinutes: 120,
                                               format: .online, joinURL: "https://meet.google.com/x",
                                               order: 1),
                        materials: [Self.videoMaterial],
                        payment: nil)],
                     materials: [Self.videoMaterial],
                     summaryOverride: nil, descriptionOverride: nil,
                     programOverride: nil, coverImageOverride: nil)
    }
    func schedule() async throws -> [ScheduleItem] {
        [ScheduleItem(session: CourseSession(id: "ses-s5-1", streamId: "s-stress-5", title: "Заняття 1",
                                             startAt: "2026-07-08T17:00:00Z", durationMinutes: 120,
                                             format: .online, joinURL: "https://meet.google.com/x",
                                             order: 1),
                      payment: nil,
                      streamId: "s-stress-5", streamTitle: "Потік 5",
                      courseId: "c-stress", courseTitle: "Стрес, втома і піклування про себе")]
    }
    func home() async throws -> HomeDigest {
        let items = try await schedule()
        return HomeDigest(nextSession: items.first, announcements: [],
                          upcoming: [], homework: [], recordings: [])
    }
    func subscriptions() async throws -> [ResolvedStream] { [Self.stream5] }
    func materialTypes() async throws -> [MaterialType] {
        [MaterialType(id: "mt-video", name: "Відеозапис", icon: "play.rectangle.fill", color: "#0E7C86", order: 1)]
    }
    func subscribe(streamId: String) async throws {}
    func unsubscribe(streamId: String) async throws {}

    func application(streamId: String) async throws -> Application? { nil }
    func apply(streamId: String, name: String, contact: String, comment: String?) async throws {}
    func applications(streamId: String) async throws -> [Application] { [] }
    func setApplicationStatus(id: String, status: ApplicationStatus) async throws {}

    func payment(sessionId: String) async throws -> Payment? { nil }
    func declarePayment(sessionId: String, amount: Int?, receiptURL: String?, note: String?) async throws {}
    func uploadReceipt(paymentId: String, image: Data, facts: ReceiptFacts) async throws -> Payment {
        throw APIError(status: 503, body: "прев'ю")
    }
    func receiptURL(paymentId: String) -> URL? { nil }
    func payments(sessionId: String) async throws -> [Payment] { [] }
    func setPaymentStatus(id: String, status: PaymentStatus) async throws {}

    func pulse(sessionId: String) async throws -> Pulse? { nil }
    func ratePulse(sessionId: String, rating: Int, comment: String?) async throws {}
    func pulseSummary(sessionId: String) async throws -> PulseSummary {
        PulseSummary(sessionId: sessionId, count: 0, average: 0, histogram: [0,0,0,0,0], comments: [])
    }

    func submission(materialId: String) async throws -> Submission? { nil }
    func submitHomework(materialId: String, text: String) async throws {}
    func submissions(materialId: String) async throws -> [Submission] { [] }
    func reviewSubmission(id: String, feedback: String) async throws {}

    func announcements(streamId: String) async throws -> [Announcement] {
        [Announcement(id: "a1", streamId: streamId, streamTitle: "Потік 5",
                      courseTitle: "Стрес, втома і піклування про себе",
                      text: "Заняття 2 переносимо на четвер, 20:00.",
                      createdAt: "2026-08-14T10:00:00Z")]
    }
    func createAnnouncement(streamId: String, text: String) async throws {}
    func deleteAnnouncement(id: String) async throws {}

    func questions(sessionId: String) async throws -> [Question] {
        [Question(id: "q1", sessionId: sessionId, text: "Що робити, якщо втома не минає після вихідних?",
                  createdAt: "2026-08-14T10:00:00Z", answeredAt: nil, isMine: true, authorEmail: nil)]
    }
    func ask(sessionId: String, text: String, isAnonymous: Bool) async throws {}
    func deleteQuestion(id: String) async throws {}
    func markQuestionAnswered(id: String, answered: Bool) async throws {}
    func playback(materialId: String) async throws -> PlaybackResponse {
        PlaybackResponse(access: .granted, descriptor: .youtube(videoId: "dQw4w9WgXcQ"))
    }
    func access(materialId: String) async throws -> AccessResponse {
        AccessResponse(access: .granted, provider: .drive)
    }

    // Адмін-методи у прев'ю — no-op.
    func adminMaterial(id: String) async throws -> AdminMaterial {
        AdminMaterial(id: id, ownerType: "stream", ownerId: "s-stress-4", typeId: "mt-video",
                      title: "Запис заняття 1", description: "Повний запис.", videoProvider: .drive,
                      videoRef: "1AbCDriveFileStress1", durationMinutes: 118, url: nil, dueAt: nil, order: 1)
    }
    func createCourse(_ input: CourseInput) async throws {}
    func updateCourse(id: String, _ input: CourseInput) async throws {}
    func deleteCourse(id: String) async throws {}
    func createStream(_ input: StreamInput) async throws {}
    func updateStream(id: String, _ input: StreamInput) async throws {}
    func deleteStream(id: String) async throws {}
    func cloneStream(id: String, _ input: CloneStreamInput) async throws {}
    func createSession(_ input: SessionInput) async throws {}
    func createSessionsBatch(_ input: SessionsBatchInput) async throws {}
    func updateSession(id: String, _ input: SessionInput) async throws {}
    func deleteSession(id: String) async throws {}
    func createMaterial(_ input: MaterialInput) async throws {}
    func updateMaterial(id: String, _ input: MaterialInput) async throws {}
    func deleteMaterial(id: String) async throws {}
    func createMaterialType(_ input: MaterialTypeInput) async throws {}
    func updateMaterialType(id: String, _ input: MaterialTypeInput) async throws {}
    func deleteMaterialType(id: String) async throws {}
}
