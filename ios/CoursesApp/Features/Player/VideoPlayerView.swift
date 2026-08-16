import AVKit
import Combine
import SwiftUI
import WebKit

/// Плеєр відіграє playback-дескриптор від бекенду. Тип джерела ховається за
/// дескриптором: direct і Drive → AVPlayer, youtube → вбудований веб-плеєр.
/// Додати джерело (HLS/R2) = новий case тут, без зміни решти застосунку.
struct VideoPlayerView: View {
    let materialId: String
    let title: String
    @Environment(\.repository) private var repo
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<PlaybackDescriptor> = .loading

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Готово") { dismiss() }
                    }
                }
        }
        .task { await resolve() }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView("Готуємо відео…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let descriptor):
            player(for: descriptor)
        case .failed(let message):
            ContentUnavailableView {
                Label("Немає доступу", systemImage: "lock.fill")
            } description: {
                Text(message)
            }
        }
    }

    @ViewBuilder private func player(for descriptor: PlaybackDescriptor) -> some View {
        switch descriptor {
        case .direct(let url):
            if let u = URL(string: url) {
                DirectVideoPlayer(url: u, materialId: materialId, title: title)
                    .ignoresSafeArea(edges: .bottom)
            } else { invalid }
        case .youtube(let videoId):
            WebPlayer(url: URL(string: "https://www.youtube.com/embed/\(videoId)?playsinline=1")!)
        case .googleDrive(let fileId):
            // Раніше тут було drive.google.com/.../preview у веб-в'ю — воно не
            // мало ні токена, ні куків Google, тож показувало «немає доступу»
            // навіть тим, кому файл розшарено. Тепер тягнемо вміст напряму з
            // Drive API, підписуючи запит токеном користувача.
            if let token = AuthTokenStore.driveAccessToken,
               let url = DriveAccess.mediaURL(fileId: fileId) {
                DirectVideoPlayer(url: url, materialId: materialId, title: title,
                                  headers: ["Authorization": "Bearer \(token)"])
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView {
                    Label("Потрібен Google-акаунт", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("Запис лежить на Google Drive. Підключіть акаунт у Налаштуваннях — той, якому надано доступ до записів.")
                }
            }
        }
    }

    private var invalid: some View {
        ContentUnavailableView("Некоректне посилання", systemImage: "exclamationmark.triangle")
    }

    private func resolve() async {
        do {
            state = .loaded(try await repo.playback(materialId: materialId).descriptor)
        } catch let e as APIError where e.status == 403 {
            state = .failed("Це відео доступне лише акаунтам Google, яким надано доступ. Підключіть потрібний акаунт у Налаштуваннях.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

/// Плеєр для `direct`-джерела: продовжує з місця, де зупинилися минулого разу,
/// і дописує позицію під час перегляду. Записи по дві години — починати їх
/// щоразу з нуля означає щоразу шукати те місце вручну.
///
/// Для youtube/drive позиція поки не зберігається: там грає веб-в'ю, чий стан
/// нам не видно. Коли Drive поїде через AVPlayer (задача про доступ до Drive),
/// він потрапить сюди й отримає те саме безкоштовно.
struct DirectVideoPlayer: View {
    let url: URL
    let materialId: String
    let title: String
    /// Заголовки запиту — для джерел, що вимагають авторизації (Drive).
    var headers: [String: String] = [:]

    @State private var player = AVPlayer()
    @State private var audio = PlayerAudioController()
    @State private var timeObserver: Any?
    @State private var duration: Double = 0
    @State private var speed = PlaybackSpeed.current
    @State private var failure: String?
    @Environment(\.openURL) private var openURL

    /// З media-посилання Drive збираємо звичайне «переглянути у Drive».
    private var driveFallbackURL: URL? {
        guard let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .path.split(separator: "/").last, url.host == "www.googleapis.com" else { return nil }
        return URL(string: "https://drive.google.com/file/d/\(id)/view")
    }

    var body: some View {
        Group {
            if let failure {
                // AVKit на провал малює лише перекреслений плей і мовчить.
                // Показуємо, що саме відповіло джерело.
                ContentUnavailableView {
                    Label("Не вдалося відтворити", systemImage: "play.slash")
                } description: {
                    ScrollView { Text(failure).font(.footnote).textSelection(.enabled) }
                } actions: {
                    // Запасний шлях: у Safari є куки Google, тож там запис
                    // відкриється навіть якщо вбудований плеєр не впорався.
                    if let fallback = driveFallbackURL {
                        Button("Відкрити у Drive") { openURL(fallback) }
                    }
                }
            } else {
                VideoPlayer(player: player)
            }
        }
        .task { await start() }
        .onDisappear(perform: stop)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { speedMenu }
        }
    }

    /// Стежить за станом айтема: .failed — привід сходити по причину.
    private func watchForFailure(_ item: AVPlayerItem) {
        Task { @MainActor in
            for await status in item.publisher(for: \.status).values where status == .failed {
                let reason = item.error?.localizedDescription ?? "невідома помилка"
                failure = headers.isEmpty
                    ? reason
                    : await DriveAccess.diagnose(url: url, headers: headers) + "\n\n(\(reason))"
                return
            }
        }
    }

    private var speedMenu: some View {
        Menu {
            Picker("Швидкість", selection: $speed) {
                ForEach(PlaybackSpeed.options, id: \.self) { Text(PlaybackSpeed.label($0)).tag($0) }
            }
        } label: {
            // Показуємо саме поточну швидкість: інакше з іконки не зрозуміло,
            // чи запис зараз грає прискорено. Label у тулбарі згортається до
            // самої іконки, тому складаємо напис руками.
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                Text(PlaybackSpeed.label(speed))
            }
            .font(.subheadline.weight(.semibold))
        }
        .onChange(of: speed) { _, new in
            PlaybackSpeed.current = new
            apply(speed: new)
        }
    }

    /// defaultRate — щоб і кнопка play (у плеєрі та на локскріні) стартувала
    /// з обраною швидкістю, а не поверталася на 1×.
    private func apply(speed: Double) {
        player.defaultRate = Float(speed)
        if player.timeControlStatus == .playing { player.rate = Float(speed) }
    }

    private func start() async {
        audio.activate()
        // AVURLAsset дозволяє підписати запити до джерела — без цього Drive
        // відповідає 401 і плеєр показує чорний екран.
        //
        // Відоме вузьке місце: якщо Drive колись почне відповідати редиректом,
        // заголовок може не пережити переходу — тоді знадобиться
        // AVAssetResourceLoaderDelegate, який підписує кожен запит окремо.
        let asset = headers.isEmpty
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        watchForFailure(item)
        player.replaceCurrentItem(with: item)
        audio.bindRemoteCommands(to: player)

        if let saved = PlaybackProgressStore.position(for: materialId), saved.resumeSeconds > 0 {
            await player.seek(to: CMTime(seconds: saved.resumeSeconds, preferredTimescale: 600))
        }
        apply(speed: speed)
        player.play()

        // Раз на 5 с — досить, щоб не загубити місце, і не смикає диск дарма.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main
        ) { time in
            let total = knownDuration()
            PlaybackProgressStore.save(seconds: time.seconds, duration: total, for: materialId)
            audio.updateNowPlaying(
                title: title, elapsed: time.seconds, duration: total, rate: player.rate)
        }
    }

    /// Тривалість стає відомою не одразу (у HLS — після завантаження плейлиста),
    /// тож питаємо айтем щоразу, а не один раз на старті.
    private func knownDuration() -> Double {
        guard let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return duration }
        duration = d
        return d
    }

    private func stop() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        PlaybackProgressStore.save(
            seconds: player.currentTime().seconds, duration: knownDuration(), for: materialId)
        player.pause()
        audio.deactivate()
    }
}

/// Вбудований веб-плеєр (YouTube embed / Drive preview) з inline-відтворенням.
struct WebPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.scrollView.isScrollEnabled = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if view.url != url { view.load(URLRequest(url: url)) }
    }
}
