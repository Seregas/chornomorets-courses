# Chornomorets Courses

Застосунок для студентів онлайн-курсів Петра Чорноморця: **бекенд (REST API)** +
**iOS (SwiftUI)**, згодом Android. Монорепо.

Працює наживо: реальний курс «Біохардкор» із записами на Google Drive, збірки їздять
у TestFlight. Публічного релізу в App Store ще не було.

Для роботи над кодом (де що лежить, які інваріанти, як задеплоїти, які граблі вже
знайдені) — `CLAUDE.md`.

## Структура

```
/CLAUDE.md      — як тут працювати: інваріанти, деплой, граблі
/courses-app.md — початкове ТЗ (збережене як є; розходження перелічені в ньому ж)
/server         — Hono + Drizzle API
  /src
    schema.ts        — Drizzle-схема (єдине місце, що знає про таблиці)
    db.ts            — драйвер БД (тут перемикається SQLite → Postgres)
    env.ts           — підвантаження server/.env (імпортується найпершим)
    repository.ts    — CourseRepository (інтерфейс) + реалізація на Drizzle
    types.ts         — API-DTO (форми відповідей)
    video.ts         — playback-дескриптор (замінне джерело відео)
    auth.ts          — Google-ідентичність + admin-allowlist
    routes.ts        — REST-ендпоінти (публічні / особисті / відео / admin)
    telegram.ts      — квитанції в телеграм-чат замість власного сховища файлів
    seed.ts          — демо-наповнення (СПЕРШУ ВИТИРАЄ базу)
    scripts/         — ідемпотентні зміни живої бази (див. нижче)
    index.ts         — bootstrap
/ios            — SwiftUI-застосунок (XcodeGen)
  project.yml        — джерело правди для .xcodeproj
  /Shared            — код, спільний для застосунку й віджета (зріз розкладу)
  /CoursesWidgets    — віджет «найближче заняття»
  /CoursesApp
    App/               — точка входу, DI-контейнер (AppEnvironment), теми, форматування
    Models/            — Codable-моделі API
    Networking/        — APIClient + CourseRepository (protocol) + Remote/Preview + InputModels
    Auth/              — Google-вхід, токен, оновлення протухлого ID-token
    Features/          — Home, Catalog, Schedule, Player, Journal, Settings, Admin
    Services/          — нагадування, прогрес перегляду, аудіо-режим, щоденник практик,
                         розбір квитанцій (Vision), логи на сервер, синк віджета
/design         — мокапи екранів (PNG/SVG) і скриншоти застосунку
```

## Запуск бекенду

