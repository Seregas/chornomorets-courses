import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { z } from "zod";
import { getIdentity, isAdminEmail } from "./auth.js";
import { repository as repo } from "./repository.js";
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
  const detail = await repo.getStreamDetail(c.req.param("id"));
  return detail ? c.json(detail) : c.json({ error: "not found" }, 404);
});

app.get("/schedule", zValidator("query", deviceQuery), async (c) =>
  c.json(await repo.getSchedule(c.req.valid("query").deviceId)),
);

app.get("/home", zValidator("query", deviceQuery), async (c) =>
  c.json(await repo.getHomeDigest(c.req.valid("query").deviceId)),
);

app.get("/material-types", async (c) => c.json(await repo.listMaterialTypes()));

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
  const access = checkAccess(material, identity);
  if (access !== "granted") {
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
    access: checkAccess(material, identity),
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
  ownerType: z.enum(["course", "stream"]),
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
