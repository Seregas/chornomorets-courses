import SwiftUI

/// Курси, яких немає на головному екрані: пройдені та прибрані в архів.
///
/// Групуємо по курсу, а не показуємо потоки плоским списком: той самий курс
/// повторюється потоками рік за роком, і «Потік 1» поруч із «Потік 3» без
/// назви курсу нічого не пояснює. Якщо потік один — показуємо його одразу,
/// без зайвого рівня, бо клацати заради одного рядка немає сенсу.
struct EnrolledStreamsView: View {
    enum Mode {
        case finished, archived

        var title: String { self == .finished ? "Завершені" : "Архів" }

        var emptyTitle: String {
            self == .finished ? "Завершених курсів немає" : "Архів порожній"
        }

        var emptyHint: String {
            self == .finished
                ? "Тут зʼявляться курси, які ви пройшли."
                : "Сюди можна прибрати пройдений курс, щоб він не лишався на очах. "
                    + "Записи й оплати при цьому нікуди не діваються."
        }

        /// Дія у свайпі: прибрати з очей або повернути.
        var actionTitle: String { self == .finished ? "В архів" : "Повернути" }
        var archived: Bool { self == .finished }
    }

    let mode: Mode

    @Environment(\.repository) private var repo
    @State private var state: LoadState<[EnrolledStream]> = .loading
    @State private var openCourse: CourseGroup?

    /// Курс разом із потоками, на які людина підписана.
    struct CourseGroup: Identifiable, Hashable {
        var id: String { courseId }
        let courseId: String
        let courseTitle: String
        let streams: [EnrolledStream]
    }

    var body: some View {
        LoadStateView(state: state, retry: { Task { await load() } }) { items in
            let groups = grouped(items)
            if groups.isEmpty {
                ContentUnavailableView(
                    mode.emptyTitle,
                    systemImage: mode == .finished ? "checkmark.seal" : "archivebox",
                    description: Text(mode.emptyHint))
            } else {
                List {
                    ForEach(groups) { group in
                        if let only = group.streams.first, group.streams.count == 1 {
                            row(courseTitle: group.courseTitle, stream: only)
                        } else {
                            courseRow(group)
                        }
                    }
                    if mode == .finished { archiveLink }
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openCourse) { group in
            CourseStreamsView(group: group, mode: mode) { await load() }
        }
        .task { await load() }
    }

    /// Один потік — рядок веде одразу в нього.
    @ViewBuilder private func row(courseTitle: String, stream: EnrolledStream) -> some View {
        NavigationLink(value: Route.stream(stream.streamId)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(courseTitle).font(.subheadline.weight(.medium))
                Text("\(stream.streamTitle) · \(stream.sessionsPassed) занять")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(mode.actionTitle) {
                Task { await archive(stream) }
            }
            .tint(mode == .finished ? .gray : .sea)
        }
    }

    /// Кілька потоків одного курсу — спершу курс, усередині потоки.
    @ViewBuilder private func courseRow(_ group: CourseGroup) -> some View {
        Button {
            openCourse = group
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.courseTitle).font(.subheadline.weight(.medium))
                    Text("\(group.streams.count) потоки").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var archiveLink: some View {
        NavigationLink(value: Route.archivedStreams) {
            Label("Архів", systemImage: "archivebox")
                .font(.subheadline)
        }
    }

    private func grouped(_ items: [EnrolledStream]) -> [CourseGroup] {
        let wanted = items.filter { mode == .finished ? !$0.isArchived : $0.isArchived }
        // Порядок курсів беремо з відповіді сервера, а не сортуємо заново:
        // там вони вже впорядковані від тих, що тривають, до пройдених.
        var order: [String] = []
        var byCourse: [String: [EnrolledStream]] = [:]
        for item in wanted {
            if byCourse[item.courseId] == nil { order.append(item.courseId) }
            byCourse[item.courseId, default: []].append(item)
        }
        return order.map { id in
            let streams = byCourse[id] ?? []
            return CourseGroup(
                courseId: id,
                courseTitle: streams.first?.courseTitle ?? "",
                streams: streams)
        }
    }

    private func archive(_ stream: EnrolledStream) async {
        try? await repo.setArchived(streamId: stream.streamId, archived: mode.archived)
        await load()
    }

    private func load() async {
        do {
            let all = try await repo.home().streams
            // На цьому екрані лише пройдені: те, що триває, живе на головному.
            state = .loaded(all.filter { $0.status == .finished })
        } catch {
            state = .from(error)
        }
    }
}

/// Потоки одного курсу — коли їх кілька.
private struct CourseStreamsView: View {
    let group: EnrolledStreamsView.CourseGroup
    let mode: EnrolledStreamsView.Mode
    let onChanged: () async -> Void

    @Environment(\.repository) private var repo
    @State private var streams: [EnrolledStream]

    init(group: EnrolledStreamsView.CourseGroup,
         mode: EnrolledStreamsView.Mode,
         onChanged: @escaping () async -> Void) {
        self.group = group
        self.mode = mode
        self.onChanged = onChanged
        _streams = State(initialValue: group.streams)
    }

    var body: some View {
        List {
            ForEach(streams) { stream in
                NavigationLink(value: Route.stream(stream.streamId)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stream.streamTitle).font(.subheadline.weight(.medium))
                        Text("\(stream.sessionsPassed) занять").font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(mode.actionTitle) {
                        Task {
                            try? await repo.setArchived(
                                streamId: stream.streamId, archived: mode.archived)
                            streams.removeAll { $0.id == stream.id }
                            await onChanged()
                        }
                    }
                    .tint(mode == .finished ? .gray : .sea)
                }
            }
        }
        .navigationTitle(group.courseTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
