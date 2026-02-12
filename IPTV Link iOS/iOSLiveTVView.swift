#if os(iOS)
import SwiftUI

struct iOSLiveTVView: View {
    @ObservedObject var client: StalkerClient
    @Binding var selectedStreamURL: IdentifiableStreamURL?
    @ObservedObject var prefs = PreferenceManager.shared
    
    @State private var categories: [Category] = []
    
    var filteredCategories: [Category] {
        categories.filter { prefs.isCategoryVisible($0.id) }
    }
    @State private var selectedCategoryId: String? = "favorites_internal"
    @State private var channels: [Channel] = []
    @State private var isLoadingCategories = false
    @State private var isLoadingChannels = false
    @State private var searchText = ""
    
    @AppStorage("favorite_channels_json_v1") private var favoriteChannelsJSON: Data = Data()
    
    var filteredChannels: [Channel] {
        let baseChannels: [Channel]
        if selectedCategoryId == "favorites_internal" {
            baseChannels = (try? JSONDecoder().decode([Channel].self, from: favoriteChannelsJSON)) ?? []
        } else {
            baseChannels = channels
        }
        
        if searchText.isEmpty {
            return baseChannels
        } else {
            return baseChannels.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Category Selection (Horizontal Scroll)
            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Favorites (Always first)
                        CategoryPill(
                            title: "Favorites",
                            isSelected: selectedCategoryId == "favorites_internal"
                        ) {
                            selectCategory("favorites_internal")
                        }
                        
                        ForEach(filteredCategories) { category in
                            CategoryPill(
                                title: category.title,
                                isSelected: selectedCategoryId == category.id
                            ) {
                                selectCategory(category.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color.black)
            }
            
            // Channel List
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if isLoadingChannels && channels.isEmpty && selectedCategoryId != "favorites_internal" {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading Channels...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else if filteredChannels.isEmpty && !isLoadingChannels {
                    VStack(spacing: 20) {
                        Image(systemName: !searchText.isEmpty ? "magnifyingglass" : (selectedCategoryId == "favorites_internal" ? "heart.slash" : "tv.slash"))
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.5))
                        Text(!searchText.isEmpty ? "No matches for \"\(searchText)\"" : (selectedCategoryId == "favorites_internal" ? "No favorite channels yet." : "No channels found."))
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        ForEach(filteredChannels) { channel in
                            ChannelListRow(channel: channel, client: client) {
                                playChannel(channel)
                            }
                            .listRowBackground(Color.black)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        if let id = selectedCategoryId, id != "favorites_internal" {
                            await loadChannels(for: id)
                        }
                    }
                }
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .navigationTitle("Live TV")
        .searchable(text: $searchText, prompt: "Search Channels")
        .task {
            await loadCategories()
        }
        .onDisappear {
            searchText = ""
        }
        .onChange(of: selectedCategoryId) {
            if let id = selectedCategoryId, id != "favorites_internal" {
                Task {
                    await loadChannels(for: id)
                }
            }
        }
    }
    
    // MARK: - Logic
    
    private func loadCategories() async {
        guard categories.isEmpty else { return }
        isLoadingCategories = true
        do {
            let cats = try await client.getCategories(type: "itv")
            self.categories = cats
            
            // Set initial category to server's All or first available
            if selectedCategoryId == nil {
                if let allCat = cats.first(where: { $0.id == "*" || $0.title.lowercased() == "all" }) {
                    self.selectedCategoryId = allCat.id
                } else if let first = cats.first {
                    self.selectedCategoryId = first.id
                }
            }
        } catch {
            print("iOSLiveTVView: Failed to load categories: \(error)")
        }
        isLoadingCategories = false
    }
    
    private func loadChannels(for categoryId: String) async {
        isLoadingChannels = true
        do {
            let results = try await client.getChannels(categoryId: categoryId)
            self.channels = results
        } catch {
            print("iOSLiveTVView: Failed to load channels: \(error)")
        }
        isLoadingChannels = false
    }
    
    private func selectCategory(_ id: String) {
        selectedCategoryId = id
    }
    
    private func playChannel(_ channel: Channel) {
        Task {
            do {
                let link = try await client.createLink(type: "itv", cmd: channel.cmd)
                if let url = URL(string: link) {
                    await MainActor.run {
                        let movie = Movie(
                            id: channel.id,
                            name: channel.name,
                            comm: channel.cmd,
                            poster: channel.logo,
                            categoryId: channel.categoryId
                        )
                        self.selectedStreamURL = IdentifiableStreamURL(url: url, movie: movie)
                    }
                }
            } catch {
                print("iOSLiveTVView: Failed to play channel: \(error)")
            }
        }
    }
}

// MARK: - Subviews

#endif
