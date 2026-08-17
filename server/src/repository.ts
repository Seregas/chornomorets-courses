import { and, asc, desc, eq, gte, inArray } from "drizzle-orm";
import { db as defaultDb, type DB } from "./db.js";
import {
  accounts,
  announcements,
  applications,
  clientLogs,
  courses,
  enrollments,
  materials,
  materialTypes,
  payments,
  pulses,
  questions,
  sessions,
  streams,
  submissions,
} from "./schema.js";
import type {
  Announcement,
  AnnouncementDTO,
  Application,
  ClientLog,
  Course,
  CourseCard,
  CourseDetail,
  Enrollment,
  EnrolledStream,
  ApplicationInContext,
  HomeDigest,
  Material,
  MaterialDTO,
  MaterialInContext,
  MaterialType,
  Payment,
  PaymentDTO,
  Pulse,
  PulseSummary,
  Question,
  QuestionDTO,
  ResolvedStream,
  ScheduleItem,
  Session,
  Stream,
  StreamDetail,
  Submission,
} from "./types.js";

/** Хто дивиться список питань: свої впізнаються за accountId, авторів бачить лише адмін. */
export interface QuestionViewer {
  /** null — гість: питання бачить, але «своїх» серед них немає. */
  accountId: string | null;
  isAdmin: boolean;
}

export interface AskQuestionInput {
  sessionId: string;
  accountId: string;
  text: string;
  isAnonymous: boolean;
}

export interface DeclarePaymentInput {
  sessionId: string;
  accountId: string;
  amount?: number | null;
  receiptURL?: string | null;
  note?: string | null;
}

export interface ReceiptRef {
  fileId: string;
  chatId: string;
  messageId: number;
  /** Що прочитали зі скріншота на пристрої. */
  parsed?: unknown;
}

export interface MarkPaymentInput {
  sessionId: string;
  email: string;
  status: Payment["status"];
  amount?: number | null;
  note?: string | null;
}

export interface ClientLogInput {
  deviceId: string;
  appVersion?: string | null;
  event: string;
  detail?: string | null;
}

export type ApplicationStatus = "new" | "waitingPayment" | "enrolled" | "declined";

export interface ApplyInput {
  streamId: string;
  accountId: string;
  name: string;
  contact: string;
  comment?: string | null;
}

export interface RatePulseInput {
  sessionId: string;
  accountId: string;
  /** 1–5. */
  rating: number;
  comment?: string | null;
}

export interface SubmitHomeworkInput {
  materialId: string;
  accountId: string;
  text: string;
  authorEmail?: string | null;
}

/** Що задає адмін, клонуючи потік. */
export interface CloneStreamInput {
  title: string;
  /** Дата першого заняття нового потоку (ISO-дата). Решта зсувається на ту саму дельту. */
  startDate: string;
}

/** Серія однотипних занять. */
export interface SessionsBatchInput {
  streamId: string;
  /** Шаблон назви: до нього додається номер («Заняття» → «Заняття 1»). */
  titlePrefix: string;
  /** Початок першого заняття, ISO 8601 UTC. */
  startAt: string;
  count: number;
  /** Крок між заняттями в днях (7 = щотижня). */
  intervalDays: number;
  durationMinutes: number;
  joinURL?: string | null;
}

// Insert-форми (без id/createdAt — їх генерує схема).
type CourseInsert = Omit<typeof courses.$inferInsert, "id" | "createdAt">;
type StreamInsert = Omit<typeof streams.$inferInsert, "id" | "createdAt">;
type SessionInsert = Omit<typeof sessions.$inferInsert, "id">;
type MaterialInsert = Omit<typeof materials.$inferInsert, "id" | "createdAt">;
type MaterialTypeInsert = Omit<
  typeof materialTypes.$inferInsert,
  "id" | "createdAt"
>;

/**
 * Контракт доступу до даних. УСІ читання/записи йдуть лише сюди — ні роути,
 * ні відео-шар не торкаються Drizzle напряму. Замінивши реалізацію (Postgres,
 * файли, зовнішнє API), решту застосунку не чіпаємо.
 */
export interface CourseRepository {
  // — Читання (відкрите для застосунку) —
  listCourses(): Promise<CourseCard[]>;
  getCourseDetail(courseId: string): Promise<CourseDetail | null>;
  getStreamDetail(streamId: string, accountId?: string | null): Promise<StreamDetail | null>;
  getSchedule(accountId: string): Promise<ScheduleItem[]>;
  /** Зведення для екрана «Моє навчання». */
  getHomeDigest(accountId: string): Promise<HomeDigest>;
  listEnrollments(accountId: string): Promise<ResolvedStream[]>;
  listMaterialTypes(): Promise<MaterialType[]>;
  /** Сирий матеріал з videoRef — лише для відео-шару (playback). Не віддавати клієнту. */
  getMaterialRaw(materialId: string): Promise<Material | null>;

  // — Оголошення на потік —
  listAnnouncements(streamId: string): Promise<AnnouncementDTO[]>;
  createAnnouncement(streamId: string, text: string): Promise<Announcement>;
  deleteAnnouncement(id: string): Promise<boolean>;

  // — Здача домашки —
  /** Своя здача (або null). */
  getSubmission(materialId: string, accountId: string): Promise<Submission | null>;
  /** Здати або переписати свою — домашку доробляють, а не подають удруге. */
  submitHomework(input: SubmitHomeworkInput): Promise<Submission>;
  /** Усі здачі по матеріалу — адміну. */
  listSubmissions(materialId: string): Promise<Array<Submission & { email: string | null }>>;
  /** Відповідь викладача. */
  reviewSubmission(id: string, feedback: string): Promise<Submission | null>;

  // — Оплати (пара «заняття + людина») —
  /** Своя оплата за заняття. */
  getPayment(sessionId: string, accountId: string): Promise<Payment | null>;
  /** Заявити оплату (або переписати свою заявку, поки її не розглянули). */
  declarePayment(input: DeclarePaymentInput): Promise<Payment>;
  /** Усі заявки по заняттю — адміну. */
  listPayments(sessionId: string): Promise<Array<Payment & { email: string | null }>>;
  /** Прикріпити квитанцію (уже надіслану в телеграм) до заявки. */
  attachReceipt(id: string, receipt: ReceiptRef): Promise<Payment | null>;
  /** Оплата за id — щоб віддати квитанцію тому, кому можна. */
  getPaymentById(id: string): Promise<Payment | null>;
  /** Заняття за id — для підпису до квитанції. */
  getSessionById(id: string): Promise<Session | null>;
  /** Підтвердити, відхилити або звільнити від оплати. */
  setPaymentStatus(
    id: string,
    status: Payment["status"],
    note?: string | null,
  ): Promise<Payment | null>;
  /** Відмітити оплату за людину по пошті (акаунт може ще не існувати). */
  markPaymentByEmail(input: MarkPaymentInput): Promise<Payment>;

