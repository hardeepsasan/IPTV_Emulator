#if os(iOS)
import SwiftUI

import AVKit

struct iOSHomeView: View {
    @ObservedObject private var client = StalkerClient.shared
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var watchlistManager: WatchlistManager
    
    // Data State
    @State private var categories: [Category] = []
    // featuredMovie state removed
    @State private var isLoading = true
    
    // Player State
    @State private var selectedStreamURL: IdentifiableStreamURL?
    @State private var showingPlayer = false
    
    // Tab Selection
    @State private var selectedTab: Int = 0
    
    // Navigation State
    @State private var selectedMovie: Movie?
    @State private var selectedSeries: Movie?
    @State private var showMovieDetail = false
    @State private var showSeriesDetail = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $selectedTab) {
                MoviesTabView(
                    client: client,
                    categories: $categories,
                    featuredMovie: $featuredMovie,
                    isLoading: $isLoading,
                    selectedMovie: $selectedMovie,
                    selectedSeries: $selectedSeries,
                    showMovieDetail: $showMovieDetail,
                    showSeriesDetail: $showSeriesDetail,
                    selectedStreamURL: $selectedStreamURL
                )
                .tabItem {
                    Label("Movies", systemImage: "film")
                }
                .tag(0)
                
                LiveTVTabView(client: client, selectedStreamURL: $selectedStreamURL)
                    .tabItem {
                        Label("Live TV", systemImage: "tv")
                    }
                    .tag(1)
                
                iOSSearchView(client: client, selectedStreamURL: $selectedStreamURL)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(2)
                
                iOSSettingsView(client: client)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(3)
            }
            .accentColor(.white)
            

            
            // Network Offline Capsule (Highest Priority)
            if !client.isConnected {
                NetworkOfflineCapsule()
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(101) // Higher than connection error
            }

            // Connection Error Capsule (Server Reachability)
            if client.connectionStatus == .failed && client.isConnected {
                 // Only show server error if we HAVE internet, otherwise "No Internet" takes precedence
                ConnectionErrorCapsule()
                    .padding(.top, 60)
                    .padding(.trailing, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedStreamURL) { item in
            PlayerView(
                url: item.url,
                client: client,
                startTime: item.startTime,
                title: item.movie?.name,
                onProgress: { time, duration in
                    if let movie = item.movie {
                        playbackManager.updateProgress(movie: movie, time: time, duration: duration)
                    }
                }
            )
            .ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("PlayMovie"))) { note in
            if let movie = note.object as? Movie {
                playMovie(movie)
            } else if let userInfo = note.userInfo,
                      let movie = userInfo["movie"] as? Movie {
                let startTime = userInfo["startTime"] as? Double ?? 0
                playMovie(movie, startTime: startTime)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("MarkAsWatched"))) { note in
            if let movie = note.object as? Movie {
                playbackManager.removeFromContinueWatching(movie)
            }
        }
        .task {
            // Restore missing data load task
            await loadData()
            
            // Warm cache (Sync with tvOS logic)
            client.buildSearchIndex()
        }
    }
    
    // MARK: - Data Fetching
    private func loadData() async {
        guard categories.isEmpty else { return }
        
        isLoading = true
        do {
            // 1. Ensure Handshake (fallback)
            try await client.authenticate()
            
            let cats = try await client.getCategories()
            self.categories = cats
            
            if let firstCat = cats.first {
                let movs = try await client.getMovies(categoryId: firstCat.id, pageLimit: 1)
                // Old featured logic removed, handled by FeaturedContentManager
            }
        } catch {
            print("iOSHomeView: Failed to load categories: \(error)")
        }
        isLoading = false
    }
    
    // MARK: - Playback
    private func playMovie(_ movie: Movie, startTime: Double = 0) {
        guard let cmd = movie.comm else { return }
        print("Playing movie: \(movie.name) cmd: \(cmd) at \(startTime)")
        
        Task {
            do {
                let streamLink = try await client.createLink(type: "vod", cmd: cmd)
                if let url = URL(string: streamLink) {
                    await MainActor.run {
                        self.selectedStreamURL = IdentifiableStreamURL(url: url, movie: movie, startTime: startTime)
                        self.showingPlayer = true
                    }
                }
            } catch {
                print("Failed to create link: \(error)")
            }
        }
    }
}

// MARK: - Tab Views

