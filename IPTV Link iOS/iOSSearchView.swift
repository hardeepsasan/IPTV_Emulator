#if os(iOS)
import SwiftUI

struct iOSSearchView: View {
    @ObservedObject var client: StalkerClient
    @Binding var selectedStreamURL: IdentifiableStreamURL?
    
    @State private var searchText = ""
    @State private var movieResults: [Movie] = []
    @State private var seriesResults: [Movie] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil
    
    // Navigation State
    @State private var selectedMovie: Movie?
    @State private var selectedSeries: Movie?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    if isSearching && (movieResults.isEmpty && seriesResults.isEmpty) {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Searching VOD & Series...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .frame(maxHeight: .infinity)
                    } else if searchText.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.gray.opacity(0.3))
                            Text("Search Movies or Series")
                                .foregroundColor(.gray)
                        }
                        .frame(maxHeight: .infinity)
                    } else if !isSearching && movieResults.isEmpty && seriesResults.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 60))
                                .foregroundColor(.gray.opacity(0.3))
                            Text("No results found for \"\(searchText)\"")
                                .foregroundColor(.gray)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                // Movies Section
                                if !movieResults.isEmpty {
                                    SectionView(title: "Movies") {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(movieResults) { movie in
                                                    Button {
                                                        selectedMovie = movie
                                                    } label: {
                                                        MobileMovieCard(movie: movie)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                                
                                // Series Section
                                if !seriesResults.isEmpty {
                                    SectionView(title: "Series") {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 12) {
                                                ForEach(seriesResults) { series in
                                                    Button {
                                                        selectedSeries = series
                                                    } label: {
                                                        MobileMovieCard(movie: series)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Movies, Series, Actors...")
            .onChange(of: searchText) {
                performDebouncedSearch()
            }
            .onDisappear {
                searchText = ""
                movieResults = []
                seriesResults = []
            }
            .sheet(item: $selectedMovie) { movie in
                iOSMovieDetailView(movie: movie)
            }
            .sheet(item: $selectedSeries) { series in
                iOSSeriesDetailView(series: series)
            }
        }
    }
    
    // MARK: - Search Logic
    
    private func performDebouncedSearch() {
        searchTask?.cancel()
        
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            movieResults = []
            seriesResults = []
            isSearching = false
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if !Task.isCancelled {
                await runSearch()
            }
        }
    }
    
    private func runSearch() async {
        isSearching = true
        let query = searchText
        
        do {
            let vodResults = try await client.searchMovies(query: query)
            
            if !Task.isCancelled {
                withAnimation {
                    // Separate Movies vs Series
                    self.movieResults = vodResults.filter { ($0.isSeries ?? 0) == 0 }
                    self.seriesResults = vodResults.filter { ($0.isSeries ?? 0) == 1 }
                    self.isSearching = false
                }
            }
        } catch {
            print("iOSSearchView: Search Error: \(error)")
            if !Task.isCancelled {
                isSearching = false
            }
        }
    }
}

// MARK: - Helper Views

struct SectionView<Content: View>: View {
    let title: String
    let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            content()
        }
    }
}
#endif
