import "../env.js";
import { and, asc, desc, eq } from "drizzle-orm";
import { db } from "../db.js";
import { materials, sessions, streams } from "../schema.js";

/**
 * Додає одне заняття до наявного потоку — і, якщо дано, запис до нього.
 *
 * Курси на кшталт «Біохардкору» безрозмірні: дати називають по одній, у чаті,
 * за кілька днів до зустрічі. Писати окремий скрипт на кожну — марно, тому цей
 * приймає їх аргументами. Повторний запуск на ту саму дату нічого не дублює:
 * якщо заняття в цей день уже є, скрипт лише допише запис, якщо його бракувало.
 *
 * Запуск:
 *   npx tsx src/scripts/add-session.ts <stream-id> <YYYY-MM-DD> [посилання-на-запис]
 * Наприклад:
 *   npx tsx src/scripts/add-session.ts s-biohardcore-1 2026-09-07 \
 *     https://drive.google.com/file/d/1gbeg.../view
 */

const [, , streamId, date, recording] = process.argv;

if (!streamId || !date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
  console.error(
    "Треба: npx tsx src/scripts/add-session.ts <stream-id> <YYYY-MM-DD> [посилання-на-запис]",
  );
  process.exit(1);
}

/**
 * Зустрічі о 18:00 за Києвом. Київ узимку UTC+2, улітку UTC+3, тож 18:00
 * місцевого — різний UTC залежно від дати. Літній час: остання неділя березня
 * — остання неділя жовтня (2026: 29.03 і 25.10).
 */
function kyivEvening(dateISO: string): string {
  const [, m, d] = dateISO.split("-").map(Number);
  const summer =
    (m! > 3 && m! < 10) || (m === 3 && d! >= 29) || (m === 10 && d! < 25);
  return `${dateISO}T${summer ? "15" : "16"}:00:00Z`;
}

function driveFileId(url: string): string {
  const match = url.match(/\/file\/d\/([^/]+)/);
  if (!match) throw new Error(`не схоже на посилання Drive: ${url}`);
  return match[1]!;
}

function dayMonth(dateISO: string): string {
  const [, m, d] = dateISO.split("-");
  return `${d}.${m}`;
}

const stream = db.select().from(streams).where(eq(streams.id, streamId)).get();
if (!stream) {
  console.error(`Потоку ${streamId} немає.`);
  process.exit(1);
}

const startAt = kyivEvening(date);
const existing = db
  .select()
  .from(sessions)
  .where(and(eq(sessions.streamId, streamId), eq(sessions.startAt, startAt)))
  .get();

let session = existing;
if (session) {
  console.log(`Заняття на ${date} уже є (${session.id}).`);
} else {
  const last = db
    .select()
    .from(sessions)
    .where(eq(sessions.streamId, streamId))
    .orderBy(desc(sessions.order))
    .get();
  const order = (last?.order ?? 0) + 1;
  // Номер у назві — порядковий у потоці, як і в решти занять курсу.
  const prefix = last?.title.replace(/\s*\d+\s*$/, "") || "Заняття";
  // Id теж продовжуємо ряд сусідів (ses-bio-10 → ses-bio-11): вони opaque, але
  // читати їх доводиться очима — у скриптах, логах і sqlite.
  const idBase = last?.id.replace(/-\d+$/, "") ?? streamId.replace(/^s-/, "ses-");
  const id = `${idBase}-${order}`;

  session = db
    .insert(sessions)
    .values({
      id,
      streamId,
      title: `${prefix} ${order}`,
      startAt,
      durationMinutes: last?.durationMinutes ?? 180,
      format: last?.format ?? "online",
      // Посилання на Zoom щоразу нове й приходить у чат перед початком.
      joinURL: null,
      order,
    })
    .returning()
    .get();
  console.log(`Додано заняття: ${session.title} (${date}) → ${session.id}`);
}

if (recording) {
  const fileId = driveFileId(recording);
  const already = db
    .select()
    .from(materials)
    .where(and(eq(materials.ownerType, "session"), eq(materials.ownerId, session.id)))
    .all()
    .find((m) => m.videoRef === fileId);

  if (already) {
    console.log("  запис уже прикріплений — нічого не роблю");
  } else {
    const siblings = db
      .select()
      .from(materials)
      .where(and(eq(materials.ownerType, "session"), eq(materials.ownerId, session.id)))
      .orderBy(asc(materials.order))
      .all();
    db.insert(materials)
      .values({
        ownerType: "session",
        ownerId: session.id,
        typeId: "mt-video",
        title: `Запис ${session.title.toLowerCase()} (${dayMonth(date)})`,
        videoProvider: "drive",
        videoRef: fileId,
        order: (siblings.at(-1)?.order ?? 0) + 1,
      })
      .run();
    console.log(`  + запис ${fileId}`);
  }
}

console.log("Готово.");
