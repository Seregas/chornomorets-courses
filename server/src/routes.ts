import { zValidator } from "@hono/zod-validator";
import { Hono, type Context } from "hono";
import { z } from "zod";
import { getIdentity, isAdminEmail } from "./auth.js";
import { repository as repo, toPaymentDTO } from "./repository.js";
import { fetchReceipt, sendReceipt, telegramConfigured } from "./telegram.js";
import { buildPlaybackDescriptor } from "./video.js";

/** Розібрані на пристрої поля можуть прийти будь-якими — не падаємо через це. */
function safeJSON(raw: string): unknown {
  try { return JSON.parse(raw); } catch { return { raw }; }
}

const app = new Hono();

const format = z.enum(["online", "offline", "hybrid"]);
const paymentStatus = z.enum(["unpaid", "paid", "free"]);
const streamStatus = z.enum(["upcoming", "ongoing", "finished"]);
const videoProvider = z.enum(["drive", "youtube", "other"]);
/**
 * Особисті дані живуть на акаунті, а не на пристрої: зміна телефона не має
 * стирати людині оплати, підписки й домашки. Тому все особисте вимагає входу.
 * Повертає id акаунта (Google `sub`) або null, якщо не увійшли.
 */
async function accountOf(c: Context): Promise<string | null> {
  const identity = await getIdentity(c);
  if (!identity) return null;
  return repo.touchAccount({
    id: identity.sub,
    email: identity.email,
    name: identity.name,
  });
}

const needSignIn = { error: "потрібен вхід через Google" } as const;

// ───────────────────────── Публічне читання ─────────────────────────

app.get("/health", (c) => c.json({ ok: true }));

/** Хто я: акаунт (якщо увійшов) + чи адмін. */
app.get("/me", async (c) => {
  const identity = await getIdentity(c);
  if (identity) {
    await repo.touchAccount({
      id: identity.sub,
      email: identity.email,
      name: identity.name,
    });
  }
  return c.json({
    accountId: identity?.sub ?? null,
    email: identity?.email ?? null,
    isAdmin: isAdminEmail(identity?.email),
  });
});

/**
 * Видалити свій акаунт. Вимога App Store 5.1.1(v): застосунок, який заводить
 * акаунти, мусить уміти їх стирати — і саме зсередини, без листування з нами.
 * Разом з акаунтом зникають підписки, оплати, домашки, питання й заявки.
 */
app.delete("/me", async (c) => {
  const identity = await getIdentity(c);
  if (!identity) return c.json(needSignIn, 401);
  await repo.deleteAccount(identity.sub);
  return c.body(null, 204);
});

app.get("/courses", async (c) => c.json(await repo.listCourses()));

app.get("/courses/:id", async (c) => {
  const detail = await repo.getCourseDetail(c.req.param("id"));
  return detail ? c.json(detail) : c.json({ error: "not found" }, 404);
});

/** Потік можна дивитися й без входу — тоді просто без «своїх» позначок. */
app.get("/streams/:id", async (c) => {
  const detail = await repo.getStreamDetail(c.req.param("id"), await accountOf(c));
  return detail ? c.json(detail) : c.json({ error: "not found" }, 404);
});

app.get("/schedule", async (c) => {
  const accountId = await accountOf(c);
  return accountId ? c.json(await repo.getSchedule(accountId)) : c.json(needSignIn, 401);
});

app.get("/home", async (c) => {
  const accountId = await accountOf(c);
  return accountId ? c.json(await repo.getHomeDigest(accountId)) : c.json(needSignIn, 401);
});

app.get("/material-types", async (c) => c.json(await repo.listMaterialTypes()));

/** Оголошення потоку — читання відкрите, створення лише адміну (нижче). */
app.get("/streams/:id/announcements", async (c) =>
  c.json(await repo.listAnnouncements(c.req.param("id"))),
);

