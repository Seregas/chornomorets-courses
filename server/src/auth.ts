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
 * Дістає ідентичність із заголовка Authorization: Bearer <token>.
 *
 * Прод-режим (заданий GOOGLE_CLIENT_ID): token — це Google ID-token, перевіряємо підпис.
 * Dev-режим (без GOOGLE_CLIENT_ID): token трактуємо як email напряму — щоб
 *   прототип і curl працювали без реального Google-конфігу. Замінюється на прод
 *   просто заданням env GOOGLE_CLIENT_ID.
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
