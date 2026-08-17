import SwiftUI

/// Кольорова пігулка-бейдж.
struct Pill: View {
    let text: String
    var fg: Color = .sea
    var bg: Color = Color.sea.opacity(0.12)
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text).font(.caption).fontWeight(.semibold)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .foregroundStyle(fg).background(bg, in: Capsule())
    }
}

struct FormatBadge: View {
    let format: CourseFormat
    var body: some View { Pill(text: format.rawValue) }
}

struct PaymentBadge: View {
    let payment: Payment?

    var body: some View {
        let tone = color
        Pill(text: payment?.status.label ?? "не оплачено",
             fg: tone, bg: tone.opacity(0.12))
    }

    private var color: Color {
        switch payment?.status {
        case .confirmed, .free: return .green
        case .declared: return .orange
        case .rejected: return .red
        case nil: return .secondary
        }
    }
}

struct StatusBadge: View {
    let status: StreamStatus
    var body: some View {
        let (fg, bg): (Color, Color) = status == .finished
            ? (.secondary, Color(.systemGray5))
            : (.sea, .sea.opacity(0.12))
        Pill(text: Fmt.statusLabel(status), fg: fg, bg: bg)
    }
}

/// Бейдж стану доступу до відео (🔓 / 🔒 / не підключено).
struct AccessBadge: View {
    let state: AccessState
    let provider: VideoProvider?

    var body: some View {
        switch state {
        case .granted:
            Pill(text: provider == .youtube ? "YouTube" : "доступно",
                 fg: .green, bg: .green.opacity(0.15), systemImage: "lock.open.fill")
        case .denied:
            Pill(text: "немає доступу", fg: .red, bg: .red.opacity(0.12), systemImage: "lock.fill")
        case .unknown:
            Pill(text: "підключіть Google", fg: .orange, bg: .orange.opacity(0.15), systemImage: "lock.fill")
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }
}

/// Кольорова «обкладинка»-плейсхолдер (поки немає coverImageURL).
struct CoverPlaceholder: View {
    let seed: String
    var body: some View {
        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .bottom) {
                WaveShape().fill(.white.opacity(0.12)).frame(height: 28)
            }
    }
    private var gradient: [Color] {
        let palettes: [[Color]] = [
            [.sea, .seaDeep],
            [Color(red: 0.18, green: 0.61, blue: 0.86), Color(red: 0.12, green: 0.44, blue: 0.70)],
            [Color(red: 0.48, green: 0.56, blue: 0.63), Color(red: 0.34, green: 0.40, blue: 0.45)],
        ]
        return palettes[abs(seed.hashValue) % palettes.count]
    }
}

struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.midY),
                       control: CGPoint(x: rect.width * 0.25, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                       control: CGPoint(x: rect.width * 0.75, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Простий стан завантаження/помилки навколо async-контенту.
enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
    /// Не помилка, а стан: особисті дані живуть на акаунті, тож без входу їх
    /// просто немає. Показувати тут «не вдалося завантажити» — брехня.
    case needsSignIn

    /// 401 від сервера — це «увійдіть», а не збій мережі.
    static func from(_ error: Error) -> LoadState<Value> {
        if let api = error as? APIError, api.status == 401 { return .needsSignIn }
        return .failed(error.localizedDescription)
    }
}

struct LoadStateView<Value, Content: View>: View {
    let state: LoadState<Value>
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let v):
            content(v)
        case .failed(let msg):
            ContentUnavailableView {
                Label("Не вдалося завантажити", systemImage: "wifi.exclamationmark")
            } description: {
                Text(msg)
            } actions: {
                Button("Спробувати ще", action: retry)
            }
        case .needsSignIn:
            SignInPrompt(retry: retry)
        }
    }
}


/// Запрошення увійти. Показується там, де без акаунта нема чого показувати:
/// підписки, розклад, оплати й домашки належать людині, а не пристрою.
struct SignInPrompt: View {
    let retry: () -> Void

    @Environment(AuthStore.self) private var auth
    @State private var signingIn = false
    @State private var error: String?

    var body: some View {
        ContentUnavailableView {
            Label("Потрібен вхід", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("Ваші підписки, заняття й оплати привʼязані до Google-акаунта — "
                 + "так вони переїжджають разом із вами на новий телефон.")
        } actions: {
            if signingIn {
                ProgressView()
            } else if GoogleAuthConfig.isConfigured {
                Button("Увійти через Google", action: signIn)
                    .buttonStyle(.borderedProminent).tint(.sea)
            } else {
                Text("Вхід через Google не налаштований у цій збірці.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func signIn() {
        signingIn = true
        Task {
            defer { signingIn = false }
            do {
                let session = try await GoogleSignInService().signIn()
                auth.connectGoogle(email: session.email, idToken: session.idToken,
                                   accessToken: session.accessToken)
                retry()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
