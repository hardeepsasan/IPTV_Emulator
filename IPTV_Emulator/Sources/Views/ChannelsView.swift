import SwiftUI

struct ChannelsView: View {
    @ObservedObject var stalkerClient: StalkerClient
    @ObservedObject var prefs = PreferenceManager.shared
    
    // Data State
    @State private var categories: [Category] = []
    @State private var preloadedChannels: [String: [Channel]] = [:]
    @State private var channelsByGenre: [String: [Channel]] = [:]
    
    // UI State
    @State private var featuredChannel: Channel?
    @State private var focusedChannel: Channel?
    @State private var displayedChannel: Channel? // Stabilized display state
    @State private var selectedCategoryId: String?
    
    @Binding var selectedStreamURL: URL?
    
    // Preview State
    @State private var previewURL: URL?
    @State private var previewTask: Task<Void, Never>?
    @State private var isNavigatingToPlayer: Bool = false // Prevents preview race conditions
    
    
    // EPG State
    @State private var currentEPG: [EPGEvent] = []
    @State private var epgTask: Task<Void, Never>?
    
    // Favorites Storage
    // Legacy: Comma separated IDs (kept for sync/migration)
    @AppStorage("favorite_channel_ids_v2") private var favoriteChannelIDsString: String = ""
    // New: Full Object Persistence
    @AppStorage("favorite_channels_json_v1") private var favoriteChannelsJSON: Data = Data()
    
    // Force TabBar Visibility State
    @State private var tabbarVisibility: Visibility = .visible
    
    // Disclaimer (Global)
    // @State private var showDisclaimer = true
    
