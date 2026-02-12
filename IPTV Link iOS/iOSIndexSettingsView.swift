#if os(iOS)
import SwiftUI

struct iOSIndexSettingsView: View {
    @ObservedObject var client: StalkerClient
    @ObservedObject var prefs = PreferenceManager.shared
    
    @State private var categories: [Category] = []
    @State private var isLoading = true
    @State private var searchText = ""
    
    var body: some View {
        List {
            Section(footer: Text("Selected categories will be included in the local Movie & Series search index.")) {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(filteredCategories) { category in
                        Toggle(isOn: Binding(
                            get: { isIndexed(category) },
                            set: { _ in toggle(category) }
                        )) {
                            HStack {
                                Text(category.title)
                                if isLocked(category) {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .disabled(isLocked(category))
                    }
                }
            }
            
            Section(header: Text("Stats")) {
                HStack {
                    Text("Total Indexed Categories")
                    Spacer()
                    Text("\(totalSelectedCount)")
                        .foregroundColor(.gray)
                }
                HStack {
                    Text("Cached Movies")
                    Spacer()
                    Text("\(client.cacheCount)")
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("Indexing")
        .searchable(text: $searchText, prompt: "Search Categories")
        .task {
            await loadCategories()
        }
    }
    
    private var filteredCategories: [Category] {
        if searchText.isEmpty { return categories }
        return categories.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    private func isLocked(_ category: Category) -> Bool {
        return StalkerClient.defaultIndexedCategoryIDs.contains(category.id)
    }
    
    private func isIndexed(_ category: Category) -> Bool {
        if isLocked(category) { return true }
        return prefs.isActionIndexed(category.id)
    }
    
    private func toggle(_ category: Category) {
        guard !isLocked(category) else { return }
        let current = prefs.isActionIndexed(category.id)
        prefs.setIndexed(category.id, isIndexed: !current)
    }
    
    private var totalSelectedCount: Int {
        let defaults = StalkerClient.defaultIndexedCategoryIDs
        let custom = prefs.additionalIndexedCategoryIds
        return defaults.union(custom).count
    }
    
    private func loadCategories() async {
        isLoading = true
        do {
            let cats = try await client.getCategories(type: "vod")
            await MainActor.run {
                self.categories = cats
                self.isLoading = false
            }
        } catch {
            print("Settings: Index Load Error: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
}
#endif
