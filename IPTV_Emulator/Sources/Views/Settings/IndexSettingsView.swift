import SwiftUI

struct IndexSettingsView: View {
    @ObservedObject var client: StalkerClient
    @ObservedObject var prefs = PreferenceManager.shared
    
    @State private var categories: [Category] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    

    
    // UI State
    @State private var filterState = 0 // 0: All, 1: Included, 2: Not Included
    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - Frozen Header
            VStack(spacing: 30) {
                
                // 1. Title (Centered)
                Text("Indexing Preferences")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                

                
                // 3. Filter Picker & Controls
                HStack(alignment: .center, spacing: 40) {
                    
                    Text("Filter:")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Picker("Filter", selection: $filterState) {
                        Text("All").tag(0)
                        Text("Included").tag(1)
                        Text("Not Included").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 600)
                    
                    Spacer()
                    
                    // Stats
                    Text("\(filteredCategories.count) Categories")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 40)
                
                // 4. Description / Info
                Text("Select additional categories to include in the local movie database. Default categories are locked.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 30)
            .background(Color.black.ignoresSafeArea()) // Opaque Header
            .zIndex(1)
            
            // MARK: - Scrolling List
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading Categories...")
                        .foregroundColor(.white)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if let error = errorMessage {
                VStack {
                    Spacer()
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                    Section(header: Text("Status")) {
                        HStack {
                            Text("Cached Movies")
                            Spacer()
                            Text("\(client.cacheCount)")
                                .foregroundColor(.gray)
                        }
                    }
                    Button("Retry") { Task { await loadCategories() } }
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                List {
                    ForEach(filteredCategories) { category in
                        IndexPreferenceRow(category: category, isIndexed: isIndexed(category), isLocked: isLocked(category)) {
                            toggle(category)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 40, bottom: 2, trailing: 40))
                    }
                }
                .listStyle(.plain)
                .background(Color.black)
            }
        }
        .navigationTitle("") // Hide Default Title
        .navigationBarHidden(true)
        .background(Color.black.ignoresSafeArea())
        .task {
            if categories.isEmpty {
                await loadCategories()
            }
        }

    }
    
    // Logic
    
    var filteredCategories: [Category] {
        switch filterState {
        case 1: // Included only
            return categories.filter { isIndexed($0) }
        case 2: // Not Included only
            return categories.filter { !isIndexed($0) }
        default: // All
            return categories
        }
    }
    
    func isLocked(_ category: Category) -> Bool {
        return StalkerClient.defaultIndexedCategoryIDs.contains(category.id)
    }
    
    func isIndexed(_ category: Category) -> Bool {
        if isLocked(category) { return true }
        return prefs.isActionIndexed(category.id)
    }
    
    func toggle(_ category: Category) {
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
            if !client.isAuthenticated {
                try await client.authenticate()
            }
            
            let cats = try await client.getCategories(type: "vod")
            await MainActor.run {
                self.categories = cats
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Row Component
struct IndexPreferenceRow: View {
    let category: Category
    let isIndexed: Bool
    let isLocked: Bool
    let action: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: {
            if !isLocked { action() }
        }) {
            HStack {
                Text(category.title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(isFocused ? .black : (isLocked ? .gray : .white))
                
                Spacer()
                
                // Visual Checkmark / Circle
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundColor(isFocused ? .black.opacity(0.5) : .gray)
                        .padding(.trailing, 8)
                }
                
                Image(systemName: isIndexed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(
                        isIndexed ?
                            (isLocked ? (isFocused ? .black : .gray) : (isFocused ? .black : .blue))
                            : (isFocused ? .black : .gray)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .buttonStyle(.plain)
        // REMOVED: .disabled(isLocked) - This prevents focus on tvOS, breaking scroll.
        // We handle the "no-op" logic in the action closure instead.
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.2), value: isFocused)
        .opacity(isLocked && !isFocused ? 0.6 : 1.0) // Dim locked items slightly unless focused
    }
}