```bash
cd server
npm install
cp .env.example .env   # і вписати свої ADMIN_EMAILS / GOOGLE_CLIENT_ID
npm run db:push        # створити таблиці у data.db
npm run seed           # демо-дані. УВАГА: спершу витирає базу — не на живій
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
| `GOOGLE_CLIENT_ID` | якщо задано — `Authorization` перевіряється як Google ID-token | не задано → потрібен `ALLOW_DEV_AUTH=1` |
| `TELEGRAM_BOT_TOKEN` | бот, який складає скріншоти квитанцій у чат | не задано → приймання вимкнене |
| `TELEGRAM_RECEIPTS_CHAT_ID` | чат, куди їх складати | не задано |
| `ALLOW_DEV_AUTH` | `1` дозволяє dev-вхід за email. Лише для локальної розробки | не задано |

**Dev-режим автентифікації:** якщо задано `ALLOW_DEV_AUTH=1` і не задано `GOOGLE_CLIENT_ID`,
заголовок `Authorization: Bearer <email>` трактується як ідентичність — зручно для `curl`
і прототипу. Без жодного з них сервер **не стартує**: мовчазне падіння в dev-режим на
публічному сервері відкрило б адмінку кожному, хто знає адресу з `ADMIN_EMAILS`.

### Скрипти для живої бази

`seed.ts` спершу все витирає, тож для живої бази — окремі ідемпотентні скрипти
в `server/src/scripts/`:

```bash
npx tsx src/scripts/add-biohardcore.ts             # додати реальний курс, не чіпаючи решту
npx tsx src/scripts/add-motivation-base.ts
npx tsx src/scripts/add-laziness.ts
npx tsx src/scripts/add-self-esteem.ts
npx tsx src/scripts/mark-paid.ts <email> <stream-id> [статус]
```

`mark-paid.ts` відмічає всі заняття потоку оплаченими для однієї людини — по пошті,
навіть якщо вона ще жодного разу не заходила в застосунок (див. заочні акаунти нижче).

## Ендпоінти

**Читання (відкрите):**
- `GET /health` — `{ ok: true }`
- `GET /courses` — каталог карток (із `nextStream`)
- `GET /courses/:id` — курс + його потоки (зі злитим описом) + матеріали рівня курсу
- `GET /streams/:id` — потік: злитий опис + заняття + матеріали потоку
- `GET /material-types` — каталог типів матеріалів
- `GET /me` — `{ accountId, email, isAdmin }`
- `DELETE /me` — видалити свій акаунт із усім, що на ньому висить (вимога App Store 5.1.1(v))

**Особисте (потрібен вхід, інакше `401`):**

Усе, що належить людині, ходить під Google-токеном — ніяких ідентифікаторів у
запиті. Акаунт сервер бере з токена (`sub`) і сам заводить його при першому вході.

- `GET /schedule` — найближчі заняття підписаних потоків
- `GET /home` — зведення «Моє навчання»: свої курси з прогресом, найближче заняття,
  наступні, домашка з дедлайнами, записи

**Заявки на потік** (заміна Google Forms):
- `GET /streams/:id/application` · `POST /streams/:id/application` `{name, contact, comment?}`
- `GET /admin/applications` — усі нерозглянуті (`new` + `waiting_payment`) з усіх потоків,
  з назвами курсу й потоку; `GET /admin/streams/:id/applications` — по одному потоку
- `POST /admin/applications/:id/status` `{status}`
- статус `enrolled` одразу підписує акаунт на потік — це і є момент, після якого курс
  з'являється в людини на екрані «Навчання»

**Оплата заняття** (на пару «заняття + людина»):
- `GET /sessions/:id/payment` · `POST /sessions/:id/payment` `{amount, receiptURL?, note?}`
- `GET /admin/sessions/:id/payments` · `POST /admin/payments/:id/status` `{status}` —
  `declared | confirmed | free | rejected`
- `POST /admin/sessions/:id/payments/mark` `{email, status?, amount?, note?}` — відмітити
  оплату за людину по **пошті**. Якщо вона ще не входила в застосунок, заводиться заочний
  акаунт `email:…`, і при першому вході все переїде на справжній (`sub`)

**Квитанції:**
- `POST /payments/:id/receipt` (multipart: `image`, `parsed`) — скріншот їде
  в телеграм-чат викладача, у нас лишається лише посилання на нього
- `GET /payments/:id/receipt?token=…` — картинка назад; автору заявки або адміну.
  Токен у query, бо URL віддається `AsyncImage`, а той заголовків не ставить

**Пульс після заняття:**
- `GET /sessions/:id/pulse` · `POST /sessions/:id/pulse` `{rating 1–5, comment?}`
- `GET /admin/sessions/:id/pulses` — зведення (середня, гістограма, коментарі)

**Домашка:**
- `GET /materials/:id/submission` — своя здача (або `null`)
- `POST /materials/:id/submission` `{text}` — здати або переписати свою
- `GET /admin/materials/:id/submissions` — усі здачі (адмін)
- `POST /admin/submissions/:id/feedback` `{feedback}` — відповідь викладача

**Оголошення потоку:**
- `GET /streams/:id/announcements` — стрічка потоку (також потрапляє в `/home`)
- `POST /admin/announcements` `{streamId, text}` · `DELETE /admin/announcements/:id`

**Питання до заняття:**
- `GET /sessions/:id/questions` — список (читання відкрите); `isMine` для своїх,
  `authorEmail` лише адміну
- `POST /sessions/:id/questions` `{text, isAnonymous?}`
- `DELETE /questions/:id` — автор або адмін
- `POST /admin/questions/:id/answered` `{answered}` — позначити розібраним

**Підписки:**
- `GET /subscriptions`
- `POST /subscriptions` `{streamId}` · `DELETE /subscriptions` `{streamId}`

**Логи з телефонів** — єдине місце, де лишився `deviceId`: вони пишуться ще до входу
й саме тоді, коли ламається вхід.
- `POST /logs` `{deviceId, appVersion?, event, detail?}` (відкрито на запис) ·
  `GET /admin/logs`

**Відео:**
- `GET /video/:materialId/playback` — типізований дескриптор `direct | youtube | google-drive`.
  Потрібен вхід (`401` без нього): сире джерело (`videoRef`) не має розсипатися з
  відкритого API. Чи відкриється файл — вирішує сам Drive

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
- **Доступ до записів** — не наша відповідальність: викладач ділиться файлом на Drive із
  Google-акаунтом студента, Drive і вирішує. Ми навмисно не просимо scope `drive.readonly`:
  він відкриває весь диск людини, а дає лише бейдж-замочок — і при цьому як restricted scope
  вимагає щорічного зовнішнього аудиту для публікації. Вхід просить тільки пошту й ім'я.
- **Identity** — усе особисте висить на Google-акаунті: ключ `accounts.id` = `sub` із
  токена (номер акаунта, який Google видає раз і назавжди), пошта лежить поруч і
  оновлюється при кожному вході. Раніше цю роль грав `deviceId` — і зміна телефона
  стирала людині підписки, домашки й оплати. Пошта ключем бути не може: її змінюють.
  ID-token живе годину, тож застосунок мовчки оновлює його й повторює запит на `401`.

## Модель даних (стисло)

`Course` (вічний опис) → `Stream` (потік/cohort; може перевизначати опис) → `Session` (заняття).
`Material` (вміст вирішує поведінку: текст / відео / лінк / дедлайн; `typeId` — косметичний ярлик
з керованого каталогу `MaterialType`, може бути порожнім). Власник матеріалу — `course`,
`stream` або `session`: запис і домашка належать конкретній зустрічі, а дошка й реквізити — потоку.
`Account` = Google-користувач (`sub` як ключ, пошта поруч) — до нього прив'язане все особисте.
`Enrollment` = підписка `accountId`↔`streamId`.
`Question` = питання до заняття (акаунт автора, прапорець анонімності; пошту віддаємо лише адміну).
`Announcement` = оголошення викладача на потік. `Submission` = здана домашка (одна на матеріал+акаунт). `Pulse` = оцінка заняття 1–5. `Payment` = оплата пари «заняття + людина» (сума, квитанція, підтвердження). `Application` = заявка на потік (одна на потік+акаунт).

## iOS-застосунок

Екрани: **Навчання** (стартовий: найближче заняття з кнопкою «Приєднатися», домашка з
дедлайнами, записи), **Розклад**, **Каталог** (курси → курс → потік), **Налаштування**.
Плеєр під кожен тип джерела: `AVPlayer` для `direct` (продовжує з місця зупинки, грає
у фоні як подкаст, 0.75×–2×, керування з локскріна), `WKWebView` для YouTube,
`SFSafariViewController` для Drive — він ділить сесію з Safari, тож людина вже
залогінена в Google і нічого не вводить повторно.
Локальні нагадування про заняття звіряються з розкладом при кожному завантаженні.
Останні успішні GET-и кешуються на диск: без мережі застосунок показує збережені дані
й банер «дані від …».

**Віджет** «найближче заняття» (`/ios/CoursesWidgets`) читає готовий зріз розкладу з
App Group `group.com.chornomorets.courses` — застосунок кладе його при кожному оновленні
розкладу, тож віджет не ходить у мережу й малюється миттєво.

**Щоденник практик** (`Features/Journal`) — чек-ін енергії 1–5 і власні нотатки —
живе ТІЛЬКИ на пристрої (файл у Documents, `.completeFileProtection`). Це домашка
на кшталт «занотуйте, коли накриває»: записи бувають надто особистими, щоб їх
бачив сервер чи викладач. Дизайн і скриншоти — у `/design`.

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

### TestFlight

`ios/scripts/testflight.sh` збирає архів і вивантажує його.

Перед першим запуском треба **увійти в Xcode → Settings → Accounts** акаунтом із
доступом до команди. Це не формальність: без облікового запису Xcode не випустить
distribution-профіль (`exportArchive: No profiles for '…' were found`), а кешований
wildcard-профіль не несе App Group і підпис падає на entitlement. З акаунтом Xcode
реєструє App ID для застосунку й віджета та саму App Group автоматично.

Ще потрібен запис застосунку в App Store Connect із bundle ID `com.chornomorets.courses`.
Для автоматичного вивантаження — App Store Connect API-ключ (`.p8` у
`~/.appstoreconnect/private_keys/`); він вимагає ролі Admin, тож за його відсутності
скрипт піде на Apple ID із паролем застосунку або лишить `.ipa` для Transporter.

```bash
cd ios
TEAM_ID=XXXXXXXXXX API_BASE_URL=https://ваш-домен \
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-… \
./scripts/testflight.sh
```

Адреса API вшивається в збірку зі змінної `API_BASE_URL` (Debug — `http://localhost:3000`).
**Без публічного бекенда тестова збірка марна**: на чужому телефоні застосунок покаже
порожні екрани й банер «немає звʼязку».

