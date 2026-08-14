import SwiftUI

/// Композитний рядок матеріалу: вміст вирішує вигляд.
///  - є відео → плей + бейдж доступу (тап відкриває плеєр);
///  - є лінк → відкриває системним браузером;
///  - є текст → показуємо разом із медіа;
///  - є дедлайн → чип.
struct MaterialRow: View {
    let material: MaterialDTO
    var adminEdit: (() -> Void)? = nil
    var adminDelete: (() -> Void)? = nil
    @Environment(\.repository) private var repo
    @Environment(\.openURL) private var openURL
    @State private var access: AccessState?
    @State private var showPlayer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3).foregroundStyle(iconColor).frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(material.title).font(.subheadline.weight(.medium))
                    if let due = material.dueAt {
                        Label("до \(Fmt.dayTime(due))", systemImage: "clock")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                trailing
            }
            if let desc = material.description, !desc.isEmpty {
                Text(desc).font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(perform: handleTap)
        .task {
            if material.hasVideo {
                access = (try? await repo.access(materialId: material.id))?.access ?? .unknown
            }
        }
        .sheet(isPresented: $showPlayer) {
            VideoPlayerView(materialId: material.id, title: material.title)
        }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 8) {
            if material.hasVideo {
                AccessBadge(state: access ?? .unknown, provider: material.videoProvider)
            } else if material.url != nil {
                Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.tertiary)
            }
            if adminEdit != nil || adminDelete != nil {
                Menu {
                    if let adminEdit {
                        Button(action: adminEdit) { Label("Редагувати", systemImage: "pencil") }
                    }
                    if let adminDelete {
                        Button(role: .destructive, action: adminDelete) { Label("Видалити", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func handleTap() {
        if material.hasVideo {
            showPlayer = true
        } else if let s = material.url, let u = URL(string: s) {
            openURL(u)
        }
    }

    private var iconName: String {
        if material.hasVideo { return "play.circle.fill" }
        if material.dueAt != nil { return "checkmark.circle.fill" }
        if material.url != nil { return "link" }
        return "text.alignleft"
    }
    private var iconColor: Color {
        if material.hasVideo { return .sea }
        if material.dueAt != nil { return .orange }
        if material.url != nil { return Color(red: 0.18, green: 0.61, blue: 0.86) }
        return .secondary
    }
}
