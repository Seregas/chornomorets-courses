import SwiftUI

@MainActor
@Observable
final class CatalogViewModel {
    var state: LoadState<[CourseCard]> = .loading

    func load(_ repo: CourseRepository) async {
        do { state = .loaded(try await repo.courses()) }
        catch { state = .from(error) }
    }
}

struct CatalogView: View {
    @Environment(\.repository) private var repo
    @Environment(AuthStore.self) private var auth
    @State private var vm = CatalogViewModel()
    @State private var path: [Route] = []
    @State private var showNewCourse = false

    var body: some View {
        NavigationStack(path: $path) {
            LoadStateView(state: vm.state, retry: { Task { await vm.load(repo) } }) { courses in
                List {
                    ForEach(courses) { course in
                        NavigationLink(value: Route.course(course.id)) {
                            CourseRow(course: course)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .swipeActions {
                            if auth.isAdmin {
                                Button("Видалити", role: .destructive) {
                                    Task { try? await repo.deleteCourse(id: course.id); await vm.load(repo) }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Курси")
            .toolbar {
                if auth.isAdmin {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewCourse = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showNewCourse) {
                CourseFormView(existing: nil) { await vm.load(repo) }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .course(let id): CourseDetailView(courseId: id)
                case .stream(let id): StreamDetailView(streamId: id)
                case .journal: JournalView()
                }
            }
        }
        .task { await vm.load(repo) }
        .onAppear {
            // Debug deep-link для демо/скриншотів.
            let env = ProcessInfo.processInfo.environment
            if path.isEmpty, let s = env["OPEN_STREAM"] { path = [.stream(s)] }
            else if path.isEmpty, let c = env["OPEN_COURSE"] { path = [.course(c)] }
        }
    }
}

struct CourseRow: View {
    let course: CourseCard

    var body: some View {
        HStack(spacing: 14) {
            CoverPlaceholder(seed: course.id)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                Text(course.title).font(.headline).lineLimit(2)
                Text(course.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    FormatBadge(format: course.format)
                    if let next = course.nextStream {
                        Pill(text: nextLabel(next),
                             fg: next.status == .finished ? .secondary : Color(red: 0.79, green: 0.42, blue: 0.14),
                             bg: next.status == .finished ? Color(.systemGray5) : Color.orange.opacity(0.15),
                             systemImage: next.status == .finished ? nil : "circle.fill")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func nextLabel(_ s: StreamBrief) -> String {
        if s.status == .finished { return s.title }
        if let d = s.startDate {
            return "Новий потік · з \(Fmt.day(d))"
        }
        return "Новий потік"
    }
}

#Preview {
    CatalogView().injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
                            auth: AuthStore())
}
