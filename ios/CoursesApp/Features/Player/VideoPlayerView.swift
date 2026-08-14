import AVKit
import SwiftUI
import WebKit

/// Плеєр відіграє playback-дескриптор від бекенду. Тип джерела ховається за
/// дескриптором: direct → AVPlayer, youtube/drive → вбудований веб-плеєр.
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
                DirectVideoPlayer(url: u, materialId: materialId).ignoresSafeArea(edges: .bottom)
            } else { invalid }
        case .youtube(let videoId):
            WebPlayer(url: URL(string: "https://www.youtube.com/embed/\(videoId)?playsinline=1")!)
        case .googleDrive(let fileId):
            WebPlayer(url: URL(string: "https://drive.google.com/file/d/\(fileId)/preview")!)
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

    @State private var player = AVPlayer()
    @State private var timeObserver: Any?
    @State private var duration: Double = 0

    var body: some View {
        VideoPlayer(player: player)
            .task { await start() }
            .onDisappear(perform: stop)
    }

    private func start() async {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))

        if let saved = PlaybackProgressStore.position(for: materialId), saved.resumeSeconds > 0 {
            await player.seek(to: CMTime(seconds: saved.resumeSeconds, preferredTimescale: 600))
        }
        player.play()

        // Раз на 5 с — досить, щоб не загубити місце, і не смикає диск дарма.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main
        ) { time in
            PlaybackProgressStore.save(
                seconds: time.seconds, duration: knownDuration(), for: materialId)
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
