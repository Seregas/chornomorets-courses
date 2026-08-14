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
                VideoPlayer(player: AVPlayer(url: u)).ignoresSafeArea(edges: .bottom)
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
