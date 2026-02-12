import SwiftUI
import AVKit

struct ChannelPreviewView: View {
    let url: URL
    
    @State private var player: AVPlayer?
    @State private var isMuted: Bool = false // Maybe false if user wants to hear it? User didn't specify. Usually previews are muted or lower volume. Let's keep it audible for now as user said "preview... will play".
    
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                setupPlayer()
            }
            .onChange(of: url) { newUrl in
                updatePlayer(with: newUrl)
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
    
    private func setupPlayer() {
        let newPlayer = AVPlayer(url: url)
        newPlayer.play()
        // newPlayer.isMuted = true // Uncomment if desired
        self.player = newPlayer
    }
    
    private func updatePlayer(with newUrl: URL) {
        // Debounce or check logic handled by parent, here we just switch
        let item = AVPlayerItem(url: newUrl)
        player?.replaceCurrentItem(with: item)
        player?.play()
    }
}
