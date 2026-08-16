import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { getIdentity, isAdminEmail } from "./auth.js";
import { repository as repo, toPaymentDTO } from "./repository.js";
import { buildPlaybackDescriptor, checkAccess } from "./video.js";

const app = new Hono();

const format = z.enum(["online", "offline", "hybrid"]);
const paymentStatus = z.enum(["unpaid", "paid", "free"]);
const streamStatus = z.enum(["upcoming", "ongoing", "finished"]);
const videoProvider = z.enum(["drive", "youtube", "other"]);
const deviceQuery = z.object({ deviceId: z.string().min(1) });

// ───────────────────────── Публічне читання ─────────────────────────

app.get("/health", (c) => c.json({ ok: true }));

/** Хто я: deviceId (анонім) + чи адмін (за Google-токеном). */
app.get("/me", zValidator("query", z.object({ deviceId: z.string().optional() })), async (c) => {
  const identity = await getIdentity(c);
  return c.json({
    deviceId: c.req.valid("query").deviceId ?? null,
    email: identity?.email ?? null,
    isAdmin: isAdminEmail(identity?.email),
  });
});

app.get("/courses", async (c) => c.json(await repo.listCourses()));

app.get("/courses/:id", async (c) => {
  const detail = await repo.getCourseDetail(c.req.param("id"));
  return detail ? c.json(detail) : c.json({ error: "not found" }, 404);
});

app.get("/streams/:id", async (c) => {
  const detail = await repo.getStreamDetail(c.req.param("id"), c.req.query("deviceId"));
  return detail ? c.json(detail) : c.json({ error: "not found" }, 404);
});

app.get("/schedule", zValidator("query", deviceQuery), async (c) =>
  c.json(await repo.getSchedule(c.req.valid("query").deviceId)),
);

app.get("/home", zValidator("query", deviceQuery), async (c) =>
  c.json(await repo.getHomeDigest(c.req.valid("query").deviceId)),
);

app.get("/material-types", async (c) => c.json(await repo.listMaterialTypes()));

/** Оголошення потоку — читання відкрите, створення лише адміну (нижче). */
app.get("/streams/:id/announcements", async (c) =>
  c.json(await repo.listAnnouncements(c.req.param("id"))),
);

/**
 * Логи з телефонів. Відкрито на запис навмисно: воно має працювати ще до
 * входу, коли ламається саме вхід. Читання — лише адміну.
 */
const logInput = z.object({
  deviceId: z.string().min(1).max(200),
  appVersion: z.string().max(50).nullish(),
  event: z.string().min(1).max(200),
  detail: z.string().max(8000).nullish(),
});
app.post("/logs", zValidator("json", logInput), async (c) => {
  await repo.writeClientLog(c.req.valid("json"));
  return c.body(null, 204);
});

// ──────────────────── Заявки на потік ────────────────────
// Заміна Google Forms: студент лишає контакт, викладач веде статус.

app.get("/streams/:id/application", zValidator("query", deviceQuery), async (c) =>
  c.json(
    await repo.getApplication(c.req.param("id"), c.req.valid("query").deviceId),
  ),
);

const applyInput = z.object({
  deviceId: z.string().min(1),
  name: z.string().min(1).max(200),
  contact: z.string().min(3).max(200),
  comment: z.string().max(1000).nullish(),
});
app.post("/streams/:id/application", zValidator("json", applyInput), async (c) => {
  const body = c.req.valid("json");
  return c.json(
    await repo.applyToStream({ streamId: c.req.param("id"), ...body }),
    201,
  );
});

// ──────────────────── Оплата заняття ────────────────────
// Стан оплати — на пару «заняття + людина». Студент заявляє й лишає
// квитанцію, адмін підтверджує. Файли поки не приймаємо: сховища немає,
// тож квитанція — це посилання.

app.get("/sessions/:id/payment", zValidator("query", deviceQuery), async (c) =>
  c.json(
    toPaymentDTO(
      await repo.getPayment(c.req.param("id"), c.req.valid("query").deviceId),
    ),
  ),
);

const declareInput = z.object({
  deviceId: z.string().min(1),
  amount: z.number().int().positive().nullish(),
  receiptURL: z.string().url().nullish(),
  note: z.string().max(500).nullish(),
});
app.post("/sessions/:id/payment", zValidator("json", declareInput), async (c) => {
  const body = c.req.valid("json");
  const identity = await getIdentity(c);
  const payment = await repo.declarePayment({
    sessionId: c.req.param("id"),
    ...body,
    authorEmail: identity?.email ?? null,
  });
  return c.json(toPaymentDTO(payment), 201);
});

// ──────────────────── Пульс після заняття ────────────────────
// Оцінка 1–5 і необовʼязковий коментар; зведення бачить лише викладач.

