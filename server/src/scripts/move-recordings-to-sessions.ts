import "../env.js";
import { db } from "../db.js";
import { materials, sessions } from "../schema.js";
import { and, eq } from "drizzle-orm";

/**
 * Переносить записи занять із рівня потоку на самі заняття.
 *
 * Досі всі матеріали висіли на потоці, і десять записів Біохардкору лежали
 * однією купою поруч із дошкою Miro та реквізитами. Тепер запис належить тій
 * зустрічі, яку він записує.
 *
 * Звірка йде за датою в назві («Запис заняття 3 (23.03)») і датою заняття —
 * порядковий номер у назві не завжди збігається з порядком у базі.
 *
 * Запуск: npx tsx src/scripts/move-recordings-to-sessions.ts [--dry]
 */

const DRY = process.argv.includes("--dry");

/** «Запис заняття 3 (23.03)» → «23.03» */
function dateFromTitle(title: string): string | null {
  return title.match(/\((\d{2}\.\d{2})\)/)?.[1] ?? null;
}

/** ISO-час заняття → «23.03» у київському часі, як у назві матеріалу. */
function dayMonthKyiv(startAt: string): string {
  const d = new Date(startAt);
  const kyiv = new Date(d.getTime() + 3 * 3600_000);
  return `${String(kyiv.getUTCDate()).padStart(2, "0")}.${String(kyiv.getUTCMonth() + 1).padStart(2, "0")}`;
}

function move() {
  const streamMaterials = db
    .select()
    .from(materials)
    .where(eq(materials.ownerType, "stream"))
    .all()
    .filter((m) => m.videoRef);

  let moved = 0;
  for (const material of streamMaterials) {
    const day = dateFromTitle(material.title);
    if (!day) {
      console.log(`— пропускаю «${material.title}»: у назві немає дати`);
      continue;
    }

    const streamSessions = db
      .select()
      .from(sessions)
      .where(eq(sessions.streamId, material.ownerId))
      .all();
    const target = streamSessions.find((s) => dayMonthKyiv(s.startAt) === day);
    if (!target) {
      console.log(`— пропускаю «${material.title}»: заняття на ${day} не знайдено`);
      continue;
    }

    console.log(`${DRY ? "[dry] " : ""}«${material.title}» → ${target.title} (${day})`);
    if (!DRY) {
      db.update(materials)
        .set({ ownerType: "session", ownerId: target.id, order: 1 })
        .where(eq(materials.id, material.id))
        .run();
    }
    moved++;
  }

  console.log(`${DRY ? "Було б перенесено" : "Перенесено"}: ${moved}`);
}

move();
