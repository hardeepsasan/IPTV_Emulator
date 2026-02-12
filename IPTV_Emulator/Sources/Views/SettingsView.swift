import SwiftUI
import Combine

struct SettingsView: View {
    // Dependencies
    @ObservedObject var client: StalkerClient // [NEW] Needed for Manifest Generation
    @ObservedObject var manifestGen = ManifestGenerator.shared // [NEW]
    @ObservedObject var prefs = PreferenceManager.shared // [NEW] Global Sort
    
    init(client: StalkerClient) {
        self.client = client
    }

    


    
    @AppStorage("settings_mac_address") private var macAddress: String = "00:1A:79:7D:7B:F4"
    @AppStorage("settings_portal_url") private var portalURL: String = "https://ipro4k.rocd.cc"
    @AppStorage("settings_provider_url") private var providerURL: String = "" // USER FACING


    @AppStorage("settings_serial_number") private var serialNumber: String = StalkerClient.defaultSerialNumber
    @AppStorage("settings_device_id") private var deviceId: String = StalkerClient.defaultDeviceId
    @AppStorage("settings_device_id2") private var deviceId2: String = StalkerClient.defaultDeviceId2
    @AppStorage("settings_signature") private var signature: String = StalkerClient.defaultSignature
    @AppStorage("settings_user_agent") private var userAgent: String = StalkerClient.defaultUserAgent
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var watchlistManager: WatchlistManager
    
    @State private var showClearHistoryAlert = false
    @State private var showClearWatchlistAlert = false
    @State private var showClearCacheAlert = false
    // Confirmation Alerts
    @State private var showRefreshIndexAlert = false
    @State private var showResetDefaultsAlert = false
    @State private var showGenerateMacAlert = false
    @State private var showResetSetupAlert = false
    @State private var showDebugStaleCacheAlert = false
    @State private var showGenerateManifestAlert = false
    
    // Auth Simplification State
    @State private var showAdvancedSettings = false
    @State private var isResolvingURL = false
    
    // [FIX] Buffered URL State to prevent App Restart on every keystroke
    @State private var tempProviderURL: String = ""
    @State private var tempPortalURL: String = ""
    @State private var tempMacAddress: String = ""
    
    // Advanced Tools Security
    @State private var isAdvancedToolsUnlocked = false
    @State private var showUnlockAlert = false
    @State private var showUnlockError = false
    @State private var unlockPasswordInput = ""
    @State private var pendingAction: (() -> Void)?
    private let adminPassword = "10072020"
    @State private var tempSerialNumber: String = ""
    @State private var tempDeviceId: String = ""
    @State private var tempDeviceId2: String = ""
    @State private var tempSignature: String = ""
    @State private var tempUserAgent: String = ""
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                // Main Content
                Form {
                    // Spacer for the header
                    Section {
                         EmptyView()
                    }
                    .listRowBackground(Color.clear)
                    .frame(height: 180) // Increased to clear opaque header completely 
                    
                    Section(header: Text("Content")) {
                        NavigationLink(destination: ContentPreferencesView()) {
                           Text("Content Preferences")
                        }
                        
                        // Sort Content
                        Picker("Sort Content", selection: $prefs.globalSortOption) {
                            ForEach(PreferenceManager.GlobalSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        
                        // Indexing Preferences
                        NavigationLink(destination: IndexSettingsView(client: client)) {
                            SettingsActionRow("Indexing Preferences", icon: "slider.horizontal.3")
                        }
                        
                        // Refresh Database (Action)
                        Button(action: {
                            showRefreshIndexAlert = true
                        }) {
                            RefreshDatabaseRow(client: client)
                        }
                        .alert("Refresh Movie Database?", isPresented: $showRefreshIndexAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Refresh") {
                                Task {
                                    client.buildSearchIndex(force: true)
                                }
                            }
                        } message: {
                            Text("This will check for updates to your movie library. If new movies are found, they will be added.")
                        }
                        
                        // DEBUG: Simulate Stale Cache

                        
                        Button(action: {
                            showClearHistoryAlert = true
                        }) {
                            SettingsActionRow("Clear Continue Watching History", color: .red)
                        }
                        .alert("Clear History", isPresented: $showClearHistoryAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Clear", role: .destructive) {
                                playbackManager.clearHistory()
                            }
                        } message: {
                            Text("Are you sure you want to clear your watching history? This cannot be undone.")
                        }
                        
                        Button(action: {
                            showClearWatchlistAlert = true
                        }) {
                            SettingsActionRow("Clear My List", color: .red)
                        }
                        .alert("Clear My List", isPresented: $showClearWatchlistAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Clear", role: .destructive) {
                                watchlistManager.clearWatchlist()
                            }
                        } message: {
                            Text("Are you sure you want to remove all items from My List? This cannot be undone.")
                        }
                        

                    }
                    
