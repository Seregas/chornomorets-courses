import { db } from "./db.js";
import {
  announcements,
  courses,
  enrollments,
  materials,
  materialTypes,
  questions,
  sessions,
  streams,
} from "./schema.js";

/**
 * Наповнення БД демо-даними (курси Петра Чорноморця).
 * Дати — ілюстративні. Відео-референси — плейсхолдери (Drive fileId / YouTube id).
 * Запуск: `npm run db:push` (створити таблиці) → `npm run seed`.
 */

function reset() {
  // Порядок з огляду на зовнішні ключі. Питання й оголошення чистимо явно:
  // каскад у SQLite вмикається прагмою, покладатися на нього тут не варто.
  db.delete(questions).run();
  db.delete(announcements).run();
  db.delete(materials).run();
  db.delete(sessions).run();
  db.delete(enrollments).run();
  db.delete(streams).run();
  db.delete(courses).run();
  db.delete(materialTypes).run();
}

const TG = "https://t.me/petro_chornomorets";

/**
 * Демо-дати рахуються ВІД СЬОГОДНІ, а не зашиті абсолютними: інакше через кілька
 * місяців усі «майбутні» заняття стають минулими, розклад порожніє і прототип
 * виглядає зламаним. Минулий потік лишається минулим, майбутній — майбутнім.
 */
const DAY_MS = 86_400_000;
function at(daysFromNow: number, hourUTC: number): string {
  const d = new Date(Date.now() + daysFromNow * DAY_MS);
  d.setUTCHours(hourUTC, 0, 0, 0);
  return d.toISOString().replace(".000Z", "Z");
}
const dayOf = (iso: string) => iso.slice(0, 10);

// Стрес: завершений потік (є записи) і майбутній.
const S4 = [at(-128, 17), at(-121, 17), at(-114, 17)] as const;
const S5 = [at(5, 17), at(12, 17), at(19, 17)] as const;
const E3 = [at(7, 17), at(14, 17)] as const;   // Самооцінка
const B1 = [at(21, 9)] as const;               // Гра «Вигорання» — цілий день
const M1 = [at(3, 17), at(10, 17)] as const;   // Мотивація

