# Chornomorets Courses

Прототип застосунку для студентів онлайн-курсів: **бекенд (REST API)** + **iOS (SwiftUI)**, згодом Android.
Монорепо. Фаза 1 — happy-path і чистий UI для демонстрації.

## Структура

```
/server      — Hono + Drizzle API (готово)
  /src
    schema.ts        — Drizzle-схема (єдине місце, що знає про таблиці)
    db.ts            — драйвер БД (тут перемикається SQLite → Postgres)
    repository.ts    — CourseRepository (інтерфейс) + реалізація на Drizzle
    types.ts         — API-DTO (форми відповідей)
    video.ts         — playback-дескриптор + перевірка доступу (замінне джерело відео)
    auth.ts          — Google-ідентичність + admin-allowlist
    routes.ts        — REST-ендпоінти (read / підписки / відео / admin)
    seed.ts          — демо-наповнення
    index.ts         — bootstrap
/ios         — SwiftUI-застосунок (далі)
/design      — мокапи екранів (PNG/SVG)
```

## Запуск бекенду

```bash
cd server
npm install
npm run db:push        # створити таблиці у data.db
npm run seed           # демо-дані (deviceId=demo-device має підписки)
ADMIN_EMAILS="you@gmail.com" npm run dev   # старт на http://localhost:3000
```

### Змінні середовища
| Змінна | Призначення | За замовчуванням |
|---|---|---|
| `PORT` | порт API | `3000` |
| `DATABASE_URL` | шлях до SQLite-файлу | `./data.db` |
| `ADMIN_EMAILS` | список admin-акаунтів через кому | порожньо (адмін недоступний) |
| `GOOGLE_CLIENT_ID` | якщо задано — `Authorization` перевіряється як Google ID-token | не задано → **dev-режим** |

**Dev-режим автентифікації:** поки `GOOGLE_CLIENT_ID` не заданий, заголовок
`Authorization: Bearer <email>` трактується як ідентичність — зручно для `curl` і прототипу.
У проді задаєте `GOOGLE_CLIENT_ID`, і той самий код починає перевіряти справжній токен.

## Ендпоінти

**Читання (відкрите):**
- `GET /courses` — каталог карток (із `nextStream`)
- `GET /courses/:id` — курс + його потоки (зі злитим описом) + матеріали рівня курсу
- `GET /streams/:id` — потік: злитий опис + заняття + матеріали потоку
- `GET /schedule?deviceId=…` — найближчі заняття підписаних потоків
- `GET /material-types` — каталог типів матеріалів
- `GET /me?deviceId=…` — `{ deviceId, email, isAdmin }`

**Підписки (deviceId):**
- `GET /subscriptions?deviceId=…`
- `POST /subscriptions` `{deviceId, streamId}` · `DELETE /subscriptions` `{deviceId, streamId}`

**Відео:**
- `GET /video/:materialId/playback` — типізований дескриптор `direct | youtube | google-drive`; `403` якщо немає доступу
- `GET /video/:materialId/access` — `{ access: granted|denied|unknown, provider }`

**Адмін (потрібен admin Google-акаунт):** CRUD під
`/admin/courses`, `/admin/streams`, `/admin/sessions`, `/admin/materials`, `/admin/material-types`.

## Архітектурні шви (де що перемикати)

- **Джерело даних** — лише через `CourseRepository` (`repository.ts`). Щоб замінити SQLite
  на Postgres/файли/зовнішнє API: нова реалізація інтерфейсу + драйвер у `db.ts`. Роути не чіпаються.
- **Джерело відео** — лише через `video.ts`. Бекенд віддає playback-дескриптор; застосунок має
  хендлер під кожен тип. Додати R2/S3/HLS = новий тип тут + хендлер у застосунку.
- **Identity** — анонімний `deviceId` для підписок; Google-вхід окремо, лише для доступу до відео
  й адмін-режиму. Заміна `deviceId` на реального користувача не зачіпає моделі.

## Модель даних (стисло)

`Course` (вічний опис) → `Stream` (потік/cohort; може перевизначати опис) → `Session` (заняття).
`Material` (вміст вирішує поведінку: текст / відео / лінк / дедлайн; `typeId` — косметичний ярлик
з керованого каталогу `MaterialType`, може бути порожнім). `Enrollment` = підписка `deviceId`↔`streamId`.

## iOS — далі

Наступний крок: моделі (Codable) → APIClient/`CourseRepository` (protocol) → каталог → курс/потік →
розклад → плеєр з access-станами → Google OAuth (нативний `ASWebAuthenticationSession`) →
локальні нагадування → адмін-режим. Дизайн — у `/design`.
