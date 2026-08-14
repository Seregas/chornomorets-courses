import AVFoundation
import MediaPlayer

/// Швидкість відтворення — наскрізне налаштування, а не властивість конкретного
/// запису: хто слухає лекції на 1.5×, слухає так усі.
enum PlaybackSpeed {
    static let options: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    private static let key = "playback_speed"

    static var current: Double {
        get {
            let v = UserDefaults.standard.double(forKey: key)
            return options.contains(v) ? v : 1
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// 1 → «1×», 1.25 → «1.25×».
    static func label(_ speed: Double) -> String { String(format: "%g×", speed) }
}

/// Робить із плеєра «подкаст»: звук не глухне на заблокованому екрані, керування
/// зʼявляється в Пункті керування та на локскріні. Двогодинний запис слухають
/// у машині й на прогулянці — дивитися в екран для цього не потрібно.
@MainActor
final class PlayerAudioController {
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private weak var player: AVPlayer?

    /// Категорія .playback = грає з вимкненим дзвінком і в фоні (разом із
    /// UIBackgroundModes: audio в Info.plist).
    func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    func deactivate() {
        removeCommandTargets()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        player = nil
    }

    /// Кнопки на локскріні: play/pause і перемотка на 15 с — рівно те, чим
    /// користуються, слухаючи лекцію.
    func bindRemoteCommands(to player: AVPlayer) {
        self.player = player
        removeCommandTargets()
        let center = MPRemoteCommandCenter.shared()

        add(center.playCommand) { [weak player] _ in
            player?.rate = Float(PlaybackSpeed.current)
            return .success
        }
        add(center.pauseCommand) { [weak player] _ in
            player?.pause()
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        add(center.skipForwardCommand) { [weak self] _ in self?.skip(by: 15) ?? .commandFailed }
        add(center.skipBackwardCommand) { [weak self] _ in self?.skip(by: -15) ?? .commandFailed }
        add(center.changePlaybackPositionCommand) { [weak player] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            player?.seek(to: CMTime(seconds: e.positionTime, preferredTimescale: 600))
            return .success
        }
    }

    /// Те, що видно на локскріні. Оновлюється з тим же тактом, що й позиція.
    func updateNowPlaying(title: String, elapsed: Double, duration: Double, rate: Float) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func skip(by seconds: Double) -> MPRemoteCommandHandlerStatus {
        guard let player else { return .commandFailed }
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        return .success
    }

    private func add(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        commandTargets.append((command, command.addTarget(handler: handler)))
    }

    private func removeCommandTargets() {
        for (command, target) in commandTargets { command.removeTarget(target) }
        commandTargets = []
    }
}