struct MoviesTabView: View {
    @ObservedObject var client: StalkerClient
    @Binding var categories: [Category]
    @Binding var featuredMovie: Movie?
    @Binding var isLoading: Bool
    
    @Binding var selectedMovie: Movie?
    @Binding var selectedSeries: Movie?
    @Binding var showMovieDetail: Bool
    @Binding var showSeriesDetail: Bool
    
    @Binding var selectedStreamURL: IdentifiableStreamURL?
    
    @ObservedObject var featuredManager = FeaturedContentManager.shared
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var watchlistManager: WatchlistManager
    @ObservedObject var prefs = PreferenceManager.shared
    
    private var filteredCategories: [Category] {
        categories.filter { prefs.isCategoryVisible($0.id) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    FeaturedCarousel(
                        manager: featuredManager,
                        selectedMovie: $selectedMovie,
                        showMovieDetail: $showMovieDetail
                    )
                    
                    // Continue Watching Section
                    if !playbackManager.watchingItems.isEmpty {
                        DynamicLocalRow(
                            title: "Continue Watching",
                            items: playbackManager.watchingItems.map { $0.movie },
                            client: client,
                            onSelect: { movie in
                                selectedMovie = movie
                                showMovieDetail = true
                            }
                        )
                    }
                    
                    // My List Section
                    if !watchlistManager.watchlist.isEmpty {
                        DynamicLocalRow(
                            title: "My List",
                            items: watchlistManager.watchlist,
                            client: client,
                            onSelect: { movie in
                                if movie.isSeries == 1 {
                                    selectedSeries = movie
                                    showSeriesDetail = true
                                } else {
                                    selectedMovie = movie
                                    showMovieDetail = true
                                }
                            }
                        )
                    }
                    
                    CategoryListView(
                        categories: filteredCategories,
                        client: client,
                        selectedMovie: $selectedMovie,
                        selectedSeries: $selectedSeries,
                        showMovieDetail: $showMovieDetail,
                        showSeriesDetail: $showSeriesDetail
                    )
                }
                .padding(.top)
            }
            .refreshable {
                featuredManager.refreshFeaturedContent()
                await withCheckedContinuation { continuation in
                    // Simple delay to simulate async refresh for UI feel
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        continuation.resume()
                    }
                }
            }
            .onAppear {
                featuredManager.refreshFeaturedContent()
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .navigationTitle("Movies")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showMovieDetail) {
                if let movie = selectedMovie {
                    iOSMovieDetailView(movie: movie)
                }
            }
            .navigationDestination(isPresented: $showSeriesDetail) {
                if let series = selectedSeries {
                    iOSSeriesDetailView(series: series)
                }
            }
        }
    }
}

