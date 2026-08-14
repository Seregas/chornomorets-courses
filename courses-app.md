# Запит до Claude Code: застосунок для керування онлайн-курсами (прототип)

> **Це початкове ТЗ, збережене як є.** Частину рішень ми свідомо змінили під час роботи —
> актуальний стан описує `README.md`. Що розійшлося з цим документом:
>
> - **Зʼявились потоки (cohorts).** `Course` — вічний шаблон; `Stream` — конкретний запуск зі
>   своїми датами, ціною й Telegram, і може перевизначати опис курсу. `Session` належить потоку,
>   підписка — теж на потік, а не на курс.
> - **Тип матеріалу став косметичним.** Поведінку визначає вміст (текст / відео / лінк / дедлайн),
>   а `MaterialType` — керований у застосунку каталог ярликів замість enum `video/resource/about`.
> - **Зʼявився Google-вхід** (GoogleSignIn SDK) — потрібен для доступу до відео й адмінки.
>   Анонімний `deviceId` лишився й далі відповідає за підписки.
> - **Відео не проксіюється бекендом.** Замість playback-URL бекенд віддає типізований дескриптор
>   (`direct | youtube | google-drive`), а доступ до Drive персональний — по Google-акаунту
>   в шарінгу; застосунок має хендлер під кожен тип. Принцип «джерело відео замінне» збережено.
> - **Додалася адмінка** — інлайн усередині iOS-застосунку (не веб), гейт по allowlist
>   Google-акаунтів у `ADMIN_EMAILS`.

## Мета
Зробити **демонстрований прототип** iOS-застосунку для студентів, які проходять онлайн-курси.
Прототип треба буде показувати, тому пріоритет — робочий happy-path і чистий UI, а не повнота фіч.
Це монорепо: **бекенд (REST API)** + **iOS-застосунок (SwiftUI)**.

Працюємо лише з **онлайн-групами** (офлайн-формат закладаємо в модель даних, але UI під нього зараз не робимо).

## Головні архітектурні принципи (дотримуватись неухильно)
1. **Джерело даних — замінне.** Застосунок ходить ТІЛЬКИ у власний REST API, ніколи напряму в БД, Google Drive чи Google Sheets. На бекенді доступ до даних схований за репозиторій-інтерфейсом, щоб БД можна було замінити (SQLite зараз → Postgres / файли / зовнішнє джерело пізніше) без зміни ендпоінтів.
2. **Джерело відео — замінне.** Застосунок не знає, що відео лежить у Google Drive. Він просить у бекенду playback-URL і отримує проксі/підписане посилання. Сьогодні за ним Drive, завтра — R2/S3/HLS; застосунок не змінюється.
3. **Без авторизації (MVP), але identity-ready.** Логіну немає. Підписки, статус оплати й офлайн-оренда прив'язуються до анонімного `deviceId` (генерується й зберігається на пристрої). Пізніше `deviceId` замінюється на реального користувача без переробки моделей.
4. **Фазовість.** Спочатку Фаза 1, далі дрібними кроками. Не реалізовувати Фазу 2/3 поки не готова Фаза 1.

## Стек
**Бекенд:** TypeScript, **Hono** (роутер; працює і на Node, і пізніше на Cloudflare Workers), **Drizzle ORM** з діалектом **SQLite** (файлова БД для прототипу; Drizzle дозволяє перемкнути на Postgres мінімальними змінами). Локальний запуск через Node.
**iOS:** Swift, **SwiftUI**, iOS 17+, `@Observable` (Observation framework), архітектура MVVM. Без сторонніх залежностей, де це розумно (нативні `URLSession`, `AVKit`, `UserNotifications`).