  // — Акаунти —
  /** Запам'ятати або оновити акаунт, що зайшов. Повертає його id. */
  touchAccount(input: { id: string; email: string; name?: string | null }): Promise<string>;
  /** Видалити акаунт з усім, що на ньому висить. Незворотно. */
  deleteAccount(accountId: string): Promise<boolean>;

  // — Логи з клієнтів —
  writeClientLog(input: ClientLogInput): Promise<void>;
  listClientLogs(limit: number): Promise<ClientLog[]>;

  // — Заявки на потік —
  getApplication(streamId: string, accountId: string): Promise<Application | null>;
  applyToStream(input: ApplyInput): Promise<Application>;
  listApplications(streamId: string): Promise<Application[]>;
  /** Усі нерозглянуті заявки з усіх потоків — щоб вони не губилися по курсах. */
  listPendingApplications(): Promise<ApplicationInContext[]>;
  /** Статус «enrolled» одразу підписує акаунт на потік — інакше довелося б робити це двічі. */
  setApplicationStatus(id: string, status: ApplicationStatus): Promise<Application | null>;

  // — Пульс після заняття —
  getPulse(sessionId: string, accountId: string): Promise<Pulse | null>;
  ratePulse(input: RatePulseInput): Promise<Pulse>;
  /** Зведення для викладача. */
  getPulseSummary(sessionId: string): Promise<PulseSummary>;

  // — Питання до заняття —
  /** `viewer` вирішує, кому показати автора: email бачить лише адмін. */
  listQuestions(sessionId: string, viewer: QuestionViewer): Promise<QuestionDTO[]>;
  askQuestion(input: AskQuestionInput): Promise<Question>;
  /** Видалити може автор (за accountId) або адмін. */
  deleteQuestion(id: string, viewer: QuestionViewer): Promise<boolean>;
  /** Позначити розібраним (адмін). */
  markQuestionAnswered(id: string, answered: boolean): Promise<Question | null>;

  // — Підписки (accountId) —
  subscribe(accountId: string, streamId: string): Promise<Enrollment>;
  unsubscribe(accountId: string, streamId: string): Promise<void>;
  isEnrolled(accountId: string, streamId: string): Promise<boolean>;

  // — Запис (адмін) —
  createCourse(input: CourseInsert): Promise<Course>;
  updateCourse(id: string, patch: Partial<CourseInsert>): Promise<Course | null>;
  deleteCourse(id: string): Promise<boolean>;

  createStream(input: StreamInsert): Promise<Stream>;
  updateStream(id: string, patch: Partial<StreamInsert>): Promise<Stream | null>;
  deleteStream(id: string): Promise<boolean>;

  /**
   * Копія потоку зі зсувом розкладу: потоки повторюються, і збирати наступний
   * руками щоразу — марна робота. Записи занять НЕ копіюються (вони належать
   * тому потоку, який їх записав), решта матеріалів — так.
   */
  cloneStream(streamId: string, input: CloneStreamInput): Promise<Stream | null>;

  createSession(input: SessionInsert): Promise<Session>;
  /** Серія занять «щочетверга о 20:00 × N» одним кроком. */
  createSessionsBatch(input: SessionsBatchInput): Promise<Session[]>;
  updateSession(
    id: string,
    patch: Partial<SessionInsert>,
  ): Promise<Session | null>;
  deleteSession(id: string): Promise<boolean>;

  createMaterial(input: MaterialInsert): Promise<Material>;
  updateMaterial(
    id: string,
    patch: Partial<MaterialInsert>,
  ): Promise<Material | null>;
  deleteMaterial(id: string): Promise<boolean>;

  createMaterialType(input: MaterialTypeInsert): Promise<MaterialType>;
  updateMaterialType(
    id: string,
    patch: Partial<MaterialTypeInsert>,
  ): Promise<MaterialType | null>;
  /** Видалення типу не чіпає матеріали — їхній typeId стає null (порожній тип). */
  deleteMaterialType(id: string): Promise<boolean>;
}

// — Хелпери відображення —

/** Застосовує override-поля потоку поверх курсу. */
function resolveStream(course: Course, stream: Stream): ResolvedStream {
  return {
    id: stream.id,
    courseId: stream.courseId,
    title: stream.title,
    startDate: stream.startDate,
    status: stream.status,
    telegramGroupURL: stream.telegramGroupURL,
    priceFull: stream.priceFull,
    pricePerSession: stream.pricePerSession,
    summary: stream.summaryOverride ?? course.summary,
    description: stream.descriptionOverride ?? course.description,
    program: stream.programOverride ?? course.program,
    coverImageURL: stream.coverImageOverride ?? course.coverImageURL,
  };
}

function toAnnouncementDTO(row: {
  a: Announcement;
  streamTitle: string;
  courseTitle: string;
}): AnnouncementDTO {
  return {
    id: row.a.id,
    streamId: row.a.streamId,
    streamTitle: row.streamTitle,
    courseTitle: row.courseTitle,
    text: row.a.text,
    createdAt: row.a.createdAt.toISOString(),
  };
}

/** Оплата для клієнта. accountId і email — лише коли дивиться адмін. */
export function toPaymentDTO(
  payment: Payment | undefined | null,
  forAdmin = false,
  email?: string | null,
): PaymentDTO | null {
  if (!payment) return null;
  return {
    id: payment.id,
    sessionId: payment.sessionId,
    status: payment.status,
    amount: payment.amount,
    receiptURL: payment.receiptURL,
    hasReceiptImage: payment.receiptFileId != null,
    receiptParsed: payment.receiptParsed,
    note: payment.note,
    declaredAt: payment.declaredAt,
    reviewedAt: payment.reviewedAt,
    ...(forAdmin
      ? { accountId: payment.accountId, authorEmail: email ?? null }
      : {}),
  };
}

