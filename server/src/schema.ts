import { sql } from "drizzle-orm";
import { integer, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";

/**
 * Drizzle-схема (SQLite-діалект).
 *
 * Принцип: це ЄДИНЕ місце, що знає про конкретні таблиці. Роути працюють
 * через CourseRepository, а не через ці визначення. Щоб перемкнути БД на
 * Postgres — міняємо імпорти діалекту тут і драйвер у db.ts; роути не чіпаємо.
 */

const id = () =>
  text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID());

const createdAt = () =>
  integer("created_at", { mode: "timestamp_ms" })
    .notNull()
    .$defaultFn(() => new Date());

/** Курс — «вічний» опис. Конкретні запуски живуть у streams. */
export const courses = sqliteTable("courses", {
  id: id(),
  title: text("title").notNull(),
  summary: text("summary").notNull(),
  description: text("description").notNull(),
  program: text("program"),
  format: text("format", { enum: ["online", "offline", "hybrid"] })
    .notNull()
    .default("online"),
  coverImageURL: text("cover_image_url"),
  order: integer("order").notNull().default(0),
  createdAt: createdAt(),
});

/**
 * Потік (cohort) — конкретний запуск курсу. Поля *Override дозволяють
 * змінити опис під цей потік; якщо null — успадковується з курсу.
 */
export const streams = sqliteTable("streams", {
  id: id(),
  courseId: text("course_id")
    .notNull()
    .references(() => courses.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  startDate: text("start_date"), // ISO date потоку (для сортування/відображення)
  status: text("status", { enum: ["upcoming", "ongoing", "finished"] })
    .notNull()
    .default("upcoming"),
  telegramGroupURL: text("telegram_group_url"),
  priceFull: integer("price_full"), // ціла сума (грн), nullable
  pricePerSession: integer("price_per_session"),
  summaryOverride: text("summary_override"),
  descriptionOverride: text("description_override"),
  programOverride: text("program_override"),
  coverImageOverride: text("cover_image_override"),
  order: integer("order").notNull().default(0),
  createdAt: createdAt(),
});

/** Заняття — належить ПОТОКУ, не курсу. */
export const sessions = sqliteTable("sessions", {
  id: id(),
  streamId: text("stream_id")
    .notNull()
    .references(() => streams.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  startAt: text("start_at").notNull(), // ISO 8601 UTC
  durationMinutes: integer("duration_minutes").notNull(),
  format: text("format", { enum: ["online", "offline", "hybrid"] })
    .notNull()
    .default("online"),
  joinURL: text("join_url"),
  paymentStatus: text("payment_status", { enum: ["unpaid", "paid", "free"] })
    .notNull()
    .default("unpaid"),
  order: integer("order").notNull().default(0),
});

/**
 * Тип матеріалу — КЕРОВАНИЙ каталог-ярлик (CRUD в адмінці). Суто косметичний:
 * name/icon/color. Поведінка матеріалу визначається його вмістом, а не типом.
 */
export const materialTypes = sqliteTable("material_types", {
  id: id(),
  name: text("name").notNull(),
  icon: text("icon"), // SF Symbol / emoji
  color: text("color"), // hex, напр. "#0E7C86"
  order: integer("order").notNull().default(0),
  createdAt: createdAt(),
});

/**
 * Матеріал. Поведінка композитна за наявними полями:
 *   description → текст; videoRef → відео (з access-станом); url → лінк; dueAt → дедлайн.
 * typeId необов'язковий (null = порожній тип, і fallback після видалення типу —
 * onDelete: "set null").
 * Власник поліморфний (course|stream), тому FK немає — цілісність на рівні репозиторію.
 */
export const materials = sqliteTable("materials", {
  id: id(),
  ownerType: text("owner_type", { enum: ["course", "stream"] }).notNull(),
  ownerId: text("owner_id").notNull(),
  typeId: text("type_id").references(() => materialTypes.id, {
    onDelete: "set null",
  }),
  title: text("title").notNull(),
  description: text("description"),
  videoProvider: text("video_provider", {
    enum: ["drive", "youtube", "other"],
  }),
  videoRef: text("video_ref"), // приватний: drive fileId / youtube id / пряме url
  durationMinutes: integer("duration_minutes"),
  url: text("url"),
  dueAt: text("due_at"), // ISO, для «домашки»
  order: integer("order").notNull().default(0),
  createdAt: createdAt(),
});

/** Підписка — на ПОТІК, прив'язана до анонімного deviceId. */
export const enrollments = sqliteTable(
  "enrollments",
  {
    id: id(),
    deviceId: text("device_id").notNull(),
    streamId: text("stream_id")
      .notNull()
      .references(() => streams.id, { onDelete: "cascade" }),
    subscribedAt: text("subscribed_at").notNull(),
  },
  (t) => [uniqueIndex("enroll_device_stream").on(t.deviceId, t.streamId)],
);

/**
 * Питання до майбутнього заняття: студент кидає заздалегідь, викладач розбирає
 * на занятті. У телеграм-групі такі питання тонуть, тут — ні.
 *
 * `authorEmail` заповнюється лише якщо студент увійшов і не поставив «анонімно»;
 * бачить його тільки адмін. Для решти всі питання однаково безіменні.
 */
export const questions = sqliteTable("questions", {
  id: id(),
  sessionId: text("session_id")
    .notNull()
    .references(() => sessions.id, { onDelete: "cascade" }),
  deviceId: text("device_id").notNull(),
  authorEmail: text("author_email"),
  text: text("text").notNull(),
  isAnonymous: integer("is_anonymous", { mode: "boolean" })
    .notNull()
    .default(false),
  /** Проставляється, коли викладач розібрав питання. */
  answeredAt: text("answered_at"),
  createdAt: createdAt(),
});

/**
 * Оголошення викладача на потік: перенесли заняття, виклали матеріал, важлива
 * дрібниця перед зустріччю. Окремо від телеграм-групи, де таке тоне між мемами.
 */
export const announcements = sqliteTable("announcements", {
  id: id(),
  streamId: text("stream_id")
    .notNull()
    .references(() => streams.id, { onDelete: "cascade" }),
  text: text("text").notNull(),
  createdAt: createdAt(),
});

export type Course = typeof courses.$inferSelect;
export type Stream = typeof streams.$inferSelect;
export type Session = typeof sessions.$inferSelect;
export type MaterialType = typeof materialTypes.$inferSelect;
export type Material = typeof materials.$inferSelect;
export type Enrollment = typeof enrollments.$inferSelect;
export type Question = typeof questions.$inferSelect;
export type Announcement = typeof announcements.$inferSelect;

export const schema = {
  courses,
  streams,
  sessions,
  materialTypes,
  materials,
  enrollments,
  questions,
  announcements,
};

// Підказка для майбутнього перемикання БД: усі timestamp-и зберігаємо як
// ISO-рядки (startAt/subscribedAt/dueAt) або timestamp_ms (createdAt) — те й те
// портативне на Postgres без зміни прикладного коду.
export const _portabilityNote = sql`SELECT 1`;
