import "../env.js";
import { eq } from "drizzle-orm";
import { db } from "../db.js";
import { courses, materials, sessions, streams } from "../schema.js";

/**
 * Додає реальний курс «Самооцінка» у наявну базу.
 *
 * Окремим скриптом, а не через seed: seed спершу все витирає, а база жива.
 * Запускати повторно безпечно — якщо курс уже є, скрипт просто виходить.
 *
 * Не плутати з демо-курсом `c-esteem` («Самооцінка») із seed: той вигаданий,
 * цей — справжній, із записами занять.
 *
 * Запуск: npx tsx src/scripts/add-self-esteem.ts
 */

const COURSE_ID = "c-self-esteem";
const STREAM_ID = "s-self-esteem-1";

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
  { date: "2026-04-30", recording: "https://drive.google.com/file/d/1-wkzFgueQglbDZJfBdKekfkdj0i94sSW/view" },
  { date: "2026-05-14", recording: "https://drive.google.com/file/d/1vmo7b8IX986SpiD0p8r67aSiuSK412jq/view" },
];

function dayMonth(dateISO: string): string {
  const [, m, d] = dateISO.split("-");
  return `${d}.${m}`;
}

function addSelfEsteem() {
  if (db.select().from(courses).where(eq(courses.id, COURSE_ID)).get()) {
    console.log("Курс «Самооцінка» уже є — нічого не роблю.");
    return;
  }

  db.insert(courses).values({
    id: COURSE_ID,
    title: "Самооцінка",
    summary: "Курс про самооцінку: як вона влаштована й на що спирається.",
    description:
      "Курс про самооцінку: як вона влаштована й на що спирається.\n\n" +
      "Зустрічі раз на два тижні по четвергах, 18:00–21:00 за Києвом, онлайн у Zoom.\n\n" +
      "Автор і ведучий — Петро Чорноморець: кандидат біологічних наук, " +
      "співзасновник системи просвіти «Змінотворці», викладач Києво-Могилянської " +
      "бізнес-школи, викладач і в минулому співавтор школи «Майбутні». " +
      "Експерт з ментального здоровʼя, освіти і системного мислення.\n\n" +
      "Запис кожного заняття зʼявляється протягом кількох днів після нього. Він " +
      "доступний усім присутнім, а також тим, хто оплатив зустріч, але не зміг " +
      "доєднатися.\n\n" +
      "Кураторка курсу — Світлана. З усіх питань щодо навчання, оплати чи " +
      "реєстрації на інші курси — @PetroChornomorets_team",
    format: "online",
    order: 8,
  }).run();

  db.insert(streams).values({
    id: STREAM_ID,
    courseId: COURSE_ID,
    title: "Потік (квіт 2026)",
    startDate: HELD[0]!.date,
    // Курс іде раз на два тижні, і в оголошенні названо лише дві дати —
    // це не те саме, що «завершено». Стан курсу все одно за викладачем.
    status: "ongoing",
    telegramGroupURL: "https://t.me/+2QoSvOcYt8hlNzIy",
    // Загальної ціни не називають: можна оплатити весь курс або кожне заняття.
    priceFull: null,
    pricePerSession: 2100,
    order: 1,
  }).run();

  db.insert(sessions).values(
    HELD.map((s, i) => ({
      id: `ses-se-${i + 1}`,
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
      id: "m-se-pay",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-link",
      title: "Як оплатити заняття",
      description:
        "Вартість заняття — 2100 грн. Можна оплатити весь курс або кожне " +
        "заняття окремо.\n\n" +
        "Призначення платежу (вказати саме так):\n" +
        "«Інформаційно-консультаційні послуги за тренінг (лекцію), Самооцінка ОНВГ3, " +
        "дата заняття, Без ПДВ. Ваше прізвище та імʼя»\n\n" +
        "Отримувач: ФОП Чорноморець Петро Матейович\n" +
        "IBAN: UA193052990000026003006212319\n" +
        "ІПН (ЄДРПОУ): 3039214671\n" +
        "Банк: АТ КБ «ПРИВАТБАНК»\n\n" +
        "Для військових, ветеранів та системних волонтерів участь безкоштовна.",
      url: "https://next.privat24.ua/payments/form/%7B%22token%22%3A%22a5ad0066-41d5-44b4-a177-70a26a47f08c%22%7D",
      order: 1,
    },
    {
      id: "m-se-miro",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-link",
      title: "Дошка Miro курсу",
      url: "https://miro.com/app/board/uXjVHav4LSs=/",
      order: 2,
    },
    {
      id: "m-se-questions",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-doc",
      title: "Padlet для ваших запитів і питань",
      description:
        "Петро переглядає документ під час заняття й відповідає на питання. " +
        "Підписуватись не обовʼязково.",
      url: "https://padlet.com/petro15/3-yq381istcj02tamm",
      order: 3,
    },
    // Записи — на занятті, якому вони належать, а не на потоці.
    ...HELD.map((s, i) => ({
      id: `m-se-rec-${i + 1}`,
      ownerType: "session" as const,
      ownerId: `ses-se-${i + 1}`,
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

addSelfEsteem();
