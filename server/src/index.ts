import "./env.js"; // має бути першим: завантажує .env до читання змінних
import { serve } from "@hono/node-server";
import { app } from "./routes.js";

const port = Number(process.env.PORT ?? 3000);

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`API запущено на http://localhost:${info.port}`);
  if (!process.env.GOOGLE_CLIENT_ID) {
    console.log(
      "  [dev] GOOGLE_CLIENT_ID не задано — Authorization: Bearer <email> трактується як ідентичність.",
    );
  }
  if (!process.env.ADMIN_EMAILS) {
    console.log("  [dev] ADMIN_EMAILS не задано — адмін-ендпоінти недоступні нікому.");
  }
});