### Налаштування застосунку

- **Адреса API** — у порядку пріоритету: `UserDefaults`-ключ `api_base_url` (поле в
  Налаштуваннях) → `APIBaseURL` з Info.plist (вшивається зі змінної збірки `API_BASE_URL`)
  → `http://localhost:3000`. На фізичному пристрої в тій самій мережі досить вписати
  LAN-IP Mac: http до локальної мережі дозволено через `NSAllowsLocalNetworking`.
- **Google-вхід** — `GIDClientID` в `project.yml` (+ reversed client ID у `CFBundleURLTypes`).
  Той самий client ID має стояти в `GOOGLE_CLIENT_ID` на бекенді. Якщо client ID не підставлений,
  застосунок автоматично показує **dev-вхід через email** — зручно для розробки без Google Cloud.
  Просимо лише пошту й ім'я: жодних scope до Drive (чому — у `CLAUDE.md`).
- **Env для демо/скриншотів:** `START_TAB=0|1|2|3`, `SKIP_NOTIF_PROMPT=1`, `OPEN_COURSE=<id>`,
  `OPEN_STREAM=<id>`, `OPEN_SESSION=<id>`, `OPEN_MATERIAL=<id>`, `OPEN_QUESTIONS=<id>`,
  `OPEN_PULSE=<id>`, `OPEN_JOURNAL=1`. Через `xcrun simctl launch` — із префіксом
  `SIMCTL_CHILD_`, інакше не доходять.

