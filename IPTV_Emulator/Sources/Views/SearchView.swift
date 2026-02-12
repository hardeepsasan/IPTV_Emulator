#if os(tvOS)
import SwiftUI

struct SearchView: View {
    @ObservedObject var stalkerClient: StalkerClient
    
    @State private var query: String = ""
    @State private var movieResults: [Movie] = []
    @State private var channelResults: [Channel] = []
    @State private var isSearching = false
    @Binding var playbackContext: PlaybackContext?
    @State private var selectedSeries: Movie?
    @State private var selectedMovie: Movie?
    @FocusState private var focusedChannelID: String?
    @FocusState private var isSearchFieldFocused: Bool
    
    @ObservedObject var preferenceManager = PreferenceManager.shared
    
    // Grid Setup
    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 40)
    ]
    
    var body: some View {
        NavigationView {
             ZStack {
                 // Dark Background
                 Color.black.ignoresSafeArea()
                 
                 VStack(alignment: .leading) {
                    
                    // WRAPPER FOR SCROLL CONTROL
                    ScrollViewReader { proxy in
                        // FIXED SEARCH BAR AREA
                        VStack(alignment: .center, spacing: 40) {
                             // Search Field
                             HStack {
                                 Spacer()
                                SearchFieldView(
                                    text: $query,
                                    onCommit: { performSearch() },
                                    onUpdate: { _ in
                                        if !isSearching && query.isEmpty {
                                            movieResults = []
                                            channelResults = []
                                        }
                                    },
                                    onEditingBegan: { 
                                        // Clear results when user starts interaction
                                        query = ""
                                        movieResults = []
                                        channelResults = []
                                    },
                                    onExit: {
                                        // Trigger Side-Effect: Reset Scroll Position
                                        print("DEBUG: Exit Search Bar -> Resetting Scroll")
                                        proxy.scrollTo("TOP", anchor: .top)
                                    },
                                    isFocused: Binding(
                                        get: { isSearchFieldFocused },
                                        set: { isSearchFieldFocused = $0 }
                                    )
                                )
                                 .focused($isSearchFieldFocused) // Bridge SwiftUI FocusState to View
                                 .frame(height: 50)
                                 .frame(maxWidth: 600)
                                 
                                 Spacer()
                             }
                             .padding(.horizontal, 100)
                             .padding(.top, 60)
                             .focusSection()
                             
                             // CONTENT AREA
                             Group {
                                 if query.isEmpty {
                                     // Initial State - No Spacer, just empty
                                     Color.clear.frame(height: 1)
                                 } else if !isSearching && movieResults.isEmpty && channelResults.isEmpty {
                                     // No Results - Static View (Non-scrollable)
                                     VStack(spacing: 20) {
                                         Text("No results found.")
                                             .foregroundColor(.gray)
                                             .font(.title3)
                                         
                                         Text("Please check content preference to make sure required category is selected to get the results from that category")
                                             .font(.caption)
                                             .foregroundColor(.gray)
                                             .multilineTextAlignment(.center)
                                             .padding(.horizontal, 100)
                                         
                                         // Push content up slightly but don't eat focus
                                         Color.clear.frame(height: 50)
                                     }
                                     .padding(.top, 50)
                                 } else {
                                     // Results - Scrollable
                                     ScrollView {
                                         VStack(alignment: .leading, spacing: 40) {
                                             Color.clear.frame(height: 1).id("TOP") // Scroll Anchor
                                             
                                             // Movies
                                             let movies = movieResults.filter { $0.isSeries != 1 }
                                             if !movies.isEmpty {
                                                 VStack(alignment: .leading) {
                                                     Text("Movies")
                                                         .font(.title2)
                                                         .padding(.bottom, 10)
                                                         .padding(.leading, 50)
                                                     
                                                     VStack(alignment: .leading, spacing: 40) {
                                                         ForEach(movies.chunked(into: 6), id: \.self) { rowMovies in
                                                             HStack(spacing: 40) {
                                                                 ForEach(rowMovies) { movie in
                                                                     Button {
                                                                         handleMovieSelection(movie)
                                                                     } label: {
                                                                         MovieCard(movie: movie, client: stalkerClient)
                                                                             .frame(width: 200)
                                                                     }
                                                                     .buttonStyle(.card)
                                                                 }
                                                                 Spacer()
                                                             }
                                                             .focusSection()
                                                         }
                                                     }
                                                     .padding(.horizontal, 50)
                                                 }
                                             }
                                             
                                             // Series
                                             let series = movieResults.filter { $0.isSeries == 1 }
                                             if !series.isEmpty {
                                                 VStack(alignment: .leading) {
                                                     Text("Series")
                                                         .font(.title2)
                                                         .padding(.bottom, 10)
                                                         .padding(.leading, 50)
                                                     
                                                     VStack(alignment: .leading, spacing: 40) {
                                                         ForEach(series.chunked(into: 6), id: \.self) { rowSeries in
                                                             HStack(spacing: 40) {
                                                                 ForEach(rowSeries) { show in
                                                                     Button {
                                                                         handleMovieSelection(show)
                                                                     } label: {
                                                                         MovieCard(movie: show, client: stalkerClient)
                                                                             .frame(width: 200)
                                                                     }
                                                                     .buttonStyle(.card)
                                                                 }
                                                                 Spacer()
                                                             }
                                                             .focusSection()
                                                         }
                                                     }
                                                     .padding(.horizontal, 50)
                                                 }
                                             }
                                             
                                             // Channels
                                             if !channelResults.isEmpty {
                                                 VStack(alignment: .leading) {
                                                     Text("Channels")
                                                         .font(.title2)
                                                         .padding(.bottom, 10)
                                                         .padding(.leading, 50)
                                                     
                                                     VStack(alignment: .leading, spacing: 40) {
                                                         ForEach(channelResults.chunked(into: 6), id: \.self) { rowChannels in
                                                             HStack(spacing: 40) {
                                                                 ForEach(rowChannels) { channel in
                                                                     Button {
                                                                         playChannel(channel)
                                                                     } label: {
                                                                         ChannelCard(
                                                                            channel: channel, 
                                                                            client: stalkerClient,
                                                                            categoryTitle: "Search", 
                                                                            isFocused: focusedChannelID == channel.id
                                                                         )
                                                                         .frame(width: 200)
                                                                     }
                                                                     .buttonStyle(.plain)
                                                                     .focused($focusedChannelID, equals: channel.id)
                                                                 }
                                                                 Spacer()
                                                             }
                                                             .focusSection()
                                                         }
                                                     }
                                                     .padding(.horizontal, 50)
                                                 }
                                             }
                                         }
                                         .padding(.bottom, 50)
                                         .padding(.top, 20)
                                     }
                                     .onExitCommand {
                                         // Trap Menu/Esc key from results and send focus to Search Bar
                                         print("DEBUG: User pressed Menu in Results -> Focusing Search Bar")
                                         isSearchFieldFocused = true
                                     }
                                 }
                             } // End Group
                        }
                    }
                     Spacer() // Push everything up if possible, but safely
                  }
              }
              .navigationBarHidden(true) // Hide Default Title
              // HIDDEN NAVIGATION LINKS moved to end and protected
              .background(
                 VStack {
                     NavigationLink(isActive: Binding(
                         get: { selectedSeries != nil },
                         set: { if !$0 { selectedSeries = nil } }
                     )) {
                         if let series = selectedSeries {
                             SeriesDetailView(series: series, stalkerClient: stalkerClient, playbackContext: $playbackContext)
                         } else { EmptyView() }
                     } label: { Color.clear.frame(width: 0, height: 0) } // Explicit zero frame
                     .hidden() // Visually hide
                     
                     NavigationLink(isActive: Binding(
                         get: { selectedMovie != nil },
                         set: { if !$0 { selectedMovie = nil } }
                     )) {
                         if let movie = selectedMovie {
                             MovieDetailView(movie: movie, stalkerClient: stalkerClient, playbackContext: $playbackContext)
                         } else { EmptyView() }
                     } label: { Color.clear.frame(width: 0, height: 0) }
                     .hidden()
                 }
                 .frame(width: 0, height: 0)
             )
         }
         .navigationViewStyle(.stack)
         .onAppear {
              // Removed auto-focus to prevent hijacking top menu navigation
         }
         .onDisappear {
             // Reset search state when leaving the view
             query = ""
             movieResults = []
             channelResults = []
             isSearching = false
         }
         .onReceive(NotificationCenter.default.publisher(for: .focusSearchBar)) { _ in
             print("DEBUG: Received focus request for SearchBar")
             // Ensure we are on main thread and reset focus
             DispatchQueue.main.async {
                 isSearchFieldFocused = true
             }
         }
    }
    
    private func performSearch() {
        guard !query.isEmpty else { return }
        // SAFEGUARD: Prevent searching for very short terms which yield massive results (e.g. "the")
        guard query.count >= 3 else {
            print("Search query too short (< 3 chars). Skipping.")
            return 
        }
        
        isSearching = true

        movieResults = []
        channelResults = []
        
        Task {
            do {
                // Run in parallel
                async let movies = stalkerClient.searchMovies(query: query)
                async let channels = stalkerClient.searchChannels(query: query)
                
                let (fetchedMovies, fetchedChannels) = try await (movies, channels)
                
                // Filter by preferences
                 let visibleMovies = fetchedMovies.filter { movie in
                     guard let catId = movie.categoryId else { return true }
                     return PreferenceManager.shared.isCategoryVisible(catId)
                 }
                 
                 let visibleChannels = fetchedChannels.filter { channel in
                     guard let catId = channel.categoryId else { return true }
                     return PreferenceManager.shared.isCategoryVisible(catId)
                 }
                 
                 print("DEBUG: Search found \(fetchedChannels.count) channels. Visible: \(visibleChannels.count)")
                 
                 await MainActor.run {
                     self.movieResults = visibleMovies
                     self.channelResults = visibleChannels
                     self.isSearching = false
                 }
             } catch {
                 print("Search failed: \(error)")
                 await MainActor.run {
                     self.isSearching = false
                 }
             }
         }
    }
    
    private func handleMovieSelection(_ movie: Movie) {
        // 1. Series Check
        if let isSeries = movie.isSeries, isSeries == 1 {
            print("Selected Search Series: \(movie.name)")
            self.selectedSeries = movie
            return
        }
        
        // 2. Episode Check (Redirect to Series)
        if let sId = movie.seriesId, !sId.isEmpty {
            print("Selected Search Episode of Series ID: \(sId). Fetching Series...")
            Task {
                var foundSeries: Movie?
                
                // Strategy 1: Direct Lookup
                do {
                    if let seriesObj = try await stalkerClient.getVodInfo(movieId: sId) {
                        if !seriesObj.name.isEmpty && seriesObj.name != "0" {
                             foundSeries = seriesObj
                        }
                    }
                } catch { print("Search direct lookup failed: \(error)") }
                
                // Strategy 2: Search Fallback
                if foundSeries == nil {
                     print("Direct lookup failed. Attempting Search Fallback...")
                     var searchName = movie.seriesName
                     if searchName == nil || searchName?.isEmpty == true {
                         let parts = movie.name.components(separatedBy: "|")
                         if parts.count > 1 {
                              searchName = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines)
                         }
                     }
                     
                     if let query = searchName, !query.isEmpty {
                         do {
                             let results = try await stalkerClient.searchMovies(query: query)
                             foundSeries = results.first { $0.id == sId }
                             if foundSeries == nil {
                                 foundSeries = results.first { $0.name.lowercased().contains(query.lowercased()) && $0.isSeries == 1 }
                             }
                         } catch { print("Search fallback failed: \(error)") }
                     }
                }
                
                if let seriesObj = foundSeries {
                     await MainActor.run {
                         self.selectedSeries = seriesObj
                     }
                } else {
                     print("Error: Could not find Series info for ID \(sId) via direct or search.")
                }
            }
            return
        }
        
        // 3. Movie Fallback
        print("Selected Search Movie: \(movie.name)")
        self.selectedMovie = movie
    }
    
    private func playChannel(_ channel: Channel) {
        let cmd = channel.cmd
        print("Playing search result channel: \(channel.name)")
        Task {
            do {
                let streamLink = try await stalkerClient.createLink(type: "itv", cmd: cmd)
                if let url = URL(string: streamLink) {
                    await MainActor.run {
                        self.playbackContext = PlaybackContext(url: url, title: channel.name)
                    }
                }
            } catch {
                print("Channel link creation failed: \(error)")
            }
        }
    }
}

// Helper for Manual Grid Layout
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension Notification.Name {
    static let focusSearchBar = Notification.Name("focusSearchBar")
}

#endif
