#if os(iOS)
import SwiftUI

struct iOSContentPreferencesView: View {
    @ObservedObject var client: StalkerClient
    @ObservedObject var prefs = PreferenceManager.shared
    
    @State private var movieCategories: [Category] = []
    @State private var channelGenres: [Category] = []
    @State private var isLoading = false
    @State private var selectedTab = 0 // 0: Movies, 1: Channels
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Content Type", selection: $selectedTab) {
                Text("Movies").tag(0)
                Text("Channels").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading...")
                        Spacer()
                    }
                } else {
                    Section {
                        Button(action: toggleAll) {
                            Label(isSelectAllAction ? "Select All" : "Deselect All", 
                                  systemImage: isSelectAllAction ? "checkmark.circle" : "xmark.circle")
                        }
                    }
                    
                    ForEach(filteredCategories) { item in
                        HStack {
                            Text(item.title)
                                .font(.body)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { prefs.isCategoryVisible(item.id) },
                                set: { _ in toggle(item.id) }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search Categories")
        }
        .navigationTitle("Content Preferences")
        .task {
            await loadData()
        }
    }
    
    private var filteredCategories: [Category] {
        let baseList = (selectedTab == 0 ? movieCategories : channelGenres)
        if searchText.isEmpty { return baseList }
        return baseList.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var isSelectAllAction: Bool {
        return filteredCategories.contains { !prefs.isCategoryVisible($0.id) }
    }
    
    private func toggleAll() {
        let shouldSelect = isSelectAllAction
        for item in filteredCategories {
            prefs.setVisible(item.id, isVisible: shouldSelect)
        }
    }
    
    private func toggle(_ id: String) {
        let isVisible = prefs.isCategoryVisible(id)
        prefs.setVisible(id, isVisible: !isVisible)
    }
    
    private func loadData() async {
        guard movieCategories.isEmpty else { return }
        isLoading = true
        do {
            async let movies = client.getCategories(type: "vod")
            async let channels = client.getCategories(type: "itv")
            let (m, c) = try await (movies, channels)
            
            await MainActor.run {
                self.movieCategories = m
                self.channelGenres = c
                if !prefs.hasUserSetPreferences {
                    let allIds = m.map{$0.id} + c.map{$0.id}
                    prefs.setAllVisible(allIds)
                }
                isLoading = false
            }
        } catch {
            print("Settings: Failed to load: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
}
#endif
