import "../env.js";
import { eq } from "drizzle-orm";
import { db } from "../db.js";
import { courses, materials, sessions, streams } from "../schema.js";

/**
 * Додає реальний курс «Емоції» у наявну базу.
 *
 * Окремим скриптом, а не через seed: seed спершу все витирає, а база жива.
 * Запускати повторно безпечно — якщо курс уже є, скрипт просто виходить.
 *
 * Запуск: npx tsx src/scripts/add-emotions.ts
 */

const COURSE_ID = "c-emotions";
const STREAM_ID = "s-emotions-1";

/**
 * Зустрічі о 18:00 за Києвом. Київ узимку UTC+2, улітку UTC+3, тож 18:00
 * місцевого — різний UTC залежно від дати. Літній час 2026: 29.03–25.10.
 */
function kyivEvening(dateISO: string): string {
  const [, m, d] = dateISO.split("-").map(Number);
  const summer =
    (m! > 3 && m! < 10) || (m === 3 && d! >= 29) || (m === 10 && d! < 25);
  return `${dateISO}T${summer ? "15" : "16"}:00:00Z`;
}

/** З посилання виду https://drive.google.com/file/d/<id>/view — сам <id>. */
function driveFileId(url: string): string {
  const match = url.match(/\/file\/d\/([^/]+)/);
  if (!match) throw new Error(`не схоже на посилання Drive: ${url}`);
  return match[1]!;
}

/** Заняття, що вже відбулися: дата + запис на Drive. */
const HELD: Array<{ date: string; recording: string }> = [
  { date: "2026-06-02", recording: "https://drive.google.com/file/d/16bQIm_hxet8r24KZvFm25_qq7X9w80Bc/view" },
  { date: "2026-06-09", recording: "https://drive.google.com/file/d/1uU2vEFEr7wbpmEFPrT3Rc4D5IuAHOog3/view" },
];

function dayMonth(dateISO: string): string {
  const [, m, d] = dateISO.split("-");
  return `${d}.${m}`;
}

function addEmotions() {
  if (db.select().from(courses).where(eq(courses.id, COURSE_ID)).get()) {
    console.log("Курс «Емоції» уже є — нічого не роблю.");
    return;
  }

  db.insert(courses).values({
    id: COURSE_ID,
    title: "Емоції",
    summary: "Курс про емоції: як вони влаштовані й навіщо потрібні.",
    description:
      "Курс про емоції: як вони влаштовані й навіщо потрібні.\n\n" +
      "Дві зустрічі по вівторках, 18:00–21:00 за Києвом, онлайн у Zoom.\n\n" +
      "Автор і ведучий — Петро Чорноморець: кандидат біологічних наук, " +
      "співзасновник системи просвіти «Змінотворці», викладач Києво-Могилянської " +
      "бізнес-школи, викладач і в минулому співавтор школи «Майбутні». " +
      "Експерт з ментального здоровʼя, освіти і системного мислення.\n\n" +
      "Запис доступний тим, хто був на занятті або попросив його. Дивитися " +
      "треба з того Google-акаунта, який вказували при реєстрації.\n\n" +
      "Кураторка курсу — Таня. З усіх питань щодо навчання, оплати чи " +
      "реєстрації на інші курси — @PetroChornomorets_team",
    format: "online",
    order: 9,
  }).run();

  db.insert(streams).values({
    id: STREAM_ID,
    courseId: COURSE_ID,
    title: "Потік (черв 2026)",
    startDate: HELD[0]!.date,
    // Обидва заняття відбулися, записи є.
    status: "finished",
    telegramGroupURL: "https://t.me/+2gcbuyRMm8gyODAy",
    // Загальної ціни немає: платять за кожне заняття окремо або за всі разом.
    priceFull: null,
    pricePerSession: 2100,
    order: 1,
  }).run();

  db.insert(sessions).values(
    HELD.map((s, i) => ({
      id: `ses-emo-${i + 1}`,
      streamId: STREAM_ID,
      title: `Заняття ${i + 1}`,
      startAt: kyivEvening(s.date),
      durationMinutes: 180,
      format: "online" as const,
      // Посилання на Zoom щоразу нове й приходить у чат перед початком.
      joinURL: null,
      order: i + 1,
    })),
  ).run();

  db.insert(materials).values([
    {
      id: "m-emo-pay",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-link",
      title: "Як оплатити заняття",
      description:
        "Вартість заняття — 2100 грн. Можна оплатити за кожне заняття окремо " +
        "або за всі разом.\n\n" +
        "Призначення платежу (вказати саме так):\n" +
        "«Інформаційно-консультаційні послуги за тренинг (лекцію), Емоції, ОНВГ, " +
        "дата заняття, Ваше прізвище та імʼя. Без ПДВ.»\n\n" +
        "Отримувач: ФОП Чорноморець Петро Матейович\n" +
        "IBAN: UA193052990000026003006212319\n" +
        "ІПН (ЄДРПОУ): 3039214671\n" +
        "Банк: АТ КБ «ПРИВАТБАНК»\n\n" +
        "Для військових, ветеранів та системних волонтерів участь безкоштовна.",
      url: "https://next.privat24.ua/payments/form/%7B%22token%22%3A%22a5ad0066-41d5-44b4-a177-70a26a47f08c%22%7D",
      order: 1,
    },
    {
      id: "m-emo-miro",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-link",
      title: "Дошка Miro курсу",
      url: "https://miro.com/app/board/uXjVHLLjuRk=/",
      order: 2,
    },
    // Записи — на занятті, якому вони належать, а не на потоці.
    ...HELD.map((s, i) => ({
      id: `m-emo-rec-${i + 1}`,
      ownerType: "session" as const,
      ownerId: `ses-emo-${i + 1}`,
      typeId: "mt-video",
      title: `Запис заняття ${i + 1} (${dayMonth(s.date)})`,
      videoProvider: "drive" as const,
      videoRef: driveFileId(s.recording),
      order: 1,
    })),
  ]).run();

  console.log(
    `Додано: курс ${COURSE_ID}, потік ${STREAM_ID}, ` +
      `занять ${HELD.length}, матеріалів ${2 + HELD.length}.`,
  );
}

addEmotions();