/** Прибирає videoRef/ownerId з матеріалу для клієнта. */
function toMaterialDTO(m: Material): MaterialDTO {
  return {
    id: m.id,
    title: m.title,
    typeId: m.typeId,
    description: m.description,
    url: m.url,
    dueAt: m.dueAt,
    order: m.order,
    hasVideo: m.videoRef != null,
    videoProvider: m.videoProvider,
    durationMinutes: m.durationMinutes,
  };
}

function pickNextStream(list: Stream[]): Stream | null {
  if (list.length === 0) return null;
  const active = list
    .filter((s) => s.status !== "finished")
    .sort((a, b) => (a.startDate ?? "").localeCompare(b.startDate ?? ""));
  if (active.length > 0) return active[0]!;
  // Усі завершені — беремо найсвіжіший.
  return [...list].sort((a, b) =>
    (b.startDate ?? "").localeCompare(a.startDate ?? ""),
  )[0]!;
}

/** Реалізація на Drizzle. better-sqlite3 синхронний; методи async — для портативності. */
export class DrizzleCourseRepository implements CourseRepository {
  constructor(private readonly db: DB = defaultDb) {}

  async listCourses(): Promise<CourseCard[]> {
    const courseRows = this.db
      .select()
      .from(courses)
      .orderBy(asc(courses.order), asc(courses.title))
      .all();
    const streamRows = this.db.select().from(streams).all();

    return courseRows.map((c) => {
      const own = streamRows.filter((s) => s.courseId === c.id);
      const next = pickNextStream(own);
      return {
        id: c.id,
        title: c.title,
        summary: c.summary,
        format: c.format,
        coverImageURL: c.coverImageURL,
        nextStream: next
          ? {
              id: next.id,
              title: next.title,
              startDate: next.startDate,
              status: next.status,
            }
          : null,
      };
    });
  }

  async getCourseDetail(courseId: string): Promise<CourseDetail | null> {
    const course = this.db
      .select()
      .from(courses)
      .where(eq(courses.id, courseId))
      .get();
    if (!course) return null;

    const own = this.db
      .select()
      .from(streams)
      .where(eq(streams.courseId, courseId))
      .orderBy(asc(streams.order), desc(streams.startDate))
      .all();

    const courseMaterials = this.db
      .select()
      .from(materials)
      .where(
        and(eq(materials.ownerType, "course"), eq(materials.ownerId, courseId)),
      )
      .orderBy(asc(materials.order))
      .all();

    return {
      id: course.id,
      title: course.title,
      summary: course.summary,
      description: course.description,
      program: course.program,
      format: course.format,
      coverImageURL: course.coverImageURL,
      streams: own.map((s) => resolveStream(course, s)),
      materials: courseMaterials.map(toMaterialDTO),
    };
  }

  async getStreamDetail(
    streamId: string,
    accountId?: string | null,
  ): Promise<StreamDetail | null> {
    const stream = this.db
      .select()
      .from(streams)
      .where(eq(streams.id, streamId))
      .get();
    if (!stream) return null;
    const course = this.db
      .select()
      .from(courses)
      .where(eq(courses.id, stream.courseId))
      .get();
    if (!course) return null;

    const streamSessions = this.db
      .select()
      .from(sessions)
      .where(eq(sessions.streamId, streamId))
      .orderBy(asc(sessions.order), asc(sessions.startAt))
      .all();

    const streamMaterials = this.db
      .select()
      .from(materials)
      .where(
        and(eq(materials.ownerType, "stream"), eq(materials.ownerId, streamId)),
      )
      .orderBy(asc(materials.order))
      .all();

    // Оплати того, хто питає: стан «оплачено» тепер персональний, і без
    // accountId ми не можемо сказати нічого — тоді просто нічого й не кажемо.
    const myPayments = new Map<string, Payment>();
    if (accountId && streamSessions.length) {
      for (const p of this.db
        .select()
        .from(payments)
        .where(
          and(
            eq(payments.accountId, accountId),
            inArray(payments.sessionId, streamSessions.map((s) => s.id)),
          ),
        )
        .all()) {
        myPayments.set(p.sessionId, p);
      }
    }

    // Матеріали занять тягнемо одним запитом на весь потік, а не по одному на
    // заняття: інакше сторінка з десятком зустрічей робить десяток запитів.
    const sessionIds = streamSessions.map((s) => s.id);
    const sessionMaterials = sessionIds.length
      ? this.db
          .select()
          .from(materials)
          .where(
            and(
              eq(materials.ownerType, "session"),
              inArray(materials.ownerId, sessionIds),
            ),
          )
          .orderBy(asc(materials.order))
          .all()
      : [];

    return {
      ...resolveStream(course, stream),
      sessions: streamSessions.map((session) => ({
        session,
        materials: sessionMaterials
          .filter((m) => m.ownerId === session.id)
          .map(toMaterialDTO),
        payment: toPaymentDTO(myPayments.get(session.id)),
      })),
      materials: streamMaterials.map(toMaterialDTO),
      summaryOverride: stream.summaryOverride,
      descriptionOverride: stream.descriptionOverride,
      programOverride: stream.programOverride,
      coverImageOverride: stream.coverImageOverride,
    };
  }

  async getSchedule(accountId: string): Promise<ScheduleItem[]> {
    const enrolled = this.db
      .select({ streamId: enrollments.streamId })
      .from(enrollments)
      .where(eq(enrollments.accountId, accountId))
      .all();
    const streamIds = enrolled.map((e) => e.streamId);
    if (streamIds.length === 0) return [];

    const nowIso = new Date().toISOString();
    const rows = this.db
      .select({
        session: sessions,
        streamId: streams.id,
        streamTitle: streams.title,
        courseId: courses.id,
        courseTitle: courses.title,
      })
      .from(sessions)
      .innerJoin(streams, eq(sessions.streamId, streams.id))
      .innerJoin(courses, eq(streams.courseId, courses.id))
      .where(
        and(inArray(sessions.streamId, streamIds), gte(sessions.startAt, nowIso)),
      )
      .orderBy(asc(sessions.startAt))
      .all();

    const myPayments = new Map<string, Payment>();
    for (const p of this.db
      .select()
      .from(payments)
      .where(eq(payments.accountId, accountId))
      .all()) {
      myPayments.set(p.sessionId, p);
    }

    return rows.map((r) => ({
      session: r.session,
      payment: toPaymentDTO(myPayments.get(r.session.id)),
      streamId: r.streamId,
      streamTitle: r.streamTitle,
      courseId: r.courseId,
      courseTitle: r.courseTitle,
    }));
  }