app.get("/sessions/:id/pulse", zValidator("query", deviceQuery), async (c) =>
  c.json(await repo.getPulse(c.req.param("id"), c.req.valid("query").deviceId)),
);

const pulseInput = z.object({
  deviceId: z.string().min(1),
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(1000).nullish(),
});
app.post("/sessions/:id/pulse", zValidator("json", pulseInput), async (c) => {
  const { deviceId, rating, comment } = c.req.valid("json");
  return c.json(
    await repo.ratePulse({ sessionId: c.req.param("id"), deviceId, rating, comment }),
    201,
  );
});

// ──────────────────── Здача домашки ────────────────────
// Своя здача — за deviceId; чужих студент не бачить узагалі.

app.get("/materials/:id/submission", zValidator("query", deviceQuery), async (c) =>
  c.json(
    await repo.getSubmission(c.req.param("id"), c.req.valid("query").deviceId),
  ),
);

const submitInput = z.object({
  deviceId: z.string().min(1),
  text: z.string().min(1).max(5000),
});
app.post("/materials/:id/submission", zValidator("json", submitInput), async (c) => {
  const { deviceId, text } = c.req.valid("json");
  const identity = await getIdentity(c);
  return c.json(
    await repo.submitHomework({
      materialId: c.req.param("id"),
      deviceId,
      text,
      authorEmail: identity?.email ?? null,
    }),
    201,
  );
});

// ──────────────────── Питання до заняття ────────────────────
// Читання відкрите (усі бачать питання свого заняття, без імен), створення —
// за deviceId. Автора віддаємо лише адміну й лише якщо питання не анонімне.

app.get("/sessions/:id/questions", zValidator("query", deviceQuery), async (c) => {
  const identity = await getIdentity(c);
  return c.json(
    await repo.listQuestions(c.req.param("id"), {
      deviceId: c.req.valid("query").deviceId,
      isAdmin: isAdminEmail(identity?.email),
    }),
  );
});

const askInput = z.object({
  deviceId: z.string().min(1),
  text: z.string().min(3).max(1000),
  isAnonymous: z.boolean().optional(),
});
app.post("/sessions/:id/questions", zValidator("json", askInput), async (c) => {
  const { deviceId, text, isAnonymous } = c.req.valid("json");
  const identity = await getIdentity(c);
  return c.json(
    await repo.askQuestion({
      sessionId: c.req.param("id"),
      deviceId,
      text,
      isAnonymous: isAnonymous ?? false,
      authorEmail: identity?.email ?? null,
    }),
    201,
  );
});

app.delete("/questions/:id", zValidator("query", deviceQuery), async (c) => {
  const identity = await getIdentity(c);
  const ok = await repo.deleteQuestion(c.req.param("id"), {
    deviceId: c.req.valid("query").deviceId,
    isAdmin: isAdminEmail(identity?.email),
  });
  return ok ? c.body(null, 204) : c.json({ error: "not found" }, 404);
});

// ───────────────────────── Підписки (deviceId) ─────────────────────────

app.get("/subscriptions", zValidator("query", deviceQuery), async (c) =>
  c.json(await repo.listEnrollments(c.req.valid("query").deviceId)),
);

const subBody = z.object({ deviceId: z.string().min(1), streamId: z.string().min(1) });

app.post("/subscriptions", zValidator("json", subBody), async (c) => {
  const { deviceId, streamId } = c.req.valid("json");
  return c.json(await repo.subscribe(deviceId, streamId), 201);
});

app.delete("/subscriptions", zValidator("json", subBody), async (c) => {
  const { deviceId, streamId } = c.req.valid("json");
  await repo.unsubscribe(deviceId, streamId);
  return c.body(null, 204);
});

// ───────────────────────── Відео ─────────────────────────

/** Типізований playback-дескриптор. Сире джерело (videoRef) застосунку не видно інакше. */
app.get("/video/:materialId/playback", async (c) => {
  const material = await repo.getMaterialRaw(c.req.param("materialId"));
  if (!material) return c.json({ error: "not found" }, 404);

  const descriptor = buildPlaybackDescriptor(material);
  if (!descriptor) return c.json({ error: "no video for material" }, 404);

  const identity = await getIdentity(c);
  const access = await checkAccess(material, identity, c.req.header("x-drive-token"));

  // Для Drive «unknown» — не відмова: сервер просто не бачить чужого токена
  // (застосунок навмисно тримає його в себе, бо scope drive.readonly відкриває
  // весь диск). Дескриптор віддаємо, а чи відкриється файл — вирішить сам Drive.
  // Але лише тим, хто увійшов: fileId не має розсипатися з відкритого API.
  const undecidable =
    access === "unknown" && material.videoProvider === "drive" && identity !== null;
  if (access !== "granted" && !undecidable) {
    return c.json({ access, error: "no access" }, 403);
  }
  return c.json({ access, descriptor });
});