struct FeaturedCarousel: View {
    @ObservedObject var manager: FeaturedContentManager
    @Binding var selectedMovie: Movie?
    @Binding var showMovieDetail: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !manager.heroMovies.isEmpty {
                // Carousel using TabView
                TabView {
                    ForEach(manager.heroMovies) { movie in
                        FeaturedMovieCard(movie: movie) {
                            selectedMovie = movie
                            showMovieDetail = true
                        }
                        .padding(.horizontal) // Padding inside the page
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 250)
                
                // Source Indicator (Optional Debug/Info)
                // Text("Source: \(manager.currentSource)")
                //    .font(.caption2)
                //    .foregroundColor(.gray)
                //    .padding(.horizontal)
            } else if manager.isLoading {
                ProgressView()
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct CategoryListView: View {
    let categories: [Category]
    @ObservedObject var client: StalkerClient
    @Binding var selectedMovie: Movie?
    @Binding var selectedSeries: Movie?
    @Binding var showMovieDetail: Bool
    @Binding var showSeriesDetail: Bool
    
    var body: some View {
        LazyVStack(spacing: 25) {
            ForEach(categories) { category in
                CategoryRow(
                    category: category,
                    client: client,
                    selectedMovie: $selectedMovie,
                    selectedSeries: $selectedSeries,
                    showMovieDetail: $showMovieDetail,
                    showSeriesDetail: $showSeriesDetail
                )
            }
        }
    }
}

struct CategoryRow: View {
    let category: Category
    @ObservedObject var client: StalkerClient
    @Binding var selectedMovie: Movie?
    @Binding var selectedSeries: Movie?
    @Binding var showMovieDetail: Bool
    @Binding var showSeriesDetail: Bool
    
    var body: some View {
        LazyMovieRow(
            category: category,
            client: client,
            horizontalPadding: 16,
            verticalPadding: 8,
            itemSpacing: 12,
            titleSpacing: 8,
            movieCard: { movie in
                MovieCardButton(
                    movie: movie,
                    selectedMovie: $selectedMovie,
                    selectedSeries: $selectedSeries,
                    showMovieDetail: $showMovieDetail,
                    showSeriesDetail: $showSeriesDetail
                )
            },
            onSelect: { movie in
                handleSelection(movie)
            }
        )
    }
    
    private func handleSelection(_ movie: Movie) {
        if movie.isSeries == 1 {
            selectedSeries = movie
            showSeriesDetail = true
        } else {
            selectedMovie = movie
            showMovieDetail = true
        }
    }
}

struct MovieCardButton: View {
    let movie: Movie
    @Binding var selectedMovie: Movie?
    @Binding var selectedSeries: Movie?
    @Binding var showMovieDetail: Bool
    @Binding var showSeriesDetail: Bool
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var watchlistManager: WatchlistManager
    
    var body: some View {
        Button {
            if movie.isSeries == 1 {
                selectedSeries = movie
                showSeriesDetail = true
            } else {
                selectedMovie = movie
                showMovieDetail = true
            }
        } label: {
            MobileMovieCard(movie: movie)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if playbackManager.getSavedTime(for: movie) != nil {
                Button(role: .destructive) {
                    playbackManager.removeFromContinueWatching(movie)
                } label: {
                    Label("Already Watched!", systemImage: "checkmark.circle")
                }
            }
            
            Button {
                watchlistManager.toggle(movie)
            } label: {
                Label(watchlistManager.inWatchlist(movie) ? "Remove from My List" : "Add to My List", 
                      systemImage: watchlistManager.inWatchlist(movie) ? "minus.circle" : "plus.circle")
            }
        }
    }
}

struct LiveTVTabView: View {
    @ObservedObject var client: StalkerClient
    @Binding var selectedStreamURL: IdentifiableStreamURL?
    
    var body: some View {
        NavigationStack {
            iOSLiveTVView(client: client, selectedStreamURL: $selectedStreamURL)
        }
    }
}

// MARK: - Components

struct FeaturedMovieCard: View {
    let movie: Movie
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    AuthenticatedImage(url: movie.getPosterURL(baseURL: StalkerClient.shared.portalURL), targetSize: geo.size, client: StalkerClient.shared)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(
                            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                        )
                        .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text(movie.name)
                            .font(.title2)
                            .fontWeight(.bold) // iOS explicit weight
                            .foregroundColor(.white)
                        
                        if let genre = movie.genresStr {
                            Text(genre)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                }
            }
        }
        .buttonStyle(.plain) // Standard button behavior
    }
}

// MARK: - Dynamic Local Row
struct DynamicLocalRow: View {
    let title: String
    let items: [Movie]
    @ObservedObject var client: StalkerClient
    let onSelect: (Movie) -> Void
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var watchlistManager: WatchlistManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            MobileMovieCard(movie: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if playbackManager.getSavedTime(for: item) != nil {
                                Button(role: .destructive) {
                                    NotificationCenter.default.post(name: NSNotification.Name("MarkAsWatched"), object: item)
                                } label: {
                                    Label("Already Watched!", systemImage: "checkmark.circle")
                                }
                            }
                            
                            Button {
                                watchlistManager.toggle(item)
                            } label: {
                                Label(watchlistManager.inWatchlist(item) ? "Remove from My List" : "Add to My List", 
                                      systemImage: watchlistManager.inWatchlist(item) ? "minus.circle" : "plus.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Local Types

// PlayerView is reused from Shared folder by target membership.
// Note: Please ensure PlayerView.swift is checked for the "IPTV Link iOS" target in Xcode.

// MARK: - Error Handling

struct ConnectionErrorCapsule: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14, weight: .bold))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Error")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Verify Network, Portal or MAC in Settings")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
    }
}

struct NetworkOfflineCapsule: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .bold))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("No Internet Connection")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Waiting for network...")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(Color.red.opacity(0.6)) // distinct from orange connection error
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
    }
}

#endif
