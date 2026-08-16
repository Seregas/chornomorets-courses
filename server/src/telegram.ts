/**
 * Телеграм як сховище квитанцій.
 *
 * Замість того щоб піднімати S3 заради кількох скріншотів на місяць,
 * пересилаємо їх у приватний чат викладача. Плюси очевидні: файли зберігає
 * Телеграм, заявка одразу видно там, де її й звіряють із випискою, а нам не
 * треба ні сховища, ні бекапів, ні окремих прав доступу.
 *
 * Потрібні дві змінні: TELEGRAM_BOT_TOKEN і TELEGRAM_RECEIPTS_CHAT_ID.
 * Без них приймання скріншотів просто вимкнене — решта застосунку працює.
 */

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const CHAT_ID = process.env.TELEGRAM_RECEIPTS_CHAT_ID;

export const telegramConfigured = Boolean(TOKEN && CHAT_ID);

export interface StoredReceipt {
  fileId: string;
  chatId: string;
  messageId: number;
}

/** Надсилає скріншот у чат і повертає ідентифікатори, щоб потім його показати. */
export async function sendReceipt(
  image: Blob,
  caption: string,
): Promise<StoredReceipt> {
  if (!TOKEN || !CHAT_ID) throw new Error("телеграм не налаштований");

  const form = new FormData();
  form.append("chat_id", CHAT_ID);
  form.append("caption", caption.slice(0, 1000));
  // Саме document, а не photo: фото Телеграм стискає, а на квитанції важливі
  // дрібні цифри — після стиснення їх не завжди видно.
  form.append("document", image, "receipt.jpg");

  const res = await fetch(`https://api.telegram.org/bot${TOKEN}/sendDocument`, {
    method: "POST",
    body: form,
    signal: AbortSignal.timeout(30_000),
  });
  const json = (await res.json()) as {
    ok: boolean;
    description?: string;
    result?: { message_id: number; document?: { file_id: string } };
  };
  if (!json.ok || !json.result?.document?.file_id) {
    throw new Error(`телеграм відмовив: ${json.description ?? res.status}`);
  }
  return {
    fileId: json.result.document.file_id,
    chatId: CHAT_ID,
    messageId: json.result.message_id,
  };
}

/** Тягне файл назад — щоб показати квитанцію в застосунку. */
export async function fetchReceipt(fileId: string): Promise<Response> {
  if (!TOKEN) throw new Error("телеграм не налаштований");

  const meta = await fetch(
    `https://api.telegram.org/bot${TOKEN}/getFile?file_id=${encodeURIComponent(fileId)}`,
    { signal: AbortSignal.timeout(15_000) },
  );
  const json = (await meta.json()) as {
    ok: boolean;
    result?: { file_path: string };
  };
  if (!json.ok || !json.result?.file_path) throw new Error("файл не знайдено");

  return fetch(
    `https://api.telegram.org/file/bot${TOKEN}/${json.result.file_path}`,
    { signal: AbortSignal.timeout(30_000) },
  );
}
