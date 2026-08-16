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
  order: integer("order").notNull().default(0),
});

/**
 * Оплата за заняття — на пару «заняття + людина», а не на заняття.
 *
 * Раніше стан оплати стояв на самому занятті: одне значення на всіх. Для
 * курсу, де кожен платить за кожну зустріч окремо, воно не здатне сказати
 * правду нікому — тому поле із заняття прибране.
 *
 * Хід такий: студент заявляє про оплату й лишає квитанцію, адмін підтверджує.
 * Статус `free` — для військових, ветеранів і системних волонтерів.
 */
export const payments = sqliteTable(
  "payments",
  {
    id: id(),
    sessionId: text("session_id")
      .notNull()
      .references(() => sessions.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    authorEmail: text("author_email"),
    status: text("status", {
      enum: ["declared", "confirmed", "free", "rejected"],
    })
      .notNull()
      .default("declared"),
    /** Сума в гривнях. Буває не рівна ціні: часткова, наперед, зі знижкою. */
    amount: integer("amount"),
    /** Посилання на квитанцію. Файли поки не приймаємо — немає сховища. */
    receiptURL: text("receipt_url"),
    note: text("note"),
    declaredAt: text("declared_at").notNull(),
    reviewedAt: text("reviewed_at"),
  },
  (t) => [uniqueIndex("payment_session_device").on(t.sessionId, t.deviceId)],
);

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
 * Власник поліморфний (course|stream|session), тому FK немає — цілісність на рівні
 * репозиторію. Матеріал на занятті — це запис, конспект і домашка саме цієї
 * зустрічі; на потоці лишається те, що стосується курсу загалом.
 */
export const materials = sqliteTable("materials", {
  id: id(),
  ownerType: text("owner_type", { enum: ["course", "stream", "session"] }).notNull(),
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

/**
 * Здана домашка. Одна на пару «матеріал + пристрій»: повторна здача
 * перезаписує попередню, бо домашку доробляють, а не подають удруге.
 *
 * Поки лише текст. Фото потребують сховища файлів — це окреме рішення.
 */
export const submissions = sqliteTable(
  "submissions",
  {
    id: id(),
    materialId: text("material_id")
      .notNull()
      .references(() => materials.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    authorEmail: text("author_email"),
    text: text("text").notNull(),
    submittedAt: text("submitted_at").notNull(),
    /** Відповідь викладача. */
    feedback: text("feedback"),
    reviewedAt: text("reviewed_at"),
  },
  (t) => [uniqueIndex("submission_material_device").on(t.materialId, t.deviceId)],
);

/**
 * «Як зайшло заняття» — оцінка 1–5 і необовʼязковий коментар. Викладачу це
 * зворотний звʼязок, студенту — привід на хвилину зупинитися й відрефлексувати.
 * Одна на пару «заняття + пристрій»: думку міняють, а не подають двічі.
 */
export const pulses = sqliteTable(
  "pulses",
  {
    id: id(),
    sessionId: text("session_id")
      .notNull()
      .references(() => sessions.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    rating: integer("rating").notNull(),
    comment: text("comment"),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex("pulse_session_device").on(t.sessionId, t.deviceId)],
);

/**
 * Заявка на потік — заміна Google Forms. Студент лишає контакт, викладач
 * веде статус. Оплату НЕ обробляємо: у застосунку це поки просто стан заявки.
 *
 * Одна на пару «потік + пристрій»: передумати можна, подавати двічі — ні.
 */
export const applications = sqliteTable(
  "applications",
  {
    id: id(),
    streamId: text("stream_id")
      .notNull()
      .references(() => streams.id, { onDelete: "cascade" }),
    deviceId: text("device_id").notNull(),
    name: text("name").notNull(),
    /** Як звʼязатися: email або телеграм — як зручніше людині. */
    contact: text("contact").notNull(),
    comment: text("comment"),
    status: text("status", {
      enum: ["new", "waitingPayment", "enrolled", "declined"],
    })
      .notNull()
      .default("new"),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex("application_stream_device").on(t.streamId, t.deviceId)],
);

/**
 * Логи з телефонів. Прототип живе в TestFlight, і кожна перевірка гіпотези
 * коштує збірки й чужого часу — без зворотного каналу діагностика сліпа.
 * Токенів сюди не пишемо, лише що сталося.
 */
export const clientLogs = sqliteTable("client_logs", {
  id: id(),
  deviceId: text("device_id").notNull(),
  appVersion: text("app_version"),
  event: text("event").notNull(),
  detail: text("detail"),
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
export type Submission = typeof submissions.$inferSelect;
export type Pulse = typeof pulses.$inferSelect;
export type ClientLog = typeof clientLogs.$inferSelect;
export type Payment = typeof payments.$inferSelect;
export type Application = typeof applications.$inferSelect;

export const schema = {
  courses,
  streams,
  sessions,
  materialTypes,
  materials,
  enrollments,
  questions,
  announcements,
  submissions,
  pulses,
  applications,
  clientLogs,
  payments,
};

// Підказка для майбутнього перемикання БД: усі timestamp-и зберігаємо як
// ISO-рядки (startAt/subscribedAt/dueAt) або timestamp_ms (createdAt) — те й те
// портативне на Postgres без зміни прикладного коду.
export const _portabilityNote = sql`SELECT 1`;