    var body: some View {
        NavigationView {
             ZStack(alignment: .top) {
                 
                 ZStack(alignment: .topLeading) {
                     // Layer 1: Scrollable Content
                     ScrollViewReader { scrollProxy in
                         ScrollView(.vertical, showsIndicators: false) {
                             LazyVStack(alignment: .leading, spacing: 40) {
                                 // Padding to push content down as requested
                                 Color.clear.frame(height: 20)
                                 
                                 // 1. Favorites Section
                                 let favs = getFavoriteChannels()
                                 if !favs.isEmpty {
                                     VStack(alignment: .leading) {
                                         HStack(spacing: 6) {
                                             Image(systemName: "heart.fill")
                                                 .foregroundColor(.red)
                                             Text("Favorites")
                                                 .font(.headline)
                                                 .shadow(color: .black, radius: 2)
                                         }
                                          .padding(.leading, 50)
                                          
                                          ScrollView(.horizontal, showsIndicators: false) {
                                             LazyHStack(alignment: .top, spacing: 40) {
                                                 ForEach(favs) { channel in
                                                     FocusableChannelButton(
                                                         channel: channel,
                                                         client: stalkerClient,
                                                         categoryTitle: "Favorites", // Context for fallback
                                                         isFavorite: true,
                                                         onFocus: {
                                                             self.focusedChannel = channel
                                                             self.selectedCategoryId = "favorites"
                                                         },
                                                         onSelect: {
                                                            self.focusedChannel = channel
                                                            playChannel(channel)
                                                        },
                                                         onToggleFavorite: { toggleFavorite(channel) }
                                                     )
                                                 }
                                             }
                                             .padding(.horizontal, 50)
                                             .padding(.vertical, 20)
                                          }
                                     }
                                     .focusSection()
                                     .id("favorites")
                                 }
                                 
                                 // 2. Categories
                                 ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                                     LazyChannelRow(
                                         category: category,
                                         client: stalkerClient,
                                         shouldDebounce: index >= 3, // Skip delay for top 3 rows
                                         initialChannels: preloadedChannels[category.id],
                                         onFocus: { channel in
                                             self.focusedChannel = channel
                                             self.selectedCategoryId = category.id
                                         },
                                         onSelect: { channel in
                                             self.focusedChannel = channel
                                             playChannel(channel)
                                         },
                                         onToggleFavorite: { channel in
                                             toggleFavorite(channel)
                                         },
                                         isChannelFavorite: { id in isFavorite(id) }
                                     )
                                     .id(category.id)
                                 }
                                 
                                 // Spacer for bottom overscan
                                 Color.clear.frame(height: 100)
                             }
                         }
                         .onChange(of: selectedCategoryId) { newId in
                             if let id = newId {
                                 withAnimation(.spring(response: 1.0, dampingFraction: 1.0)) {
                                     scrollProxy.scrollTo(id, anchor: .top)
                                 }
                             }
                         }
                     } // End ScrollProxy
                     
                     .safeAreaInset(edge: .top) {
                          Color.clear.frame(height: 490)
                     }
                     .ignoresSafeArea(edges: [.bottom, .horizontal])
                     
                     // Layer 2: Fixed Header Content
                     Group {
                         Color.black
                             .frame(height: 380)
                             .padding(.top, 110)
                             .frame(maxWidth: .infinity, alignment: .top)
                             .edgesIgnoringSafeArea(.top)
                             
                         if let channel = displayedChannel ?? featuredChannel {
                             // Banner Image (Using Logo or placeholder for now, maybe stream preview later)
                             ZStack {
                                 Color.black
                                 if let logoURL = channel.getLogoURL(baseURL: stalkerClient.portalURL) {
                                      AuthenticatedImage(url: logoURL, client: stalkerClient)
                                         .aspectRatio(contentMode: .fit)
                                         .frame(maxWidth: 600, maxHeight: 300)
                                         .opacity(0.5)
                                         .blur(radius: 20) // Blur the logo for background effect
                                         
                                      AuthenticatedImage(url: logoURL, client: stalkerClient)
                                         .aspectRatio(contentMode: .fit)
                                          .frame(height: 150)
                                          .shadow(radius: 10)
                                 }
                             }
                             .frame(height: 320)
                             .padding(.top, 110)
                             .frame(maxWidth: .infinity, alignment: .top)
                             .clipped()
                             .edgesIgnoringSafeArea(.top)
                             .overlay(
                                 LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                             )
                             .id(channel.id)
                             .background(Color.black)
                             .animation(.easeInOut(duration: 0.5), value: channel.id)
                         }
                     }
                     .zIndex(50)
                     
                     // Layer 3: Header Text
                      ChannelInfoTray(channel: displayedChannel ?? featuredChannel, client: stalkerClient, epgEvents: currentEPG)
                         .background(
                              LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                         )
                         .padding(.top, 110)
                         .allowsHitTesting(false)
                         .zIndex(100)
                         
                     // Layer 3.5: Preview Window
                     // Layer 3.5: Preview Window & Progress
                     VStack(alignment: .leading, spacing: 8) {
                         ZStack {
                             Color.black // Placeholder background
                             
                             if let url = previewURL {
                                 ChannelPreviewView(url: url)
                                     .transition(.opacity)
                             }
                         }
                         .frame(width: 620, height: 300) // Reduced Height (-50px)
                         .cornerRadius(12)
                         .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                         )
                         .shadow(radius: 10)
                         
                         // PROGRESS BAR (Under Video)
                         if !currentEPG.isEmpty,
                            let currentEvent = currentEPG.first(where: {
                                guard let start = $0.startTimeDate, let end = $0.endTimeDate else { return false }
                                return Date() >= start && Date() < end
                            }),
                            let start = currentEvent.startTimeDate,
                            let end = currentEvent.endTimeDate {
                             
                             let total = end.timeIntervalSince(start)
                             let elapsed = Date().timeIntervalSince(start)
                             let progress = min(max(elapsed / total, 0), 1)
                             
                             HStack {
                                 Text(currentEvent.formattedTimeRange)
                                     .font(.system(size: 12)) // Reduced font size
                                     .foregroundColor(.cyan)
                                 
                                 ProgressBar(value: progress, color: .cyan)
                                     .frame(height: 4)
                             }
                             .frame(width: 620) // Match video width
                         }
                     }
                     .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                     .padding(.top, 170) // Moved down by 30px (140 -> 170)
                     .padding(.trailing, 80)
                     .zIndex(150)
                         
                     // Layer 4: Ghost Focus Bridge
                     Button(action: {}) {
                         Color.clear.frame(height: 320)
                     }
                     .padding(.top, 110)
                     .buttonStyle(.plain)
                     .opacity(0.001)
                     .accessibilityLabel("Menu Bridge")
                     .ignoresSafeArea()
                 }
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
                  .task {
                      if categories.isEmpty {
                          if !stalkerClient.hasShownDisclaimer {
                              async let loading: () = loadData()
                              async let timer = try? Task.sleep(nanoseconds: 2 * 1_000_000_000)
                              _ = await (loading, timer)
                              withAnimation { stalkerClient.hasShownDisclaimer = true }
                          } else {
                              await loadData()
                          }
                      } else {
                          await loadData()
                      }
                  }
                 .background(Color.black)
                 .edgesIgnoringSafeArea(.all)
                 .onChange(of: focusedChannel) { newChannel in
                      print("DEBUG: onChange(focusedChannel) FIRED. Channel: \(newChannel?.name ?? "nil")")
                      
                      // 1. Update UI (Immediate)
                      if let newChannel = newChannel {
                          withAnimation { displayedChannel = newChannel }
                      }
                      
                      loadPreview(for: newChannel)
                 }
                 .onChange(of: selectedStreamURL) { newUrl in
                     if newUrl == nil {
                         print("DEBUG: Fullscreen player dismissed. Resuming preview.")
                         isNavigatingToPlayer = false
                         // Resume preview for currently focused channel
                         if let channel = focusedChannel {
                             loadPreview(for: channel)
                         }
                     }
                 }
                 .toolbar(tabbarVisibility, for: .tabBar)
                 .onAppear { 
                     tabbarVisibility = .visible 
                     // Restore preview if we have a focused channel but no video (e.g. returning from fullscreen)
                     // Restore preview if we have a focused channel but no video (e.g. returning from fullscreen)
                     if let channel = focusedChannel, previewURL == nil {
                         print("DEBUG: View appeared, restoring preview for \(channel.name)")
                         isNavigatingToPlayer = false // Reset navigation flag
                         loadPreview(for: channel)
                     } else {
                         isNavigatingToPlayer = false
                     }
                 }
                                  if !stalkerClient.hasShownDisclaimer {
                      DisclaimerLoadingView()
                          .zIndex(200)
                          .transition(.opacity)
                  }
             }
        }
        .navigationViewStyle(.stack)
    }
    
    @State private var favoriteChannels: [Channel] = []

    // MARK: - Logic
    
    private func loadPreview(for newChannel: Channel?) {
        guard !isNavigatingToPlayer else {
            print("DEBUG: Skipping preview load - Navigating to player")
            return
        }

        // 2. Debounce Preview Fetch
        previewTask?.cancel()
        previewURL = nil // Clear previous
        
        guard let channel = newChannel else {
            print("DEBUG: newChannel is nil, returning.")
            return
        }
        
        previewTask = Task {
             print("DEBUG: Preview Task STARTED for \(channel.name)")
             // Wait 0.5 second before fetching to avoid spamming during scroll
             try? await Task.sleep(nanoseconds: 500_000_000)
             
             // Re-check navigation state after sleep
             if isNavigatingToPlayer {
                 print("DEBUG: Preview Task aborted - User navigated to player")
                 return
             }

             if Task.isCancelled {
                 print("DEBUG: Preview Task CANCELLED for \(channel.name)")
                 return
             }
            
             print("DEBUG: 0.5s Debounce passed. Starting EPG & Preview fetch for channel: \(channel.id)")
  
             // Fetch EPG
             do {
                 // 1. Try Full EPG first
                 var epg = try await stalkerClient.getEPG(channelId: channel.id)
                 
                 // 2. Fallback to Short EPG if empty
                 if epg.isEmpty {
                      print("DEBUG: Full EPG empty for \(channel.name). Trying Short EPG...")
                      epg = try await stalkerClient.getShortEPG(channelId: channel.id)
                 }
                 
                 print("DEBUG: EPG Fetch successful. Events count: \(epg.count)")
                 await MainActor.run {
                     self.currentEPG = epg
                 }
             } catch {
                 print("DEBUG: EPG Fetch failed: \(error)")
             }
            
            // 2b. Fetch Stream Link
            // Use a throw-away check or just fetch
            do {
                if Task.isCancelled { return }
                let link = try await stalkerClient.createLink(type: "itv", cmd: channel.cmd)
                if !link.isEmpty, let url = URL(string: link) {
                    await MainActor.run {
                        withAnimation {
                            self.previewURL = url
                        }
                    }
                }
            } catch {
                print("Preview fetch failed: \(error)")
            }
        }
    }
    
    @MainActor
    private func loadData() async {
        print("ChannelsView: loadData called.")
        do {
            // 1. Load Categories
            let cats = try await stalkerClient.getCategories(type: "itv")
            if cats.isEmpty { throw NSError(domain: "App", code: -1, userInfo: nil) }
            
            // Sort
            // Sort (Removed as per user request)
            // let order = prefs.channelCategoryOrder
            // let sortedCats = ...
            
            let filtered = cats.filter { prefs.isCategoryVisible($0.id) }
            
            // Prefetch Channels for Top 3 Categories
            var preloadResults: [String: [Channel]] = [:]
            let topCategories = Array(filtered.prefix(3))
            
            await withTaskGroup(of: (String, [Channel]?).self) { group in
               for cat in topCategories {
                   group.addTask {
                       do {
                           // Fetch just 1 page (same as initial load)
                           let channels = try await stalkerClient.getChannels(categoryId: cat.id, startPage: 1, pageLimit: 2) // Match initial fetch limit? 1 page? 
                           // Movies used 2. Let's start with 1 page for now as it loads fast.
                           // Actually 1 page is usually enough for a viewport.
                           return (cat.id, channels)
                       } catch {
                           return (cat.id, nil)
                       }
                   }
               }
               
               for await (catId, channels) in group {
                   if let channels = channels {
                       preloadResults[catId] = channels
                   }
               }
            }
            
            self.preloadedChannels = preloadResults
            self.categories = filtered
            
            // TEMP DEBUG: SCAN for EPG on startup
            Task {
                 try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2s
                 print("DEBUG: Starting Auto-Scan for EPG...")
                 
                 var channelsToTest: [Channel] = []
                 // 1. Try first category
                 if let firstCat = self.categories.first {
                     if let chans = try? await stalkerClient.getChannels(categoryId: firstCat.id) {
                         channelsToTest = Array(chans.prefix(20))
                     }
                 }
                 // 2. Fallback to all
                 if channelsToTest.isEmpty {
                     if let chans = try? await stalkerClient.getChannels(categoryId: "*") {
                         channelsToTest = Array(chans.prefix(20))
                     }
                 }
                 
                 print("DEBUG: Scannable Channels Count: \(channelsToTest.count)")
                 
                 for channel in channelsToTest {
                     print("DEBUG: Auto-Scanning \(channel.name) (\(channel.id))...")
                     do {
                         // 1. Try Full EPG
                         var epg = try await stalkerClient.getEPG(channelId: channel.id)
                         
                         // 2. Fallback to Short EPG
                         if epg.isEmpty {
                             print("DEBUG: Full EPG empty for \(channel.name). Trying Short EPG...")
                             try? await Task.sleep(nanoseconds: 50_000_000) // Tiny delay
                             epg = try await stalkerClient.getShortEPG(channelId: channel.id)
                         }
                         
                         if !epg.isEmpty {
                             print("DEBUG: ✅ FOUND EPG! \(epg.count) events for \(channel.name)")
                             await MainActor.run {
                                 self.currentEPG = epg
                                 print("DEBUG: FIRST 3 EVENTS: \(epg.prefix(3))")
                                 // Auto-focus this channel to show the result
                                 self.focusedChannel = channel
                             }
                             return // Success!
                         } else {
                             print("DEBUG: ❌ Empty data (Full & Short) for \(channel.name)")
                         }
                     } catch {
                         print("DEBUG: Scan Error: \(error)")
                     }
                     try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                 }
                 print("DEBUG: Auto-Scan Complete. No EPG found.")
            }
            
            // 2. Load Favorites (Local)
             Task { await loadFavorites() } 
            
            // 3. Initial Pre-fetch to populate featured
            if let firstCat = self.categories.first {
                 if let chans = try? await stalkerClient.getChannels(categoryId: firstCat.id), let first = chans.first {
                     self.featuredChannel = first
                     self.focusedChannel = first
                     self.displayedChannel = first
                 }
            }
            
        } catch {
             print("Channels fallback to All.")
             let allCat = Category(id: "*", title: "All Channels", alias: "all")
             self.categories = prefs.isCategoryVisible("*") ? [allCat] : []
             // Task { await loadFavorites() }
        }
    }
    
    @MainActor
    private func loadFavorites() async {
        // Strategy: Load from JSON first (Fast, Offline)
        // If JSON is empty but IDs exist, try legacy fetch logic ONE TIME (Migration)
        
        // 1. Try JSON Load
        if !favoriteChannelsJSON.isEmpty {
            do {
                let savedChannels = try JSONDecoder().decode([Channel].self, from: favoriteChannelsJSON)
                self.favoriteChannels = savedChannels.sorted { $0.number < $1.number }
                print("DEBUG: Loaded \(savedChannels.count) favorites from persistence.")
                return 
            } catch {
                print("DEBUG: Failed to decode favorites JSON: \(error)")
            }
        }
        
        // 2. Fallback / Migration (Only if IDs exist but no JSON)
        guard !favoriteChannelIDsString.isEmpty else { return }
        print("DEBUG: Migrating legacy favorites...")
        
        do {
            // "all" or "*" depends on portal. StalkerClient usually handles fetching by ID.
            // If we assume the user has favorites, we want them. 
            // Let's try fetching category "*" which represents all.
            let allChannels = try await stalkerClient.getChannels(categoryId: "*")
            let favSet = getFavoriteSet()
            let matches = allChannels.filter { favSet.contains($0.id) }
            self.favoriteChannels = matches.sorted { $0.number < $1.number }
            
            // Save immediately to JSON for next time
            if !matches.isEmpty {
                if let data = try? JSONEncoder().encode(matches) {
                    favoriteChannelsJSON = data
                }
            }
        } catch {
            print("Failed to load favorites source: \(error)")
        }
    }
    
    private func playChannel(_ channel: Channel) {
        // Stop Preview Immediately
        print("ChannelsView: Stopping preview to play full screen")
        isNavigatingToPlayer = true // Block any pending previews

        previewTask?.cancel()
        previewURL = nil
        
        let cmd = channel.cmd
        print("Playing: \(channel.name)")
        Task {
            if let link = try? await stalkerClient.createLink(type: "itv", cmd: cmd), let url = URL(string: link) {
                await MainActor.run { self.selectedStreamURL = url }
            }
        }
    }
    
    // MARK: - Favorites Logic Helper
    private func getFavoriteSet() -> Set<String> {
        let ids = favoriteChannelIDsString.split(separator: ",").map { String($0) }
        return Set(ids)
    }
    
    private func isFavorite(_ id: String) -> Bool {
        return getFavoriteSet().contains(id)
    }
    
    private func toggleFavorite(_ channel: Channel) {
        // 1. Update ID Set (Legacy/Fast Lookup)
        var set = getFavoriteSet()
        let id = channel.id
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
        favoriteChannelIDsString = set.joined(separator: ",")
        
        // 2. Update Object List (Source of Truth for UI)
        if isFavorite(id) {
            // Add to list if not present
            if !favoriteChannels.contains(where: { $0.id == id }) {
                var newFavs = favoriteChannels
                newFavs.append(channel)
                favoriteChannels = newFavs.sorted { $0.number < $1.number }
            }
        } else {
            // Remove from list
            favoriteChannels.removeAll { $0.id == id }
        }
        
        // 3. Persist Full Objects
        do {
            let data = try JSONEncoder().encode(favoriteChannels)
            favoriteChannelsJSON = data
            print("DEBUG: Saved \(favoriteChannels.count) favorites to disk.")
        } catch {
            print("DEBUG: Failed to save favorites: \(error)")
        }
    }
    
    private func getFavoriteChannels() -> [Channel] {
        return favoriteChannels
    }
}