/**
 * Логи з телефонів. Єдине місце, де лишається deviceId: логи пишуться ще до
 * входу — і саме тоді, коли ламається вхід. Відкрито на запис навмисно;
 * читання — лише адміну.
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

app.get("/streams/:id/application", async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  return c.json(await repo.getApplication(c.req.param("id"), accountId));
});

const applyInput = z.object({
  name: z.string().min(1).max(200),
  contact: z.string().min(3).max(200),
  comment: z.string().max(1000).nullish(),
});
app.post("/streams/:id/application", zValidator("json", applyInput), async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  return c.json(
    await repo.applyToStream({
      streamId: c.req.param("id"),
      accountId,
      ...c.req.valid("json"),
    }),
    201,
  );
});

// ──────────────────── Оплата заняття ────────────────────
// Стан оплати — на пару «заняття + людина», де людина це акаунт, а не
// пристрій. Студент заявляє й лишає квитанцію, адмін підтверджує.

app.get("/sessions/:id/payment", async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  return c.json(toPaymentDTO(await repo.getPayment(c.req.param("id"), accountId)));
});

const declareInput = z.object({
  amount: z.number().int().positive().nullish(),
  receiptURL: z.string().url().nullish(),
  note: z.string().max(500).nullish(),
});
app.post("/sessions/:id/payment", zValidator("json", declareInput), async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  const payment = await repo.declarePayment({
    sessionId: c.req.param("id"),
    accountId,
    ...c.req.valid("json"),
  });
  return c.json(toPaymentDTO(payment), 201);
});

/**
 * Скріншот квитанції. Не зберігаємо в себе: пересилаємо в телеграм-чат
 * викладача — там його і звіряють із випискою, і там він зберігається.
 * Розібрані на пристрої поля йдуть поруч, щоб не читати картинку очима.
 */
app.post("/payments/:id/receipt", async (c) => {
  if (!telegramConfigured) {
    return c.json({ error: "приймання скріншотів не налаштоване" }, 503);
  }
  const identity = await getIdentity(c);
  if (!identity) return c.json(needSignIn, 401);

  const payment = await repo.getPaymentById(c.req.param("id"));
  if (!payment) return c.json({ error: "not found" }, 404);
  // Заявку може прикріпити лише той, хто її подав.
  if (payment.accountId !== identity.sub) return c.json({ error: "чужа заявка" }, 403);

  const form = await c.req.formData();
  const image = form.get("image");
  if (!(image instanceof Blob)) return c.json({ error: "немає файлу" }, 400);
  if (image.size > 10 * 1024 * 1024) return c.json({ error: "завеликий файл" }, 413);

  const parsedRaw = form.get("parsed");
  const parsed = typeof parsedRaw === "string" ? safeJSON(parsedRaw) : undefined;

  const session = await repo.getSessionById(payment.sessionId);
  const caption = [
    "Квитанція за заняття",
    session ? `${session.title} (${session.startAt.slice(0, 10)})` : payment.sessionId,
    identity.email,
    payment.amount ? `${payment.amount} грн` : null,
  ].filter(Boolean).join(" · ");

  try {
    const stored = await sendReceipt(image, caption);
    const updated = await repo.attachReceipt(payment.id, { ...stored, parsed });
    return c.json(toPaymentDTO(updated));
  } catch (e) {
    return c.json({ error: String(e) }, 502);
  }
});

/** Показати квитанцію: власнику заявки або адміну. */
app.get("/payments/:id/receipt", async (c) => {
  const payment = await repo.getPaymentById(c.req.param("id"));
  if (!payment?.receiptFileId) return c.json({ error: "not found" }, 404);

  const identity = await getIdentity(c);
  const isOwner = identity?.sub === payment.accountId;
  if (!isOwner && !isAdminEmail(identity?.email)) {
    return c.json({ error: "no access" }, 403);
  }

  try {
    const file = await fetchReceipt(payment.receiptFileId);
    return new Response(file.body, {
      headers: {
        "Content-Type": file.headers.get("content-type") ?? "image/jpeg",
        "Cache-Control": "private, max-age=3600",
      },
    });
  } catch (e) {
    return c.json({ error: String(e) }, 502);
  }
});

// ──────────────────── Пульс після заняття ────────────────────
// Оцінка 1–5 і необовʼязковий коментар; зведення бачить лише викладач.

app.get("/sessions/:id/pulse", async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  return c.json(await repo.getPulse(c.req.param("id"), accountId));
});

const pulseInput = z.object({
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(1000).nullish(),
});
app.post("/sessions/:id/pulse", zValidator("json", pulseInput), async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  const { rating, comment } = c.req.valid("json");
  return c.json(
    await repo.ratePulse({ sessionId: c.req.param("id"), accountId, rating, comment }),
    201,
  );
});

// ──────────────────── Здача домашки ────────────────────
// Своя здача — за акаунтом; чужих студент не бачить узагалі.

app.get("/materials/:id/submission", async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  return c.json(await repo.getSubmission(c.req.param("id"), accountId));
});

