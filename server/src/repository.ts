import { and, asc, desc, eq, gte, inArray } from "drizzle-orm";
import { db as defaultDb, type DB } from "./db.js";
import {
  announcements,
  courses,
  enrollments,
  materials,
  materialTypes,
  pulses,
  questions,
  sessions,
  streams,
  submissions,
} from "./schema.js";
import type {
  Announcement,
  AnnouncementDTO,
  Course,
  CourseCard,
  CourseDetail,
  Enrollment,
  HomeDigest,
  Material,
  MaterialDTO,
  MaterialInContext,
  MaterialType,
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

/** Хто дивиться список питань: свої впізнаються за deviceId, авторів бачить лише адмін. */
export interface QuestionViewer {
  deviceId: string;
  isAdmin: boolean;
}

export interface AskQuestionInput {
  sessionId: string;
  deviceId: string;
  text: string;
  isAnonymous: boolean;
  /** Email автора, якщо він увійшов і не приховався. */
  authorEmail?: string | null;
}

export interface RatePulseInput {
  sessionId: string;
  deviceId: string;
  /** 1–5. */
  rating: number;
  comment?: string | null;
}

export interface SubmitHomeworkInput {
  materialId: string;
  deviceId: string;
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
  getStreamDetail(streamId: string): Promise<StreamDetail | null>;
  getSchedule(deviceId: string): Promise<ScheduleItem[]>;
  /** Зведення для екрана «Моє навчання». */
  getHomeDigest(deviceId: string): Promise<HomeDigest>;
  listEnrollments(deviceId: string): Promise<ResolvedStream[]>;
  listMaterialTypes(): Promise<MaterialType[]>;
  /** Сирий матеріал з videoRef — лише для відео-шару (playback). Не віддавати клієнту. */
  getMaterialRaw(materialId: string): Promise<Material | null>;

  // — Оголошення на потік —
  listAnnouncements(streamId: string): Promise<AnnouncementDTO[]>;
  createAnnouncement(streamId: string, text: string): Promise<Announcement>;
  deleteAnnouncement(id: string): Promise<boolean>;

  // — Здача домашки —
  /** Своя здача (або null). */
  getSubmission(materialId: string, deviceId: string): Promise<Submission | null>;
  /** Здати або переписати свою — домашку доробляють, а не подають удруге. */
  submitHomework(input: SubmitHomeworkInput): Promise<Submission>;
  /** Усі здачі по матеріалу — адміну. */
  listSubmissions(materialId: string): Promise<Submission[]>;
  /** Відповідь викладача. */
  reviewSubmission(id: string, feedback: string): Promise<Submission | null>;

  // — Пульс після заняття —
  getPulse(sessionId: string, deviceId: string): Promise<Pulse | null>;
  ratePulse(input: RatePulseInput): Promise<Pulse>;
  /** Зведення для викладача. */
  getPulseSummary(sessionId: string): Promise<PulseSummary>;

  // — Питання до заняття —
  /** `viewer` вирішує, кому показати автора: email бачить лише адмін. */
  listQuestions(sessionId: string, viewer: QuestionViewer): Promise<QuestionDTO[]>;
  askQuestion(input: AskQuestionInput): Promise<Question>;
  /** Видалити може автор (за deviceId) або адмін. */
  deleteQuestion(id: string, viewer: QuestionViewer): Promise<boolean>;
  /** Позначити розібраним (адмін). */
  markQuestionAnswered(id: string, answered: boolean): Promise<Question | null>;

  // — Підписки (deviceId) —
  subscribe(deviceId: string, streamId: string): Promise<Enrollment>;
  unsubscribe(deviceId: string, streamId: string): Promise<void>;
  isEnrolled(deviceId: string, streamId: string): Promise<boolean>;

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

  async getStreamDetail(streamId: string): Promise<StreamDetail | null> {
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

    return {
      ...resolveStream(course, stream),
      sessions: streamSessions,
      materials: streamMaterials.map(toMaterialDTO),
      summaryOverride: stream.summaryOverride,
      descriptionOverride: stream.descriptionOverride,
      programOverride: stream.programOverride,
      coverImageOverride: stream.coverImageOverride,
    };
  }

  async getSchedule(deviceId: string): Promise<ScheduleItem[]> {
    const enrolled = this.db
      .select({ streamId: enrollments.streamId })
      .from(enrollments)
      .where(eq(enrollments.deviceId, deviceId))
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

    return rows.map((r) => ({
      session: r.session,
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
  async getHomeDigest(deviceId: string): Promise<HomeDigest> {
    const schedule = await this.getSchedule(deviceId);
    const [nextSession, ...upcoming] = schedule;

    const streamRows = this.db
      .select({ streamId: streams.id, streamTitle: streams.title, courseId: courses.id, courseTitle: courses.title })
      .from(enrollments)
      .innerJoin(streams, eq(enrollments.streamId, streams.id))
      .innerJoin(courses, eq(streams.courseId, courses.id))
      .where(eq(enrollments.deviceId, deviceId))
      .all();
    if (streamRows.length === 0) {
      return {
        nextSession: null,
        announcements: [],
        upcoming: [],
        homework: [],
        recordings: [],
      };
    }

    const context = new Map(streamRows.map((r) => [r.streamId, r]));
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

    const withContext = (m: Material): MaterialInContext => {
      const c = context.get(m.ownerId)!;
      return { material: toMaterialDTO(m), ...c };
    };

    // Щойно прострочену домашку теж показуємо: зникнути рівно о дедлайні —
    // найгірший момент, саме тоді про неї згадують.
    const graceFrom = new Date(Date.now() - 7 * 86_400_000).toISOString();
    const homework = streamMaterials
      .filter((m) => m.dueAt && m.dueAt >= graceFrom)
      .sort((a, b) => (a.dueAt! < b.dueAt! ? -1 : 1))
      .slice(0, 5)
      .map(withContext);

    const recordings = streamMaterials
      .filter((m) => m.videoRef)
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
      nextSession: nextSession ?? null,
      announcements: announcementRows.map(toAnnouncementDTO),
      upcoming: upcoming.slice(0, 3),
      homework,
      recordings,
    };
  }

  // — Пульс після заняття —

  async getPulse(sessionId: string, deviceId: string): Promise<Pulse | null> {
    return (
      this.db
        .select()
        .from(pulses)
        .where(and(eq(pulses.sessionId, sessionId), eq(pulses.deviceId, deviceId)))
        .get() ?? null
    );
  }

  async ratePulse(input: RatePulseInput): Promise<Pulse> {
    const existing = await this.getPulse(input.sessionId, input.deviceId);
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
        deviceId: input.deviceId,
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
    deviceId: string,
  ): Promise<Submission | null> {
    return (
      this.db
        .select()
        .from(submissions)
        .where(
          and(
            eq(submissions.materialId, materialId),
            eq(submissions.deviceId, deviceId),
          ),
        )
        .get() ?? null
    );
  }

  async submitHomework(input: SubmitHomeworkInput): Promise<Submission> {
    const existing = await this.getSubmission(input.materialId, input.deviceId);
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
        deviceId: input.deviceId,
        authorEmail: input.authorEmail ?? null,
        text: input.text,
        submittedAt: now,
      })
      .returning()
      .get();
  }

  async listSubmissions(materialId: string): Promise<Submission[]> {
    return this.db
      .select()
      .from(submissions)
      .where(eq(submissions.materialId, materialId))
      .orderBy(asc(submissions.submittedAt))
      .all();
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

    return rows.map((q) => ({
      id: q.id,
      sessionId: q.sessionId,
      text: q.text,
      createdAt: q.createdAt.toISOString(),
      answeredAt: q.answeredAt,
      isMine: q.deviceId === viewer.deviceId,
      // Автора віддаємо лише адміну й лише якщо питання не анонімне.
      ...(viewer.isAdmin
        ? { authorEmail: q.isAnonymous ? null : q.authorEmail }
        : {}),
    }));
  }

  async askQuestion(input: AskQuestionInput): Promise<Question> {
    return this.db
      .insert(questions)
      .values({
        sessionId: input.sessionId,
        deviceId: input.deviceId,
        text: input.text,
        isAnonymous: input.isAnonymous,
        authorEmail: input.isAnonymous ? null : (input.authorEmail ?? null),
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
    if (!viewer.isAdmin && existing.deviceId !== viewer.deviceId) return false;
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

  async listEnrollments(deviceId: string): Promise<ResolvedStream[]> {
    const rows = this.db
      .select({ stream: streams, course: courses })
      .from(enrollments)
      .innerJoin(streams, eq(enrollments.streamId, streams.id))
      .innerJoin(courses, eq(streams.courseId, courses.id))
      .where(eq(enrollments.deviceId, deviceId))
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

  async subscribe(deviceId: string, streamId: string): Promise<Enrollment> {
    const existing = this.db
      .select()
      .from(enrollments)
      .where(
        and(
          eq(enrollments.deviceId, deviceId),
          eq(enrollments.streamId, streamId),
        ),
      )
      .get();
    if (existing) return existing;
    return this.db
      .insert(enrollments)
      .values({ deviceId, streamId, subscribedAt: new Date().toISOString() })
      .returning()
      .get();
  }

  async unsubscribe(deviceId: string, streamId: string): Promise<void> {
    this.db
      .delete(enrollments)
      .where(
        and(
          eq(enrollments.deviceId, deviceId),
          eq(enrollments.streamId, streamId),
        ),
      )
      .run();
  }

  async isEnrolled(deviceId: string, streamId: string): Promise<boolean> {
    const row = this.db
      .select({ id: enrollments.id })
      .from(enrollments)
      .where(
        and(
          eq(enrollments.deviceId, deviceId),
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
