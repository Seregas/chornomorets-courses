import "../env.js";
import { db } from "../db.js";
import { courses, materials, sessions, streams } from "../schema.js";
import { eq } from "drizzle-orm";

/**
 * Додає реальний курс «Біохардкор» у наявну базу.
 *
 * Чому окремим скриптом, а не через seed: seed спершу все витирає, а база вже
 * жива — там будуть підписки, заявки й питання справжніх людей. Цей скрипт
 * нічого не чіпає, крім свого курсу, і його безпечно запускати повторно:
 * якщо курс уже є, він просто виходить.
 *
 * Запуск: npx tsx src/scripts/add-biohardcore.ts
 */

const COURSE_ID = "c-biohardcore";
const STREAM_ID = "s-biohardcore-1";

/**
 * Зустрічі о 18:00 за Києвом. Київ узимку UTC+2, улітку UTC+3 — тож 18:00
 * місцевого це різний UTC залежно від дати. Літній час: остання неділя
 * березня — остання неділя жовтня (2026: 29.03 і 25.10).
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
  { date: "2026-02-23", recording: "https://drive.google.com/file/d/1ZKAxcd0lLQw3UHz2uhs_UbJMggxWvRWk/view" },
  { date: "2026-03-09", recording: "https://drive.google.com/file/d/1tuhD_esmzDMGzlYbtqirfaK8N2G7ckqr/view" },
  { date: "2026-03-23", recording: "https://drive.google.com/file/d/10_QTal6DmOasA0gGJZqlW5hhWt-Tlgtf/view" },
  { date: "2026-04-06", recording: "https://drive.google.com/file/d/1kUtbuH56SnO85vAKVCY-QO3eYwBIjS3v/view" },
  { date: "2026-04-20", recording: "https://drive.google.com/file/d/11dIB0k7nx9ySyUt24thg38NTpaq35SiW/view" },
  { date: "2026-05-04", recording: "https://drive.google.com/file/d/1LpEEO9v7QwyKkYyqTLXu2gXQFZlN7Vrk/view" },
  { date: "2026-05-18", recording: "https://drive.google.com/file/d/11CTWJqVvPFFuBFvwjEblXKjwSZXmtsfi/view" },
  { date: "2026-06-01", recording: "https://drive.google.com/file/d/1TCorcxZbjfwBsXIOCNtBREG_0smJzyET/view" },
  { date: "2026-06-15", recording: "https://drive.google.com/file/d/1JVvR759MofMLQa1z4Co7I9omf5x0sUum/view" },
  { date: "2026-06-29", recording: "https://drive.google.com/file/d/1vK86PSgxzoneoIUonn2IkKScW80o4yJ0/view" },
];

function dayMonth(dateISO: string): string {
  const [, m, d] = dateISO.split("-");
  return `${d}.${m}`;
}

function addBiohardcore() {
  const existing = db.select().from(courses).where(eq(courses.id, COURSE_ID)).get();
  if (existing) {
    console.log("Курс «Біохардкор» уже є — нічого не роблю.");
    return;
  }

  db.insert(courses).values({
    id: COURSE_ID,
    title: "Біохардкор",
    summary:
      "Молекули, гени, клітини, хаос, еволюція, імунітет, енергетичний обмін, " +
      "електричні процеси на мембранах і все таке. Теорія для тих, хто хоче упороцца.",
    description:
      "Молекули, гени, клітини, хаос, еволюція, імунітет, енергетичний обмін, " +
      "електричні процеси на мембранах і все таке. Теорія для тих, хто хоче упороцца.\n\n" +
      "Курс умовно безрозмірний: будемо досліджувати, поки буде група. " +
      "Зустрічі раз на два тижні по понеділках, 18:00–21:00 за Києвом, онлайн у Zoom.\n\n" +
      "Ведуть курс:\n\n" +
      "Петро Чорноморець — кандидат біологічних наук, співзасновник системи просвіти «Змінотворці», " +
      "викладач Києво-Могилянської бізнес-школи, викладач і в минулому співавтор школи «Майбутні». " +
      "Експерт з ментального здоровʼя, освіти і системного мислення.\n\n" +
      "Олена Соляник — біолог, еколог, провізор; тренерка шкільної олімпійської команди з біології " +
      "на Всеукраїнській та Міжнародній олімпіаді; заслужена вчителька України; викладачка " +
      "природничих дисциплін у «Майбутніх» і «Змінотворцях».\n\n" +
      "Олексій Болдирєв — кандидат біологічних наук, завідувач кафедри біотехнології Київського " +
      "авіаційного інституту, доцент кафедри біомедицини та нейронаук Київського академічного " +
      "університету; науковий редактор порталу «Моя наука», співорганізатор акції «Тиждень мозку в Україні».",
    program:
      "Молекули · гени · клітини · хаос · еволюція · імунітет · енергетичний обмін · " +
      "електричні процеси на мембранах",
    format: "online",
    order: 5,
  }).run();

  db.insert(streams).values({
    id: STREAM_ID,
    courseId: COURSE_ID,
    title: "Потік (лют 2026)",
    startDate: HELD[0]!.date,
    status: "ongoing",
    telegramGroupURL: "https://t.me/+4y3aQlyLM-s3MWVi",
    // Загальної ціни за курс немає — платять за кожне заняття окремо.
    priceFull: null,
    pricePerSession: 2100,
    order: 1,
  }).run();

  db.insert(sessions).values(
    HELD.map((s, i) => ({
      id: `ses-bio-${i + 1}`,
      streamId: STREAM_ID,
      title: `Заняття ${i + 1}`,
      startAt: kyivEvening(s.date),
      durationMinutes: 180,
      format: "online" as const,
      // Посилання на Zoom щоразу нове й приходить у чат перед початком.
      joinURL: null,
      // Заняття відбулися; оплата насправді індивідуальна, а це поле — на
      // заняття потоку, тож точніше воно не вміє (див. нотатку в звіті).
      paymentStatus: "paid" as const,
      order: i + 1,
    })),
  ).run();

  db.insert(materials).values([
    {
      id: "m-bio-pay",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-link",
      title: "Як оплатити заняття",
      description:
        "Вартість заняття — 2100 грн.\n\n" +
        "Призначення платежу (вказати саме так):\n" +
        "«Інформаційно-консультаційні послуги за тренинг (лекцію), Біохардкор онлайн, " +
        "дата заняття, Ваше прізвище та імʼя. Без ПДВ.»\n\n" +
        "Отримувач: ФОП Чорноморець Петро Матейович\n" +
        "IBAN: UA193052990000026003006212319\n" +
        "ІПН (ЄДРПОУ): 3039214671\n" +
        "Банк: АТ КБ «ПРИВАТБАНК»\n\n" +
        "Для військових, ветеранів та системних волонтерів участь безкоштовна.\n" +
        "Питання щодо навчання, оплати чи реєстрації — @PetroChornomorets_team",
      url: "https://next.privat24.ua/payments/form/%7B%22token%22%3A%22a5ad0066-41d5-44b4-a177-70a26a47f08c%22%7D",
      order: 1,
    },
    {
      id: "m-bio-miro",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-link",
      title: "Дошка Miro із занять",
      url: "https://miro.com/app/board/uXjVG8M2fpQ=",
      order: 2,
    },
    {
      id: "m-bio-questions",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-doc",
      title: "Файл для ваших запитань",
      description: "Спільний документ, куди можна писати питання до наступного заняття.",
      url: "https://docs.google.com/document/d/1JESK9r_lPZ6q2KAbybrpr1xqgE-ypo6fkQjjsylWLZs/edit",
      order: 3,
    },
    {
      id: "m-bio-info",
      ownerType: "stream",
      ownerId: STREAM_ID,
      typeId: "mt-link",
      title: "Інформаційне повідомлення в чаті",
      description: "Закріплене повідомлення з усією важливою інформацією по курсу.",
      url: "https://t.me/c/3708073783/9",
      order: 4,
    },
    // Записи занять — на Drive, доступ персональний по Google-акаунту.
    ...HELD.map((s, i) => ({
      id: `m-bio-rec-${i + 1}`,
      ownerType: "stream" as const,
      ownerId: STREAM_ID,
      typeId: "mt-video",
      title: `Запис заняття ${i + 1} (${dayMonth(s.date)})`,
      videoProvider: "drive" as const,
      videoRef: driveFileId(s.recording),
      order: 10 + i,
    })),
  ]).run();

  console.log(
    `Додано: курс ${COURSE_ID}, потік ${STREAM_ID}, ` +
      `занять ${HELD.length}, матеріалів ${4 + HELD.length}.`,
  );
}

addBiohardcore();
