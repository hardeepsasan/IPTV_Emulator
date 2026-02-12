import SwiftUI

struct ContentPreferencesView: View {
    @EnvironmentObject var client: StalkerClient
    @ObservedObject var prefs = PreferenceManager.shared
    
    @State private var movieCategories: [Category] = []
    @State private var seriesCategories: [Category] = []
    @State private var channelGenres: [Category] = [] 
    
    @State private var isLoading = false
    @State private var selectedTab = 0
    
    @State private var filterState = 0 // 0: All, 1: Selected, 2: Not Selected
    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - Frozen Header
            VStack(spacing: 30) {
                
                // 1. Title (Centered)
                Text("Content Preferences")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                
                // 2. Tab Picker (Prominent)
                Picker("Content Type", selection: $selectedTab) {
                    Text("Movies").tag(0)
                    Text("Channels").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 600)
                .onChange(of: selectedTab) {
                     // Tab switch
                }
                

                
                // 4. Visibility Filter Picker & Controls
                HStack(alignment: .center, spacing: 40) {
                    
                    Text("Filter:")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Picker("Filter", selection: $filterState) {
                        Text("All").tag(0)
                        Text("Selected").tag(1)
                        Text("Not Selected").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 700)
                    
                    Spacer()
                    
                    // Stats
                    Text("\(currentList.count) Results")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 40)
                
                // 4. Action Bar (Select All)
                HStack {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading content...")
                        }
                        .foregroundColor(.gray)
                    } else {
                        Button(action: toggleAll) {
                            HStack(spacing: 12) {
                                Image(systemName: isSelectAllAction ? "checkmark.circle" : "xmark.circle")
                                Text(isSelectAllAction ? "Select All" : "Deselect All")
                            }
                            .font(.headline)
                            .padding(.horizontal, 25)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 30)
            .background(Color.black.ignoresSafeArea()) // Opaque Header
            .zIndex(1)
            
            // MARK: - Scrolling List
            List {
                ForEach(currentList) { item in
                    PreferenceRow(item: item, isVisible: prefs.isCategoryVisible(item.id)) {
                         toggle(item.id)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 2, leading: 40, bottom: 2, trailing: 40))
                }
            }
            .listStyle(.plain)
            .background(Color.black)
        }
        .navigationTitle("") // Hide Default Title
        .navigationBarHidden(true)
        .background(Color.black.ignoresSafeArea())
        .task {
            await loadData()
        }
    }
    
    // ... logic remains ...
    
    var currentList: [Category] {
        let baseList: [Category]
        switch selectedTab {
        case 0: baseList = movieCategories
        case 2: baseList = channelGenres
        default: baseList = []
        }
        
        switch filterState {
        case 1: // Selected Only
            return baseList.filter { prefs.isCategoryVisible($0.id) }
        case 2: // Not Selected Only
            return baseList.filter { !prefs.isCategoryVisible($0.id) }
        default: // All
            return baseList
        }
    }
    
    var isSelectAllAction: Bool {
        return currentList.contains { !prefs.isCategoryVisible($0.id) }
    }
    
    func toggleAll() {
        let shouldSelect = isSelectAllAction
        for item in currentList {
            prefs.setVisible(item.id, isVisible: shouldSelect)
        }
    }
    
    func toggle(_ id: String) {
        let isVisible = prefs.isCategoryVisible(id)
        prefs.setVisible(id, isVisible: !isVisible)
    }
    
    func loadData() async {
        // ... (existing load logic) ...
        guard movieCategories.isEmpty else { return }
        isLoading = true
        do {
            async let movies = client.getCategories(type: "vod")
            async let channels = client.getCategories(type: "itv")
            let (m, c) = try await (movies, channels)
            
            await MainActor.run {
                // Sort Movies (Default / Alphabetical order - or server order)
                // We keep server order or simple alphabetical if needed, but remove custom user preferences reorder logic.
                // Assuming server returns them in a reasonable default order.
                self.movieCategories = m
                
                // Sort Channels
                self.channelGenres = c
                
                if !prefs.hasUserSetPreferences {
                    let allIds = m.map{$0.id} + c.map{$0.id}
                    prefs.setAllVisible(allIds)
                }
                isLoading = false
            }
        } catch {
             print("Failed to load: \(error)")
             await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Subcomponents
struct PreferenceRow: View {
    let item: Category
    let isVisible: Bool
    let action: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(item.title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(isFocused ? .black : .white)
                
                Spacer()
                
                // Visual Checkmark / Circle
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isVisible ? (isFocused ? .black : .blue) : (isFocused ? .black : .gray))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14) // Standard Row Height
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain) // Custom layout handles focus visuals
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.2), value: isFocused)
    }
}
