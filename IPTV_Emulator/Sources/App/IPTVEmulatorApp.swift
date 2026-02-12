import SwiftUI

@main
struct IPTVEmulatorApp: App {
    // 1. AppStorage binds to UserDefaults.
    // NOTE: Defaults here are fallbacks. DeviceInfoManager should pre-populate them on first launch.
    @AppStorage("settings_mac_address") private var macAddress: String = ""
    @AppStorage("settings_portal_url") private var portalURL: String = "" // Empty default triggers WelcomeView
    
    // Configuration Settings
    @AppStorage("settings_serial_number") private var serialNumber: String = ""
    @AppStorage("settings_device_id") private var deviceId: String = ""
    @AppStorage("settings_device_id2") private var deviceId2: String = ""
    @AppStorage("settings_signature") private var signature: String = ""
    @AppStorage("settings_user_agent") private var userAgent: String = ""
    
    @StateObject private var watchlistManager = WatchlistManager()
    @StateObject private var playbackManager = PlaybackManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    
    init() {
        // 2. Ensure Identity Exists (First Run Logic)
        DeviceInfoManager.shared.ensureIdentityExists()
    }
    
    var body: some Scene {
        WindowGroup {
//            // DEBUG: Force Reset (Uncomment to test Welcome Flow)
//            Button("Reset Identity") {
//                UserDefaults.standard.removeObject(forKey: "settings_portal_url")
//                UserDefaults.standard.removeObject(forKey: "settings_mac_address")
//            }
            
            // 3. Conditional Navigation
            if portalURL.isEmpty {
                WelcomeView()
                    .environmentObject(networkMonitor)
                    .preferredColorScheme(.dark)
            } else {
                // Pass config to a root view that holds the shared StateObject
                // Adding .id forces a full reload when settings change, effectively resetting the StalkerClient
                AuthenticatedRootView(
                    macAddress: macAddress,
                    portalURL: portalURL,
                    serialNumber: serialNumber,
                    deviceId: deviceId,
                    deviceId2: deviceId2,
                    signature: signature,
                    userAgent: userAgent
                )
                .id(macAddress + portalURL + serialNumber + deviceId + deviceId2 + signature + userAgent)
                .environmentObject(watchlistManager)
                .environmentObject(playbackManager)
                .environmentObject(networkMonitor)
                .preferredColorScheme(.dark)
            }
        }
    }
}

struct AuthenticatedRootView: View {
    @StateObject private var stalkerClient: StalkerClient
    @EnvironmentObject var networkMonitor: NetworkMonitor // Access Network Monitor
    
    init(macAddress: String, portalURL: String, serialNumber: String, deviceId: String, deviceId2: String, signature: String, userAgent: String) {
        // Initialize StateObject with current settings
        _stalkerClient = StateObject(wrappedValue: StalkerClient(
            portalURL: portalURL,
            macAddress: macAddress,
            serialNumber: serialNumber,
            deviceId: deviceId,
            deviceId2: deviceId2,
            signature: signature,
            userAgent: userAgent
        ))
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            MainTabView(stalkerClient: stalkerClient)
                .environmentObject(stalkerClient)
            
            // Global Offline Notification
            if !networkMonitor.isConnected {
                OfflineNotificationView()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 60)
                    .padding(.trailing, 60)
                    .zIndex(999)
            }
        }
        .onChange(of: networkMonitor.isConnected) { isConnected in
            if isConnected {
                print("App: Network Restored. Triggering Indexer...")
                Task {
                    // "force: false" means it will only index if needed (cache empty or stale)
                    await stalkerClient.buildSearchIndex(force: false)
                }
            }
        }
    }
}

