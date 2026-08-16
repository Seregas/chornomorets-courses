import SwiftUI

/// Екран одного заняття: коли воно, як приєднатися і що до нього належить —
/// запис, конспект, домашка. Матеріали потоку сюди не потрапляють: там лежить
/// те, що стосується курсу загалом, і воно не має мозолити очі на кожній зустрічі.
struct SessionDetailView: View {
    let item: SessionWithMaterials
    let types: [MaterialType]
    /// Ціна за заняття з потоку — підставляється у форму оплати.
    var pricePerSession: Int? = nil
    /// Перезавантажити потік після адмінських правок.
    let onChanged: () async -> Void

    @Environment(\.repository) private var repo
    @Environment(\.openURL) private var openURL
    @Environment(AuthStore.self) private var auth
    @State private var sheet: SessionSheet?
    @State private var showQuestions = false
    @State private var showPulse = false
    @State private var showPayment = false

    private enum SessionSheet: Identifiable {
        case newMaterial, editMaterial(String)
        var id: String {
            switch self {
            case .newMaterial: return "nm"
            case .editMaterial(let id): return "em-\(id)"
            }
        }
    }

    private var session: CourseSession { item.session }
    private var isUpcoming: Bool { (Fmt.date(session.startAt) ?? .distantFuture) > Date() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                materialsSection
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { which in
            switch which {
            case .newMaterial:
                MaterialFormView(ownerType: "session", ownerId: session.id,
                                 editingId: nil, types: types) { await onChanged() }
            case .editMaterial(let id):
                MaterialFormView(ownerType: "session", ownerId: session.id,
                                 editingId: id, types: types) { await onChanged() }
            }
        }
        .sheet(isPresented: $showQuestions) { SessionQuestionsView(session: session) }
        .sheet(isPresented: $showPulse) { SessionPulseView(session: session) }
        .sheet(isPresented: $showPayment) {
            SessionPaymentView(session: session, suggestedAmount: pricePerSession)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Fmt.relativeDayTime(session.startAt))
                .font(.title3.weight(.bold)).foregroundStyle(Color.sea)
            HStack(spacing: 8) {
                FormatBadge(format: session.format)
                PaymentBadge(payment: item.payment)
                Text("\(session.durationMinutes) хв")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if let join = session.joinURL, let url = URL(string: join), isUpcoming {
            Button {
                openURL(url)
            } label: {
                Label("Приєднатися", systemImage: "video.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.sea)
        }

        // До заняття доречні питання, після — оцінка.
        Button {
            if isUpcoming { showQuestions = true } else { showPulse = true }
        } label: {
            Label(isUpcoming ? "Питання до заняття" : "Як зайшло?",
                  systemImage: isUpcoming ? "questionmark.bubble" : "star.bubble")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        // Оплата — на пару «заняття + людина», тож живе тут, а не в потоці.
        Button { showPayment = true } label: {
            Label(item.payment == nil ? "Я оплатив" : "Оплата: \(item.payment!.status.label)",
                  systemImage: "hryvniasign.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private var materialsSection: some View {
        if !item.materials.isEmpty || auth.isAdmin {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Матеріали заняття")
                    Spacer()
                    if auth.isAdmin {
                        Button { sheet = .newMaterial } label: { Image(systemName: "plus.circle.fill") }
                    }
                }
                if item.materials.isEmpty {
                    Text("Порожньо. Запис, конспект чи домашка додаються сюди.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(item.materials) { material in
                    MaterialRow(
                        material: material,
                        adminEdit: auth.isAdmin ? { sheet = .editMaterial(material.id) } : nil,
                        adminDelete: auth.isAdmin ? {
                            Task { try? await repo.deleteMaterial(id: material.id); await onChanged() }
                        } : nil)
                }
            }
        }
    }
}

/// Іконки того, що є в занятті — щоб не відкривати кожне заради з'ясування.
struct SessionContentIcons: View {
    let item: SessionWithMaterials

    var body: some View {
        HStack(spacing: 6) {
            if item.hasVideo { icon("play.rectangle.fill", .sea) }
            if item.hasHomework { icon("checkmark.circle.fill", .orange) }
            if item.hasDocuments { icon("doc.text.fill", Color(red: 0.18, green: 0.61, blue: 0.86)) }
        }
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.caption).foregroundStyle(color)
    }
}
