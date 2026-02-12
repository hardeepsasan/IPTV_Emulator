#if os(iOS)
//
//  IPTV_Link_iOSApp.swift
//  IPTV Link iOS
//
//  Created by hardeepsasan on 2/9/26.
//

import SwiftUI

@main
struct IPTV_Link_iOSApp: App {
    var body: some Scene {
        WindowGroup {
            iOSRootView()
                .environmentObject(PreferenceManager.shared) // Inject shared preferences
                .environmentObject(WatchlistManager()) // Inject watchlist manager
                .environmentObject(PlaybackManager()) // Inject playback manager
        }
    }
}
#endif
