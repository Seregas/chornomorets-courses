import { defineConfig } from "drizzle-kit";

// Прототип: файлова SQLite. Щоб перемкнути БД (Postgres тощо) —
// міняємо dialect + dbCredentials тут і драйвер у src/db.ts.
export default defineConfig({
  schema: "./src/schema.ts",
  out: "./drizzle",
  dialect: "sqlite",
  dbCredentials: {
    url: process.env.DATABASE_URL ?? "./data.db",
  },
});