                    Section(header: Text("Connection")) {
                        Group {
                            VStack(alignment: .leading, spacing: 2) {
                                // Bind to TEMP variable
                                Text("Portal URL")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                TextField("Enter http://ipro.gol.ci", text: $tempProviderURL, onEditingChanged: { editing in
                                    if !editing {
                                        // COMMIT Change only when done editing
                                        if tempProviderURL != providerURL {
                                            print("Settings: Committing URL Change: \(tempProviderURL)")
                                            providerURL = tempProviderURL
                                            resolvePortalURL()
                                        }
                                    }
                                })
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            
                                if isResolvingURL {
                                    Text("Checking for redirects...")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            // READ ONLY: System/Actual URL
                            if !portalURL.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("System/Actual URL")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    TextField("https://...", text: .constant(portalURL))
                                        .foregroundColor(.gray)
                                        .disabled(true)
                                }
                            }
                            // Removed duplicate listRowBackground on VStack if present previously
                        
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Virtual Mac")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                TextField("MAC Address", text: $tempMacAddress, onEditingChanged: { editing in
                                    if !editing {
                                        if tempMacAddress != macAddress {
                                            print("Settings: Committing MAC Change: \(tempMacAddress)")
                                            macAddress = tempMacAddress
                                            handleMacChange(tempMacAddress)
                                        }
                                    }
                                })
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                            }
                        

                        
                            // MOVED: "Generate New Virtual MAC" to Advanced Tools

                            Text("Format: 00:1A:79:XX:XX:XX")
                                .font(.caption)
                                .foregroundColor(.gray)
                                
                            Toggle("Show Advanced Identity", isOn: $showAdvancedSettings)
                                .padding(.top, 8)
                            
                            if showAdvancedSettings {
                                Group {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Serial Number")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        TextField("Serial Number", text: $tempSerialNumber, onEditingChanged: { editing in
                                            if !editing && tempSerialNumber != serialNumber {
                                                serialNumber = tempSerialNumber
                                                client.serialNumber = tempSerialNumber
                                            }
                                        })
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                            Text("Device ID")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            TextField("Device ID", text: $tempDeviceId, onEditingChanged: { editing in
                                                if !editing && tempDeviceId != deviceId {
                                                    deviceId = tempDeviceId
                                                    client.deviceId = tempDeviceId
                                                }
                                            })
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Device ID 2")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        TextField("Device ID 2", text: $tempDeviceId2, onEditingChanged: { editing in
                                            if !editing && tempDeviceId2 != deviceId2 {
                                                deviceId2 = tempDeviceId2
                                                client.deviceId2 = tempDeviceId2
                                            }
                                        })
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Signature")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        TextField("Signature", text: $tempSignature, onEditingChanged: { editing in
                                            if !editing && tempSignature != signature {
                                                signature = tempSignature
                                                client.signature = tempSignature
                                            }
                                        })
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("User Agent")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        TextField("User Agent", text: $tempUserAgent, onEditingChanged: { editing in
                                            if !editing && tempUserAgent != userAgent {
                                                userAgent = tempUserAgent
                                                client.userAgent = tempUserAgent
                                            }
                                        })
                                    }
                                    
                                    // Device Model Selector
                                    Menu {
                                        Button(action: {
                                            tempUserAgent = StalkerClient.legacyUserAgent
                                            userAgent = StalkerClient.legacyUserAgent
                                            client.userAgent = StalkerClient.legacyUserAgent
                                            client.objectWillChange.send()
                                        }) {
                                            Label("Legacy (MAG200)", systemImage: "clock.arrow.circlepath")
                                        }
                                        
                                        Button(action: {
                                            tempUserAgent = StalkerClient.defaultUserAgent
                                            userAgent = StalkerClient.defaultUserAgent
                                            client.userAgent = StalkerClient.defaultUserAgent
                                            client.objectWillChange.send()
                                        }) {
                                            Label("Modern (MAG322)", systemImage: "sparkles")
                                        }
                                        
                                        Button(action: {
                                            tempUserAgent = StalkerClient.mag324UserAgent
                                            userAgent = StalkerClient.mag324UserAgent
                                            client.userAgent = StalkerClient.mag324UserAgent
                                            client.objectWillChange.send()
                                        }) {
                                            Label("Ultra (MAG324)", systemImage: "bolt.fill")
                                        }
                                    } label: {
                                        HStack {
                                            Text("Emulation Profile")
                                                .foregroundColor(.primary)
                                            Spacer()
                                            if userAgent.contains("MAG324") {
                                                Text("Ultra (MAG324)")
                                                    .foregroundColor(.purple)
                                                Image(systemName: "bolt.fill")
                                                    .foregroundColor(.purple)
                                            } else if userAgent.contains("MAG322") {
                                                Text("Modern (MAG322)")
                                                    .foregroundColor(.blue)
                                                Image(systemName: "sparkles")
                                                    .foregroundColor(.blue)
                                            } else {
                                                Text("Legacy (MAG200)")
                                                    .foregroundColor(.orange)
                                                Image(systemName: "clock.arrow.circlepath")
                                                    .foregroundColor(.orange)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                    Button(role: .destructive, action: {
                                        showResetDefaultsAlert = true
                                    }) {
                                        Text("Reset to Defaults")
                                    }
                                    .alert("Reset Identity to Defaults?", isPresented: $showResetDefaultsAlert) {
                                        Button("Cancel", role: .cancel) { }
                                        Button("Reset", role: .destructive) {
                                            resetDefaults()
                                        }
                                    } message: {
                                        Text("This will restore the original Serial Number, Device ID 1/2, and Signature. It does NOT clear your MAC address or login URL.")
                                    }
                                }
                                .listRowBackground(Color.white.opacity(0.1))
                            }
                            Button(role: .destructive, action: {
                               showResetSetupAlert = true
                            }) {
                                 SettingsActionRow("Reset Setup (Logout)", icon: "rectangle.portrait.and.arrow.right", color: .red, rightIcon: true)
                            }
                            .padding(.top, 8)
                            .alert("Reset Setup?", isPresented: $showResetSetupAlert) {
                                Button("Cancel", role: .cancel) { }
                                Button("Reset", role: .destructive) {
                                   // CLEAR Settings to Trigger WelcomeView
                                   UserDefaults.standard.removeObject(forKey: "settings_portal_url")
                                   UserDefaults.standard.removeObject(forKey: "settings_provider_url")
                                   // Trigger Logic
                                   portalURL = ""
                                   providerURL = ""
                                }
                            } message: {
                                Text("This will remove all connection details and return you to the Welcome screen. Are you sure?")
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.1))
                    }

                    

                    

                    

                    
                    Section(header: Text("Advanced Tools")) {
                        // Generate New Virtual MAC (Moved & Protected)
                        Button(action: {
                            performProtectedAction {
                                showGenerateMacAlert = true
                            }
                        }) {
                            SettingsActionRow("Generate New Virtual MAC", icon: isAdvancedToolsUnlocked ? nil : "lock.fill", color: .blue)
                        }
                        .alert("Generate New MAC?", isPresented: $showGenerateMacAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Generate", role: .destructive) {
                                // Generate new MAC with 00:1A:79 prefix
                                let prefix = "00:1A:79"
                                let suffix = (0..<3).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined(separator: ":")
                                let newMac = "\(prefix):\(suffix)"
                                
                                // Update State and Trigger Change Logic
                                tempMacAddress = newMac
                                macAddress = newMac
                                handleMacChange(newMac)
                                print("Settings: Generated New MAC: \(newMac)")
                            }
                        } message: {
                            Text("This will change your device identity. You may need to ask your provider to reset your MAC address.")
                        }

                        // Debug: Simulate Stale Cache
                        Button(action: {
                            performProtectedAction {
                                showDebugStaleCacheAlert = true
                            }
                        }) {
                            SettingsActionRow("Debug: Simulate Stale Cache (>24h)", icon: isAdvancedToolsUnlocked ? nil : "lock.fill", color: .orange)
                        }
                        .alert("Simulate Stale Cache?", isPresented: $showDebugStaleCacheAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Simulate", role: .destructive) {
                                // Set timestamp to 49 hours ago (safe margin for >24h check)
                                let staleDate = Date().addingTimeInterval(-49 * 3600)
                                // CRITICAL: Update BOTH keys because app uses split keys (Indexer uses date, UI uses timestamp)
                                UserDefaults.standard.set(staleDate, forKey: "last_index_date")
                                UserDefaults.standard.set(staleDate.timeIntervalSince1970, forKey: "last_index_timestamp")
                                // Force client to invalidate computed property notification
                                client.objectWillChange.send()
                                print("DEBUG: Set last_index_timestamp to \(staleDate)")
                            }
                        } message: {
                            Text("This will trick the app into thinking the database is 48 hours old to test auto-refresh logic. Are you sure?")
                        }
                        
                        // Clear Movie Cache
                        Button(action: {
                            performProtectedAction {
                                showClearCacheAlert = true
                            }
                        }) {
                            ClearCacheRow(client: client, isLocked: !isAdvancedToolsUnlocked)
                        }
                        .alert("Clear Cache?", isPresented: $showClearCacheAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Clear", role: .destructive) {
                                client.clearCache()
                            }
                        } message: {
                            Text("This will remove all cached movies and index data. The app will need to re-index on next launch.")
                        }
                        
                        Button(action: {
                            performProtectedAction {
                                showGenerateManifestAlert = true
                            }
                        }) {
                            SettingsActionRow("Generate Logo Manifest", icon: isAdvancedToolsUnlocked ? nil : "lock.fill", color: .blue)
                        }
                        .disabled(manifestGen.isGenerating)
                        .alert("Generate Logo Manifest?", isPresented: $showGenerateManifestAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Generate") {
                                Task {
                                    await manifestGen.generateManifest(client: client)
                                }
                            }
                        } message: {
                            Text("This will scan all channels to build a logo mapping file (JSON). This process may take a while.")
                        }
                        
                        if manifestGen.isGenerating {
                            ProgressView()
                        }
                        
                        if !manifestGen.progressMessage.isEmpty {
                            Text(manifestGen.progressMessage)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        if let url = manifestGen.generatedJSONURL {
                             // Path Display
                             Text("Full Path: \(url.path)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.leading)
                             
                             // Share Link (iOS 16+ / macOS 13+)
                             #if os(iOS) || os(macOS)
                             ShareLink(item: url) {
                                 Label("Export JSON", systemImage: "square.and.arrow.up")
                             }
                             #else
                             Text("Check Xcode Console for JSON Content")
                                .font(.caption2)
                                .foregroundColor(.blue)
                             #endif
                        }
                        
                        if let missingUrl = manifestGen.generatedMissingJSONURL {
                             Divider()
                             Text("Missing Logos Report:")
                                .font(.caption)
                                .foregroundColor(.gray)
                                
                             // Path Display
                             Text("Full Path: \(missingUrl.path)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.leading)
                             
                             // Share Link
                             #if os(iOS) || os(macOS)
                             ShareLink(item: missingUrl) {
                                 Label("Export Missing Logos", systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")
                             }
                             #endif
                        }
                    }
                    
                    Section(header: Text("About")) {
                        // NEW: Subscription Info
                        if let expiry = client.subscriptionExpiration {
                            HStack {
                                Text("Subscription Expires")
                                Spacer()
                                Text(expiry.formatted(date: .long, time: .omitted))
                                    .foregroundColor(.gray)
                            }
                        }
                        NavigationLink(destination: FAQView()) {
                            HStack {
                                Text("Help")
                                Spacer()
                                Image(systemName: "questionmark.circle")
                            }
                        }
                        
                        Button(action: {}) {
                            HStack {
                                Text("IPTV Link v1.0")
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {}) {
                            HStack {
                                Text("Emulates MAG322 / Stalker Middleware")
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Spacer for bottom overscan / clipping
                    Section {
                         EmptyView()
                    }
                    .listRowBackground(Color.clear)
                    .frame(height: 100)
                }
                .background(Color.black.ignoresSafeArea())
                
                // Custom Sticky Header
                VStack {
                    Text("Settings")
                        .font(.title3) // Reduced size for polish
                        .fontWeight(.bold)
                        .padding(.bottom, 20)
                        .padding(.top, 120) // INCREASED PADDING (60 -> 120)
                        .frame(maxWidth: .infinity)
                        .background(Color.black) // OPAQUE BACKGROUND
                        .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 10) // Shadow to mask content underneath
                }
                .edgesIgnoringSafeArea(.top)
            }
            .unlockAlert(isPresented: $showUnlockAlert, isError: $showUnlockError, password: $unlockPasswordInput) {
                isAdvancedToolsUnlocked = true
                if let action = pendingAction {
                    action()
                    pendingAction = nil
                }
            }
            .navigationBarHidden(true) // Hide Native Bar
            .onAppear {
                // Initialize Temp Buffer
                if providerURL.isEmpty && !portalURL.isEmpty {
                    providerURL = portalURL
                }
                tempProviderURL = providerURL
                tempPortalURL = portalURL
                tempMacAddress = macAddress
                tempSerialNumber = serialNumber
                tempDeviceId = deviceId
                tempDeviceId2 = deviceId2
                tempSignature = signature
                tempUserAgent = userAgent
            }
        }
    }
    
    private func resetDefaults() {
        // Portal URL kept as current default for safety, but could be reset too
        macAddress = "00:1A:79:7D:7B:F4"
        portalURL = "https://ipro4k.rocd.cc"
        providerURL = ""
        
        serialNumber = StalkerClient.defaultSerialNumber
        deviceId = StalkerClient.defaultDeviceId
        deviceId2 = StalkerClient.defaultDeviceId2
        signature = StalkerClient.defaultSignature
        userAgent = StalkerClient.defaultUserAgent
    }
    
    // MARK: - Auth Simplification Logic
    
    private func handleMacChange(_ newMac: String) {
        // 1. Sync to Client immediately so app reacts
        client.macAddress = newMac
        
        // 2. Deterministic Generation Logic
        // SAFETY: Do NOT change IDs for the known legacy MAC
        // Legacy MAC: 00:1A:79:7D:7B:F4
        let legacyMac = "00:1A:79:7D:7B:F4"
        
        if newMac.uppercased() == legacyMac {
            // Restore legacy defaults if not already set? 
            // Or just leave them alone. User said "Preserve existing ones".
            // If they manually type the legacy MAC, we should ensure the LEGACY IDs are there.
            serialNumber = StalkerClient.defaultSerialNumber
            deviceId = StalkerClient.defaultDeviceId
            deviceId2 = StalkerClient.defaultDeviceId2
            signature = StalkerClient.defaultSignature
            print("Settings: Restored Legacy Identity for \(legacyMac)")
        } else {
            // For any OTHER mac, auto-generate identity
            // Only if "Advanced" is NOT shown (implies user wants auto-config)
            if !showAdvancedSettings {
                let identity = IdentityGenerator.generate(for: newMac)
                serialNumber = identity.serialNumber
                deviceId = identity.deviceId
                deviceId2 = identity.deviceId2
                signature = identity.signature
                print("Settings: Auto-Generated Identity for \(newMac)")
            }
        }
        
        client.deviceId2 = deviceId2
        client.signature = signature
    }
    
    // MARK: - Advanced Tools Security
    private func performProtectedAction(action: @escaping () -> Void) {
        if isAdvancedToolsUnlocked {
            action()
        } else {
            pendingAction = action
            unlockPasswordInput = ""
            showUnlockAlert = true
        }
    }
    
    
    private func resolvePortalURL() {
        guard let url = URL(string: providerURL), let scheme = url.scheme, ["http", "https"].contains(scheme) else { return }
        
        isResolvingURL = true
        Task {
            // Use StalkerClient's robust resolve
            print("Settings: Resolving \(providerURL)...")
            let resolved = await StalkerClient.resolveURL(providerURL)
            
            await MainActor.run {
                self.portalURL = resolved
                self.client.portalURL = URL(string: resolved) ?? url
                self.isResolvingURL = false
                print("Settings: Resolved \(providerURL) -> \(resolved)")
            }
        }
    }
}

// MARK: - Unlock Alert Extension
extension View {
    func unlockAlert(isPresented: Binding<Bool>, isError: Binding<Bool>, password: Binding<String>, onUnlock: @escaping () -> Void) -> some View {
        self.alert(isError.wrappedValue ? "Incorrect Password" : "Advanced Tools Locked", isPresented: isPresented) {
            SecureField("Password", text: password)
            Button("Cancel", role: .cancel) {
                isError.wrappedValue = false
            }
            Button("Unlock") {
                if password.wrappedValue == "10072020" {
                    onUnlock()
                    isError.wrappedValue = false
                } else {
                    // Feedback Logic:
                    // 1. Set Error State
                    isError.wrappedValue = true
                    
                    // 2. Clear Password? (Optional, maybe keep for correction - usually clearing is better for security/feedback)
                    password.wrappedValue = ""
                    
                    // 3. Re-present Alert
                    // SwiftUI Alerts dismiss on button tap. We need to trigger it again.
                    // A small delay ensures the dismissal animation completes or state resets.
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                        await MainActor.run {
                            isPresented.wrappedValue = true
                        }
                    }
                }
            }
        } message: {
            Text(isError.wrappedValue ? "Please try again." : "Enter admin password to proceed.")
        }
    }
}


struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(client: StalkerClient(macAddress: "00:00:00:00:00:00"))
    }
}

// MARK: - FAQ View
struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

struct FAQView: View {
    private let faqs: [FAQItem] = [
        FAQItem(
            question: "How do I connect to my provider?",
            answer: "Enter your Portal URL (provided by your service) in the 'Portal URL' field on the Welcome Screen or Settings. You must also share the 'Virtual MAC' address shown on the screen with your provider for registration."
        ),
        FAQItem(
            question: "Why are some categories empty?",
            answer: "The app builds a search index in the background to make browsing fast. It may take a few minutes for all content to appear initially. You can check the 'Indexer Status' toggle in Settings to see if it is running."
        ),
        FAQItem(
            question: "How do I force a refresh?",
            answer: "Go to Settings > Content Preferences and click 'Clear Cache'. This will force the app to re-scan the server for the latest content."
        ),
        FAQItem(
            question: "What is a 'Virtual MAC'?",
            answer: "This is a unique, safe device identity generated for this specific app installation. It mimics a set-top box so you can register with your provider without exposing your real device hardware."
        ),
        FAQItem(
            question: "My playlist isn't loading / generic error?",
            answer: "1. Ensure your provider supports 'Stalker Portal' (MAG) connections.\n2. Verify you have registered the correct MAC address.\n3. Check your internet connection."
        ),
        FAQItem(
            question: "Why does the indexer stop?",
            answer: "To save bandwidth, the indexer uses 'Smart Sync'. If it sees a page of movies that are already in your cache, it stops downloading automatically because it knows your list is up to date."
        ),
        FAQItem(
            question: "Developer: What does 'Debug: Simulate Stale Cache' do?",
            answer: "This tool manually expires the database timestamp (sets it to 48 hours ago). It is used to verify that the app correctly detects an old database and triggers an auto-refresh on launch."
        ),
        FAQItem(
            question: "Developer: What does 'Clear Movie Cache' do?",
            answer: "This completely wipes the local database of movies and resets the indexing status. Use this if you are experiencing data corruption, missing entries, or want to start fresh."
        ),
        FAQItem(
            question: "Developer: What does 'Generate Logo Manifest' do?",
            answer: "This developer tool scans your current playlist and creates a JSON file mapping channel names to their logo URLs. It is used for creating logo packs or debugging missing assets."
        ),
         FAQItem(
            question: "What does 'Reset to Defaults' do?",
            answer: "This restores the advanced identity fields (Serial Number, Device IDs, Signature) to their initial values. It is useful if you have manually changed them and messed up your connection."
        ),
        FAQItem(
            question: "What does 'Reset Setup (Logout)' do?",
            answer: "This completely logs you out by removing the saved Portal URL and MAC Address. You will be returned to the Welcome screen to start over."
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - Scrolling List
            List {
                Section(header: 
                    Text("FAQ & Troubleshooting")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                        .padding(.bottom, 10)
                ) {
                    ForEach(faqs) { item in
                        FAQRow(item: item)
                    }
                }
                
                Section(header: 
                    Text("Contact us")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                        .padding(.bottom, 10)
                ) {
                    ContactRow()
                }
            }
            .listStyle(.plain)
            .background(Color.black)
        }
        .navigationBarHidden(true)
        .background(Color.black.ignoresSafeArea())
    }
}

