import SwiftUI

struct MoviesView: View {


    var stalkerClient: StalkerClient
    @EnvironmentObject var watchlistManager: WatchlistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @ObservedObject var prefs = PreferenceManager.shared
    
    // Explicit refresh trigger
    var refreshID: UUID
    
    // Data State
    @State private var categories: [Category] = []
    @State private var preloadedMovies: [String: [Movie]] = [:]
    
    // UI State
    @State private var featuredMovie: Movie? // Initial fallback
    @State private var focusedMovie: Movie? // Driving the Tray
    @State private var displayedMovie: Movie? // Stabilized display state
    @State private var selectedMovie: Movie?
    @State private var selectedSeries: Movie?
    @Binding var playbackContext: PlaybackContext?
    
    // Scroll Focus State
    @State private var focusedCategoryId: String?
        
    // Force TabBar Visibility State
    @State private var tabbarVisibility: Visibility = .visible
    
    // Disclaimer (Managed by StalkerClient global state)
    // Manually managed because stalkerClient is not ObservedObject
    @State private var showDisclaimer = true
    
    // Logic to group episodes: Show only the most recent episode for a series
    var uniqueWatchingItems: [WatchingItem] {
        var seenSeries = Set<String>()
        var result: [WatchingItem] = []
        
        for item in playbackManager.watchingItems {
            // HYDRATE: Check if we have a fresher version in cache (with description)
            // If cached version exists and has description, use it. Prefer cached version generally.
            var freshMovie = stalkerClient.movieCache[item.movie.id] ?? item.movie
            
            // FIX: Fallback to Series Poster if Episode missing thumbnail
            if (freshMovie.poster == nil || freshMovie.poster?.isEmpty == true),
               let sId = freshMovie.seriesId, !sId.isEmpty,
               let series = stalkerClient.movieCache[sId],
               let sPoster = series.poster, !sPoster.isEmpty {
                freshMovie.poster = sPoster
            }
            
            // Check if it's an episode with a seriesId
            if let sId = freshMovie.seriesId, !sId.isEmpty {
                if !seenSeries.contains(sId) {
                    seenSeries.insert(sId)
                    let newItem = WatchingItem(id: item.id, movie: freshMovie, currentWaitTime: item.currentWaitTime, duration: item.duration, lastUpdated: item.lastUpdated)
                    result.append(newItem)
                }
            } else {
                // Movies are always unique
                let newItem = WatchingItem(id: item.id, movie: freshMovie, currentWaitTime: item.currentWaitTime, duration: item.duration, lastUpdated: item.lastUpdated)
                result.append(newItem)
            }
        }
        return result
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                // 1. Background Layer (Fixed)
                // 1. Background Layer Moved Inside to Mask Content
                
                ZStack(alignment: .topLeading) {
                    
                    // Layer 1: Scrollable Content
                    ScrollViewReader { scrollProxy in // 1. Wrap in ScrollViewReader
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 40) {
                            
                            // 0. SPACER REMOVED - Using Padding on ScrollView instead
                            
                            // 1. Continue Watching Section (Top Priority)
                            if !uniqueWatchingItems.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("Continue Watching")
                                        .font(.headline)
                                        .padding(.leading, 50)
                                        .shadow(color: .black, radius: 2)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(alignment: .top, spacing: 40) {
                                            ForEach(uniqueWatchingItems) { item in
                                                FocusableMovieButton(
                                                    movie: item.movie,
                                                    client: stalkerClient,
                                                    onFocus: { 
                                                        focusedMovie = item.movie
                                                        focusedCategoryId = "continue-watching-section" // Track Section
                                                    },
                                                    onSelect: { handleSelection(item.movie) }
                                                ) {
                                                    ZStack(alignment: .leading) {
                                                        Rectangle()
                                                            .fill(Color.gray.opacity(0.5))
                                                        Rectangle()
                                                            .fill(Color.red)
                                                            .frame(width: 250 * (item.currentWaitTime / item.duration))
                                                    }
                                                    .frame(height: 4)
                                                    .padding(.bottom, 12)
                                                    .padding(.horizontal, 8)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 50)
                                        .padding(.vertical, 20)
                                    }
                                }
                                .focusSection()
                                .id("continue-watching-section") // ID for scroller
                            }
                            
                            // 2. My List Section
                            if !watchlistManager.watchlist.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("My List")
                                        .font(.headline)
                                        .padding(.leading, 50)
                                        .shadow(color: .black, radius: 2)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(alignment: .top, spacing: 40) {
                                            ForEach(watchlistManager.watchlist) { movie in
                                                FocusableMovieButton(
                                                    movie: movie,
                                                    client: stalkerClient,
                                                    onFocus: { 
                                                        focusedMovie = movie 
                                                        focusedCategoryId = "mylist-section" // Track Section
                                                    },
                                                    onSelect: { handleSelection(movie) }
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 50)
                                        .padding(.vertical, 20)
                                    }
                                }
                                .focusSection()
                                .id("mylist-section") // ID for scroller
                            }
                            
                            // 3. All Categories
                            if !categories.isEmpty {
                                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                                    LazyMovieRow(
                                        category: category,
                                        client: stalkerClient,
                                        shouldDebounce: index >= 3,
                                        initialMovies: preloadedMovies[category.id]?.map { UniqueMovie(movie: $0) },
                                        titleSpacing: 20, // Restore exact tvOS breathing room
                                        movieCard: { movie in
                                            FocusableMovieButton(
                                                movie: movie,
                                                client: stalkerClient,
                                                onFocus: { 
                                                    self.focusedMovie = movie
                                                    self.focusedCategoryId = category.id
                                                },
                                                onSelect: { handleSelection(movie) }
                                            )
                                        },
                                        onSelect: { movie in
                                            handleSelection(movie)
                                        }
                                    )
                                    .id(category.id)
                                }
                            }
                            