  /**
   * Зведення «Моє навчання». Каталог — вітрина для нових; тому, хто вже вчиться,
   * потрібне інше: коли наступне заняття, що не здано і які записи є.
   */
  async getHomeDigest(accountId: string): Promise<HomeDigest> {
    const schedule = await this.getSchedule(accountId);
    const [nextSession, ...upcoming] = schedule;

    const streamRows = this.db
      .select({
        streamId: streams.id,
        streamTitle: streams.title,
        streamStatus: streams.status,
        courseId: courses.id,
        courseTitle: courses.title,
      })
      .from(enrollments)
      .innerJoin(streams, eq(enrollments.streamId, streams.id))
      .innerJoin(courses, eq(streams.courseId, courses.id))
      .where(eq(enrollments.accountId, accountId))
      .all();
    if (streamRows.length === 0) {
      return {
        streams: [],
        nextSession: null,
        announcements: [],
        upcoming: [],
        homework: [],
        recordings: [],
      };
    }

    const context = new Map(streamRows.map((r) => [r.streamId, r]));

    // «Де я вчуся» — окремо від «що найближче»: курс, у якого всі заняття вже
    // позаду, з екрана зникав зовсім, лишаючи по собі самі записи без назви.
    const now = new Date().toISOString();
    const allSessions = this.db
      .select({ id: sessions.id, streamId: sessions.streamId, startAt: sessions.startAt })
      .from(sessions)
      .where(inArray(sessions.streamId, [...context.keys()]))
      .orderBy(asc(sessions.startAt))
      .all();
    const paidSessionIds = new Set(
      this.db
        .select({ sessionId: payments.sessionId })
        .from(payments)
        .where(
          and(
            eq(payments.accountId, accountId),
            inArray(payments.status, ["confirmed", "free"]),
          ),
        )
        .all()
        .map((p) => p.sessionId),
    );

    const enrolled: EnrolledStream[] = streamRows.map((row) => {
      const own = allSessions.filter((s) => s.streamId === row.streamId);
      return {
        streamId: row.streamId,
        streamTitle: row.streamTitle,
        status: row.streamStatus,
        courseId: row.courseId,
        courseTitle: row.courseTitle,
        sessionsPassed: own.filter((s) => s.startAt <= now).length,
        sessionsTotal: own.length,
        nextSessionAt: own.find((s) => s.startAt > now)?.startAt ?? null,
        unpaidSessions: own.filter((s) => !paidSessionIds.has(s.id)).length,
      };
    });
    // Спершу ті, що тривають: завершений курс — довідка, а не те, чим живуть.
    const rank = (s: EnrolledStream) => (s.status === "finished" ? 1 : 0);
    enrolled.sort((a, b) => {
      if (rank(a) !== rank(b)) return rank(a) - rank(b);
      if (!!a.nextSessionAt !== !!b.nextSessionAt) return a.nextSessionAt ? -1 : 1;
      return (a.nextSessionAt ?? "") < (b.nextSessionAt ?? "") ? -1 : 1;
    });
    // Матеріали потоку — і матеріали його занять: після того, як записи
    // переїхали на заняття, пошук лише по потоку перестав їх знаходити,
    // і секція «Записи занять» на головному екрані спорожніла.
    const streamSessionIds = this.db
      .select({ id: sessions.id, streamId: sessions.streamId })
      .from(sessions)
      .where(inArray(sessions.streamId, [...context.keys()]))
      .all();
    const sessionToStream = new Map(streamSessionIds.map((s) => [s.id, s.streamId]));

    const streamMaterials = this.db
      .select()
      .from(materials)
      .where(
        and(
          eq(materials.ownerType, "stream"),
          inArray(materials.ownerId, [...context.keys()]),
        ),
      )
      .orderBy(asc(materials.order))
      .all();

    const ofSessions = streamSessionIds.length
      ? this.db
          .select()
          .from(materials)
          .where(
            and(
              eq(materials.ownerType, "session"),
              inArray(materials.ownerId, [...sessionToStream.keys()]),
            ),
          )
          .orderBy(asc(materials.order))
          .all()
      : [];

    const withContext = (m: Material): MaterialInContext => {
      const streamId = m.ownerType === "session"
        ? sessionToStream.get(m.ownerId)!
        : m.ownerId;
      return { material: toMaterialDTO(m), ...context.get(streamId)! };
    };

    // Щойно прострочену домашку теж показуємо: зникнути рівно о дедлайні —
    // найгірший момент, саме тоді про неї згадують.
    const graceFrom = new Date(Date.now() - 7 * 86_400_000).toISOString();
    const homework = [...streamMaterials, ...ofSessions]
      .filter((m) => m.dueAt && m.dueAt >= graceFrom)
      .sort((a, b) => (a.dueAt! < b.dueAt! ? -1 : 1))
      .slice(0, 5)
      .map(withContext);

    // Спершу найсвіжіші: до купи записів за півроку цікавить останній.
    const recordings = [...ofSessions, ...streamMaterials]
      .filter((m) => m.videoRef)
      .reverse()
      .slice(0, 5)
      .map(withContext);

    const announcementRows = this.db
      .select({ a: announcements, streamTitle: streams.title, courseTitle: courses.title })
      .from(announcements)
      .innerJoin(streams, eq(announcements.streamId, streams.id))
      .innerJoin(courses, eq(streams.courseId, courses.id))
      .where(inArray(announcements.streamId, [...context.keys()]))
      .orderBy(desc(announcements.createdAt))
      .limit(5)
      .all();

    return {
      streams: enrolled,
      nextSession: nextSession ?? null,
      announcements: announcementRows.map(toAnnouncementDTO),
      upcoming: upcoming.slice(0, 3),
      homework,
      recordings,
    };
  }

  // — Оплати —

  async getPayment(sessionId: string, accountId: string): Promise<Payment | null> {
    return (
      this.db
        .select()
        .from(payments)
        .where(and(eq(payments.sessionId, sessionId), eq(payments.accountId, accountId)))
        .get() ?? null
    );
  }