// Helper Row to handle Focus State
struct ContactRow: View {
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: {}) {
            HStack {
                Text("Support Email")
                    .foregroundColor(isFocused ? .black : .white)
                Spacer()
                Text("infotainment.dr@gmail.com")
                    .foregroundColor(isFocused ? .black : .gray)
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .focused($isFocused) // Bind focus state to the button
    }
}

// Custom Row for tvOS Compatibility (DisclosureGroup unavailable)
struct FAQRow: View {
    let item: FAQItem
    @State private var isExpanded: Bool = false
    @Environment(\.isFocused) var isFocused // Track focus state
    
    var body: some View {
        Button(action: {
            withAnimation {
                isExpanded.toggle()
            }
        }) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.question)
                        .font(.headline)
                        .foregroundColor(isFocused ? .black : .primary) // Explicit contrast fix for tvOS
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(isFocused ? .darkGray : .gray)
                        .font(.caption)
                }
                
                if isExpanded {
                    Text(item.answer)
                        .font(.body)
                        .foregroundColor(isFocused ? .black : .secondary) // Ensure answer is also readable if expanded while focused
                        .padding(.top, 5)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain) // Important for List behavior
    }
}

// Helper color
extension Color {
    static let darkGray = Color(white: 0.3)
}

struct SettingsActionRow: View {
    let title: String
    let icon: String?
    let color: Color
    let rightIcon: Bool
    
