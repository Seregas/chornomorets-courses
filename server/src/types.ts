import type {
  Course,
  Enrollment,
  Material,
  MaterialType,
  Session,
  Stream,
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

/** Деталь потоку: злитий опис + заняття + матеріали потоку.
 *  Поля *Override — сирі значення (для адмін-редагування; null = успадковано). */
export interface StreamDetail extends ResolvedStream {
  sessions: Session[];
  materials: MaterialDTO[];
  summaryOverride: string | null;
  descriptionOverride: string | null;
  programOverride: string | null;
  coverImageOverride: string | null;
}

/** Елемент розкладу: заняття з контекстом курсу/потоку. */
export interface ScheduleItem {
  session: Session;
  streamId: string;
  streamTitle: string;
  courseId: string;
  courseTitle: string;
}

export type { Course, Stream, Session, Material, MaterialType, Enrollment };
