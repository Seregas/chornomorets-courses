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
 * Стан доступу до відео під конкретного користувача.
 *  - youtube/other (публічні) → завжди granted;
 *  - drive → питаємо Drive API токеном самого користувача.
 *
 * `driveToken` — OAuth access token зі scope drive.readonly, який застосунок
 * шле заголовком X-Drive-Token. Без нього сказати щось про доступ неможливо:
 * Drive відповідає не «чи є доступ у цього файлу», а «чи бачить його той,
 * хто питає».
 */
export async function checkAccess(
  material: Material,
  identity: Identity | null,
  driveToken?: string | null,
): Promise<AccessState> {
  if (!material.videoRef) return "denied";
  if (material.videoProvider !== "drive") return "granted";
  if (!identity || !driveToken) return "unknown";
  return checkDriveAccess(material.videoRef, driveToken);
}

/**
 * Питає Drive, чи бачить цей токен цей файл.
 *
 * Коди Drive:
 *   200 — бачить;
 *   404 — не бачить (Drive навмисно не зізнається, що файл існує);
 *   401 — токен протух або недійсний — це не «немає доступу», а «увійдіть знову»;
 *   403 — прав бракує (зокрема коли викликають без жодної ідентичності).
 */
async function checkDriveAccess(
  fileId: string,
  token: string,
): Promise<AccessState> {
  const cached = accessCache.get(cacheKey(fileId, token));
  if (cached && cached.until > Date.now()) return cached.state;

  let state: AccessState;
  try {
    const res = await fetch(
      `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?fields=id`,
      {
        headers: { Authorization: `Bearer ${token}` },
        // Drive не має вішати наш API: краще чесне "unknown", ніж запит, що висить.
        signal: AbortSignal.timeout(5000),
      },
    );
    if (res.status === 200) state = "granted";
    else if (res.status === 401) state = "unknown";
    else state = "denied";
  } catch {
    // Мережа впала або таймаут — не стверджуємо, що доступу немає.
    state = "unknown";
  }

  // Кеш на 5 хвилин: екран потоку питає доступ для кожного запису окремо,
  // а їх буває пів десятка — без кешу це стільки ж звернень до Drive щоразу.
  accessCache.set(cacheKey(fileId, token), {
    state,
    until: Date.now() + 5 * 60_000,
  });
  return state;
}

const accessCache = new Map<string, { state: AccessState; until: number }>();

/** Токен у ключ не пишемо: у пам'яті процесу йому робити нічого. */
function cacheKey(fileId: string, token: string): string {
  let hash = 0;
  for (let i = 0; i < token.length; i++) {
    hash = (hash * 31 + token.charCodeAt(i)) | 0;
  }
  return `${fileId}:${hash}`;
}