                            // Spacer for bottom overscan
                            Color.clear.frame(height: 100)
                        }
                    }
                    .onChange(of: focusedCategoryId) { newId in
                        if let id = newId {
                            // Swift Spring Animation prevents "Jumpiness" by blending with system gesture
                            // ADJUSTED: Slower response (1.0) and Critical Damping (1.0) for "Gliding" feel w/ no bounce
                            withAnimation(.spring(response: 1.0, dampingFraction: 1.0)) {
                                scrollProxy.scrollTo(id, anchor: .top) // Align to TOP (Snap Title to Header)
                            }
                        }
                    }
                    } // End ScrollViewReader




                    // ADJUSTED to 440: Header ends at Y=430 (110+320). 440 gives 10px buffer. 600 was too large.
                    .safeAreaInset(edge: .top) {
                         Color.clear.frame(height: 440)
                    }
                    .ignoresSafeArea(edges: [.bottom, .horizontal]) // Ignore bottom/sides, but respect top for Menu access
                    // Removed safeAreaPadding as frame padding handles focus bounds strictly.
                    
                    // Layer 2: Fixed Header (Manual Placement)
                    // Layer 2: Fixed Header (Manual Placement)
                    // Layer 2: Fixed Header Background (Masks content)
                    // Layer 2: Fixed Header Background (Masks content)
                    Group {
                        // 1. ZStack Container for Layered Header
                        ZStack(alignment: .bottom) { // ALIGN CONTENT TO BOTTOM
                            if let movie = displayedMovie ?? featuredMovie {
                                // A. BACKGROUND LAYER (Blurred & Darkened)
                                // OPTIMIZATION: Use thumbnail size (200x300) to hit existing cache. Since it's potentially blurred, low-res is fine!
                                AuthenticatedImage(url: movie.getPosterURL(baseURL: stalkerClient.portalURL), targetSize: CGSize(width: 200, height: 300), client: stalkerClient)
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 430) // FULL HEIGHT (320 + 110)
                                    .frame(maxWidth: .infinity)
                                    .blur(radius: 50) // HEAVY BLUR
                                    .overlay(Color.black.opacity(0.4)) // Darken to make text pop
                                    .clipped()
                                    .zIndex(0) // Force Background Layer to Bottom
                                
                                // B. FOREGROUND LAYER (Seamless Left Side)
                                // OPTIMIZATION: Use Medium Size (400x600) to ensure quality but avoid 4K raw loads
                                AuthenticatedImage(url: movie.getPosterURL(baseURL: stalkerClient.portalURL), targetSize: CGSize(width: 400, height: 600), client: stalkerClient)
                                    .aspectRatio(contentMode: .fill) // Fill the left area
                                    .frame(width: 390, height: 430) // FIXED WIDTH: 390px, HEIGHT: 430px
                                    .clipped()
                                    .mask(
                                        LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: .black, location: 0.0),
                                                .init(color: .black, location: 0.5), // Solid half-way
                                                .init(color: .black.opacity(0.8), location: 0.7), // Start fade gently
                                                .init(color: .clear, location: 1.0) // Fully transparent at right edge
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading) // Align to Left
                                    .padding(.leading, 0) // No padding, flush left
                                    .zIndex(1) // Force Foreground Layer to Top
                            } else {
                                Image("AppBackground")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 430) // Full Height
                                    .frame(maxWidth: .infinity) // Flexible Width
                                    .blur(radius: 20)
                            }
                        }
                        .frame(height: 430) // Increased to cover top area
                        .frame(maxWidth: .infinity, alignment: .top)
                        .edgesIgnoringSafeArea(.top)
                        .background(Color.black)
                        .zIndex(50)
                    }
                    .zIndex(50) // Ensure Header Background stays ABOVE scrolling content (cards)

                    // Layer 3: Fixed Header Text
                    MovieInfoTray(movie: displayedMovie ?? featuredMovie, client: stalkerClient)
                        // Border removed
                        .background(
                             LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                        )
                        .padding(.top, 110) // Push down header text (Total 110px)
                        .padding(.leading, 350) // Push text to Right of Poster (Adjusted to avoid overlap)
                        .allowsHitTesting(false)
                        .zIndex(100)
                        
                    // Layer 4: Ghost Focus Bridge (Fixes Menu Access)
                    // This invisible button sits at the top. When scrollview is at top, focus moves here.
                    // From here, "Up" triggers the Menu.
                    Button(action: {}) {
                        Color.clear.frame(height: 320)
                    }
                    .padding(.top, 110) // Push ghost button down (Total 110px)
                    .buttonStyle(.plain)
                    .opacity(0.001) // Invisible but focusable
                    .accessibilityLabel("Menu Bridge")
                    .ignoresSafeArea()
                    
                    // Layer 5: Info Banners
                    VStack(spacing: 0) {
                        // Removed local OfflineNotificationView (Moved to Global Root)
                        
                        if let expiry = stalkerClient.subscriptionExpiration {
                            let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 100
                            if days < 10 {
                                Text(days < 0 ? "Subscription Expired" : "Subscription Expires in \(days) days")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(days < 0 ? Color.red : Color.yellow)
                            }
                        }
                    }
                    .zIndex(999) // Top of ZStack
                    .transition(.move(edge: .top))
                }
                // .ignoresSafeArea(.all) // REMOVED: This was likely causing the TabBar to be hidden/unresponsive
            .frame(maxWidth: .infinity, maxHeight: .infinity) // CRITICAL: Lock window size
            .background(
                VStack {
                    NavigationLink(isActive: Binding(
                        get: { selectedSeries != nil },
                        set: { if !$0 { selectedSeries = nil } }
                    )) {
                        if let series = selectedSeries {
                            SeriesDetailView(series: series, stalkerClient: stalkerClient, playbackContext: $playbackContext)
                        } else { EmptyView() }
                    } label: { EmptyView() }
                    .hidden()
                    .frame(width: 0, height: 0)
                    .buttonStyle(.plain)

                    NavigationLink(isActive: Binding(
                        get: { selectedMovie != nil },
                        set: { if !$0 { selectedMovie = nil } }
                    )) {
                        if let movie = selectedMovie {
                            MovieDetailView(movie: movie, stalkerClient: stalkerClient, playbackContext: $playbackContext)
                        } else { EmptyView() }
                    } label: { EmptyView() }
                    .hidden()
                    .frame(width: 0, height: 0)
                    .buttonStyle(.plain)
                }
                .frame(width: 0, height: 0)
            )
            // .ignoresSafeArea(.all) // REMOVED: Fix Menu Disappearance. Allow TabBar to reserve space/interact.
            .task(id: prefs.visibleCategoryIds) {
                // Initial Load Logic with Minimum Duration
                if categories.isEmpty {
                    print("DEBUG: MoviesView Task Started. Network Connected: \(networkMonitor.isConnected)")
                    // Check Global Disclaimer State
                    if showDisclaimer {
                        async let loading: () = loadData()
                        // Ensure minimum 5s display time if needed, OR just wait for load
                        try? await Task.sleep(nanoseconds: 3_000_000_000) // Reduced to 3s for snappier experience if load is fast
                        await loading
                        
                        withAnimation {
                            showDisclaimer = false
                            stalkerClient.hasShownDisclaimer = true
                        }
                    } else {
                        await loadData()
                    }
                } else {
                    await loadData()
                }
            }
            .background(Color.black)
            .edgesIgnoringSafeArea(.all)
            .task(id: focusedMovie) {
                guard let newMovie = focusedMovie else { return }
                
                // DEBOUNCE UI UPDATE + FETCH
                // Wait 800ms (Increased from 300ms). If 'focusedMovie' changes during this time, the task is CANCELLED.
                // This prevents the heavy Header (AuthenticatedImage + Gradients) from re-rendering during rapid scroll.
                do {
                    // 1. Debounce (0.8s) - Only fetch if user LOITERS on an item.
                    try await Task.sleep(nanoseconds: 800_000_000)
                    
                    // Task wasn't cancelled. Now safe to update the UI.
                    withAnimation {
                        displayedMovie = newMovie
                    }
                    
                    // Fetch Details if missing (and description is empty)
                    // OPTIMIZATION: Check Memory/Index Cache first
                    if newMovie.description == nil || newMovie.description?.isEmpty == true {
                        // 1. Check if we already have a better version in cache
                        // DEBUG: Cache Performance Logging
                        let startLookup = Date()
                        let cached = stalkerClient.movieCache[newMovie.id]
                        let diff = Date().timeIntervalSince(startLookup) * 1000
                        if diff > 5 { // Only log slow lookups (> 5ms)
                             print("DEBUG: Slow Cache Lookup: \(String(format: "%.2f", diff))ms for \(newMovie.id)")
                        }
                        
                        if let cached = cached,
                           let desc = cached.description, !desc.isEmpty {
                            withAnimation {
                                displayedMovie = cached
                            }
                        } 
                        // 2. Check VOD Info Cache (Detail Cache)
                        else if let cachedDetail = stalkerClient.vodInfoCache[newMovie.id] {
                            withAnimation {
                                displayedMovie = cachedDetail
                            }
                        }
                        // 3. Network Fallback (DISABLED FOR PERFORMANCE)
                        // We do NOT fetch details on hover. This causes network storms during scrolling.
                        // Users can click to see details in the Detail View.
                        else {
                             // Just use what we have (fallback)
                             var fallback = newMovie
                             // Don't set description to "No details" as it overrides empty state in a weird way?
                             // Actually, keeping it empty is fine.
                             withAnimation { displayedMovie = fallback }
                        }
                    }
                } catch {
                    // Task cancelled (User managed to scroll to next item < 300ms)
                    // Nothing happens. UI stays on the *previous* stable movie until user stops scrolling.
                }
            }

            // Dynamic Visibility: If navigating to details (movie/series !nil), HIDE. Else SHOW.
            .toolbar((selectedMovie != nil || selectedSeries != nil) ? .hidden : .visible, for: .tabBar)
            .onAppear {
                 // Ensure visibility remains stable to prevent bouncing
                 // No-op: The toolbar modifier handles it based on state
            }
            if showDisclaimer {
                DisclaimerLoadingView()
                    .zIndex(200)
                    .transition(.opacity)
            }
            } // End Outer ZStack
        } // End NavigationView
        .navigationViewStyle(.stack)
        .id(refreshID) // Reset Navigation Stack when tab is re-selected
    } // End Body
    
    @MainActor
    private func loadData() async {
        do {
            try await stalkerClient.authenticate()
            
            // Fetch Categories
            let allCats = try await stalkerClient.getCategories(type: "vod")
            print("MoviesView: allCats count: \(allCats.count)")
            
            // Sort
            // Sort (Removed as per user request)
            // let order = prefs.movieCategoryOrder
            // let sortedCats = ...
            // We now rely on server order or simple filtering.
            
            let filtered = allCats.filter { prefs.isCategoryVisible($0.id) }
            print("MoviesView: filtered count: \(filtered.count)")
            
            self.categories = filtered
            
            // Prefetch Movies for Top 3 Categories
            // This ensures they are ready immediately when the View renders, avoiding the "blink"
            // FIX: Wait for Cache first to avoid unnecessary network calls
            await stalkerClient.ensureCacheLoaded()
            
            var preloadResults: [String: [Movie]] = [:]
            let topCategories = Array(filtered.prefix(3))
            
            await withTaskGroup(of: (String, [Movie]?).self) { group in
                for cat in topCategories {
                    group.addTask {
                        // Optimistic Cache Check
                        let cached = self.stalkerClient.getCachedMovies(categoryId: cat.id)
                        if !cached.isEmpty {
                            return (cat.id, cached)
                        }
                        
                        do {
                            // Only hit network if cache is empty
                            let movies = try await self.stalkerClient.getMovies(categoryId: cat.id, startPage: 0, pageLimit: 2) 
                            return (cat.id, movies)
                        } catch {
                            return (cat.id, nil)
                        }
                    }
                }
                
                for await (catId, movies) in group {
                    if let movies = movies {
                        // Deduplicate preloaded items
                        let uniqueMovies = movies.reduce(into: [Movie]()) { result, movie in
                            if !result.contains(where: { $0.id == movie.id }) {
                                result.append(movie)
                            }
                        }
                        preloadResults[catId] = uniqueMovies
                    }
                }
            }
            
            self.preloadedMovies = preloadResults
            self.categories = filtered
            
            // Fetch Featured (First item of first category) to populate initial tray if empty
            // Fetch Featured (Priority: Continue Watching -> My List -> First Category)
            if focusedMovie == nil {
                // 1. Continue Watching
                if let firstContinue = uniqueWatchingItems.first?.movie {
                    self.featuredMovie = firstContinue
                    self.focusedMovie = firstContinue
                    self.displayedMovie = firstContinue
                }
                // 2. My List
                else if let firstList = watchlistManager.watchlist.first {
                    self.featuredMovie = firstList
                    self.focusedMovie = firstList
                    self.displayedMovie = firstList
                }
                // 3. Fallback to First Category
                else if let firstCat = filtered.first {
                    do {
                        // OPTIMIZATION: Fetched only 1 item (we just need one for the header), not 20 pages!
                        let movs = try await stalkerClient.getMovies(categoryId: firstCat.id, startPage: 0, pageLimit: 1)
                        if let first = movs.first {
                            self.featuredMovie = first
                            self.focusedMovie = first // Set initial focus context
                            self.displayedMovie = first // Initialize rigid display state
                        }
                    } catch { print("Failed to load featured movie: \(error)") }
                }
            }
        } catch {
            print("Movies Service error: \(error)")
        }
    }
    
    private func handleSelection(_ movie: Movie) {
        // 1. Check if it's a Series object itself
        if let isSeries = movie.isSeries, isSeries == 1 {
            self.selectedSeries = movie
            return
        }
        
        // 2. Check if it's an Episode (has seriesId)
        if let sId = movie.seriesId, !sId.isEmpty {
            Task {
                var foundSeries: Movie?
                do {
                    if let seriesObj = try await stalkerClient.getVodInfo(movieId: sId) {
                        if !seriesObj.name.isEmpty && seriesObj.name != "0" {
                             foundSeries = seriesObj
                        }
                    }
                } catch { print("Direct series lookup failed: \(error)") }
                
                if foundSeries == nil {
                    // Fallback Search Logic
                    var searchName = movie.seriesName
                    if searchName == nil || searchName?.isEmpty == true {
                        let parts = movie.name.components(separatedBy: "|")
                        if parts.count > 1 { searchName = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    if let query = searchName, !query.isEmpty {
                        do {
                            let results = try await stalkerClient.searchMovies(query: query)
                            foundSeries = results.first { $0.id == sId } ?? results.first { $0.name.lowercased().contains(query.lowercased()) && $0.isSeries == 1 }
                        } catch { print("Search fallback failed: \(error)") }
                    }
                }

                if let seriesObj = foundSeries {
                    await MainActor.run { self.selectedSeries = seriesObj }
                }
            }
            return
        }
        
        // 3. Is a Movie
        self.selectedMovie = movie
    }
}

// MARK: - Helper Components

/// A wrapper around button that detects focus efficiently
private struct FocusableMovieButton<Content: View>: View {
    let movie: Movie
    let client: StalkerClient
    let onFocus: () -> Void
    let onSelect: () -> Void
    let overlayContent: () -> Content
    
    @EnvironmentObject var watchlistManager: WatchlistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @FocusState private var isFocused: Bool
    
    @State private var showContextMenu = false
    
    init(movie: Movie, client: StalkerClient, onFocus: @escaping () -> Void, onSelect: @escaping () -> Void, @ViewBuilder overlayContent: @escaping () -> Content = { EmptyView() }) {
        self.movie = movie
        self.client = client
        self.onFocus = onFocus
        self.onSelect = onSelect
        self.overlayContent = overlayContent
    }
    
    var body: some View {
        Button(action: onSelect) {
                ZStack(alignment: .bottom) {
                    // Inline MovieCard content to verify focus behavior (remove nested .focusable)
                    AuthenticatedImage(url: movie.getPosterURL(baseURL: client.portalURL), targetSize: CGSize(width: 200, height: 300), client: client)
                        .frame(width: 200, height: 300)
                        // OPTIMIZATION: Fix _UIReplicantView warning on tvOS
                        // Use clipShape for the image content
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        // Apply shadow to a separate background view
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black)
                                // .shadow(radius: 5) // REMOVED: Expensive on tvOS, card style handles focus shadow
                        )
                    overlayContent()
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isFocused ? Color.white : Color.clear, lineWidth: 4)
                )
        }
        .contextMenu(menuItems: {
            // Basic context menu fallback if system supports it
             if watchlistManager.watchlist.contains(where: { $0.id == movie.id }) {
                Button(action: { watchlistManager.removeFromWatchlist(movie) }) {
                    Label("Remove from My List", systemImage: "minus.circle")
                }
            } else {
                Button(action: { watchlistManager.addToWatchlist(movie) }) {
                   Label("Add to My List", systemImage: "plus.circle")
                }
            }
            
            if playbackManager.getSavedTime(for: movie) != nil {
                Button(action: { playbackManager.removeFromContinueWatching(movie) }) {
                    Label("Already Watched!", systemImage: "checkmark.circle")
                }
            }
        })
        .buttonStyle(.card)
        .focused($isFocused)
        .onChange(of: isFocused) { old, newValue in
            if newValue {
                onFocus()
            }
        }
        // Restored Long Press Gesture
        .onLongPressGesture {
            showContextMenu = true
        }
        .confirmationDialog("Options", isPresented: $showContextMenu, titleVisibility: .hidden) {
            // 2. Add/Remove
            if watchlistManager.watchlist.contains(where: { $0.id == movie.id }) {
                Button("Remove from My List") {
                    watchlistManager.removeFromWatchlist(movie)
                }
            } else {
                Button("Add to My List") {
                    watchlistManager.addToWatchlist(movie)
                }
            }
            
            // 3. Mark Watched (if applicable)
            if playbackManager.getSavedTime(for: movie) != nil {
                Button("Already Watched!") {
                    playbackManager.removeFromContinueWatching(movie)
                }
            }
            
            Button("Cancel", role: .cancel) { }
        }
    }
}


// MARK: - Helper Components

