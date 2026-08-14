import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import { schema } from "./schema.js";

/**
 * Єдина точка створення з'єднання з БД. Щоб перемкнути SQLite → Postgres:
 * міняємо тут драйвер (напр. drizzle-orm/node-postgres) і dialect у schema/конфізі.
 * Прикладний код (repository/routes) лишається без змін.
 */
const dbFile = process.env.DATABASE_URL ?? "./data.db";

const sqlite = new Database(dbFile);
sqlite.pragma("journal_mode = WAL");
sqlite.pragma("foreign_keys = ON");

export const db = drizzle(sqlite, { schema });
export type DB = typeof db;
