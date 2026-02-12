import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct PlayerView: UIViewControllerRepresentable {
    let url: URL
    let client: StalkerClient
    var startTime: Double? = nil
    var title: String? = nil
    var subtitle: String? = nil
    
    // New: Overlay Data
    var relatedEpisodes: [Movie]? = nil
    var currentEpisode: Movie? = nil // To identify current position for auto-play
    var onSelectEpisode: ((Movie) -> Void)? = nil // To play new episode
    var onMoreEpisodes: (() -> Void)? = nil // To close player and go back
    
    var onProgress: ((Double, Double) -> Void)? = nil
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("DEBUG: PlayerView makeUIViewController. URL: \(url)")
        let controller = CustomAVPlayerViewController()
        controller.coordinator = context.coordinator
        
        // Ensure audio plays even if silent switch is on (IMPORTANT)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("DEBUG: Failed to set audio session: \(error)")
        }
        
        let item = createPlayerItem(for: url)
        
        // Debug Observer
        context.coordinator.itemObserver = item.observe(\.status) { item, _ in
            if item.status == .readyToPlay {
                 print("DEBUG: PlayerItem Ready.")
                 print("DEBUG: Presentation Size: \(item.presentationSize)")
                 
                 // Inspect Asset Tracks (Source)
                 Task {
                     do {
                         let tracks = try await item.asset.load(.tracks)
                         print("DEBUG: Asset Source Tracks: \(tracks.map { "\($0.mediaType.rawValue)" })")
                     } catch {
                         print("DEBUG: Failed to load asset tracks: \(error)")
                     }
                 }
                 
                 // Inspect Player Item Tracks (Selected)
                 print("DEBUG: Item Tracks (Selected): \(item.tracks.map { "\($0.assetTrack?.mediaType.rawValue ?? "Unknown"): Enabled=\($0.isEnabled)" })")
                 
            } else if item.status == .failed {
                print("DEBUG: PlayerItem FAILED (Status): \(String(describing: item.error?.localizedDescription))")
            }
            
            // ALWAYS Print Logs to catch non-fatal streaming errors
            if let errorLog = item.errorLog() {
                print("DEBUG: Error Log Events: \(errorLog.events.map { "\($0.date): \($0.errorComment ?? "No Comment") (Code: \($0.errorStatusCode))" })")
            }
            if let accessLog = item.accessLog() {
                print("DEBUG: Access Log Events (Last): \(accessLog.events.last.map { "Observed Bitrate: \($0.observedBitrate), Bytes: \($0.numberOfBytesTransferred)" } ?? "None")")
            }
        }
        
        // Debug: Observe Presentation Size changes
        context.coordinator.presentationSizeObserver = item.observe(\.presentationSize) { item, _ in
            print("DEBUG: Presentation Size Changed: \(item.presentationSize)")
        }
        
        // Auto-Play: Verify completion

        
        // Better approach for Observer: Use Coordinator to handle notification
        let player = AVPlayer(playerItem: item)
        controller.player = player
        context.coordinator.currentURL = url
        
        // Assign Coordinator as delegate or just let it manage observers? 
        // We will register the observer in the Coordinator or handle it here passing context logic.
        // Re-doing the observer block to use context safely
        NotificationCenter.default.removeObserver(context.coordinator) // Safety
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            print("DEBUG: AVPlayerItemDidPlayToEndTime notification received.")
            // Trigger Auto-Play Logic
            context.coordinator.handleVideoCompletion()
        }
        
        // Metadata Injection
        var metadata: [AVMetadataItem] = []
        if let title = title {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierTitle
            item.value = title as NSString
            item.extendedLanguageTag = "und"
            metadata.append(item)
        }
        if let subtitle = subtitle {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierDescription
            item.value = subtitle as NSString
            item.extendedLanguageTag = "und"
            metadata.append(item)
        }
        player.currentItem?.externalMetadata = metadata
        
        // Seek to Start Time
        if let start = startTime, start > 0 {
            let targetTime = CMTime(seconds: start, preferredTimescale: 1)
            player.seek(to: targetTime) { _ in 
                 player.play()
            }
        } else {
            player.play()
        }
        
        // Custom Overlay
        controller.showsPlaybackControls = true
        
        // Capture client for closure
        let client = self.client
        
        // Setup Coordinator with Controller access for Overlay
        context.coordinator.parentController = controller
        context.coordinator.relatedEpisodes = relatedEpisodes
        context.coordinator.currentEpisode = currentEpisode
        context.coordinator.cancelledAutoPlay = false
        
        // Transport Bar - Custom Menu Items (Episodes)
        if let related = relatedEpisodes, !related.isEmpty {
            let episodesAction = UIAction(title: "Episodes", image: UIImage(systemName: "list.number")) { [weak controller] _ in
                guard let controller = controller else { return }
                
                // Create SwiftUI View
                let episodesView = PlayerEpisodesView(
                    episodes: related,
                    client: client,
                    onSelect: { episode in
                        // Callback to parent coordinator
                        print("DEBUG: PlayerEpisodesView onSelect called for \(episode.name)")
                        
                        // Dismiss the episodes sheet FIRST, then trigger update
                        controller.dismiss(animated: true) {
                             context.coordinator.onSelectEpisode?(episode)
                        }
                    },
                    onMoreEpisodes: {
                        context.coordinator.onMoreEpisodes?()
                        controller.dismiss(animated: true)
                    }
                )
                
                let hostingVC = UIHostingController(rootView: episodesView)
                hostingVC.view.backgroundColor = .clear
                hostingVC.modalPresentationStyle = .overFullScreen 
                
                controller.present(hostingVC, animated: true)
            }
            
            #if os(tvOS)
            controller.transportBarCustomMenuItems = [episodesAction]
            #endif
        }
        
        // Progress Observer - Reduced interval for smoother countdown (1s is fine for simple overlay)
        setupPeriodicObserver(for: player, client: client, context: context)
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Simplified log - Commented out to reduce spam during layout updates
        // print("DEBUG: PlayerView updateUIViewController. New URL: \(url)")
        
        // Update callbacks
        context.coordinator.onProgress = onProgress
        context.coordinator.onSelectEpisode = onSelectEpisode
        context.coordinator.onMoreEpisodes = onMoreEpisodes
        // Sync Data for Auto-Play
        context.coordinator.relatedEpisodes = relatedEpisodes
        context.coordinator.currentEpisode = currentEpisode
        
        // Seamless Playback Switching
        if context.coordinator.currentURL != url {
            print("DEBUG: URL changed, creating NEW AVPlayer to ensure clean pipeline")
            
            // Reset Flags
            context.coordinator.cancelledAutoPlay = false
            context.coordinator.overlayDismissed = false
            context.coordinator.hideOverlay()
            
            // Clean up old player and observer
            context.coordinator.itemObserver = nil
            context.coordinator.presentationSizeObserver = nil
            
            // Reset controls state
            uiViewController.showsPlaybackControls = true
            
            uiViewController.player?.pause()
            uiViewController.player?.replaceCurrentItem(with: nil)
            uiViewController.player = nil
            
            let item = createPlayerItem(for: url)
            
            // Debug Observer
            context.coordinator.itemObserver = item.observe(\.status) { item, _ in
                if item.status == .readyToPlay {
                     print("DEBUG: PlayerItem Ready (Switch).")
                     print("DEBUG: Presentation Size: \(item.presentationSize)")
                     print("DEBUG: Tracks: \(item.tracks.map { "\($0.assetTrack?.mediaType.rawValue ?? "Unknown"): Enabled=\($0.isEnabled)" })")
                } else if item.status == .failed {
                     print("DEBUG: PlayerItem FAILED (Switch): \(String(describing: item.error?.localizedDescription))")
                }
            }
            
            context.coordinator.presentationSizeObserver = item.observe(\.presentationSize) { item, _ in
                print("DEBUG: Presentation Size Changed (Switch): \(item.presentationSize)")
            }
            
            // Re-register Completion Observer for new Item
            NotificationCenter.default.removeObserver(context.coordinator)
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                print("DEBUG: AVPlayerItemDidPlayToEndTime notification received (Switched).")
                context.coordinator.handleVideoCompletion()
            }
            
            // Metadata Injection for new item
            var metadata: [AVMetadataItem] = []
            if let title = title {
                let mItem = AVMutableMetadataItem()
                mItem.identifier = .commonIdentifierTitle
                mItem.value = title as NSString
                mItem.extendedLanguageTag = "und"
                metadata.append(mItem)
            }
            if let subtitle = subtitle {
                let mItem = AVMutableMetadataItem()
                mItem.identifier = .commonIdentifierDescription
                mItem.value = subtitle as NSString
                mItem.extendedLanguageTag = "und"
                metadata.append(mItem)
            }
            item.externalMetadata = metadata
            
            // Create FRESH AVPlayer
            let newPlayer = AVPlayer(playerItem: item)
            uiViewController.player = newPlayer
            
            // Seek if needed
            if let start = startTime, start > 0 {
                let targetTime = CMTime(seconds: start, preferredTimescale: 1)
                newPlayer.seek(to: targetTime) { _ in
                     newPlayer.play()
                }
            } else {
                newPlayer.play()
            }
            
            // Re-attach Time Observer to NEW Player
            setupPeriodicObserver(for: newPlayer, client: client, context: context)
            
            context.coordinator.currentURL = url
        } else {
            // Ensure observer is attached even if URL unchanged (e.g. init)
            if context.coordinator.itemObserver == nil, let item = uiViewController.player?.currentItem {
                 context.coordinator.itemObserver = item.observe(\.status) { item, _ in
                    if item.status == .failed {
                        print("DEBUG: PlayerItem FAILED (Existing): \(String(describing: item.error?.localizedDescription))")
                    }
                }
            }
        }
    }
    
    // Extracted Helper to attach observer to any player instance
    private func setupPeriodicObserver(for player: AVPlayer, client: StalkerClient, context: Context) {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak client] time in
             guard let currentItem = player.currentItem, let client = client else { return }
             let duration = currentItem.duration.seconds
             guard duration > 0, duration.isFinite else { return }
             
             // Update Progress
             context.coordinator.onProgress?(time.seconds, duration)
             
             // Update Overlay Logic
             context.coordinator.updateOverlay(currentTime: time.seconds, duration: duration, client: client)
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        print("DEBUG: PlayerView dismantleUIViewController")
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
        NotificationCenter.default.removeObserver(coordinator)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var currentURL: URL?
        var onProgress: ((Double, Double) -> Void)?
        var onSelectEpisode: ((Movie) -> Void)?
        var onMoreEpisodes: (() -> Void)?
        var itemObserver: NSKeyValueObservation?
        var presentationSizeObserver: NSKeyValueObservation?
        
        // Auto-Play Data
        var relatedEpisodes: [Movie]?
        var currentEpisode: Movie?
        var cancelledAutoPlay = false // If user cancels, don't show again for this video
        var overlayDismissed = false // If user selects "Watch Credits", hide UI but still auto-play
        
        var overlayHostingController: UIHostingController<UpNextOverlay>?
        var parentController: CustomAVPlayerViewController?
        
        func handleVideoCompletion() {
            print("DEBUG: Handling Video Completion...")
            if cancelledAutoPlay {
                print("DEBUG: Auto-play cancelled by user. Doing nothing.")
                return
            }
            
            if !triggerNextEpisode() {
                print("DEBUG: No next episode found. Dismissing player.")
                // If it's a movie or last episode, dismiss the player
                onMoreEpisodes?() 
            }
        }
        
        
        @discardableResult
        private func triggerNextEpisode() -> Bool {
            guard let current = currentEpisode,
                  let related = relatedEpisodes,
                  !related.isEmpty else { return false }
            
            if let currentIndex = related.firstIndex(where: { $0.id == current.id }) {
                let nextIndex = currentIndex + 1
                if nextIndex < related.count {
                    let nextEpisode = related[nextIndex]
                    print("DEBUG: Auto-playing NEXT episode: \(nextEpisode.name)")
                    onSelectEpisode?(nextEpisode)
                    return true
                }
            }
            return false
        }
        
        func updateOverlay(currentTime: Double, duration: Double, client: StalkerClient) {
            guard let current = currentEpisode,
                  let related = relatedEpisodes,
                  !related.isEmpty,
                  let currentIndex = related.firstIndex(where: { $0.id == current.id }),
                  currentIndex + 1 < related.count else {
                return
            }
            
            let nextEpisode = related[currentIndex + 1]
            let remaining = duration - currentTime
            
            // Show if within 15 seconds, and not cancelled/dismissed, and not already very close to end
            if remaining <= 15 && remaining > 0.5 && !cancelledAutoPlay && !overlayDismissed {
                // Determine if we need to create or update
                if overlayHostingController == nil {
                    print("DEBUG: Showing Up Next Overlay (Presenting Modal)")
                    
                    let overlayView = UpNextOverlay(
                        nextEpisode: nextEpisode,
                        client: client,
                        remainingSeconds: remaining,
                        onPlayNow: { [weak self] in
                            self?.triggerNextEpisode()
                        },
                        onCancel: { [weak self] in
                            self?.hideOverlay()
                            self?.overlayDismissed = true
                        }
                    )
                    
                    let hosting = UIHostingController(rootView: overlayView)
                    hosting.view.backgroundColor = .clear
                    hosting.modalPresentationStyle = .overFullScreen
                    hosting.modalTransitionStyle = .crossDissolve
                    
                    // Presenting via modal ensures we capture focus completely and breaks away from AVPlayerVC's layout
                    if let parent = parentController {
                        parent.present(hosting, animated: true)
                        self.overlayHostingController = hosting
                    }
                } else {
                    // Update State
                    overlayHostingController?.rootView = UpNextOverlay(
                        nextEpisode: nextEpisode,
                        client: client,
                        remainingSeconds: remaining,
                        onPlayNow: { [weak self] in
                            self?.triggerNextEpisode()
                        },
                        onCancel: { [weak self] in
                            self?.hideOverlay()
                            self?.overlayDismissed = true
                        }
                    )
                }
            } else {
                // Hide if we actively seeked back or conditions not met
                if overlayHostingController != nil {
                     hideOverlay()
                }
            }
        }
        
        func hideOverlay() {
            if let hosting = overlayHostingController {
                print("DEBUG: Hiding Up Next Overlay")
                
                // Dismiss Modal
                hosting.dismiss(animated: true)
                overlayHostingController = nil
            }
        }
    }
    
    private func createPlayerItem(for url: URL) -> AVPlayerItem {
        print("DEBUG: Creating AVURLAsset with headers for \(url)")
        // Construct headers to mimic Smart STB / Stalker Client
        let headers: [String: String] = [
            "User-Agent": client.userAgent
        ]
        
        let options: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": headers
        ]
        
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        
        // Optimize for High Quality / 4K
        item.preferredPeakBitRate = 0 // Unlimited
        item.preferredForwardBufferDuration = 10 // Increase buffer
        if #available(iOS 14.0, tvOS 14.0, *) {
            item.startsOnFirstEligibleVariant = true
        }
        
        return item
    }
}

// Custom Player Controller to handle Focus Engine and Debugging
class CustomAVPlayerViewController: AVPlayerViewController {
    weak var coordinator: PlayerView.Coordinator?
    
    // No longer overriding preferredFocusEnvironments for the overlay since it is presented modally
    
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if let next = context.nextFocusedView {
            print("DEBUG: Focus moved to: \(next)")
        } else {
            print("DEBUG: Focus lost or moved to nil")
        }
    }
}