const submitInput = z.object({ text: z.string().min(1).max(5000) });
app.post("/materials/:id/submission", zValidator("json", submitInput), async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  return c.json(
    await repo.submitHomework({
      materialId: c.req.param("id"),
      accountId,
      text: c.req.valid("json").text,
    }),
    201,
  );
});

// ──────────────────── Питання до заняття ────────────────────
// Читання відкрите (усі бачать питання свого заняття, без імен), створення —
// за акаунтом. Автора віддаємо лише адміну й лише якщо питання не анонімне.

app.get("/sessions/:id/questions", async (c) => {
  const identity = await getIdentity(c);
  return c.json(
    await repo.listQuestions(c.req.param("id"), {
      accountId: identity?.sub ?? null,
      isAdmin: isAdminEmail(identity?.email),
    }),
  );
});

const askInput = z.object({
  text: z.string().min(3).max(1000),
  isAnonymous: z.boolean().optional(),
});
app.post("/sessions/:id/questions", zValidator("json", askInput), async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  const { text, isAnonymous } = c.req.valid("json");
  return c.json(
    await repo.askQuestion({
      sessionId: c.req.param("id"),
      accountId,
      text,
      isAnonymous: isAnonymous ?? false,
    }),
    201,
  );
});

app.delete("/questions/:id", async (c) => {
  const identity = await getIdentity(c);
  if (!identity) return c.json(needSignIn, 401);
  const ok = await repo.deleteQuestion(c.req.param("id"), {
    accountId: identity.sub,
    isAdmin: isAdminEmail(identity.email),
  });
  return ok ? c.body(null, 204) : c.json({ error: "not found" }, 404);
});

// ───────────────────────── Підписки ─────────────────────────

app.get("/subscriptions", async (c) => {
  const accountId = await accountOf(c);
  return accountId ? c.json(await repo.listEnrollments(accountId)) : c.json(needSignIn, 401);
});

const subBody = z.object({ streamId: z.string().min(1) });

app.post("/subscriptions", zValidator("json", subBody), async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  return c.json(await repo.subscribe(accountId, c.req.valid("json").streamId), 201);
});

app.delete("/subscriptions", zValidator("json", subBody), async (c) => {
  const accountId = await accountOf(c);
  if (!accountId) return c.json(needSignIn, 401);
  await repo.unsubscribe(accountId, c.req.valid("json").streamId);
  return c.body(null, 204);
});

// ───────────────────────── Відео ─────────────────────────

/**
 * Типізований playback-дескриптор. Сире джерело (videoRef) застосунку не видно
 * інакше — тому й потрібен вхід: fileId записів платного курсу не має
 * розсипатися з відкритого API.
 *
 * Чи відкриється файл, вирішує сам Drive: доступ до записів роздається
 * пошарингом на Google-акаунт, і перевірити його ми могли б лише попросивши в
 * кожного студента право читати весь його диск. Така ціна за бейдж-замочок
 * зависока, тож про відсутність доступу людині скаже Drive, коли вона
 * відкриє запис.
 */
app.get("/video/:materialId/playback", async (c) => {
  const identity = await getIdentity(c);
  if (!identity) return c.json(needSignIn, 401);

  const material = await repo.getMaterialRaw(c.req.param("materialId"));
  if (!material) return c.json({ error: "not found" }, 404);

  const descriptor = buildPlaybackDescriptor(material);
  if (!descriptor) return c.json({ error: "no video for material" }, 404);

  return c.json({ descriptor });
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
/** Усі нерозглянуті заявки — щоб не обходити потоки по одному. */
admin.get("/applications", async (c) => c.json(await repo.listPendingApplications()));

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
  return c.json(list.map((p) => toPaymentDTO(p, true, p.email)));
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

/**
 * Відмітити оплату за людину — по пошті, а не по акаунту.
 *
 * Викладач знає пошту студента (нею ж шарить відео) задовго до того, як той
 * поставить застосунок. Якщо акаунта ще немає — створюємо заочний; при
 * першому вході Google все переїде на справжній номер акаунта.
 */
admin.post(
  "/sessions/:id/payments/mark",
  zValidator("json", z.object({
    email: z.string().email(),
    status: z.enum(["declared", "confirmed", "free", "rejected"]).default("confirmed"),
    amount: z.number().int().positive().nullish(),
    note: z.string().max(500).nullish(),
  })),
  async (c) => {
    const body = c.req.valid("json");
    const payment = await repo.markPaymentByEmail({
      sessionId: c.req.param("id"),
      ...body,
    });
    return c.json(toPaymentDTO(payment, true, body.email), 201);
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
