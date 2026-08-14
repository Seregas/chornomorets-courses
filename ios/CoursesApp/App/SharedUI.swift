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
    let status: PaymentStatus
    var body: some View {
        switch status {
        case .paid: Pill(text: Fmt.paymentLabel(status), fg: .green, bg: .green.opacity(0.15))
        case .free: Pill(text: Fmt.paymentLabel(status), fg: .sea, bg: .sea.opacity(0.12))
        case .unpaid: Pill(text: Fmt.paymentLabel(status), fg: .red, bg: .red.opacity(0.12))
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
        }
    }
}
