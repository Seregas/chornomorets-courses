import type { Identity } from "./auth.js";
import type { Material } from "./types.js";

/**
 * Відео-шар: ховає реальне джерело відео від застосунку. Клієнт отримує лише
 * типізований playback-дескриптор і знає набір типів-хендлерів. Додати джерело
 * (R2/S3/HLS) = додати тип тут + хендлер у застосунку; верх застосунку не змінюється.
 */
export type PlaybackDescriptor =
  | { type: "direct"; url: string }
  | { type: "youtube"; videoId: string }
  | { type: "google-drive"; fileId: string; requiresGoogleAuth: true };

export type AccessState = "granted" | "denied" | "unknown";

/** Будує дескриптор за збереженим провайдером/референсом матеріалу. */
export function buildPlaybackDescriptor(
  material: Material,
): PlaybackDescriptor | null {
  if (!material.videoRef) return null;
  switch (material.videoProvider) {
    case "youtube":
      return { type: "youtube", videoId: material.videoRef };
    case "drive":
      return {
        type: "google-drive",
        fileId: material.videoRef,
        requiresGoogleAuth: true,
      };
    case "other":
    default:
      return { type: "direct", url: material.videoRef };
  }
}

/**
 * Стан доступу до відео під конкретну Google-ідентичність.
 *  - youtube/other (публічні) → завжди granted;
 *  - drive → залежить від того, чи акаунт у шарінгу.
 *
 * Прототип: без реального виклику Drive — якщо Google не підключено, повертаємо
 * "unknown" (UI показує «підключіть акаунт»), якщо підключено — "granted".
 * TODO(прод): тут робити Drive permissions.get / files.get з токеном користувача
 * й повертати granted/denied по факту шарінгу.
 */
export function checkAccess(
  material: Material,
  identity: Identity | null,
): AccessState {
  if (!material.videoRef) return "denied";
  if (material.videoProvider === "drive") {
    if (!identity) return "unknown";
    return checkDriveAccess(material.videoRef, identity);
  }
  return "granted";
}

/** Плаг-пойнт для реальної перевірки доступу в Google Drive. */
function checkDriveAccess(_fileId: string, _identity: Identity): AccessState {
  // Прод: викликати Drive API з токеном користувача. Прототип: оптимістично granted.
  return "granted";
}