  async declarePayment(input: DeclarePaymentInput): Promise<Payment> {
    const existing = await this.getPayment(input.sessionId, input.accountId);
    const now = new Date().toISOString();
    if (existing) {
      // Поки заявку не розглянули, її можна виправити — наприклад, прикріпити
      // квитанцію, про яку забули. Підтверджену не чіпаємо.
      if (existing.status === "confirmed" || existing.status === "free") return existing;
      return this.db
        .update(payments)
        .set({
          amount: input.amount ?? existing.amount,
          receiptURL: input.receiptURL ?? existing.receiptURL,
          note: input.note ?? existing.note,
          status: "declared",
          declaredAt: now,
        })
        .where(eq(payments.id, existing.id))
        .returning()
        .get();
    }
    return this.db
      .insert(payments)
      .values({
        sessionId: input.sessionId,
        accountId: input.accountId,
        amount: input.amount ?? null,
        receiptURL: input.receiptURL ?? null,
        note: input.note ?? null,
        status: "declared",
        declaredAt: now,
      })
      .returning()
      .get();
  }

  async attachReceipt(id: string, receipt: ReceiptRef): Promise<Payment | null> {
    return (
      this.db
        .update(payments)
        .set({
          receiptFileId: receipt.fileId,
          receiptChatId: receipt.chatId,
          receiptMessageId: receipt.messageId,
          receiptParsed: receipt.parsed ? JSON.stringify(receipt.parsed) : null,
        })
        .where(eq(payments.id, id))
        .returning()
        .get() ?? null
    );
  }

  async getPaymentById(id: string): Promise<Payment | null> {
    return this.db.select().from(payments).where(eq(payments.id, id)).get() ?? null;
  }

  async getSessionById(id: string): Promise<Session | null> {
    return this.db.select().from(sessions).where(eq(sessions.id, id)).get() ?? null;
  }

  async listPayments(sessionId: string): Promise<Array<Payment & { email: string | null }>> {
    const rows = this.db
      .select({ payment: payments, email: accounts.email })
      .from(payments)
      .leftJoin(accounts, eq(payments.accountId, accounts.id))
      .where(eq(payments.sessionId, sessionId))
      .orderBy(asc(payments.declaredAt))
      .all();
    return rows.map((r) => ({ ...r.payment, email: r.email }));
  }

  async setPaymentStatus(
    id: string,
    status: Payment["status"],
    note?: string | null,
  ): Promise<Payment | null> {
    return (
      this.db
        .update(payments)
        .set({ status, note: note ?? null, reviewedAt: new Date().toISOString() })
        .where(eq(payments.id, id))
        .returning()
        .get() ?? null
    );
  }

  async markPaymentByEmail(input: MarkPaymentInput): Promise<Payment> {
    const accountId = await this.accountIdForEmail(input.email);
    const now = new Date().toISOString();
    const existing = this.db
      .select()
      .from(payments)
      .where(and(eq(payments.sessionId, input.sessionId), eq(payments.accountId, accountId)))
      .get();

    if (existing) {
      return this.db
        .update(payments)
        .set({
          status: input.status,
          // Суму й нотатку не затираємо, якщо їх не передали: студент міг сам
          // заявити оплату з квитанцією, і викладач лише підтверджує.
          amount: input.amount ?? existing.amount,
          note: input.note ?? existing.note,
          reviewedAt: now,
        })
        .where(eq(payments.id, existing.id))
        .returning()
        .get();
    }

    return this.db
      .insert(payments)
      .values({
        sessionId: input.sessionId,
        accountId,
        status: input.status,
        amount: input.amount ?? null,
        note: input.note ?? null,
        declaredAt: now,
        reviewedAt: now,
      })
      .returning()
      .get();
  }

  /** Акаунт за поштою; якщо людина ще не входила — заочний. */
  private async accountIdForEmail(email: string): Promise<string> {
    const normalized = email.trim().toLowerCase();
    const existing = this.db
      .select()
      .from(accounts)
      .where(eq(accounts.email, normalized))
      .get();
    if (existing) return existing.id;

    const id = DrizzleCourseRepository.placeholderAccountId(normalized);
    this.db.insert(accounts).values({ id, email: normalized }).run();
    return id;
  }

  // — Акаунти —

  /**
   * Заочний акаунт: викладач знає пошту студента задовго до того, як той
   * поставить застосунок. Такий акаунт тримає оплати й доступи, поки людина
   * не увійде вперше — тоді `touchAccount` перенесе все на справжній номер
   * Google-акаунта й видалить заглушку.
   */
  static placeholderAccountId(email: string): string {
    return `email:${email.trim().toLowerCase()}`;
  }

  /**
   * Забирає заочний акаунт із тією ж поштою під справжній номер акаунта.
   * Переносимо рядки, а не міняємо ключ: FK оголошені без ON UPDATE CASCADE,
   * і мовчазна зміна первинного ключа — надто тихий спосіб втратити дані.
   */
  private claimPlaceholder(realId: string, email: string): void {
    const placeholderId = DrizzleCourseRepository.placeholderAccountId(email);
    if (placeholderId === realId) return;
    const placeholder = this.db
      .select()
      .from(accounts)
      .where(eq(accounts.id, placeholderId))
      .get();
    if (!placeholder) return;

    this.db.transaction((tx) => {
      for (const table of [payments, enrollments, questions, submissions, pulses, applications]) {
        tx.update(table)
          .set({ accountId: realId })
          .where(eq(table.accountId, placeholderId))
          .run();
      }
      tx.delete(accounts).where(eq(accounts.id, placeholderId)).run();
    });
  }

  async touchAccount(input: {
    id: string;
    email: string;
    name?: string | null;
  }): Promise<string> {
    const now = new Date().toISOString();
    const existing = this.db
      .select()
      .from(accounts)
      .where(eq(accounts.id, input.id))
      .get();
    if (existing) {
      // Пошту оновлюємо щоразу: людина могла її змінити, а нам із нею шарити відео.
      this.db
        .update(accounts)
        .set({ email: input.email, name: input.name ?? existing.name, lastSeenAt: now })
        .where(eq(accounts.id, input.id))
        .run();
    } else {
      this.db
        .insert(accounts)
        .values({ id: input.id, email: input.email, name: input.name ?? null, lastSeenAt: now })
        .run();
    }
    // Могли відмітити оплату наперед — тепер їй є до кого прикріпитися.
    this.claimPlaceholder(input.id, input.email);
    return input.id;
  }

