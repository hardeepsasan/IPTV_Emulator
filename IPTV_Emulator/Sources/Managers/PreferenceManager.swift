import Foundation
import Combine
import SwiftUI

class PreferenceManager: ObservableObject {
    static let shared = PreferenceManager()
    
    private let kVisibleCategories = "visible_categories"
    private let kAdditionalIndexedCategories = "additional_indexed_categories"
    
    // We store a Set of IDs that are VISIBLE. 
    // If nil (or empty on first run), we assume ALL are visible.
    // - We can check if the key exists in UserDefaults. If not, return true for all.
    // - Once user saves, we write the set.
    
    private let kTMDBKey = "tmdb_api_key"
    @Published var tmdbAPIKey: String = "8a2379aeed908cded747b51bc0b28f31" {
        didSet { saveAPIKey() }
    }
    
    // We store a Set of IDs that are VISIBLE. 
    
    @Published var additionalIndexedCategoryIds: Set<String> {
        didSet { save() }
    }
    
    @Published var visibleCategoryIds: Set<String> {
        didSet {
            save()
        }
    }

    
    // MARK: - Global Sort Preference
    enum GlobalSortOption: String, CaseIterable, Identifiable {
        case date = "Recently Added"
        case alpha = "A-Z"
        case favorites = "Favorites"
        var id: String { rawValue }
    }
    
    private let kGlobalSortOption = "global_sort_option"
    
    @Published var globalSortOption: GlobalSortOption = .date {
        didSet {
            UserDefaults.standard.set(globalSortOption.rawValue, forKey: kGlobalSortOption)
        }
    }
    
    private let kMovieOrder = "movie_category_order"
    private let kChannelOrder = "channel_category_order"
    
    @Published var movieCategoryOrder: [String] = [] {
        didSet { saveOrders() }
    }
    
    @Published var channelCategoryOrder: [String] = [] {
        didSet { saveOrders() }
    }

    private init() {
        if let indexedArray = UserDefaults.standard.stringArray(forKey: kAdditionalIndexedCategories) {
            self.additionalIndexedCategoryIds = Set(indexedArray)
        } else {
            self.additionalIndexedCategoryIds = []
        }
        
        if let array = UserDefaults.standard.stringArray(forKey: kVisibleCategories) {
            self.visibleCategoryIds = Set(array)
        } else {
            self.visibleCategoryIds = []
        }
        
        if let movies = UserDefaults.standard.stringArray(forKey: kMovieOrder) {
            self.movieCategoryOrder = movies
        }
        
        if let channels = UserDefaults.standard.stringArray(forKey: kChannelOrder) {
            self.channelCategoryOrder = channels
        }
        
        if let key = UserDefaults.standard.string(forKey: kTMDBKey), !key.isEmpty {
            self.tmdbAPIKey = key
        }
        
        if let sortRaw = UserDefaults.standard.string(forKey: kGlobalSortOption), 
           let option = GlobalSortOption(rawValue: sortRaw) {
            self.globalSortOption = option
        }
    }
    
    var hasUserSetPreferences: Bool {
        return UserDefaults.standard.object(forKey: kVisibleCategories) != nil
    }
    
    func save() {
        UserDefaults.standard.set(Array(visibleCategoryIds), forKey: kVisibleCategories)
        UserDefaults.standard.set(Array(additionalIndexedCategoryIds), forKey: kAdditionalIndexedCategories)
    }
    
    func saveOrders() {
        UserDefaults.standard.set(movieCategoryOrder, forKey: kMovieOrder)
        UserDefaults.standard.set(channelCategoryOrder, forKey: kChannelOrder)
    }
    
    func saveAPIKey() {
        UserDefaults.standard.set(tmdbAPIKey, forKey: kTMDBKey)
    }
    
    func isCategoryVisible(_ id: String) -> Bool {
        // Always show mock categories
        if id.hasPrefix("mock_") { return true }
        
        if !hasUserSetPreferences {
            return true // Show all by default if no prefs set
        }
        return visibleCategoryIds.contains(id)
    }
    
    func setAllVisible(_ ids: [String]) {
        visibleCategoryIds = Set(ids)
    }
    
    func setVisible(_ id: String, isVisible: Bool) {
        if isVisible {
            visibleCategoryIds.insert(id)
        } else {
            visibleCategoryIds.remove(id)
        }
    }
    
    func isActionIndexed(_ id: String) -> Bool {
        return additionalIndexedCategoryIds.contains(id)
    }
    
    func setIndexed(_ id: String, isIndexed: Bool) {
        if isIndexed {
            additionalIndexedCategoryIds.insert(id)
        } else {
            additionalIndexedCategoryIds.remove(id)
        }
    }
    
    /// Updates the order for a specific type
    func updateOrder(type: String, newOrder: [String]) {
        if type == "vod" {
            movieCategoryOrder = newOrder
        } else {
            channelCategoryOrder = newOrder
        }
    }
    
    /// Advanced Reorder: Moves an ID relative to another ID in the master list
    func moveCategory(type: String, id: String, toBefore targetId: String?) {
        var list = (type == "vod") ? movieCategoryOrder : channelCategoryOrder
        
        // 1. Remove the moving item if it exists
        guard let sourceIndex = list.firstIndex(of: id) else { return }
        let item = list.remove(at: sourceIndex)
        
        // 2. Find insertion point
        if let tId = targetId, let targetIndex = list.firstIndex(of: tId) {
            // Insert before target
            list.insert(item, at: targetIndex)
        } else {
            // If targetId is nil (end of list) OR target not found (rare), append
            list.append(item)
        }
        
        // 3. Save
        if type == "vod" {
            movieCategoryOrder = list
        } else {
            channelCategoryOrder = list
        }
    }
}
