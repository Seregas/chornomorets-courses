# Chornomorets Courses

Прототип застосунку для студентів онлайн-курсів: **бекенд (REST API)** + **iOS (SwiftUI)**, згодом Android.
Монорепо. Фаза 1 — happy-path і чистий UI для демонстрації.

## Структура

```
/courses-app.md — специфікація прототипу
/server         — Hono + Drizzle API
  /src
    schema.ts        — Drizzle-схема (єдине місце, що знає про таблиці)
    db.ts            — драйвер БД (тут перемикається SQLite → Postgres)
    env.ts           — підвантаження server/.env (імпортується найпершим)
    repository.ts    — CourseRepository (інтерфейс) + реалізація на Drizzle
    types.ts         — API-DTO (форми відповідей)
    video.ts         — playback-дескриптор + перевірка доступу (замінне джерело відео)
    auth.ts          — Google-ідентичність + admin-allowlist
    routes.ts        — REST-ендпоінти (read / підписки / відео / admin)
    seed.ts          — демо-наповнення
    index.ts         — bootstrap
/ios            — SwiftUI-застосунок (XcodeGen)
  project.yml        — джерело правди для .xcodeproj
  /CoursesApp
    App/               — точка входу, DI-контейнер (AppEnvironment), теми, форматування
    Models/            — Codable-моделі API
    Networking/        — APIClient + CourseRepository (protocol) + Remote/Preview + InputModels
    Auth/              — deviceId, AuthTokenStore, GoogleSignIn
    Features/          — Catalog, Schedule, Player, Settings, Admin
    Services/          — локальні нагадування, заглушка завантажень
/design         — мокапи екранів (PNG/SVG) і скриншоти застосунку
```

## Запуск бекенду

```bash
cd server
npm install
cp .env.example .env   # і вписати свої ADMIN_EMAILS / GOOGLE_CLIENT_ID
npm run db:push        # створити таблиці у data.db
npm run seed           # демо-дані (deviceId=demo-device має підписки)
npm run dev            # старт на http://localhost:3000
```

`server/.env` підвантажується автоматично (`src/env.ts`) і не комітиться; будь-яку змінну
можна натомість передати через оточення. Перевірка типів — `npm run typecheck`.

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
- `GET /health` — `{ ok: true }`
- `GET /courses` — каталог карток (із `nextStream`)
- `GET /courses/:id` — курс + його потоки (зі злитим описом) + матеріали рівня курсу
- `GET /streams/:id` — потік: злитий опис + заняття + матеріали потоку
- `GET /schedule?deviceId=…` — найближчі заняття підписаних потоків
- `GET /home?deviceId=…` — зведення «Моє навчання»: найближче заняття, наступні, домашка з дедлайнами, записи
- `GET /material-types` — каталог типів матеріалів
- `GET /me?deviceId=…` — `{ deviceId, email, isAdmin }`

**Підписки (deviceId):**
- `GET /subscriptions?deviceId=…`
- `POST /subscriptions` `{deviceId, streamId}` · `DELETE /subscriptions` `{deviceId, streamId}`

**Відео:**
- `GET /video/:materialId/playback` — типізований дескриптор `direct | youtube | google-drive`; `403` якщо немає доступу
- `GET /video/:materialId/access` — `{ access: granted|denied|unknown, provider }`

**Адмін (потрібен admin Google-акаунт):** `POST` / `PUT :id` / `DELETE :id` під
`/admin/courses`, `/admin/streams`, `/admin/sessions`, `/admin/materials`, `/admin/material-types`.
Плюс:
- `GET /admin/materials/:id` — сирий матеріал (із `videoRef`) для префілу форм редагування;
- `POST /admin/streams/:id/clone` `{title, startDate}` — копія потоку зі зсувом розкладу
  (записи не копіюються, решта матеріалів — так);
- `POST /admin/sessions/batch` `{streamId, titlePrefix, startAt, count, intervalDays, durationMinutes}`
  — серія занять одним запитом.
`GET /streams/:id` віддає поряд зі злитим описом ще й сирі `*Override`-поля (`null` = успадковано),
щоб адмін-форма показувала, що успадковано, а що перевизначено.

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

## iOS-застосунок

Екрани: **Навчання** (стартовий: найближче заняття з кнопкою «Приєднатися», домашка з
дедлайнами, записи), **Розклад**, **Каталог** (курси → курс → потік), **Налаштування**.
Плеєр: `AVPlayer` для `direct`, `WKWebView` для `youtube` й `google-drive` — продовжує
з місця зупинки, грає у фоні як подкаст, зі швидкістю 0.75×–2× і керуванням з локскріна.
Локальні нагадування про заняття звіряються з розкладом при кожному завантаженні.
Дизайн і скриншоти — у `/design`.

**Адмінка живе всередині застосунку, інлайн** — окремого вебу немає. Адмінам (за
`ADMIN_EMAILS` на бекенді) прямо на сторінках зʼявляються кнопки: додати/редагувати/видалити
курс, потік, заняття, матеріал. Форми — `Features/Admin/AdminForms.swift`.
Типи матеріалів — окремий список у Налаштуваннях, бо це глобальний каталог.

### Збірка

Проєкт генерується XcodeGen — `project.yml` є джерелом правди, а `.xcodeproj` похідний.

```bash
brew install xcodegen
cd ios
xcodegen generate      # ПОВТОРЮВАТИ після додавання нових .swift-файлів
open CoursesApp.xcodeproj
```

Залежність одна — GoogleSignIn-iOS (через SPM). Deployment target — iOS 17.
Для симулятора підпис не потрібен; для пристрою — `DEVELOPMENT_TEAM=XXXX xcodegen generate`
або вибір команди в Xcode.

### Налаштування застосунку

- **Адреса API** — `UserDefaults`-ключ `api_base_url`; дефолт `http://localhost:3000`.
  На фізичному пристрої треба вписати LAN-IP Mac (http дозволено через `NSAppTransportSecurity`
  — перед релізом прибрати).
- **Google-вхід** — `GIDClientID` в `project.yml` (+ reversed client ID у `CFBundleURLTypes`).
  Той самий client ID має стояти в `GOOGLE_CLIENT_ID` на бекенді. Якщо client ID не підставлений,
  застосунок автоматично показує **dev-вхід через email** — зручно для прототипу без Google Cloud.
- **Env для демо/скриншотів:** `START_TAB=0|1|2`, `SKIP_NOTIF_PROMPT=1`,
  `OPEN_COURSE=<id>`, `OPEN_STREAM=<id>`.

## Статус і що далі

Бекенд і iOS-застосунок робочі та перевірені наживо (симулятор проти локального сервера).
Лишилось:

- **Стрімінг захищеного Drive-відео** — зараз плеєр відкриває `drive.google.com/.../preview`
  у `WKWebView` без токена; потрібен `AVURLAsset` із заголовком або `SFSafariViewController`.
- **Справжня перевірка доступу до Drive** — `video.ts` поки повертає `granted` оптимістично,
  без виклику Drive API.
- Полірування UI (бейджі в рядку розкладу переносяться).
- Android — нативний застосунок на Kotlin/Compose поверх того самого бекенду.