  /**
   * Видаляє акаунт і все особисте разом із ним — цього вимагає App Store
   * (5.1.1(v)): якщо застосунок заводить акаунти, він має вміти їх стирати.
   *
   * Дочірні рядки йдуть каскадом за FK, тому це справді видалення, а не
   * позначка «видалений». Квитанції, вже надіслані в телеграм викладачу,
   * лишаються там: це його бухгалтерія, а не наші дані.
   */
  async deleteAccount(accountId: string): Promise<boolean> {
    const result = this.db.delete(accounts).where(eq(accounts.id, accountId)).run();
    return result.changes > 0;
  }

  // — Логи з клієнтів —

  async writeClientLog(input: ClientLogInput): Promise<void> {
    this.db.insert(clientLogs).values({
      deviceId: input.deviceId,
      appVersion: input.appVersion ?? null,
      event: input.event,
      // Обрізаємо: з телефона може прилетіти дуже багатослівна помилка.
      detail: input.detail?.slice(0, 4000) ?? null,
    }).run();
  }

  async listClientLogs(limit: number): Promise<ClientLog[]> {
    return this.db
      .select()
      .from(clientLogs)
      .orderBy(desc(clientLogs.createdAt))
      .limit(limit)
      .all();
  }

  // — Заявки на потік —

  async getApplication(
    streamId: string,
    accountId: string,
  ): Promise<Application | null> {
    return (
      this.db
        .select()
        .from(applications)
        .where(
          and(
            eq(applications.streamId, streamId),
            eq(applications.accountId, accountId),
          ),
        )
        .get() ?? null
    );
  }

  async applyToStream(input: ApplyInput): Promise<Application> {
    const existing = await this.getApplication(input.streamId, input.accountId);
    if (existing) {
      // Передумав щодо контакту чи коментаря — оновлюємо, але статус лишаємо
      // за викладачем: не студенту вирішувати, що він уже зарахований.
      return this.db
        .update(applications)
        .set({
          name: input.name,
          contact: input.contact,
          comment: input.comment ?? null,
        })
        .where(eq(applications.id, existing.id))
        .returning()
        .get();
    }
    return this.db
      .insert(applications)
      .values({
        streamId: input.streamId,
        accountId: input.accountId,
        name: input.name,
        contact: input.contact,
        comment: input.comment ?? null,
      })
      .returning()
      .get();
  }

  async listApplications(streamId: string): Promise<Application[]> {
    return this.db
      .select()
      .from(applications)
      .where(eq(applications.streamId, streamId))
      .orderBy(asc(applications.createdAt))
      .all();
  }

  async listPendingApplications(): Promise<ApplicationInContext[]> {
    return this.db
      .select({
        application: applications,
        streamId: streams.id,
        streamTitle: streams.title,
        courseTitle: courses.title,
      })
      .from(applications)
      .innerJoin(streams, eq(applications.streamId, streams.id))
      .innerJoin(courses, eq(streams.courseId, courses.id))
      // «Очікує оплати» теж нерозглянута: людина вже сказала «хочу», і поки
      // викладач не поставив «зараховано», курс у неї не з'явиться.
      .where(inArray(applications.status, ["new", "waitingPayment"]))
      .orderBy(asc(applications.createdAt))
      .all();
  }

  async setApplicationStatus(
    id: string,
    status: ApplicationStatus,
  ): Promise<Application | null> {
    const updated =
      this.db
        .update(applications)
        .set({ status })
        .where(eq(applications.id, id))
        .returning()
        .get() ?? null;
    if (updated && status === "enrolled") {
      // Зарахували — значить, потік має зʼявитися в людини на екрані
      // «Навчання» сам, без окремої дії «підписатися».
      await this.subscribe(updated.accountId, updated.streamId);
    }
    return updated;
  }

  // — Пульс після заняття —

  async getPulse(sessionId: string, accountId: string): Promise<Pulse | null> {
    return (
      this.db
        .select()
        .from(pulses)
        .where(and(eq(pulses.sessionId, sessionId), eq(pulses.accountId, accountId)))
        .get() ?? null
    );
  }

  async ratePulse(input: RatePulseInput): Promise<Pulse> {
    const existing = await this.getPulse(input.sessionId, input.accountId);
    if (existing) {
      return this.db
        .update(pulses)
        .set({ rating: input.rating, comment: input.comment ?? null })
        .where(eq(pulses.id, existing.id))
        .returning()
        .get();
    }
    return this.db
      .insert(pulses)
      .values({
        sessionId: input.sessionId,
        accountId: input.accountId,
        rating: input.rating,
        comment: input.comment ?? null,
      })
      .returning()
      .get();
  }

  async getPulseSummary(sessionId: string): Promise<PulseSummary> {
    const rows = this.db
      .select()
      .from(pulses)
      .where(eq(pulses.sessionId, sessionId))
      .orderBy(desc(pulses.createdAt))
      .all();

    const histogram = [0, 0, 0, 0, 0];
    for (const r of rows) {
      const bucket = Math.min(5, Math.max(1, r.rating)) - 1;
      histogram[bucket]! += 1;
    }
    const sum = rows.reduce((acc, r) => acc + r.rating, 0);
    return {
      sessionId,
      count: rows.length,
      average: rows.length ? Math.round((sum / rows.length) * 10) / 10 : 0,
      histogram,
      comments: rows.map((r) => r.comment).filter((c): c is string => !!c),
    };
  }

  // — Здача домашки —

  async getSubmission(
    materialId: string,
    accountId: string,
  ): Promise<Submission | null> {
    return (
      this.db
        .select()
        .from(submissions)
        .where(
          and(
            eq(submissions.materialId, materialId),
            eq(submissions.accountId, accountId),
          ),
        )
        .get() ?? null
    );
  }