// MARK: - Subviews

private struct FocusableChannelButton: View {
    let channel: Channel
    let client: StalkerClient
    let categoryTitle: String? // [NEW]
    var isFavorite: Bool = false
    let onFocus: () -> Void
    let onSelect: () -> Void
    let onToggleFavorite: (() -> Void)? // Callback for context menu
    
    @FocusState private var isFocused: Bool
    
    // Default init for backward compatibility or strict init
    init(channel: Channel, client: StalkerClient, categoryTitle: String? = nil, isFavorite: Bool = false, onFocus: @escaping () -> Void, onSelect: @escaping () -> Void, onToggleFavorite: (() -> Void)? = nil) {
         self.channel = channel
         self.client = client
         self.categoryTitle = categoryTitle
         self.isFavorite = isFavorite
         self.onFocus = onFocus
         self.onSelect = onSelect
         self.onToggleFavorite = onToggleFavorite
    }
    
    var body: some View {
        Button(action: onSelect) {
            ChannelCard(
                channel: channel, 
                client: client, 
                categoryTitle: categoryTitle, // [NEW]
                isFocused: isFocused, 
                isFavorite: isFavorite
            )
            .frame(width: 200)
        }
        .buttonStyle(FlatButtonStyle())
        .focused($isFocused)
        .onChange(of: isFocused) { newValue in
            if newValue {
                print("DEBUG: FocusableChannelButton FOCUSED for \(channel.name)")
                onFocus()
            }
        }
        .contextMenu {
            if let toggle = onToggleFavorite {
                Button(action: toggle) {
                    Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "heart.slash" : "heart")
                }
            }
        }
    }
}

