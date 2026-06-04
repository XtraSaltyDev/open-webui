import AVFoundation
import Foundation

protocol AudioPlaybackControlling {
    func play(data: Data, fileName: String) throws
    func pause()
    func stop()
}

final class AVAudioPlaybackController: AudioPlaybackControlling {
    private var player: AVAudioPlayer?

    func play(data: Data, fileName: String) throws {
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        player.play()
        self.player = player
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
