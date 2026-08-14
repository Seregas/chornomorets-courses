import SwiftUI

/// Керування каталогом типів матеріалів (глобальний, тому окремий список,
/// доступний адмінам із Налаштувань). Решта адмінки — інлайн на сторінках.
@MainActor
@Observable
final class MaterialTypesViewModel {
    var types: [MaterialType] = []
    func load(_ repo: CourseRepository) async {
        types = (try? await repo.materialTypes()) ?? []
    }
}

struct MaterialTypesView: View {
    @Environment(\.repository) private var repo
    @State private var vm = MaterialTypesViewModel()
    @State private var showNew = false
    @State private var editType: MaterialType?

    var body: some View {
        List {
            Section {
                Text("Типи — косметичні ярлики. Поведінка матеріалу залежить від вмісту, "
                     + "тож видалення типу нічого не ламає (матеріали стають «без типу»).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(vm.types) { t in
                Button { editType = t } label: {
                    HStack {
                        Image(systemName: t.icon ?? "tag").foregroundStyle(Color(hex: t.color) ?? .sea)
                        Text(t.name).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    Button("Видалити", role: .destructive) {
                        Task { try? await repo.deleteMaterialType(id: t.id); await vm.load(repo) }
                    }
                }
            }
        }
        .navigationTitle("Типи матеріалів")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNew) {
            MaterialTypeFormView(existing: nil) { await vm.load(repo) }
        }
        .sheet(item: $editType) { t in
            MaterialTypeFormView(existing: t) { await vm.load(repo) }
        }
        .task { await vm.load(repo) }
    }
}

extension Color {
    /// Парсинг #RRGGBB.
    init?(hex: String?) {
        guard var s = hex else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

#Preview {
    NavigationStack { MaterialTypesView() }
        .injecting(.init(repository: PreviewRepository(), notifications: NotificationScheduler()),
                   auth: AuthStore())
}