/** Стан доступу (для бейджа 🔓/🔒) без видачі самого playback. */
app.get("/video/:materialId/access", async (c) => {
  const material = await repo.getMaterialRaw(c.req.param("materialId"));
  if (!material) return c.json({ error: "not found" }, 404);
  const identity = await getIdentity(c);
  return c.json({
    access: await checkAccess(material, identity, c.req.header("x-drive-token")),
    provider: material.videoProvider,
  });
});

// ───────────────────────── Адмін (Google-allowlist) ─────────────────────────

const admin = new Hono();

admin.use("*", async (c, next) => {
  const identity = await getIdentity(c);
  if (!isAdminEmail(identity?.email)) {
    return c.json({ error: "admin only" }, 403);
  }
  await next();
});

const courseInput = z.object({
  title: z.string().min(1),
  summary: z.string().min(1),
  description: z.string().min(1),
  program: z.string().nullish(),
  format: format.optional(),
  coverImageURL: z.string().url().nullish(),
  order: z.number().int().optional(),
});

const streamInput = z.object({
  courseId: z.string().min(1),
  title: z.string().min(1),
  startDate: z.string().nullish(),
  status: streamStatus.optional(),
  telegramGroupURL: z.string().url().nullish(),
  priceFull: z.number().int().nullish(),
  pricePerSession: z.number().int().nullish(),
  summaryOverride: z.string().nullish(),
  descriptionOverride: z.string().nullish(),
  programOverride: z.string().nullish(),
  coverImageOverride: z.string().url().nullish(),
  order: z.number().int().optional(),
});

const sessionInput = z.object({
  streamId: z.string().min(1),
  title: z.string().min(1),
  startAt: z.string().min(1),
  durationMinutes: z.number().int().positive(),
  format: format.optional(),
  joinURL: z.string().url().nullish(),
  paymentStatus: paymentStatus.optional(),
  order: z.number().int().optional(),
});

const materialInput = z.object({
  ownerType: z.enum(["course", "stream", "session"]),
  ownerId: z.string().min(1),
  typeId: z.string().nullish(),
  title: z.string().min(1),
  description: z.string().nullish(),
  videoProvider: videoProvider.nullish(),
  videoRef: z.string().nullish(),
  durationMinutes: z.number().int().nullish(),
  url: z.string().url().nullish(),
  dueAt: z.string().nullish(),
  order: z.number().int().optional(),
});

admin.get("/logs", async (c) => {
  const limit = Number(c.req.query("limit") ?? 100);
  return c.json(await repo.listClientLogs(Math.min(Math.max(limit, 1), 500)));
});

// applications — заявки на потік
admin.get("/streams/:id/applications", async (c) =>
  c.json(await repo.listApplications(c.req.param("id"))),
);
admin.post(
  "/applications/:id/status",
  zValidator("json", z.object({
    status: z.enum(["new", "waitingPayment", "enrolled", "declined"]),
  })),
  async (c) => {
    const r = await repo.setApplicationStatus(c.req.param("id"), c.req.valid("json").status);
    return r ? c.json(r) : c.json({ error: "not found" }, 404);
  },
);

// payments — заявки на оплату по заняттю
admin.get("/sessions/:id/payments", async (c) => {
  const list = await repo.listPayments(c.req.param("id"));
  return c.json(list.map((p) => toPaymentDTO(p, true)));
});
admin.post(
  "/payments/:id/status",
  zValidator("json", z.object({
    status: z.enum(["declared", "confirmed", "free", "rejected"]),
    note: z.string().max(500).nullish(),
  })),
  async (c) => {
    const { status, note } = c.req.valid("json");
    const r = await repo.setPaymentStatus(c.req.param("id"), status, note);
    return r ? c.json(toPaymentDTO(r, true)) : c.json({ error: "not found" }, 404);
  },
);

// pulses — зведення відгуків по заняттю
admin.get("/sessions/:id/pulses", async (c) =>
  c.json(await repo.getPulseSummary(c.req.param("id"))),
);

// submissions
admin.get("/materials/:id/submissions", async (c) =>
  c.json(await repo.listSubmissions(c.req.param("id"))),
);
admin.post(
  "/submissions/:id/feedback",
  zValidator("json", z.object({ feedback: z.string().min(1).max(2000) })),
  async (c) => {
    const r = await repo.reviewSubmission(c.req.param("id"), c.req.valid("json").feedback);
    return r ? c.json(r) : c.json({ error: "not found" }, 404);
  },
);

// announcements
const announcementInput = z.object({
  streamId: z.string().min(1),
  text: z.string().min(1).max(2000),
});
admin.post("/announcements", zValidator("json", announcementInput), async (c) => {
  const { streamId, text } = c.req.valid("json");
  return c.json(await repo.createAnnouncement(streamId, text), 201);
});
admin.delete("/announcements/:id", async (c) =>
  (await repo.deleteAnnouncement(c.req.param("id")))
    ? c.body(null, 204)
    : c.json({ error: "not found" }, 404),
);