function seed() {
  reset();

  // — Типи матеріалів (керований каталог-ярлик) —
  db.insert(materialTypes).values([
    { id: "mt-video", name: "Відеозапис", icon: "play.rectangle.fill", color: "#0E7C86", order: 1 },
    { id: "mt-doc", name: "Документ", icon: "doc.text.fill", color: "#2D9CDB", order: 2 },
    { id: "mt-link", name: "Корисне посилання", icon: "link", color: "#8E8E93", order: 3 },
    { id: "mt-hw", name: "Домашнє завдання", icon: "checkmark.circle.fill", color: "#E8833A", order: 4 },
  ]).run();

  // — Курси —
  db.insert(courses).values([
    {
      id: "c-stress",
      title: "Стрес, втома і піклування про себе",
      summary: "Міні-курс на 3 заняття про ефективні тактики й стратегії життя замість звикання до стресу.",
      description: "Неможливо погано жити і добре почуватися. Розбираємо стрес, втому й піклування про себе з біологічної точки зору.",
      program: "1) Як не заїдати емоції; 2) Що робити, якщо «подихати» не допомагає; 3) Стресостійкість і відновлення.",
      format: "online",
      order: 1,
    },
    {
      id: "c-esteem",
      title: "Самооцінка",
      summary: "Міні-курс на 2 заняття про самооцінку, самоцінність і те, як її підвищити.",
      description: "Чому найкраща самооцінка не в тих, хто найбільше досягає? І як її собі підвищити.",
      program: "1) Чому хвалити й сварити однаково непродуктивно; 2) Різниця між заниженою самооцінкою та недостатньою самоцінністю.",
      format: "online",
      order: 2,
    },
    {
      id: "c-burnout",
      title: "Гра «Вигорання»",
      summary: "Гра-симуляція на 1 день про ліміти, відпочинок і вихід із петлі робота–дім–робота.",
      description: "Гра дозволяє подивитися на власні ліміти інакше й почати діяти й не-діяти краще.",
      program: "Одноденний інтенсив 12:00–20:00: переосмислення власних лімітів і тактик відпочинку.",
      format: "online",
      order: 3,
    },
    {
      id: "c-motivation",
      title: "Мотивація та фундамент психіки",
      summary: "Курс про натхнення, мотивацію, стрес і щастя — на рівні біохімії та системного підходу.",
      description: "Цілісне розуміння того, як працює мотивація, стрес і щастя.",
      program: "Базові принципи роботи системи мотивації; індивідуальний підхід до власних станів.",
      format: "online",
      order: 4,
    },
  ]).run();

  // — Потоки —
  db.insert(streams).values([
    // Стрес: завершений Потік 4 (із записами) + майбутній Потік 5.
    {
      id: "s-stress-4", courseId: "c-stress", title: "Потік 4", startDate: dayOf(S4[0]),
      status: "finished", telegramGroupURL: TG, priceFull: 900, pricePerSession: 350, order: 1,
    },
    {
      id: "s-stress-5", courseId: "c-stress", title: "Потік 5", startDate: dayOf(S5[0]),
      status: "upcoming", telegramGroupURL: TG, priceFull: 900, pricePerSession: 350, order: 2,
    },
    // Самооцінка: майбутній потік з ПЕРЕВИЗНАЧЕНИМ описом (демо override).
    {
      id: "s-esteem-3", courseId: "c-esteem", title: "Потік 3", startDate: dayOf(E3[0]),
      status: "upcoming", telegramGroupURL: TG, priceFull: 700, pricePerSession: 400,
      descriptionOverride: "Оновлений потік: цього разу більше практики й розборів конкретних кейсів самооцінки в роботі та стосунках.",
      order: 1,
    },
    {
      id: "s-burnout-1", courseId: "c-burnout", title: "Найближча гра", startDate: dayOf(B1[0]),
      status: "upcoming", telegramGroupURL: TG, priceFull: 1200, order: 1,
    },
    {
      id: "s-motivation-1", courseId: "c-motivation", title: "Потік 1", startDate: dayOf(M1[0]),
      status: "upcoming", telegramGroupURL: TG, priceFull: 1000, pricePerSession: 550, order: 1,
    },
  ]).run();

  // — Заняття —
  db.insert(sessions).values([
    // Стрес, Потік 4 (минулі — є записи).
    { id: "ses-s4-1", streamId: "s-stress-4", title: "Заняття 1", startAt: S4[0], durationMinutes: 120, format: "online", paymentStatus: "paid", order: 1 },
    { id: "ses-s4-2", streamId: "s-stress-4", title: "Заняття 2", startAt: S4[1], durationMinutes: 120, format: "online", paymentStatus: "paid", order: 2 },
    { id: "ses-s4-3", streamId: "s-stress-4", title: "Заняття 3", startAt: S4[2], durationMinutes: 120, format: "online", paymentStatus: "paid", order: 3 },
    // Стрес, Потік 5 (майбутні).
    { id: "ses-s5-1", streamId: "s-stress-5", title: "Заняття 1", startAt: S5[0], durationMinutes: 120, format: "online", joinURL: "https://meet.google.com/abc-stress-1", paymentStatus: "unpaid", order: 1 },
    { id: "ses-s5-2", streamId: "s-stress-5", title: "Заняття 2", startAt: S5[1], durationMinutes: 120, format: "online", joinURL: "https://meet.google.com/abc-stress-2", paymentStatus: "unpaid", order: 2 },
    { id: "ses-s5-3", streamId: "s-stress-5", title: "Заняття 3", startAt: S5[2], durationMinutes: 120, format: "online", joinURL: "https://meet.google.com/abc-stress-3", paymentStatus: "unpaid", order: 3 },
    // Самооцінка, Потік 3.
    { id: "ses-e3-1", streamId: "s-esteem-3", title: "Заняття 1", startAt: E3[0], durationMinutes: 120, format: "online", joinURL: "https://meet.google.com/abc-esteem-1", paymentStatus: "free", order: 1 },
    { id: "ses-e3-2", streamId: "s-esteem-3", title: "Заняття 2", startAt: E3[1], durationMinutes: 120, format: "online", joinURL: "https://meet.google.com/abc-esteem-2", paymentStatus: "unpaid", order: 2 },
    // Гра Вигорання.
    { id: "ses-b1-1", streamId: "s-burnout-1", title: "Гра (онлайн, цілий день)", startAt: B1[0], durationMinutes: 480, format: "online", joinURL: "https://meet.google.com/abc-burnout", paymentStatus: "unpaid", order: 1 },
    // Мотивація.
    { id: "ses-m1-1", streamId: "s-motivation-1", title: "Заняття 1", startAt: M1[0], durationMinutes: 120, format: "online", paymentStatus: "unpaid", order: 1 },
    { id: "ses-m1-2", streamId: "s-motivation-1", title: "Заняття 2", startAt: M1[1], durationMinutes: 120, format: "online", paymentStatus: "unpaid", order: 2 },
  ]).run();

  // — Матеріали —
  db.insert(materials).values([
    // Рівень КУРСУ (вічні): «про курс» (текст, без типу) + реєстрація (лінк).
    { id: "m-stress-about", ownerType: "course", ownerId: "c-stress", title: "Про курс", description: "Розбираємо стрес, втому й піклування про себе з біологічної точки зору. Без води — лише робочі тактики.", order: 1 },
    { id: "m-stress-reg", ownerType: "course", ownerId: "c-stress", typeId: "mt-link", title: "Реєстрація (анкета)", url: "https://forms.gle/J2ASG5UWBj4hh3py8", order: 2 },
    { id: "m-esteem-reg", ownerType: "course", ownerId: "c-esteem", typeId: "mt-link", title: "Реєстрація (анкета)", url: "https://forms.gle/jJgT8Wa7sm1TtvR56", order: 1 },
    { id: "m-burnout-reg", ownerType: "course", ownerId: "c-burnout", typeId: "mt-link", title: "Реєстрація (анкета)", url: "https://forms.gle/V6UuTdj99whwyWzd6", order: 1 },

    // Рівень ПОТОКУ (Стрес, Потік 4): записи занять.
    // Композитний матеріал: текст + відео (Drive).
    { id: "m-s4-rec1", ownerType: "session", ownerId: "ses-s4-1", typeId: "mt-video", title: "Запис заняття 1", description: "Як не заїдати емоції — повний запис.", videoProvider: "drive", videoRef: "1AbCDriveFileStress1", durationMinutes: 118, order: 1 },
    { id: "m-s4-rec2", ownerType: "session", ownerId: "ses-s4-2", typeId: "mt-video", title: "Запис заняття 2", videoProvider: "drive", videoRef: "1AbCDriveFileStress2", durationMinutes: 121, order: 2 },
    { id: "m-s4-yt", ownerType: "stream", ownerId: "s-stress-4", typeId: "mt-video", title: "Бонусна лекція (YouTube)", videoProvider: "youtube", videoRef: "dQw4w9WgXcQ", order: 3 },
    { id: "m-s4-doc", ownerType: "session", ownerId: "ses-s4-1", typeId: "mt-doc", title: "Конспект заняття 1", url: "https://docs.google.com/document/d/EXAMPLE", order: 4 },
    { id: "m-s4-hw", ownerType: "session", ownerId: "ses-s4-1", typeId: "mt-hw", title: "Домашнє завдання до заняття 1", description: "Протягом тижня занотуйте 3 ситуації, де ви заїдали емоції, і що передувало.", dueAt: S4[1], order: 5 },

    // Підготовка до майбутнього потоку — жива домашка з дедлайном попереду.
    { id: "m-s5-hw", ownerType: "session", ownerId: "ses-s5-1", typeId: "mt-hw", title: "Підготовка до заняття 1", description: "До першого заняття занотуйте, у які моменти тижня втома накриває найсильніше.", dueAt: S5[0], order: 1 },
  ]).run();

  // — Демо-підписка для розкладу —
  db.insert(enrollments).values([
    // Правдоподібна історія студента: пройшов минулий потік «Стресу» (звідти
    // записи й домашка), записався на наступний і ще на «Самооцінку».
    { id: "en-demo-0", deviceId: "demo-device", streamId: "s-stress-4", subscribedAt: new Date().toISOString() },
    { id: "en-demo-1", deviceId: "demo-device", streamId: "s-stress-5", subscribedAt: new Date().toISOString() },
    { id: "en-demo-2", deviceId: "demo-device", streamId: "s-esteem-3", subscribedAt: new Date().toISOString() },
  ]).run();

  // — Оголошення потоку —
  db.insert(announcements).values([
    { streamId: "s-stress-5", text: "Заняття 2 переносимо на четвер, 20:00 — у вівторок я на конференції." },
    { streamId: "s-esteem-3", text: "Виклав конспект першого заняття — у матеріалах потоку." },
  ]).run();

  console.log("Seed готово: 4 курси, 5 потоків, 11 занять, 9 матеріалів, 4 типи, демо-підписки (deviceId=demo-device).");
}

seed();