## Структура репозиторію
```
/server      — Hono + Drizzle API
  /src
    schema.ts        — Drizzle-схема
    repository.ts     — інтерфейс CourseRepository + реалізація на Drizzle
    routes.ts         — REST-ендпоінти
    seed.ts           — наповнення БД seed-даними (нижче)
    video.ts          — проксі playback-URL (Фаза 1: редірект/проксі на Drive)
    index.ts          — bootstrap
/ios         — SwiftUI-застосунок
  /Models           — Codable-моделі (Course, Session, Material, ...)
  /Networking       — APIClient + CourseRepository (protocol) + RemoteCourseRepository
  /Features
    /Schedule       — екран розкладу
    /Catalog        — каталог курсів + деталі курсу
    /Player         — відеоплеєр
    /Settings       — підписки, завантаження, нотифікації
  /Services         — NotificationScheduler, DownloadManager (заглушка під Фазу 2)
README.md    — як запускати обидві частини
```

## Модель даних
- **Course**: `id`, `title`, `summary`, `description`, `program` (optional), `format` (`online`/`offline`/`hybrid`), `telegramGroupURL` (optional), `priceFull` (optional), `pricePerSession` (optional), `coverImageURL` (optional).
- **Session** (заняття): `id`, `courseId`, `title`, `startAt` (ISO 8601 UTC), `durationMinutes`, `format`, `joinURL` (для онлайн), `paymentStatus` (`unpaid`/`paid`/`free`), `order`.
- **Material**: `id`, `courseId`, `type` (`video`/`resource`/`about`), `title`, `description` (optional), `order`, і залежно від типу:
  - `video`: `videoId` (внутрішній id для запиту playback-URL — НЕ сирий Drive-лінк), `durationMinutes` (optional).
  - `resource`: `url` (Miro, документ тощо).
  - `about`: текст у `description` (опис/програма).
- **Subscription** (локально на пристрої для MVP): `courseId`, `subscribedAt`. Дублюється на бекенді з прив'язкою до `deviceId` через ендпоінти нижче.

## REST API (бекенд)
- `GET /courses` — список курсів (короткі картки).
- `GET /courses/:id` — повна картка: курс + sessions + materials.
- `GET /schedule?deviceId=...` — найближчі sessions по підписаних курсах, відсортовані за `startAt`.
- `GET /subscriptions?deviceId=...`
- `POST /subscriptions` `{deviceId, courseId}` / `DELETE /subscriptions` `{deviceId, courseId}`
- `GET /video/:videoId/playback?deviceId=...` — повертає playback-URL.
  - **Фаза 1:** бекенд проксіює потік із Google Drive з підтримкою HTTP Range (щоб `AVPlayer` міг перемотувати), або повертає короткоживучий підписаний URL. Drive-конфіг (file id / credentials) тримається на бекенді й застосунку не видний.
- (Фаза 3) `GET/POST` під оплату — поки заглушки, що повертають `paymentStatus`.

Усі дані БД — лише через `CourseRepository`-інтерфейс. `routes.ts` не звертається до Drizzle напряму.

## iOS — екрани (Tab Bar)
1. **Розклад** — агенда найближчих занять по підписаних курсах (дата, час, назва курсу, бейдж формату й статусу оплати, кнопка «Приєднатися» для онлайн із `joinURL`).
2. **Курси** — каталог карток. Деталь курсу:
   - опис + програма (`about`-матеріали),
   - перемикач «Підписатися/Відписатися»,
   - список занять зі статусом оплати,
   - матеріали: відео (відкривають плеєр), ресурси (відкривають `url`), посилання на Telegram-групу.
3. **Налаштування** — мої підписки, (Фаза 2) завантажені відео та їх термін, тумблер нагадувань.