// Позначити питання розібраним — щоб у списку було видно, що воно вже не висить.
admin.post("/questions/:id/answered", zValidator("json", z.object({ answered: z.boolean() })), async (c) => {
  const r = await repo.markQuestionAnswered(c.req.param("id"), c.req.valid("json").answered);
  return r ? c.json(r) : c.json({ error: "not found" }, 404);
});

const materialTypeInput = z.object({
  name: z.string().min(1),
  icon: z.string().nullish(),
  color: z.string().nullish(),
  order: z.number().int().optional(),
});

const notFound = { error: "not found" } as const;

// courses
admin.post("/courses", zValidator("json", courseInput), async (c) =>
  c.json(await repo.createCourse(c.req.valid("json")), 201),
);
admin.put("/courses/:id", zValidator("json", courseInput.partial()), async (c) => {
  const r = await repo.updateCourse(c.req.param("id"), c.req.valid("json"));
  return r ? c.json(r) : c.json(notFound, 404);
});
admin.delete("/courses/:id", async (c) =>
  (await repo.deleteCourse(c.req.param("id"))) ? c.body(null, 204) : c.json(notFound, 404),
);

// streams
admin.post("/streams", zValidator("json", streamInput), async (c) =>
  c.json(await repo.createStream(c.req.valid("json")), 201),
);
admin.put("/streams/:id", zValidator("json", streamInput.partial()), async (c) => {
  const r = await repo.updateStream(c.req.param("id"), c.req.valid("json"));
  return r ? c.json(r) : c.json(notFound, 404);
});
admin.delete("/streams/:id", async (c) =>
  (await repo.deleteStream(c.req.param("id"))) ? c.body(null, 204) : c.json(notFound, 404),
);

const cloneStreamInput = z.object({
  title: z.string().min(1),
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});
admin.post("/streams/:id/clone", zValidator("json", cloneStreamInput), async (c) => {
  const r = await repo.cloneStream(c.req.param("id"), c.req.valid("json"));
  return r ? c.json(r, 201) : c.json(notFound, 404);
});

// sessions
admin.post("/sessions", zValidator("json", sessionInput), async (c) =>
  c.json(await repo.createSession(c.req.valid("json")), 201),
);
const sessionsBatchInput = z.object({
  streamId: z.string().min(1),
  titlePrefix: z.string().min(1),
  startAt: z.string().min(1),
  count: z.number().int().min(1).max(52),
  intervalDays: z.number().int().min(1).max(365),
  durationMinutes: z.number().int().positive(),
  joinURL: z.string().url().nullish(),
});
admin.post("/sessions/batch", zValidator("json", sessionsBatchInput), async (c) =>
  c.json(await repo.createSessionsBatch(c.req.valid("json")), 201),
);

admin.put("/sessions/:id", zValidator("json", sessionInput.partial()), async (c) => {
  const r = await repo.updateSession(c.req.param("id"), c.req.valid("json"));
  return r ? c.json(r) : c.json(notFound, 404);
});
admin.delete("/sessions/:id", async (c) =>
  (await repo.deleteSession(c.req.param("id"))) ? c.body(null, 204) : c.json(notFound, 404),
);

// materials
// Raw-матеріал (із videoRef) — лише адмінам, для префілу форми редагування.
admin.get("/materials/:id", async (c) => {
  const m = await repo.getMaterialRaw(c.req.param("id"));
  return m ? c.json(m) : c.json(notFound, 404);
});
admin.post("/materials", zValidator("json", materialInput), async (c) =>
  c.json(await repo.createMaterial(c.req.valid("json")), 201),
);
admin.put("/materials/:id", zValidator("json", materialInput.partial()), async (c) => {
  const r = await repo.updateMaterial(c.req.param("id"), c.req.valid("json"));
  return r ? c.json(r) : c.json(notFound, 404);
});
admin.delete("/materials/:id", async (c) =>
  (await repo.deleteMaterial(c.req.param("id"))) ? c.body(null, 204) : c.json(notFound, 404),
);

// material types
admin.post("/material-types", zValidator("json", materialTypeInput), async (c) =>
  c.json(await repo.createMaterialType(c.req.valid("json")), 201),
);
admin.put("/material-types/:id", zValidator("json", materialTypeInput.partial()), async (c) => {
  const r = await repo.updateMaterialType(c.req.param("id"), c.req.valid("json"));
  return r ? c.json(r) : c.json(notFound, 404);
});
admin.delete("/material-types/:id", async (c) =>
  (await repo.deleteMaterialType(c.req.param("id"))) ? c.body(null, 204) : c.json(notFound, 404),
);

app.route("/admin", admin);

export { app };
