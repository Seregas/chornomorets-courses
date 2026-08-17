import "../env.js";
import { and, eq } from "drizzle-orm";
import { db } from "../db.js";
import { repository } from "../repository.js";
import { accounts, courses, enrollments, sessions, streams } from "../schema.js";

/**
 * Відмічає всі заняття потоку оплаченими для однієї людини — по пошті.
 *
 * Це те, що викладач робить руками для тих, хто заплатив за курс наперед або
 * поза застосунком. Акаунта в людини може ще не бути: тоді заводиться заочний
 * (`email:...`), а при першому вході через Google усе переїде на справжній
 * номер акаунта — цим займається `touchAccount`.
 *
 * Запуск:
 *   npx tsx src/scripts/mark-paid.ts <email> <stream-id> [статус]
 * Наприклад:
 *   npx tsx src/scripts/mark-paid.ts hello@example.com s-biohardcore-1
 */

const [, , emailArg, streamId, statusArg = "confirmed"] = process.argv;

if (!emailArg || !streamId) {
  console.error("Треба: npx tsx src/scripts/mark-paid.ts <email> <stream-id> [статус]");
  process.exit(1);
}

const email = emailArg.trim().toLowerCase();
const status = statusArg as "declared" | "confirmed" | "free" | "rejected";

const stream = db.select().from(streams).where(eq(streams.id, streamId)).get();
if (!stream) {
  console.error(`Потоку ${streamId} немає.`);
  process.exit(1);
}
const course = db.select().from(courses).where(eq(courses.id, stream.courseId)).get();

const list = db
  .select()
  .from(sessions)
  .where(eq(sessions.streamId, streamId))
  .orderBy(sessions.order)
  .all();

console.log(`${course?.title ?? stream.courseId} · ${stream.title}: ${list.length} занять`);

for (const session of list) {
  const payment = await repository.markPaymentByEmail({
    sessionId: session.id,
    email,
    status,
    // Ціна за заняття — саме те, що людина мала заплатити; якщо потік її не
    // називає, лишаємо порожньою, а не вигадуємо.
    amount: stream.pricePerSession ?? null,
    note: "Відмічено викладачем",
  });
  console.log(`  ${session.title} (${session.startAt.slice(0, 10)}) → ${payment.status}`);
}

// Оплачений курс без підписки виглядав би дивно: занять не було б ні в
// розкладі, ні на головному екрані.
const accountId = db.select().from(accounts).where(eq(accounts.email, email)).get()?.id;
if (accountId) {
  const already = db
    .select()
    .from(enrollments)
    .where(and(eq(enrollments.accountId, accountId), eq(enrollments.streamId, streamId)))
    .get();
  if (!already) {
    db.insert(enrollments)
      .values({ accountId, streamId, subscribedAt: new Date().toISOString() })
      .run();
    console.log("  + підписка на потік");
  }
}

console.log("Готово.");