  async submitHomework(input: SubmitHomeworkInput): Promise<Submission> {
    const existing = await this.getSubmission(input.materialId, input.accountId);
    const now = new Date().toISOString();
    if (existing) {
      // Переписуємо текст, але НЕ чіпаємо відповідь викладача: зникла б рецензія
      // разом із виправленням, а вона й до виправлення стосується.
      return this.db
        .update(submissions)
        .set({ text: input.text, submittedAt: now })
        .where(eq(submissions.id, existing.id))
        .returning()
        .get();
    }
    return this.db
      .insert(submissions)
      .values({
        materialId: input.materialId,
        accountId: input.accountId,
        text: input.text,
        submittedAt: now,
      })
      .returning()
      .get();
  }

  async listSubmissions(
    materialId: string,
  ): Promise<Array<Submission & { email: string | null }>> {
    const rows = this.db
      .select({ submission: submissions, email: accounts.email })
      .from(submissions)
      .leftJoin(accounts, eq(submissions.accountId, accounts.id))
      .where(eq(submissions.materialId, materialId))
      .orderBy(asc(submissions.submittedAt))
      .all();
    return rows.map((r) => ({ ...r.submission, email: r.email }));
  }

  async reviewSubmission(
    id: string,
    feedback: string,
  ): Promise<Submission | null> {
    return (
      this.db
        .update(submissions)
        .set({ feedback, reviewedAt: new Date().toISOString() })
        .where(eq(submissions.id, id))
        .returning()
        .get() ?? null
    );
  }

  // — Оголошення на потік —

  async listAnnouncements(streamId: string): Promise<AnnouncementDTO[]> {
    const rows = this.db
      .select({ a: announcements, streamTitle: streams.title, courseTitle: courses.title })
      .from(announcements)
      .innerJoin(streams, eq(announcements.streamId, streams.id))
      .innerJoin(courses, eq(streams.courseId, courses.id))
      .where(eq(announcements.streamId, streamId))
      .orderBy(desc(announcements.createdAt))
      .all();
    return rows.map(toAnnouncementDTO);
  }

  async createAnnouncement(streamId: string, text: string): Promise<Announcement> {
    return this.db
      .insert(announcements)
      .values({ streamId, text })
      .returning()
      .get();
  }

  async deleteAnnouncement(id: string): Promise<boolean> {
    return (
      this.db.delete(announcements).where(eq(announcements.id, id)).returning().all()
        .length > 0
    );
  }

  // — Питання до заняття —

  async listQuestions(
    sessionId: string,
    viewer: QuestionViewer,
  ): Promise<QuestionDTO[]> {
    const rows = this.db
      .select()
      .from(questions)
      .where(eq(questions.sessionId, sessionId))
      .orderBy(asc(questions.createdAt))
      .all();

    // Пошту тягнемо з акаунтів однією вибіркою — копії в питаннях не тримаємо.
    const emails = new Map<string, string>();
    if (viewer.isAdmin && rows.length) {
      for (const a of this.db
        .select()
        .from(accounts)
        .where(inArray(accounts.id, rows.map((r) => r.accountId)))
        .all()) {
        emails.set(a.id, a.email);
      }
    }

    return rows.map((q) => ({
      id: q.id,
      sessionId: q.sessionId,
      text: q.text,
      createdAt: q.createdAt.toISOString(),
      answeredAt: q.answeredAt,
      isMine: q.accountId === viewer.accountId,
      // Автора віддаємо лише адміну й лише якщо питання не анонімне.
      ...(viewer.isAdmin
        ? { authorEmail: q.isAnonymous ? null : emails.get(q.accountId) ?? null }
        : {}),
    }));
  }

  async askQuestion(input: AskQuestionInput): Promise<Question> {
    return this.db
      .insert(questions)
      .values({
        sessionId: input.sessionId,
        accountId: input.accountId,
        text: input.text,
        isAnonymous: input.isAnonymous,
      })
      .returning()
      .get();
  }

  async deleteQuestion(id: string, viewer: QuestionViewer): Promise<boolean> {
    const existing = this.db
      .select()
      .from(questions)
      .where(eq(questions.id, id))
      .get();
    if (!existing) return false;
    if (!viewer.isAdmin && existing.accountId !== viewer.accountId) return false;
    this.db.delete(questions).where(eq(questions.id, id)).run();
    return true;
  }

  async markQuestionAnswered(
    id: string,
    answered: boolean,
  ): Promise<Question | null> {
    return (
      this.db
        .update(questions)
        .set({ answeredAt: answered ? new Date().toISOString() : null })
        .where(eq(questions.id, id))
        .returning()
        .get() ?? null
    );
  }

  async listEnrollments(accountId: string): Promise<ResolvedStream[]> {
    const rows = this.db
      .select({ stream: streams, course: courses })
      .from(enrollments)
      .innerJoin(streams, eq(enrollments.streamId, streams.id))
      .innerJoin(courses, eq(streams.courseId, courses.id))
      .where(eq(enrollments.accountId, accountId))
      .all();
    return rows.map((r) => resolveStream(r.course, r.stream));
  }

  async listMaterialTypes(): Promise<MaterialType[]> {
    return this.db
      .select()
      .from(materialTypes)
      .orderBy(asc(materialTypes.order), asc(materialTypes.name))
      .all();
  }

  async getMaterialRaw(materialId: string): Promise<Material | null> {
    return (
      this.db.select().from(materials).where(eq(materials.id, materialId)).get() ??
      null
    );
  }

  async subscribe(accountId: string, streamId: string): Promise<Enrollment> {
    const existing = this.db
      .select()
      .from(enrollments)
      .where(
        and(
          eq(enrollments.accountId, accountId),
          eq(enrollments.streamId, streamId),
        ),
      )
      .get();
    if (existing) return existing;
    return this.db
      .insert(enrollments)
      .values({ accountId, streamId, subscribedAt: new Date().toISOString() })
      .returning()
      .get();
  }

  async unsubscribe(accountId: string, streamId: string): Promise<void> {
    this.db
      .delete(enrollments)
      .where(
        and(
          eq(enrollments.accountId, accountId),
          eq(enrollments.streamId, streamId),
        ),
      )
      .run();
  }

  async isEnrolled(accountId: string, streamId: string): Promise<boolean> {
    const row = this.db
      .select({ id: enrollments.id })
      .from(enrollments)
      .where(
        and(
          eq(enrollments.accountId, accountId),
          eq(enrollments.streamId, streamId),
        ),
      )
      .get();
    return row != null;
  }

