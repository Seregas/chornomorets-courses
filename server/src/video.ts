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