private struct LazyChannelRow: View {
    let category: Category
    @ObservedObject var client: StalkerClient
    let shouldDebounce: Bool
    let onFocus: (Channel) -> Void
    let onSelect: (Channel) -> Void
    let onToggleFavorite: (Channel) -> Void
    let isChannelFavorite: (String) -> Bool
    
    @State private var channels: [Channel]?
    @State private var isLoading = false
    @State private var page = 1
    @State private var hasMore = true
    
    init(category: Category, client: StalkerClient, shouldDebounce: Bool, initialChannels: [Channel]? = nil, onFocus: @escaping (Channel) -> Void, onSelect: @escaping (Channel) -> Void, onToggleFavorite: @escaping (Channel) -> Void, isChannelFavorite: @escaping (String) -> Bool) {
        self.category = category
        self.client = client
        self.shouldDebounce = shouldDebounce
        self.onFocus = onFocus
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
        self.isChannelFavorite = isChannelFavorite
        
        _channels = State(initialValue: initialChannels)
        if let initial = initialChannels {
            _hasMore = State(initialValue: !initial.isEmpty)
            _page = State(initialValue: 1) // Initial load is Page 1-2 usually
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if let channels = channels {
                if !channels.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(category.title)
                            .font(.headline)
                            .shadow(color: .black, radius: 2)
                            .padding(.leading, 50)
                        
                        let currentChannels = channels
                        let prefetchThreshold = 5
                        let triggerIndex = max(0, currentChannels.count - prefetchThreshold)
                        let triggerId = currentChannels.indices.contains(triggerIndex) ? currentChannels[triggerIndex].id : nil
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 40) {
                                ForEach(currentChannels) { channel in
                                    FocusableChannelButton(
                                        channel: channel,
                                        client: client,
                                        categoryTitle: category.title,
                                        isFavorite: isChannelFavorite(channel.id),
                                        onFocus: { onFocus(channel) },
                                        onSelect: { onSelect(channel) },
                                        onToggleFavorite: { onToggleFavorite(channel) }
                                    )
                                    .onAppear {
                                        // Pagination Trigger
                                        if hasMore {
                                            if channel.id == triggerId || (triggerId == nil && channel.id == currentChannels.last?.id) {
                                                Task { await fetchMore() }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 50)
                            .padding(.bottom, 20)
                            .padding(.top, 10) 
                        }
                    }
                    .focusSection()
                }
            } else {
                HStack {
                   Text(category.title)
                       .font(.headline)
                       .padding(.leading, 50)
                }
                .padding(.vertical, 20)
                .task { await fetchChannels() }
            }
        }
    }
    
    private func fetchChannels() async {
        guard channels == nil else { return }
        
        if shouldDebounce {
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
        }
        
        isLoading = true
        do {
            let fetched = try await client.getChannels(categoryId: category.id, startPage: 1, pageLimit: 2)
            await MainActor.run {
                self.channels = fetched
                self.hasMore = !fetched.isEmpty
                self.page = 2 // Since we fetched 2 pages
                isLoading = false
            }
        } catch {
            print("Lazy fetch failed for \(category.title): \(error)")
            isLoading = false
        }
    }
    
    private func fetchMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        
        let batchSize = 5
        let startPage = page + 1
        
        do {
            let fetched = try await client.getChannels(categoryId: category.id, startPage: startPage, pageLimit: batchSize)
            await MainActor.run {
                if fetched.isEmpty {
                    self.hasMore = false
                } else {
                    self.channels?.append(contentsOf: fetched)
                    self.page = startPage + batchSize - 1
                }
                self.isLoading = false
            }
        } catch {
            print("Fetch more failed: \(error)")
            isLoading = false
        }
    }
}
