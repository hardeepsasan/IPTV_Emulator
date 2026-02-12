import SwiftUI

struct HomeView: View {
    @StateObject private var stalkerClient: StalkerClient
    
    // Data State
    @State private var categories: [Category] = []
    @State private var moviesByCategory: [String: [Movie]] = [:]
    @State private var featuredMovie: Movie?
    @State private var selectedStreamURL: IdentifiableStreamURL?
    @State private var showingPlayer = false
    
    init(macAddress: String, portalURL: String) {
        _stalkerClient = StateObject(wrappedValue: StalkerClient(portalURL: portalURL, macAddress: macAddress))
    }
    
    var body: some View {
        NavigationView {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 40) {
                    
                    // Header / Featured (Netflix-style Hero)
                    if let featured = featuredMovie {
                        HeroView(movie: featured, client: stalkerClient) { movie in
                            playMovie(movie)
                        }
                        .frame(height: 500)
                    }
                    
                    // Rows
                    ForEach(categories) { category in
                        if let movies = moviesByCategory[category.id], !movies.isEmpty {
                            VStack(alignment: .leading) {
                                Text(category.title)
                                    .font(.headline)
                                    .padding(.leading, 50)
                                
                                ScrollView(.horizontal) {
                                    LazyHStack(spacing: 40) {
                                        ForEach(movies) { movie in
                                            Button {
                                                playMovie(movie)
                                            } label: {
                                                MovieCard(movie: movie, client: stalkerClient)
                                            }
                                            .buttonStyle(.card) // Custom style needed or just plain button
                                        }
                                    }
                                    .padding(.horizontal, 50)
                                    .padding(.vertical, 20)
                                }
                            }
                        }
                    }
                }
            }
            .edgesIgnoringSafeArea(.horizontal)
            .fullScreenCover(item: $selectedStreamURL) { item in
                PlayerView(url: item.url, client: stalkerClient)
                    .ignoresSafeArea()
            }
            .task {
                do {
                   try await stalkerClient.authenticate()
                   // Fetch Categories
                   let cats = try await stalkerClient.getCategories()
                   self.categories = cats
                   
                   // Fetch Movies for each category (Limit 5 categories for performance initially)
                   // Fetch Movies for each category (Limit 5 categories for performance initially)
                   print("HomeView: Found \(cats.count) categories.")
                   for category in cats.prefix(5) {
                       print("HomeView: Loading movies for category: \(category.title) (ID: \(category.id))")
                       let movs = try await stalkerClient.getMovies(categoryId: category.id)
                       print("HomeView: Loaded \(movs.count) movies for \(category.title)")
                       self.moviesByCategory[category.id] = movs
                       
                       // Set first available movie as hero
                       if self.featuredMovie == nil, let first = movs.first {
                           self.featuredMovie = first
                       }
                   }
                } catch {
                    print("Service error: \(error)")
                }
                
                // Start Background Indexing for Search
                stalkerClient.buildSearchIndex()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            handleSceneChange(newPhase)
        }
    }
    
    private func playMovie(_ movie: Movie) {
        guard let cmd = movie.comm else { return }
        print("Playing movie: \(movie.name) cmd: \(cmd)")
        
        Task {
            do {
                let streamLink = try await stalkerClient.createLink(type: "vod", cmd: cmd)
                print("Stream Link: \(streamLink)")
                if let url = URL(string: streamLink) {
                     self.selectedStreamURL = IdentifiableStreamURL(url: url)
                     self.showingPlayer = true
                }
            } catch {
                print("Failed to create link: \(error)")
            }
        }
    }
    
    // MARK: - Lifecycle Logic
    @Environment(\.scenePhase) var scenePhase
    
    private func handleSceneChange(_ phase: ScenePhase) {
        if phase == .active {
            print("App Foregrounded: Checking Index Freshness...")
            stalkerClient.buildSearchIndex()
        }
    }
}



struct HeroView: View {
    let movie: Movie
    @ObservedObject var client: StalkerClient
    let onPlay: (Movie) -> Void
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AuthenticatedImage(url: movie.getPosterURL(baseURL: client.portalURL), targetSize: CGSize(width: 400, height: 600), client: client)
            .mask(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .bottom, endPoint: .top))
            
            VStack(alignment: .leading) {
                Text(movie.name)
                    .font(.system(size: 60, weight: .bold))
                Text(movie.description ?? "")
                    .lineLimit(3)
                    .font(.body)
                
                Button("Play") {
                    onPlay(movie)
                }
                .focused($isFocused)
            }
            .padding(50)
        }
        .clipped() // Ensure Header Image does not bleed
    }
}

struct MovieCard: View {
    let movie: Movie
    @ObservedObject var client: StalkerClient
    @FocusState private var isFocused: Bool
    
    var body: some View {
        AuthenticatedImage(url: movie.getPosterURL(baseURL: client.portalURL), targetSize: CGSize(width: 200, height: 300), client: client)
            .frame(width: 200, height: 300)
            .cornerRadius(10)
            .scaleEffect(isFocused ? 1.15 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white, lineWidth: isFocused ? 4 : 0)
            )
            .animation(.spring(), value: isFocused)
            .focusable(true)
            .focused($isFocused)
    }
}