  // — CRUD: courses —
  async createCourse(input: CourseInsert): Promise<Course> {
    return this.db.insert(courses).values(input).returning().get();
  }
  async updateCourse(
    id: string,
    patch: Partial<CourseInsert>,
  ): Promise<Course | null> {
    return (
      this.db
        .update(courses)
        .set(patch)
        .where(eq(courses.id, id))
        .returning()
        .get() ?? null
    );
  }
  async deleteCourse(id: string): Promise<boolean> {
    const res = this.db.delete(courses).where(eq(courses.id, id)).run();
    return res.changes > 0;
  }

  // — CRUD: streams —
  async createStream(input: StreamInsert): Promise<Stream> {
    return this.db.insert(streams).values(input).returning().get();
  }
  async updateStream(
    id: string,
    patch: Partial<StreamInsert>,
  ): Promise<Stream | null> {
    return (
      this.db
        .update(streams)
        .set(patch)
        .where(eq(streams.id, id))
        .returning()
        .get() ?? null
    );
  }
  async deleteStream(id: string): Promise<boolean> {
    const res = this.db.delete(streams).where(eq(streams.id, id)).run();
    return res.changes > 0;
  }

  // — CRUD: sessions —
  async cloneStream(
    streamId: string,
    input: CloneStreamInput,
  ): Promise<Stream | null> {
    const source = this.db
      .select()
      .from(streams)
      .where(eq(streams.id, streamId))
      .get();
    if (!source) return null;

    const sourceSessions = this.db
      .select()
      .from(sessions)
      .where(eq(sessions.streamId, streamId))
      .orderBy(asc(sessions.startAt))
      .all();

    const created = this.db
      .insert(streams)
      .values({
        courseId: source.courseId,
        title: input.title,
        startDate: input.startDate,
        status: "upcoming",
        telegramGroupURL: source.telegramGroupURL,
        priceFull: source.priceFull,
        pricePerSession: source.pricePerSession,
        summaryOverride: source.summaryOverride,
        descriptionOverride: source.descriptionOverride,
        programOverride: source.programOverride,
        coverImageOverride: source.coverImageOverride,
        order: source.order + 1,
      })
      .returning()
      .get();

    // Зсуваємо весь розклад на ту саму дельту, зберігаючи час доби й проміжки
    // між заняттями: «той самий курс, просто починається іншого дня».
    const first = sourceSessions[0];
    if (first) {
      const shiftMs = Date.parse(`${input.startDate}T00:00:00Z`) -
        Date.parse(`${first.startAt.slice(0, 10)}T00:00:00Z`);
      this.db
        .insert(sessions)
        .values(
          sourceSessions.map((s) => ({
            streamId: created.id,
            title: s.title,
            startAt: new Date(Date.parse(s.startAt) + shiftMs).toISOString()
              .replace(".000Z", "Z"),
            durationMinutes: s.durationMinutes,
            format: s.format,
            joinURL: s.joinURL,
            paymentStatus: "unpaid" as const,
            order: s.order,
          })),
        )
        .run();
    }

    // Записи занять не копіюємо — вони належать тому потоку, який їх записав.
    // Домашка, конспекти й посилання переносяться: вони про курс, не про потік.
    const carried = this.db
      .select()
      .from(materials)
      .where(and(eq(materials.ownerType, "stream"), eq(materials.ownerId, streamId)))
      .all()
      .filter((m) => !m.videoRef);
    if (carried.length > 0) {
      this.db
        .insert(materials)
        .values(
          carried.map((m) => ({
            ownerType: "stream" as const,
            ownerId: created.id,
            typeId: m.typeId,
            title: m.title,
            description: m.description,
            url: m.url,
            // Дедлайн прив'язаний до старого розкладу — переносити його наосліп
            // гірше, ніж лишити порожнім: адмін виставить під новий потік.
            dueAt: null,
            order: m.order,
          })),
        )
        .run();
    }

    return created;
  }

  async createSession(input: SessionInsert): Promise<Session> {
    return this.db.insert(sessions).values(input).returning().get();
  }

  async createSessionsBatch(input: SessionsBatchInput): Promise<Session[]> {
    const start = Date.parse(input.startAt);
    const step = input.intervalDays * 86_400_000;
    const rows = Array.from({ length: input.count }, (_, i) => ({
      streamId: input.streamId,
      title: `${input.titlePrefix} ${i + 1}`.trim(),
      startAt: new Date(start + i * step).toISOString().replace(".000Z", "Z"),
      durationMinutes: input.durationMinutes,
      joinURL: input.joinURL ?? null,
      order: i + 1,
    }));
    return this.db.insert(sessions).values(rows).returning().all();
  }
  async updateSession(
    id: string,
    patch: Partial<SessionInsert>,
  ): Promise<Session | null> {
    return (
      this.db
        .update(sessions)
        .set(patch)
        .where(eq(sessions.id, id))
        .returning()
        .get() ?? null
    );
  }
  async deleteSession(id: string): Promise<boolean> {
    const res = this.db.delete(sessions).where(eq(sessions.id, id)).run();
    return res.changes > 0;
  }

  // — CRUD: materials —
  async createMaterial(input: MaterialInsert): Promise<Material> {
    return this.db.insert(materials).values(input).returning().get();
  }
  async updateMaterial(
    id: string,
    patch: Partial<MaterialInsert>,
  ): Promise<Material | null> {
    return (
      this.db
        .update(materials)
        .set(patch)
        .where(eq(materials.id, id))
        .returning()
        .get() ?? null
    );
  }
  async deleteMaterial(id: string): Promise<boolean> {
    const res = this.db.delete(materials).where(eq(materials.id, id)).run();
    return res.changes > 0;
  }

  // — CRUD: material types —
  async createMaterialType(input: MaterialTypeInsert): Promise<MaterialType> {
    return this.db.insert(materialTypes).values(input).returning().get();
  }
  async updateMaterialType(
    id: string,
    patch: Partial<MaterialTypeInsert>,
  ): Promise<MaterialType | null> {
    return (
      this.db
        .update(materialTypes)
        .set(patch)
        .where(eq(materialTypes.id, id))
        .returning()
        .get() ?? null
    );
  }
  async deleteMaterialType(id: string): Promise<boolean> {
    const res = this.db
      .delete(materialTypes)
      .where(eq(materialTypes.id, id))
      .run();
    return res.changes > 0;
  }
}

export const repository: CourseRepository = new DrizzleCourseRepository();
