import "../env.js";
import { eq } from "drizzle-orm";
import { db } from "../db.js";
import { courses, materials, sessions, streams } from "../schema.js";

/**
 * Додає реальний курс «Мотивація: база» у наявну базу.
 *
 * Окремим скриптом, а не через seed: seed спершу все витирає, а база жива.
 * Запускати повторно безпечно — якщо курс уже є, скрипт просто виходить.
 *
 * Не плутати з демо-курсом `c-motivation` («Мотивація та фундамент психіки»)
 * із seed: той вигаданий, цей — справжній, із записами занять.
 *
 * Запуск: npx tsx src/scripts/add-motivation-base.ts
 */

const COURSE_ID = "c-motivation-base";
const STREAM_ID = "s-motivation-base-1";

/**
 * Зустрічі о 18:00 за Києвом. Київ узимку UTC+2, улітку UTC+3, тож 18:00
 * місцевого — різний UTC залежно від дати. У чаті написано «UTC+2», але
 * червень — це літній час, тобто 15:00Z; вірити треба київському годиннику,
 * а не приписці.
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
  { date: "2026-06-16", recording: "https://drive.google.com/file/d/1RsuCkZus_BUA5CeE0s8OssK-IK_ODz4T/view" },
  { date: "2026-06-23", recording: "https://drive.google.com/file/d/1k4AhbOOMrycWOTi5E5YNFQRGd7tHfbnZ/view" },
  { date: "2026-06-30", recording: "https://drive.google.com/file/d/1UnXPSN2umN5iJPpFXJgLHoDIAl1LxZaA/view" },
];

function dayMonth(dateISO: string): string {
  const [, m, d] = dateISO.split("-");
  return `${d}.${m}`;
}

function addMotivationBase() {
  if (db.select().from(courses).where(eq(courses.id, COURSE_ID)).get()) {
    console.log("Курс «Мотивація: база» уже є — нічого не роблю.");
    return;
  }

  db.insert(courses).values({
    id: COURSE_ID,
    title: "Мотивація: база",
    summary:
      "Базовий курс про мотивацію: як вона влаштована й на чому тримається.",
    description:
      "Базовий курс про мотивацію: як вона влаштована й на чому тримається.\n\n" +
      "Три зустрічі по вівторках, 18:00–21:00 за Києвом, онлайн у Zoom.\n\n" +
      "Автор і ведучий — Петро Чорноморець: кандидат біологічних наук, " +
      "співзасновник системи просвіти «Змінотворці», викладач Києво-Могилянської " +
      "бізнес-школи, викладач і в минулому співавтор школи «Майбутні». " +
      "Експерт з ментального здоровʼя, освіти і системного мислення.\n\n" +
      "Кураторка курсу — Таня. З усіх питань щодо навчання, оплати чи реєстрації " +
      "на інші курси — @PetroChornomorets_team",
    format: "online",
    order: 6,
  }).run();

  db.insert(streams).values({
    id: STREAM_ID,
    courseId: COURSE_ID,
    title: "Потік (черв 2026)",
    startDate: HELD[0]!.date,
    // Усі три заняття відбулися, записи всіх трьох викладені.
    status: "finished",
    // Телеграм-групу цього потоку в матеріалах не називали.
    telegramGroupURL: null,
    // Загальної ціни немає: платять за кожне заняття окремо або за всі разом.
    priceFull: null,
    pricePerSession: 2100,
    order: 1,
  }).run();

  db.insert(sessions).values(
    HELD.map((s, i) => ({
      id: `ses-mb-${i + 1}`,
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
      id: "m-mb-pay",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-link",
      title: "Як оплатити заняття",
      description:
        "Вартість заняття — 2100 грн. Можна платити за кожне заняття окремо " +
        "або за всі разом.\n\n" +
        "Призначення платежу (вказати саме так):\n" +
        "«Інформаційно-консультаційні послуги за тренинг (лекцію), Мотивація, ОНВГ, " +
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
      id: "m-mb-miro",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-link",
      title: "Дошка Miro з візуалізаціями Петра",
      url: "https://miro.com/app/board/uXjVHG92o9s=/",
      order: 2,
    },
    {
      id: "m-mb-questions",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-doc",
      title: "Padlet для ваших запитань",
      description:
        "Петро переглядає документ під час заняття й відповідає на питання. " +
        "Підписуватись не обовʼязково.",
      url: "https://padlet.com/petro15/_-26-fhac2ast1p8yoh0n",
      order: 3,
    },
    // Записи — на занятті, якому вони належать, а не на потоці.
    ...HELD.map((s, i) => ({
      id: `m-mb-rec-${i + 1}`,
      ownerType: "session" as const,
      ownerId: `ses-mb-${i + 1}`,
      typeId: "mt-video",
      title: `Запис заняття ${i + 1} (${dayMonth(s.date)})`,
      videoProvider: "drive" as const,
      videoRef: driveFileId(s.recording),
      order: 1,
    })),
  ]).run();

  console.log(
    `Додано: курс ${COURSE_ID}, потік ${STREAM_ID}, ` +
      `занять ${HELD.length}, матеріалів ${3 + HELD.length}.`,
  );
}

addMotivationBase();