    @Environment(\.isFocused) var isFocused
    
    init(_ title: String, icon: String? = nil, color: Color = .primary, rightIcon: Bool = false) {
        self.title = title
        self.icon = icon
        self.color = color
        self.rightIcon = rightIcon
    }
    
    var body: some View {
        HStack {
            if let icon = icon, !rightIcon {
                Image(systemName: icon)
            }
            Text(title)
            if rightIcon {
                Spacer()
                if let icon = icon {
                    Image(systemName: icon)
                }
            }
        }
        .foregroundColor(isFocused ? .black : color)
    }
}

struct RefreshDatabaseRow: View {
    @ObservedObject var client: StalkerClient
    @Environment(\.isFocused) var isFocused
    
    var body: some View {
        HStack {
            Text("Refresh Movie Database")
                .foregroundColor(isFocused ? .black : .primary)
            
            if client.isIndexing {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
            } else if let date = client.lastIndexDate {
                Spacer()
                Text("(\(date.formatted(date: .abbreviated, time: .shortened)) \(TimeZone.current.abbreviation() ?? "") - \(client.lastIndexDurationString))")
                    .font(.caption)
                    .foregroundColor(isFocused ? .black : .gray)
            }
        }
    }
}

struct ClearCacheRow: View {
    @ObservedObject var client: StalkerClient
    var isLocked: Bool = false
    @Environment(\.isFocused) var isFocused
    
    var body: some View {
        HStack {
            if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundColor(isFocused ? .black : .gray)
            }
            Text("Clear Movie Cache")
                .foregroundColor(isFocused ? .black : .red)
            Spacer()
            // Using monospaced for numbers to avoid jitter
            Text(client.cacheSizeString)
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(isFocused ? .black : .gray)
        }
    }
}
