import SwiftUI

@MainActor
@Observable
final class CourseDetailViewModel {
    var state: LoadState<CourseDetail> = .loading
    var types: [MaterialType] = []

    var current: CourseDetail? { if case .loaded(let c) = state { return c } else { return nil } }

    func load(_ repo: CourseRepository, id: String) async {
        do {
            async let detail = repo.course(id: id)
            async let t = repo.materialTypes()
            state = .loaded(try await detail)
            types = (try? await t) ?? []
        } catch { state = .failed(error.localizedDescription) }
    }
}

private enum CourseSheet: Identifiable {
    case editCourse, newStream, newMaterial, editMaterial(String)
    var id: String {
        switch self {
        case .editCourse: return "ec"
        case .newStream: return "ns"
        case .newMaterial: return "nm"
        case .editMaterial(let id): return "em-\(id)"
        }
    }
}

struct CourseDetailView: View {
    let courseId: String
    @Environment(\.repository) private var repo
    @Environment(AuthStore.self) private var auth
    @State private var vm = CourseDetailViewModel()
    @State private var sheet: CourseSheet?

    private func reload() async { await vm.load(repo, id: courseId) }

    var body: some View {
        LoadStateView(state: vm.state, retry: { Task { await vm.load(repo, id: courseId) } }) { course in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CoverPlaceholder(seed: course.id)
                        .frame(height: 150)
                        .overlay(alignment: .bottomLeading) {
                            Text(course.title).font(.title2.bold())
                                .foregroundStyle(.white).padding(16)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    section("Про курс") {
                        Text(course.description)
                        if let program = course.program {
                            Text(program).font(.subheadline).foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }

                    if !course.streams.isEmpty || auth.isAdmin {
                        VStack(alignment: .leading, spacing: 10) {
                            adminSectionHeader("Потоки") { sheet = .newStream }
                            ForEach(course.streams) { stream in
                                NavigationLink(value: Route.stream(stream.id)) {
                                    StreamCard(stream: stream)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !course.materials.isEmpty || auth.isAdmin {
                        VStack(alignment: .leading, spacing: 10) {
                            adminSectionHeader("Матеріали курсу") { sheet = .newMaterial }
                            ForEach(course.materials) { m in
                                MaterialRow(
                                    material: m,
                                    adminEdit: auth.isAdmin ? { sheet = .editMaterial(m.id) } : nil,
                                    adminDelete: auth.isAdmin ? {
                                        Task { try? await repo.deleteMaterial(id: m.id); await reload() }
                                    } : nil)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Курс")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if auth.isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .editCourse } label: { Image(systemName: "pencil") }
                }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .editCourse:
                if let c = vm.current { CourseFormView(existing: c) { await reload() } }
            case .newStream:
                StreamFormView(courseId: courseId, existing: nil) { await reload() }
            case .newMaterial:
                MaterialFormView(ownerType: "course", ownerId: courseId, editingId: nil,
                                 types: vm.types) { await reload() }
            case .editMaterial(let id):
                MaterialFormView(ownerType: "course", ownerId: courseId, editingId: id,
                                 types: vm.types) { await reload() }
            }
        }
        .task { await vm.load(repo, id: courseId) }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            content()
        }
    }

    @ViewBuilder
    private func adminSectionHeader(_ title: String, add: @escaping () -> Void) -> some View {
        HStack {
            SectionHeader(title: title)
            Spacer()
            if auth.isAdmin {
                Button(action: add) { Image(systemName: "plus.circle.fill") }
            }
        }
    }
}

struct StreamCard: View {
    let stream: ResolvedStream

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stream.title).font(.headline)
                StatusBadge(status: stream.status)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            if let date = stream.startDate {
                Text(date).font(.subheadline).foregroundStyle(.secondary)
            }
            if let price = Fmt.price(stream.priceFull, perSession: stream.pricePerSession) {
                Text(price).font(.subheadline.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(stream.status == .finished ? Color.secondary : Color.sea)
                .frame(width: 4).padding(.vertical, 12)
        }
    }
}

#Preview {
    NavigationStack { CourseDetailView(courseId: "c-stress") }
        .injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
                   auth: AuthStore())
}
