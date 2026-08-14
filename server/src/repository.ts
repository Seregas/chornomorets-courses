import { and, asc, desc, eq, gte, inArray } from "drizzle-orm";
import { db as defaultDb, type DB } from "./db.js";
import {
  courses,
  enrollments,
  materials,
  materialTypes,
  sessions,
  streams,
} from "./schema.js";
import type {
  Course,
  CourseCard,
  CourseDetail,
  Enrollment,
  HomeDigest,
  Material,
  MaterialDTO,
  MaterialInContext,
  MaterialType,
  ResolvedStream,
  ScheduleItem,
  Session,
  Stream,
  StreamDetail,
} from "./types.js";

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

  createSession(input: SessionInsert): Promise<Session>;
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
      return { nextSession: null, upcoming: [], homework: [], recordings: [] };
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

    return { nextSession: nextSession ?? null, upcoming: upcoming.slice(0, 3), homework, recordings };
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
  async createSession(input: SessionInsert): Promise<Session> {
    return this.db.insert(sessions).values(input).returning().get();
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
