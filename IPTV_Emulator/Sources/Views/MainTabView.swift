import SwiftUI

struct MainTabView: View {
    @ObservedObject var stalkerClient: StalkerClient
    @EnvironmentObject var playbackManager: PlaybackManager
    
    @State private var selection = 1 // Default to Movies
    @State private var settingsID = UUID()
    @State private var moviesID = UUID()
    @State private var playbackContext: PlaybackContext?
    
    // Binding adapter for views that still use simple URL
    var selectedURLBinding: Binding<URL?> {
        Binding(
            get: { playbackContext?.url },
            set: { url in
                if let url = url {
                    // Default context for simple URL (Live TV)
                    playbackContext = PlaybackContext(url: url)
                } else {
                    playbackContext = nil
                }
            }
        )
    }
    
    // Binding proxy to intercept tab re-selection
    var selectionBinding: Binding<Int> {
        Binding(
            get: { self.selection },
            set: { newValue in
                if newValue == 2 && self.selection == 2 {
                    // Search Tab Re-selected: Trigger Focus
                    print("DEBUG: Search Tab re-selected. Post notification.")
                    NotificationCenter.default.post(name: .focusSearchBar, object: nil)
                }
                
                if newValue == 1 && self.selection == 1 {
                    // Movies Tab Re-selected: Reset Navigation
                    print("DEBUG: Movies Tab re-selected. Resetting moviesID.")
                     self.moviesID = UUID()
                }
                
                // Update selection
                self.selection = newValue
                
                // Reset settings ID if leaving settings
                if newValue != 3 {
                    settingsID = UUID()
                }
            }
        )
    }
    
    var body: some View {
        TabView(selection: selectionBinding) {
            // Live TV Tab
            ChannelsView(stalkerClient: stalkerClient, selectedStreamURL: selectedURLBinding)
                .tabItem {
                    Label("Live TV", systemImage: "tv")
                        .symbolRenderingMode(.monochrome)
                }
                .tag(0)
            
            // Movies Tab
            MoviesView(stalkerClient: stalkerClient, refreshID: moviesID, playbackContext: $playbackContext)
                .tabItem {
                    Label("Movies", systemImage: "film")
                }
                .tag(1)
            
            // Search Tab
            SearchView(stalkerClient: stalkerClient, playbackContext: $playbackContext)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(2)
            
            // Settings Tab (Placeholder for now)
            SettingsView(client: stalkerClient)
                .id(settingsID) // Forces recreation when ID changes
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        // Removed .onChange(of: selection) as logic is now in the Binding setter
        .fullScreenCover(item: $playbackContext) { context in
            PlayerView(
                url: context.url,
                client: stalkerClient,
                startTime: context.startTime,
                title: context.title,
                subtitle: context.movie?.seriesName,
                relatedEpisodes: context.relatedEpisodes,
                currentEpisode: context.movie,
                onSelectEpisode: { episode in
                    // Fetch URL and Play Immediately
                    Task {
                        print("DEBUG: MainTabView onSelectEpisode: \(episode.name) (ID: \(episode.id))")
                        var cmd = episode.comm
                        
                        // If 'cmd' is missing (common for episodes in lists), fetch specific file info
                        // We check for seriesId and seasonId. If missing, we might be in a flat list or error state.
                        if (cmd == nil || cmd?.isEmpty == true), 
                           let sId = episode.seriesId, 
                           let seaId = episode.seasonId {
                            print("DEBUG: 'cmd' missing. Fetching episode files for Series \(sId), Season \(seaId), Ep \(episode.id)...")
                            do {
                                let files = try await stalkerClient.getEpisodeFiles(seriesId: sId, seasonId: seaId, episodeId: episode.id)
                                if let firstFile = files.first, let fileCmd = firstFile.comm {
                                    print("DEBUG: Found file info. Cmd: \(fileCmd)")
                                    cmd = fileCmd
                                } else {
                                     print("DEBUG: Fetched files but no valid cmd found.")
                                }
                            } catch {
                                print("DEBUG: Failed to fetch episode files: \(error)")
                            }
                        }
                        
                        guard let validCmd = cmd else {
                             print("DEBUG: No 'cmd' available to play episode. Aborting.")
                             return
                        }
                        
                        do {
                            let streamLink = try await stalkerClient.createLink(type: "vod", cmd: validCmd)
                            print("DEBUG: Generated stream link: \(streamLink)")
                            
                            if let url = URL(string: streamLink) {
                                // Resolve Redirect to ensure AVPlayer gets the final URL with correct context
                                let finalURL = await stalkerClient.resolveRedirect(url: url)
                                
                                // Update context to play new episode
                                // We reuse the same relatedEpisodes list so navigation persists
                                let newContext = PlaybackContext(
                                    id: context.id,
                                    url: finalURL,
                                    title: episode.name,
                                    movie: episode,
                                    relatedEpisodes: context.relatedEpisodes,
                                    startTime: playbackManager.getSavedTime(for: episode) ?? 0
                                )
                                
                                // Updating the state will trigger the player to reload with the new URL
                                await MainActor.run {
                                    self.playbackContext = newContext
                                    
                                    // Force immediate save so it appears in Continue Watching even if stopped quickly
                                    // Using dummy duration (will be corrected by first progress update)
                                    self.playbackManager.updateProgress(movie: episode, time: 1, duration: 100)
                                }
                            }
                        } catch {
                            print("Failed to play next episode: \(error)")
                        }
                    }
                },
                onMoreEpisodes: {
                    playbackContext = nil
                },
                onProgress: { time, duration in
                    if let movie = context.movie {
                        playbackManager.updateProgress(movie: movie, time: time, duration: duration)
                    }
                }

            )
            .ignoresSafeArea()
        }
        .task {
            // Start Search Indexer on App Launch
            // This ensures deep indexing runs regardless of which tab is selected first
            stalkerClient.buildSearchIndex()
        }
    }
}

extension Notification.Name {
    static let resetMoviesNav = Notification.Name("resetMoviesNav")
}
