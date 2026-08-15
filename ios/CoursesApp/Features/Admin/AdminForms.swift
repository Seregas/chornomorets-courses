import SwiftUI

// Спільна обгортка форми: NavigationStack + Скасувати/Зберегти + показ помилки.
private struct FormScaffold<Content: View>: View {
    let titleText: String
    let canSave: Bool
    let onSave: () async -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form { content() }
                .navigationTitle(titleText)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if saving { ProgressView() }
                        else { Button("Зберегти") { Task { saving = true; await onSave(); saving = false } }.disabled(!canSave) }
                    }
                }
        }
    }
}

// MARK: - Курс

struct CourseFormView: View {
    let existing: CourseDetail?
    let onDone: () async -> Void
    @Environment(\.repository) private var repo

    @State private var title: String
    @State private var summary: String
    @State private var desc: String
    @State private var program: String
    @State private var cover: String
    @State private var format: CourseFormat
    @State private var error: String?

    init(existing: CourseDetail?, onDone: @escaping () async -> Void) {
        self.existing = existing
        self.onDone = onDone
        _title = State(initialValue: existing?.title ?? "")
        _summary = State(initialValue: existing?.summary ?? "")
        _desc = State(initialValue: existing?.description ?? "")
        _program = State(initialValue: existing?.program ?? "")
        _cover = State(initialValue: existing?.coverImageURL ?? "")
        _format = State(initialValue: existing?.format ?? .online)
    }