## Статус і що далі

Бекенд і iOS-застосунок робочі та перевірені наживо, зокрема на реальному курсі
«Біохардкор» із десятьма записами на Google Drive. Збірки їздять у TestFlight.

**Блокер публікації в App Store — один:**

- **Sign in with Apple.** За guideline 4.8 обовʼязковий: Google-вхід створює основний
  акаунт застосунку, а жоден із винятків (власна система входу, корпоративні акаунти,
  державний eID, клієнт конкретного сервісу) сюди не підходить. Для TestFlight це не
  блокер. Вхід через Apple має заводити той самий запис в `accounts`; складність у тім,
  що Apple може віддати relay-пошту, якою запис на Drive не пошариш — тобто Google
  все одно доведеться підключати окремо, для доступу до відео.
  Видалення акаунта (5.1.1(v)) уже є.

**Далі за пріоритетом:**

- **Телеграм-сповіщення** про нові заявки (і квитанції) — чекає на токен бота й chat_id.
- **Транскрипти записів** — пошук по сказаному й автоконспект (потрібне рішення щодо
  ASR-сервісу й бюджету).
- **Live Activity** «почнеться за 10 хв» на локскріні та в Dynamic Island.
- Полірування UI (бейджі в рядку розкладу переносяться).
- Android — нативний застосунок на Kotlin/Compose поверх того самого бекенду.

**Перевірено на пристрої (17 серп. 2026):** екран згоди Google просить лише пошту й
ім'я. У консолі `drive.readonly` прописаний не був — SDK просив його прямо з застосунку,
тож зі збіркою 17 він зник сам, і прибирати в Google Cloud Console нічого не треба.
