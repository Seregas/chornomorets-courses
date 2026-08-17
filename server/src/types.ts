import type {
  Account,
  Announcement,
  Application,
  ClientLog,
  Payment,
  Course,
  Enrollment,
  Material,
  MaterialType,
  Question,
  Session,
  Pulse,
  Stream,
  Submission,
} from "./schema.js";

/**
 * API-DTO (форми відповідей). Окремо від БД-рядків, щоб структура API не залежала
 * від таблиць. Клієнт орієнтується лише на ці типи.
 */

/** Короткий опис потоку всередині картки курсу. */
export interface StreamBrief {
  id: string;
  title: string;
  startDate: string | null;
  status: Stream["status"];
}

/** Картка курсу для каталогу. */
export interface CourseCard {
  id: string;
  title: string;
  summary: string;
  format: Course["format"];
  coverImageURL: string | null;
  nextStream: StreamBrief | null;
}

/** «Злитий» опис потоку: override-поля вже застосовані поверх курсу. */
export interface ResolvedStream {
  id: string;
  courseId: string;
  title: string;
  startDate: string | null;
  status: Stream["status"];
  telegramGroupURL: string | null;
  priceFull: number | null;
  pricePerSession: number | null;
  // Поля опису з урахуванням override:
  summary: string;
  description: string;
  program: string | null;
  coverImageURL: string | null;
}

/** Матеріал у вигляді для клієнта: videoRef НЕ віддаємо, лише ознаку наявності відео. */
export interface MaterialDTO {
  id: string;
  title: string;
  typeId: string | null;
  description: string | null;
  url: string | null;
  dueAt: string | null;
  order: number;
  // Відео-фасет (без сирого джерела): для запиту playback використовується id матеріалу.
  hasVideo: boolean;
  videoProvider: Material["videoProvider"] | null;
  durationMinutes: number | null;
}

/** Деталь курсу: курс + його потоки (зі злитим описом) + матеріали рівня курсу. */
export interface CourseDetail {
  id: string;
  title: string;
  summary: string;
  description: string;
  program: string | null;
  format: Course["format"];
  coverImageURL: string | null;
  streams: ResolvedStream[];
  materials: MaterialDTO[];
}

/** Стан оплати конкретної людини за конкретне заняття. */
export interface PaymentDTO {
  id: string;
  sessionId: string;
  status: Payment["status"];
  amount: number | null;
  receiptURL: string | null;
  note: string | null;
  declaredAt: string;
  reviewedAt: string | null;
  /** Чи прикріплено скріншот — саме зображення тягнеться окремим запитом. */
  hasReceiptImage: boolean;
  /** Що вдалося прочитати зі скріншота (сума, дата, призначення). */
  receiptParsed: string | null;
  /** Лише адміну: хто саме заявив. */
  accountId?: string;
  authorEmail?: string | null;
}

/** Заняття разом зі своїми матеріалами (запис, конспект, домашка цієї зустрічі). */
export interface SessionWithMaterials {
  session: Session;
  materials: MaterialDTO[];
  /** Оплата того, хто питає. null — не заявляв. */
  payment: PaymentDTO | null;
}

/** Деталь потоку: злитий опис + заняття + матеріали потоку.
 *  Поля *Override — сирі значення (для адмін-редагування; null = успадковано). */
export interface StreamDetail extends ResolvedStream {
  sessions: SessionWithMaterials[];
  materials: MaterialDTO[];
  summaryOverride: string | null;
  descriptionOverride: string | null;
  programOverride: string | null;
  coverImageOverride: string | null;
}

/** Елемент розкладу: заняття з контекстом курсу/потоку. */
export interface ScheduleItem {
  session: Session;
  payment: PaymentDTO | null;
  streamId: string;
  streamTitle: string;
  courseId: string;
  courseTitle: string;
}

/** Оголошення на потік разом із контекстом курсу (для стрічки «Навчання»). */
export interface AnnouncementDTO {
  id: string;
  streamId: string;
  streamTitle: string;
  courseTitle: string;
  text: string;
  createdAt: string;
}

/**
 * Питання до заняття у вигляді для клієнта. Автора не показуємо нікому, крім
 * адміна (`authorEmail` приходить лише йому й лише якщо питання не анонімне) —
 * питати «дурне» має бути безпечно.
 */
export interface QuestionDTO {
  id: string;
  sessionId: string;
  text: string;
  createdAt: string;
  answeredAt: string | null;
  /** Чи це питання того, хто питає — щоб показати «ваше» й дозволити видалити. */
  isMine: boolean;
  /** Лише адміну: автор, якщо питання не анонімне. */
  authorEmail?: string | null;
}

/** Матеріал разом із потоком/курсом, з якого він походить. */
export interface MaterialInContext {
  material: MaterialDTO;
  streamId: string;
  streamTitle: string;
  courseId: string;
  courseTitle: string;
}

/**
 * Курс, на якому людина вчиться зараз. Розклад показує окремі заняття, а це —
 * відповідь на «де я взагалі вчуся»: без цього курс, у якого всі заняття вже
 * позаду, зникав з екрана зовсім, лишаючи по собі самі записи.
 */
export interface EnrolledStream {
  streamId: string;
  streamTitle: string;
  courseId: string;
  courseTitle: string;
  /**
   * Стан потоку так, як його виставив викладач. Саме він вирішує, чи курс
   * завершено: відсутність запланованих занять попереду означає лише, що
   * наступну дату ще не назвали.
   */
  status: Stream["status"];
  /** Скільки занять уже відбулося з усіх. */
  sessionsPassed: number;
  sessionsTotal: number;
  /** Найближче заняття попереду; null — наступної дати ще немає. */
  nextSessionAt: string | null;
  /** За скільки занять оплата ще не підтверджена. */
  unpaidSessions: number;
}

/**
 * Зведення для екрана «Моє навчання»: усе, що стосується того, хто ВЖЕ вчиться.
 * Каталог відповідає на питання «що взяти», а це — на «що зараз і що я пропустив».
 */
export interface HomeDigest {
  /** Курси, на яких людина вчиться — включно з тими, що вже завершилися. */
  streams: EnrolledStream[];
  nextSession: ScheduleItem | null;
  /** Свіжі оголошення підписаних потоків — найголовніше, що міг сказати викладач. */
  announcements: AnnouncementDTO[];
  /** Наступні заняття після найближчого. */
  upcoming: ScheduleItem[];
  /** Домашка з дедлайном: спершу найближчі; щойно прострочені теж показуємо. */
  homework: MaterialInContext[];
  /** Записи занять підписаних потоків. */
  recordings: MaterialInContext[];
}

/**
 * Заявка разом із курсом і потоком — для списку «усі нерозглянуті».
 * Без нього заявки видно лише зайшовши в кожен потік окремо, і про нову
 * викладач дізнається випадково.
 */
export interface ApplicationInContext {
  application: Application;
  streamId: string;
  streamTitle: string;
  courseTitle: string;
}

/** Зведення відгуків по заняттю — для викладача. */
export interface PulseSummary {
  sessionId: string;
  count: number;
  average: number;
  /** Розподіл оцінок: індекс 0 = «1 зірка». */
  histogram: number[];
  comments: string[];
}

export type {
  Course,
  Stream,
  Session,
  Material,
  MaterialType,
  Enrollment,
  Question,
  Announcement,
  Submission,
  Pulse,
  Application,
  ClientLog,
  Payment,
  Account,
};
