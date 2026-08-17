import AVKit
import Combine
import SafariServices
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
        case .needsSignIn:
            SignInPrompt(retry: { Task { await resolve() } })
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
            // Грає плеєр самого Drive у Safari-контролері.
            //
            // Спроба тягнути вміст через Drive API впирається в 403
            // cannotDownloadFile: у налаштуваннях доступу до записів вимкнено
            // завантаження для глядачів. Це свідома політика власника — файли
            // платного курсу не мають розходитися, — і обійти її не можна й не
            // треба. Drive у такому режимі показує відео сам, не віддаючи байтів.
            //
            // Саме SFSafariViewController, а не WKWebView: він поділяє сесію з
            // Safari, тож користувач уже залогінений у Google і нічого не
            // вводить повторно.
            SafariView(url: URL(string: "https://drive.google.com/file/d/\(fileId)/view")!)
                .ignoresSafeArea()
        }
    }

    private var invalid: some View {
        ContentUnavailableView("Некоректне посилання", systemImage: "exclamationmark.triangle")
    }

    private func resolve() async {
        do {
            state = .loaded(try await repo.playback(materialId: materialId).descriptor)
        } catch let e as APIError where e.status == 403 {
            RemoteLog.send("playback.descriptor.denied", "material=\(materialId)")
            state = .failed("Це відео доступне лише акаунтам Google, яким надано доступ. Підключіть потрібний акаунт у Налаштуваннях.")
        } catch {
            RemoteLog.send("playback.descriptor.error", "material=\(materialId) \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }
}

/// Плеєр для `direct`-джерела: продовжує з місця, де зупинилися минулого разу,
/// і дописує позицію під час перегляду. Записи по дві години — починати їх
/// щоразу з нуля означає щоразу шукати те місце вручну.
///
/// Для youtube/drive позиція не зберігається: там грає веб-в'ю, чий стан нам не
/// видно. Тягнути вміст Drive через AVPlayer не вийде — власник вимкнув
/// завантаження для глядачів, і це свідома політика, а не перешкода.
struct DirectVideoPlayer: View {
    let url: URL
    let materialId: String
    let title: String

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

    /// Провал буває трьох видів, і .failed ловить лише один із них:
    ///  - айтем не завантажився взагалі → status == .failed;
    ///  - почав грати й обірвався → failedToPlayToEndTime;
    ///  - AVFoundation пише в errorLog HTTP-код, нічого не змінюючи в status —
    ///    саме там видно 401/403 від джерела.
    private func watchForFailure(_ item: AVPlayerItem) {
        Task { @MainActor in
            for await status in item.publisher(for: \.status).values where status == .failed {
                await report(item, reason: item.error?.localizedDescription ?? "status == failed")
                return
            }
        }
        Task { @MainActor in
            for await note in NotificationCenter.default.publisher(
                for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item).values {
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                await report(item, reason: error?.localizedDescription ?? "failedToPlayToEnd")
                return
            }
        }
        Task { @MainActor in
            for await _ in NotificationCenter.default.publisher(
                for: AVPlayerItem.newErrorLogEntryNotification, object: item).values {
                await report(item, reason: "newErrorLogEntry")
                return
            }
        }
    }

    /// Збирає все, що знає AVFoundation, питає джерело напряму — і показує
    /// це на екрані та відправляє на сервер.
    @MainActor private func report(_ item: AVPlayerItem, reason: String) async {
        guard failure == nil else { return }

        var parts = ["Причина: \(reason)"]
        if let log = item.errorLog() {
            for entry in log.events.suffix(3) {
                parts.append(
                    "HTTP \(entry.errorStatusCode) · \(entry.errorComment ?? "без коментаря")")
            }
        }
        let text = parts.joined(separator: "\n\n")
        failure = text
        player.pause()
        RemoteLog.send("playback.failed", "material=\(materialId)\n\(text)")
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
        // Сюди потрапляють лише відкриті джерела: Drive і YouTube грають
        // власними плеєрами у веб-в'ю, тож підписувати запити нічим і нікому.
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        watchForFailure(item)
        player.replaceCurrentItem(with: item)
        audio.bindRemoteCommands(to: player)

        if let saved = PlaybackProgressStore.position(for: materialId), saved.resumeSeconds > 0 {
            await player.seek(to: CMTime(seconds: saved.resumeSeconds, preferredTimescale: 600))
        }
        apply(speed: speed)
        player.play()
        RemoteLog.send(
            "playback.start",
            "material=\(materialId) host=\(url.host ?? "?")")

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

/// Плеєр Drive у Safari-контролері: ділить сесію з Safari, тож окремий вхід
/// у Google не потрібен.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Вбудований веб-плеєр (YouTube embed) з inline-відтворенням.
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