Шар мережі: `CourseRepository` (protocol) + `RemoteCourseRepository` (б'є API). ViewModels залежать від протоколу, не від конкретної реалізації, щоб легко підкласти мок/прев'ю-дані.

## Нагадування
`NotificationScheduler` на `UserNotifications`: при підписці на курс планує **локальні** нотифікації за N хвилин до кожного `startAt` майбутніх занять (N — налаштовуване, дефолт 30 хв). Працює офлайн, без push-сервера. При відписці — знімає заплановані нотифікації курсу.

## Відео — фазовий план
- **Фаза 1 (зараз): стрімінг.** Плеєр (`AVPlayer`) грає playback-URL, отриманий від `GET /video/:videoId/playback`. Жодних прямих Drive-лінків у застосунку.
- **Фаза 2 (потім): офлайн з орендою.** `DownloadManager` качає потік у sandbox, шифрує (AES-GCM, ключ у Keychain), грає через `AVAssetResourceLoaderDelegate` з дешифруванням на льоту. Бекенд видає `expiresAt` (lease TTL, дефолт 14 днів); після спливання — онлайн-перевалідація або видалення файлу. М'який захист: файли поза Files-доступом + детект запису екрана (`UIScreen.isCaptured` / `capturedDidChangeNotification`) із затемненням плеєра. (Закласти інтерфейс зараз, реалізувати окремим кроком.)
- **Фаза 3 (опційно): FairPlay** для жорсткого DRM — потребує HLS-хостингу й ліцензійного сервера; робиться заміною video-джерела без зміни верхніх шарів застосунку.

## Seed-дані (курси Петра Чорноморця)
Реальні курси/формати (онлайн). Дати онлайн-занять — ілюстративні плейсхолдери для прототипу. Telegram-група: `https://t.me/petro_chornomorets`. Реєстрація історично через Google Forms (можна як `resource`-матеріал). Відео-матеріали — плейсхолдери з `videoId`, бекенд мапить їх на тестовий Drive-файл.

```json
[
  {
    "title": "Стрес, втома і піклування про себе",
    "format": "online",
    "summary": "Міні-курс на 3 заняття про ефективні тактики й стратегії життя замість звикання до стресу.",
    "program": "1) Як не заїдати емоції; 2) Що робити, якщо «подихати» не допомагає; 3) Стресостійкість і відновлення.",
    "telegramGroupURL": "https://t.me/petro_chornomorets",
    "sessions": [
      {"title": "Заняття 1", "startAt": "2026-07-08T17:00:00Z", "durationMinutes": 120, "format": "online", "paymentStatus": "unpaid", "order": 1},
      {"title": "Заняття 2", "startAt": "2026-07-15T17:00:00Z", "durationMinutes": 120, "format": "online", "paymentStatus": "unpaid", "order": 2},
      {"title": "Заняття 3", "startAt": "2026-07-22T17:00:00Z", "durationMinutes": 120, "format": "online", "paymentStatus": "unpaid", "order": 3}
    ],
    "materials": [
      {"type": "about", "title": "Про курс", "description": "Неможливо погано жити і добре почуватися. Розбираємо стрес, втому й піклування про себе з біологічної точки зору.", "order": 1},
      {"type": "resource", "title": "Реєстрація (анкета)", "url": "https://forms.gle/J2ASG5UWBj4hh3py8", "order": 2},
      {"type": "video", "title": "Запис заняття 1", "videoId": "stress-1", "order": 3}
    ]
  },
  {
    "title": "Самооцінка",
    "format": "online",
    "summary": "Міні-курс на 2 заняття про самооцінку, самоцінність і те, як її підвищити.",
    "program": "1) Чому хвалити й сварити однаково непродуктивно; 2) Різниця між заниженою самооцінкою та недостатньою самоцінністю.",
    "telegramGroupURL": "https://t.me/petro_chornomorets",
    "sessions": [
      {"title": "Заняття 1", "startAt": "2026-07-10T17:00:00Z", "durationMinutes": 120, "format": "online", "paymentStatus": "unpaid", "order": 1},
      {"title": "Заняття 2", "startAt": "2026-07-17T17:00:00Z", "durationMinutes": 120, "format": "online", "paymentStatus": "unpaid", "order": 2}
    ],
    "materials": [
      {"type": "about", "title": "Про курс", "description": "Чому найкраща самооцінка не в тих, хто найбільше досягає? І як її собі підвищити.", "order": 1},
      {"type": "resource", "title": "Реєстрація (анкета)", "url": "https://forms.gle/jJgT8Wa7sm1TtvR56", "order": 2}
    ]
  },
  {
    "title": "Гра «Вигорання»",
    "format": "online",
    "summary": "Гра-симуляція на 1 день про ліміти, відпочинок і вихід із петлі робота–дім–робота.",
    "program": "Одноденний інтенсив 12:00–20:00: переосмислення власних лімітів і тактик відпочинку.",
    "telegramGroupURL": "https://t.me/petro_chornomorets",
    "sessions": [
      {"title": "Гра (онлайн, цілий день)", "startAt": "2026-07-26T09:00:00Z", "durationMinutes": 480, "format": "online", "paymentStatus": "unpaid", "order": 1}
    ],
    "materials": [
      {"type": "about", "title": "Про гру", "description": "Гра дозволяє подивитися на власні ліміти інакше й почати діяти й не-діяти краще.", "order": 1},
      {"type": "resource", "title": "Реєстрація (анкета)", "url": "https://forms.gle/V6UuTdj99whwyWzd6", "order": 2}
    ]
  },
  {
    "title": "Мотивація та фундамент психіки",
    "format": "online",
    "summary": "Курс про натхнення, мотивацію, стрес і щастя — на рівні біохімії та системного підходу.",
    "program": "Базові принципи роботи системи мотивації; індивідуальний підхід до власних станів.",
    "telegramGroupURL": "https://t.me/petro_chornomorets",
    "sessions": [
      {"title": "Заняття 1", "startAt": "2026-08-05T17:00:00Z", "durationMinutes": 120, "format": "online", "paymentStatus": "unpaid", "order": 1},
      {"title": "Заняття 2", "startAt": "2026-08-12T17:00:00Z", "durationMinutes": 120, "format": "online", "paymentStatus": "unpaid", "order": 2}
    ],
    "materials": [
      {"type": "about", "title": "Про курс", "description": "Цілісне розуміння того, як працює мотивація, стрес і щастя.", "order": 1}
    ]
  }
]
```

## Поза межами (зараз НЕ робити)
- Авторизацію/реєстрацію (тільки `deviceId`).
- Реальну оплату й Apple In-App Purchase (лише поле `paymentStatus` + заглушки). **Примітка для майбутнього:** продаж цифрового контенту в iOS зазвичай вимагає IAP (−30%); живі онлайн-заняття — сіра зона, валідувати перед релізом.
- Офлайн-завантаження відео (це Фаза 2 — лише закласти інтерфейс `DownloadManager`).
- FairPlay / HLS.
- Адмін-панель редагування курсів (дані наповнюються через `seed.ts`).
- Офлайн-формат у UI.

## Критерії готовності Фази 1
1. `cd server && npm i && npm run seed && npm run dev` піднімає API з наповненою БД.
2. iOS-застосунок збирається, на старті тягне каталог із API.
3. Можна підписатися на кілька курсів; розклад показує об'єднані найближчі заняття.
4. Деталь курсу показує опис, програму, заняття зі статусом оплати, ресурси й посилання на Telegram.
5. Відео відкривається в плеєрі через playback-URL від бекенду (стрімінг).
6. Локальні нагадування плануються за 30 хв до занять підписаних курсів.
7. `README.md` пояснює запуск і де перемикати джерело даних/відео.

## Перше, що зробити
Почни з `README.md` + плану файлів, потім бекенд (схема → репозиторій → роути → seed → відео-проксі), запусти й перевір ендпоінти `curl`-ом, далі iOS (моделі → APIClient/repository → каталог → деталь → розклад → плеєр → нотифікації). Питай, якщо щось у моделі чи seed неоднозначне.
```
```
