import { OAuth2Client } from "google-auth-library";
import type { Context } from "hono";

/**
 * Ідентичність користувача за Google-входом. deviceId (анонімний) — окремо,
 * це не тут: Google-ідентичність потрібна лише для доступу до відео й адмін-режиму.
 */
export interface Identity {
  email: string;
  sub: string; // Google subject id
}

const ADMIN_EMAILS = new Set(
  (process.env.ADMIN_EMAILS ?? "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean),
);

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const googleClient = GOOGLE_CLIENT_ID
  ? new OAuth2Client(GOOGLE_CLIENT_ID)
  : null;

/**
 * Dev-режим (token === email) відкриває адмінку кожному, хто знає адресу
 * з ADMIN_EMAILS. Поки сервер жив на localhost, це було зручно й безпечно.
 * Тепер він доступний з інтернету — і мовчазне падіння в dev-режим через
 * зниклу змінну оточення стало б дірою, яку ніхто не помітить.
 *
 * Тому вмикати його треба явно: ALLOW_DEV_AUTH=1. Без цього сервер без
 * GOOGLE_CLIENT_ID просто не стартує.
 */
if (!googleClient && process.env.ALLOW_DEV_AUTH !== "1") {
  throw new Error(
    "Не задано GOOGLE_CLIENT_ID. Для локальної розробки без Google додайте " +
      "ALLOW_DEV_AUTH=1 — тоді Authorization: Bearer <email> вважається входом. " +
      "У жодному разі не вмикайте це на сервері, доступному ззовні.",
  );
}

/**
 * Дістає ідентичність із заголовка Authorization: Bearer <token>.
 *
 * Прод-режим (заданий GOOGLE_CLIENT_ID): token — це Google ID-token, перевіряємо підпис.
 * Dev-режим (ALLOW_DEV_AUTH=1 і без GOOGLE_CLIENT_ID): token трактуємо як email
 *   напряму — щоб curl і прототип працювали без реального Google-конфігу.
 */
export async function getIdentity(c: Context): Promise<Identity | null> {
  const header = c.req.header("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  if (!token) return null;

  if (googleClient) {
    try {
      const ticket = await googleClient.verifyIdToken({
        idToken: token,
        audience: GOOGLE_CLIENT_ID,
      });
      const payload = ticket.getPayload();
      if (!payload?.email || !payload.sub) return null;
      return { email: payload.email.toLowerCase(), sub: payload.sub };
    } catch {
      return null;
    }
  }

  // Dev-режим: token === email.
  const email = token.toLowerCase();
  if (!email.includes("@")) return null;
  return { email, sub: `dev:${email}` };
}

export function isAdminEmail(email: string | undefined | null): boolean {
  return email != null && ADMIN_EMAILS.has(email.toLowerCase());
}

export async function getIsAdmin(c: Context): Promise<boolean> {
  const identity = await getIdentity(c);
  return isAdminEmail(identity?.email);
}
