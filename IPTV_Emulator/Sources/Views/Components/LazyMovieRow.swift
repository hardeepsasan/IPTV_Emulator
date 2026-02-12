import SwiftUI

struct LazyMovieRow<Content: View>: View {
    let category: Category
    let client: StalkerClient
    let shouldDebounce: Bool
    let initialMovies: [UniqueMovie]?
    let movieCard: (Movie) -> Content
    let onSelect: (Movie) -> Void
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let itemSpacing: CGFloat
    let titleSpacing: CGFloat
    
    @ObservedObject var prefs = PreferenceManager.shared
    @EnvironmentObject var watchlistManager: WatchlistManager
    
    @State private var movies: [UniqueMovie]?
    @State private var allCachedMovies: [UniqueMovie] = []
    @State private var visibleCount = 30
    @State private var totalCount: Int? = 0
    @State private var isLoading = false
    @State private var page = 1
    @State private var hasMore = true
    
    init(category: Category, 
         client: StalkerClient, 
         shouldDebounce: Bool = false, 
         initialMovies: [UniqueMovie]? = nil,
         horizontalPadding: CGFloat = 50,
         verticalPadding: CGFloat = 30,
         itemSpacing: CGFloat = 40,
         titleSpacing: CGFloat = 15,
         @ViewBuilder movieCard: @escaping (Movie) -> Content,
         onSelect: @escaping (Movie) -> Void) {
        self.category = category
        self.client = client
        self.shouldDebounce = shouldDebounce
        self.initialMovies = initialMovies
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.itemSpacing = itemSpacing
        self.titleSpacing = titleSpacing
        self.movieCard = movieCard
        self.onSelect = onSelect
        
        if let initial = initialMovies, !initial.isEmpty {
            _movies = State(initialValue: initial)
            _allCachedMovies = State(initialValue: initial)
            _visibleCount = State(initialValue: initial.count)
            _hasMore = State(initialValue: true)
            _page = State(initialValue: 1)
        }
    }
    
    private func updateDisplayedMovies() {
        Task {
            let fullList = allCachedMovies
            let option = prefs.globalSortOption
            let limit = visibleCount
            
            let sorted = await Task.detached(priority: .userInitiated) { () -> [UniqueMovie] in
                switch option {
                case .date:
                    return fullList
                case .alpha:
                    return fullList.sorted { $0.movie.name.localizedCaseInsensitiveCompare($1.movie.name) == .orderedAscending }
                case .favorites:
                    return fullList
                }
            }.value
            
            await MainActor.run {
                if option == .favorites {
                    let favs = sorted.filter { watchlistManager.inWatchlist($0.movie) }
                    self.movies = Array(favs.prefix(limit))
                } else {
                    self.movies = Array(sorted.prefix(limit))
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: titleSpacing) {
            // Category Title
            HStack(alignment: .firstTextBaseline) {
                Text(category.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let count = totalCount, count > 0 {
                    Text("\(count)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .padding(.horizontal, horizontalPadding)
            
            if let items = movies {
                if items.isEmpty {
                    Text(prefs.globalSortOption == .favorites ? "No favorites in this category." : "No movies found.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 10)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: itemSpacing) {
                            ForEach(items) { wrapper in
                                // movieCard is now responsible for handling its own interaction
                                movieCard(wrapper.movie)
                                .onAppear {
                                    // Prefetch Trigger: 10 items from end
                                    if hasMore, let lastId = items.last?.id, wrapper.id == lastId {
                                        Task { await fetchMore() }
                                    }
                                }
                            }
                            
                            if isLoading {
                                ProgressView()
                                    .padding(.horizontal, horizontalPadding)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                    }
                }
            } else {
                // Initial Loading State
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .task { await fetchMovies() }
            }
        }
        .onReceive(client.$categoryMetadata) { newMetadata in
            if let count = newMetadata[category.id], self.totalCount != count {
                self.totalCount = count
            }
        }
        .onChange(of: prefs.globalSortOption) { _, _ in updateDisplayedMovies() }
    }
    
    private func fetchMovies() async {
        guard movies == nil else { return }
        
        if shouldDebounce {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        
        isLoading = true
        do {
            let hybridList = try await client.getHybridMovies(categoryId: category.id)
            await MainActor.run {
                if !hybridList.isEmpty {
                    let wrappers = hybridList.map { UniqueMovie(movie: $0) }
                    self.allCachedMovies = wrappers
                    self.visibleCount = 30
                    self.totalCount = client.categoryMetadata[category.id]
                    self.updateDisplayedMovies()
                    self.page = 1
                    self.hasMore = true
                } else {
                    self.movies = []
                    self.allCachedMovies = []
                    self.hasMore = false
                }
                self.isLoading = false
            }
        } catch {
            print("LazyMovieRow: fetchMovies failed for \(category.title): \(error)")
            isLoading = false
        }
    }
    
    private func fetchMore() async {
        guard !isLoading, hasMore else { return }
        
        await MainActor.run { isLoading = true }
        
        // 1. Memory Pagination
        if visibleCount < allCachedMovies.count {
            await MainActor.run {
                visibleCount = min(allCachedMovies.count, visibleCount + 30)
                updateDisplayedMovies()
                isLoading = false
            }
            return
        }
        
        // 2. Network Fetch
        let batchSize = 4
        let startPage = page + 1
        
        do {
            let fetched = try await client.getMovies(categoryId: category.id, startPage: startPage, pageLimit: batchSize)
            await MainActor.run {
                if fetched.isEmpty {
                    self.hasMore = false
                } else {
                    let existingIDs = Set(self.allCachedMovies.map { $0.movie.id })
                    let newUnique = fetched.filter { !existingIDs.contains($0.id) }
                    
                    if !newUnique.isEmpty {
                        let newWrappers = newUnique.map { UniqueMovie(movie: $0) }
                        self.allCachedMovies.append(contentsOf: newWrappers)
                        self.visibleCount += newWrappers.count
                        self.totalCount = client.categoryMetadata[category.id]
                        self.updateDisplayedMovies()
                    }
                    self.page = startPage + batchSize - 1
                }
                self.isLoading = false
            }
        } catch {
            print("LazyMovieRow: fetchMore failed: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
}