    var body: some View {
        FormScaffold(titleText: existing == nil ? "Новий курс" : "Редагувати курс",
                     canSave: !title.isEmpty && !summary.isEmpty && !desc.isEmpty, onSave: save) {
            Section("Основне") {
                TextField("Назва", text: $title)
                TextField("Короткий опис", text: $summary, axis: .vertical)
                TextField("Повний опис", text: $desc, axis: .vertical)
                TextField("Програма", text: $program, axis: .vertical)
            }
            Section("Додатково") {
                Picker("Формат", selection: $format) {
                    Text("online").tag(CourseFormat.online)
                    Text("offline").tag(CourseFormat.offline)
                    Text("hybrid").tag(CourseFormat.hybrid)
                }
                TextField("URL обкладинки", text: $cover).keyboardType(.URL).autocapitalization(.none)
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
    }

    private func save() async {
        let input = CourseInput(title: title, summary: summary, description: desc,
                                program: nilIfEmpty(program), format: format.rawValue,
                                coverImageURL: nilIfEmpty(cover))
        do {
            if let existing { try await repo.updateCourse(id: existing.id, input) }
            else { try await repo.createCourse(input) }
            await onDone()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Потік

struct StreamFormView: View {
    let courseId: String
    let existing: StreamDetail?
    let onDone: () async -> Void
    @Environment(\.repository) private var repo

    @State private var title: String
    @State private var startDate: String
    @State private var status: StreamStatus
    @State private var telegram: String
    @State private var priceFull: String
    @State private var pricePer: String
    @State private var summaryOv: String
    @State private var descOv: String
    @State private var programOv: String
    @State private var error: String?

    init(courseId: String, existing: StreamDetail?, onDone: @escaping () async -> Void) {
        self.courseId = courseId
        self.existing = existing
        self.onDone = onDone
        _title = State(initialValue: existing?.title ?? "")
        _startDate = State(initialValue: existing?.startDate ?? "")
        _status = State(initialValue: existing?.status ?? .upcoming)
        _telegram = State(initialValue: existing?.telegramGroupURL ?? "")
        _priceFull = State(initialValue: existing?.priceFull.map(String.init) ?? "")
        _pricePer = State(initialValue: existing?.pricePerSession.map(String.init) ?? "")
        _summaryOv = State(initialValue: existing?.summaryOverride ?? "")
        _descOv = State(initialValue: existing?.descriptionOverride ?? "")
        _programOv = State(initialValue: existing?.programOverride ?? "")
    }

    var body: some View {
        FormScaffold(titleText: existing == nil ? "Новий потік" : "Редагувати потік",
                     canSave: !title.isEmpty, onSave: save) {
            Section("Основне") {
                TextField("Назва (напр. Потік 5)", text: $title)
                TextField("Дата початку (YYYY-MM-DD)", text: $startDate).autocapitalization(.none)
                Picker("Статус", selection: $status) {
                    Text("скоро").tag(StreamStatus.upcoming)
                    Text("триває").tag(StreamStatus.ongoing)
                    Text("завершено").tag(StreamStatus.finished)
                }
                TextField("Телеграм-група (URL)", text: $telegram).keyboardType(.URL).autocapitalization(.none)
            }
            Section("Ціна, ₴") {
                TextField("Повна", text: $priceFull).keyboardType(.numberPad)
                TextField("За заняття", text: $pricePer).keyboardType(.numberPad)
            }
            Section {
                TextField("Короткий опис", text: $summaryOv, axis: .vertical)
                TextField("Повний опис", text: $descOv, axis: .vertical)
                TextField("Програма", text: $programOv, axis: .vertical)
            } header: {
                Text("Перевизначення опису")
            } footer: {
                Text("Порожнє — успадковується з курсу.")
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
    }

    private func save() async {
        let input = StreamInput(
            courseId: existing == nil ? courseId : nil,
            title: title, startDate: nilIfEmpty(startDate), status: status.rawValue,
            telegramGroupURL: nilIfEmpty(telegram),
            priceFull: Int(priceFull), pricePerSession: Int(pricePer),
            summaryOverride: nilIfEmpty(summaryOv), descriptionOverride: nilIfEmpty(descOv),
            programOverride: nilIfEmpty(programOv))
        do {
            if let existing { try await repo.updateStream(id: existing.id, input) }
            else { try await repo.createStream(input) }
            await onDone()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Заняття

struct SessionFormView: View {
    let streamId: String
    let existing: CourseSession?
    let onDone: () async -> Void
    @Environment(\.repository) private var repo

    @State private var title: String
    @State private var startAt: Date
    @State private var duration: String
    @State private var format: CourseFormat
    @State private var joinURL: String
    @State private var payment: PaymentStatus
    @State private var error: String?

    init(streamId: String, existing: CourseSession?, onDone: @escaping () async -> Void) {
        self.streamId = streamId
        self.existing = existing
        self.onDone = onDone
        _title = State(initialValue: existing?.title ?? "")
        _startAt = State(initialValue: existing.flatMap { Fmt.date($0.startAt) } ?? Date())
        _duration = State(initialValue: existing.map { String($0.durationMinutes) } ?? "120")
        _format = State(initialValue: existing?.format ?? .online)
        _joinURL = State(initialValue: existing?.joinURL ?? "")
        _payment = State(initialValue: existing?.paymentStatus ?? .unpaid)
    }

    var body: some View {
        FormScaffold(titleText: existing == nil ? "Нове заняття" : "Редагувати заняття",
                     canSave: !title.isEmpty && Int(duration) != nil, onSave: save) {
            Section {
                TextField("Назва", text: $title)
                DatePicker("Початок", selection: $startAt)
                TextField("Тривалість, хв", text: $duration).keyboardType(.numberPad)
            }
            Section {
                Picker("Формат", selection: $format) {
                    Text("online").tag(CourseFormat.online)
                    Text("offline").tag(CourseFormat.offline)
                    Text("hybrid").tag(CourseFormat.hybrid)
                }
                Picker("Оплата", selection: $payment) {
                    Text("не оплачено").tag(PaymentStatus.unpaid)
                    Text("оплачено").tag(PaymentStatus.paid)
                    Text("безкоштовно").tag(PaymentStatus.free)
                }
                TextField("Посилання на зустріч (URL)", text: $joinURL).keyboardType(.URL).autocapitalization(.none)
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
    }

    private func save() async {
        let iso = ISO8601DateFormatter().string(from: startAt)
        let input = SessionInput(
            streamId: existing == nil ? streamId : nil,
            title: title, startAt: iso, durationMinutes: Int(duration),
            format: format.rawValue, joinURL: nilIfEmpty(joinURL), paymentStatus: payment.rawValue)
        do {
            if let existing { try await repo.updateSession(id: existing.id, input) }
            else { try await repo.createSession(input) }
            await onDone()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Оголошення

/// Коротке повідомлення потоку: перенесли заняття, виклали матеріал.
struct AnnouncementFormView: View {
    let streamId: String
    let onDone: () async -> Void
    @Environment(\.repository) private var repo

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        FormScaffold(titleText: "Оголошення",
                     canSave: !text.trimmingCharacters(in: .whitespaces).isEmpty,
                     onSave: save) {
            Section {
                TextField("Що сказати потоку?", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            } footer: {
                Text("Побачать усі, хто підписаний на потік — на екрані «Навчання» і на сторінці потоку.")
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
    }

    private func save() async {
        do {
            try await repo.createAnnouncement(
                streamId: streamId,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            await onDone()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Клон потоку

/// Потоки повторюються щосезону з тим самим розкладом. Замість «створити потік +
/// N разів створити заняття» — назва й дата початку, решта переноситься зі зсувом.
struct CloneStreamFormView: View {
    let source: StreamDetail
    let onDone: () async -> Void
    @Environment(\.repository) private var repo

    @State private var title: String
    @State private var startDate: Date
    @State private var error: String?

    init(source: StreamDetail, onDone: @escaping () async -> Void) {
        self.source = source
        self.onDone = onDone
        _title = State(initialValue: Self.nextTitle(after: source.title))
        // За замовчуванням — через тиждень після останнього заняття джерела.
        let lastSession = source.sessions.compactMap { Fmt.date($0.startAt) }.max()
        _startDate = State(initialValue: (lastSession ?? Date()).addingTimeInterval(7 * 86_400))
    }

    /// «Потік 4» → «Потік 5»; якщо номера немає — лишаємо як є, адмін виправить.
    private static func nextTitle(after title: String) -> String {
        guard let range = title.range(of: #"\d+$"#, options: .regularExpression),
              let n = Int(title[range]) else { return title }
        return title.replacingCharacters(in: range, with: String(n + 1))
    }

    var body: some View {
        FormScaffold(titleText: "Клонувати потік", canSave: !title.isEmpty, onSave: save) {
            Section {
                TextField("Назва нового потоку", text: $title)
                DatePicker("Перше заняття", selection: $startDate, displayedComponents: .date)
            } footer: {
                Text("Заняття скопіюються з тим самим кроком і часом доби. "
                     + "Записи не переносяться; конспекти, посилання й домашка — так, без дедлайнів.")
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
    }

    private func save() async {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(secondsFromGMT: 0)
        do {
            try await repo.cloneStream(
                id: source.id,
                CloneStreamInput(title: title, startDate: day.string(from: startDate)))
            await onDone()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Серія занять

/// «Щочетверга о 20:00, три заняття» — одна форма замість трьох однакових.
struct SessionsBatchFormView: View {
    let streamId: String
    let onDone: () async -> Void
    @Environment(\.repository) private var repo

    @State private var titlePrefix = "Заняття"
    @State private var startAt = Date()
    @State private var count = 3
    @State private var intervalDays = 7
    @State private var duration = "120"
    @State private var joinURL = ""
    @State private var error: String?

    var body: some View {
        FormScaffold(titleText: "Серія занять",
                     canSave: !titlePrefix.isEmpty && Int(duration) != nil, onSave: save) {
            Section {
                TextField("Назва (додасться номер)", text: $titlePrefix)
                DatePicker("Перше заняття", selection: $startAt)
                Stepper("Кількість: \(count)", value: $count, in: 1...52)
                Picker("Крок", selection: $intervalDays) {
                    Text("щодня").tag(1)
                    Text("щотижня").tag(7)
                    Text("раз на 2 тижні").tag(14)
                }
                TextField("Тривалість, хв", text: $duration).keyboardType(.numberPad)
            } footer: {
                Text("Створить \(count) занять: «\(titlePrefix) 1» … «\(titlePrefix) \(count)».")
            }
            Section {
                TextField("Посилання на зустріч (URL)", text: $joinURL)
                    .keyboardType(.URL).autocapitalization(.none)
            } footer: {
                Text("Одне на всі заняття серії — зазвичай так і буває.")
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
    }

    private func save() async {
        do {
            try await repo.createSessionsBatch(SessionsBatchInput(
                streamId: streamId,
                titlePrefix: titlePrefix,
                startAt: ISO8601DateFormatter().string(from: startAt),
                count: count,
                intervalDays: intervalDays,
                durationMinutes: Int(duration) ?? 120,
                joinURL: nilIfEmpty(joinURL)))
            await onDone()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Матеріал

struct MaterialFormView: View {
    let ownerType: String      // "course" | "stream"
    let ownerId: String
    let editingId: String?
    let types: [MaterialType]
    let onDone: () async -> Void
    @Environment(\.repository) private var repo

    @State private var title = ""
    @State private var typeId: String = ""        // "" = без типу
    @State private var desc = ""
    @State private var provider: String = ""       // "" = без відео
    @State private var videoRef = ""
    @State private var url = ""
    @State private var hasDue = false
    @State private var dueAt = Date()
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        FormScaffold(titleText: editingId == nil ? "Новий матеріал" : "Редагувати матеріал",
                     canSave: !title.isEmpty, onSave: save) {
            Section("Основне") {
                TextField("Назва", text: $title)
                Picker("Тип", selection: $typeId) {
                    Text("— без типу —").tag("")
                    ForEach(types) { t in Text(t.name).tag(t.id) }
                }
                TextField("Опис / текст", text: $desc, axis: .vertical)
            }
            Section("Відео") {
                Picker("Джерело", selection: $provider) {
                    Text("немає").tag("")
                    Text("Google Drive").tag("drive")
                    Text("YouTube").tag("youtube")
                    Text("Інше (пряме URL)").tag("other")
                }
                if !provider.isEmpty {
                    TextField(refPlaceholder, text: $videoRef).autocapitalization(.none)
                }
            }
            Section("Посилання") {
                TextField("URL (доку / Miro тощо)", text: $url).keyboardType(.URL).autocapitalization(.none)
            }
            Section("Домашнє завдання") {
                Toggle("Є дедлайн", isOn: $hasDue)
                if hasDue { DatePicker("Дедлайн", selection: $dueAt) }
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .task {
            guard !loaded, let id = editingId else { loaded = true; return }
            if let m = try? await repo.adminMaterial(id: id) {
                title = m.title; typeId = m.typeId ?? ""; desc = m.description ?? ""
                provider = m.videoProvider?.rawValue ?? ""; videoRef = m.videoRef ?? ""
                url = m.url ?? ""
                if let d = m.dueAt, let date = Fmt.date(d) { hasDue = true; dueAt = date }
            }
            loaded = true
        }
    }

    private var refPlaceholder: String {
        switch provider {
        case "drive": return "Drive file ID"
        case "youtube": return "YouTube video ID"
        default: return "Пряме URL відео"
        }
    }

    private func save() async {
        let input = MaterialInput(
            ownerType: editingId == nil ? ownerType : nil,
            ownerId: editingId == nil ? ownerId : nil,
            typeId: typeId.isEmpty ? nil : typeId,
            title: title, description: nilIfEmpty(desc),
            videoProvider: provider.isEmpty ? nil : provider,
            videoRef: provider.isEmpty ? nil : nilIfEmpty(videoRef),
            url: nilIfEmpty(url),
            dueAt: hasDue ? ISO8601DateFormatter().string(from: dueAt) : nil)
        do {
            if let editingId { try await repo.updateMaterial(id: editingId, input) }
            else { try await repo.createMaterial(input) }
            await onDone()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Тип матеріалу

struct MaterialTypeFormView: View {
    let existing: MaterialType?
    let onDone: () async -> Void
    @Environment(\.repository) private var repo

    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @State private var error: String?

    init(existing: MaterialType?, onDone: @escaping () async -> Void) {
        self.existing = existing
        self.onDone = onDone
        _name = State(initialValue: existing?.name ?? "")
        _icon = State(initialValue: existing?.icon ?? "")
        _color = State(initialValue: existing?.color ?? "")
    }

    var body: some View {
        FormScaffold(titleText: existing == nil ? "Новий тип" : "Редагувати тип",
                     canSave: !name.isEmpty, onSave: save) {
            Section {
                TextField("Назва", text: $name)
                TextField("SF Symbol (напр. play.rectangle.fill)", text: $icon).autocapitalization(.none)
                TextField("Колір (#RRGGBB)", text: $color).autocapitalization(.none)
            } footer: {
                HStack {
                    Image(systemName: icon.isEmpty ? "tag" : icon)
                        .foregroundStyle(Color(hex: color) ?? .sea)
                    Text("Попередній перегляд")
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
    }

    private func save() async {
        let input = MaterialTypeInput(name: name, icon: nilIfEmpty(icon), color: nilIfEmpty(color))
        do {
            if let existing { try await repo.updateMaterialType(id: existing.id, input) }
            else { try await repo.createMaterialType(input) }
            await onDone()
        } catch { self.error = error.localizedDescription }
    }
}
