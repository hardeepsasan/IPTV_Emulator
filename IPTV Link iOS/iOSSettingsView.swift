#if os(iOS)
import SwiftUI

struct iOSSettingsView: View {
    @ObservedObject var client: StalkerClient
    @ObservedObject var manifestGen = ManifestGenerator.shared
    @ObservedObject var prefs = PreferenceManager.shared
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var watchlistManager: WatchlistManager
    
    @AppStorage("settings_mac_address") private var macAddress: String = "00:1A:79:7D:7B:F4"
    @AppStorage("settings_portal_url") private var portalURL: String = "https://ipro4k.rocd.cc"
    @AppStorage("settings_provider_url") private var providerURL: String = ""
    
    @AppStorage("settings_serial_number") private var serialNumber: String = StalkerClient.defaultSerialNumber
    @AppStorage("settings_device_id") private var deviceId: String = StalkerClient.defaultDeviceId
    @AppStorage("settings_device_id2") private var deviceId2: String = StalkerClient.defaultDeviceId2
    @AppStorage("settings_signature") private var signature: String = StalkerClient.defaultSignature
    @AppStorage("settings_user_agent") private var userAgent: String = StalkerClient.defaultUserAgent
    
    // UI State
    @State private var showClearHistoryAlert = false
    @State private var showClearWatchlistAlert = false
    @State private var showClearCacheAlert = false
    @State private var showRefreshIndexAlert = false
    @State private var showDebugStaleCacheAlert = false
    @State private var showResetDefaultsAlert = false
    @State private var showGenerateMacAlert = false
    @State private var showResetSetupAlert = false
    @State private var showGenerateManifestAlert = false
    
    @State private var showAdvancedIdentity = false
    @State private var isResolvingURL = false
    @State private var isAdvancedToolsUnlocked = false
    @State private var showUnlockAlert = false
    @State private var showUnlockError = false
    @State private var unlockPasswordInput = ""
    @State private var pendingAction: (() -> Void)?
    
    // Temp buffers for text fields
    @State private var tempProviderURL: String = ""
    @State private var tempMacAddress: String = ""
    @State private var tempSerialNumber: String = ""
    @State private var tempDeviceId: String = ""
    @State private var tempDeviceId2: String = ""
    @State private var tempSignature: String = ""
    @State private var tempUserAgent: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                ContentManagementSection(client: client, prefs: prefs, showRefreshIndexAlert: $showRefreshIndexAlert)
                
                ConnectionSection(
                    client: client,
                    providerURL: $providerURL,
                    portalURL: $portalURL,
                    macAddress: $macAddress,
                    tempProviderURL: $tempProviderURL,
                    tempMacAddress: $tempMacAddress,
                    isResolvingURL: $isResolvingURL,
                    showAdvancedIdentity: $showAdvancedIdentity,
                    resolvePortalURL: resolvePortalURL,
                    handleMacChange: handleMacChange
                )
                
                if showAdvancedIdentity {
                    IdentitySection(
                        client: client,
                        serialNumber: $serialNumber,
                        deviceId: $deviceId,
                        deviceId2: $deviceId2,
                        signature: $signature,
                        userAgent: $userAgent,
                        tempSerialNumber: $tempSerialNumber,
                        tempDeviceId: $tempDeviceId,
                        tempDeviceId2: $tempDeviceId2,
                        tempSignature: $tempSignature,
                        tempUserAgent: $tempUserAgent,
                        showResetDefaultsAlert: $showResetDefaultsAlert,
                        updateEmulationProfile: updateEmulationProfile,
                        currentProfileName: currentProfileName
                    )
                }
                
                CleanupSection(
                    client: client,
                    playbackManager: playbackManager,
                    watchlistManager: watchlistManager,
                    showClearHistoryAlert: $showClearHistoryAlert,
                    showClearWatchlistAlert: $showClearWatchlistAlert,
                    showClearCacheAlert: { performProtectedAction { showClearCacheAlert = true } }
                )
                
                AdvancedToolsSection(
                    manifestGen: manifestGen,
                    isAdvancedToolsUnlocked: isAdvancedToolsUnlocked,
                    showGenerateMacAlert: { performProtectedAction { showGenerateMacAlert = true } },
                    showGenerateManifestAlert: { performProtectedAction { showGenerateManifestAlert = true } },
                    showDebugStaleCacheAlert: { performProtectedAction { showDebugStaleCacheAlert = true } },
                    client: client
                )
                
                SupportInfoSection(
                    client: client,
                    showResetSetupAlert: $showResetSetupAlert
                )
            }
            .navigationTitle("Settings")
            .onAppear {
                initializeTempBuffers()
                client.calculateCacheSize()
            }
            .settingsAlerts(
                client: client,
                playbackManager: playbackManager,
                watchlistManager: watchlistManager,
                manifestGen: manifestGen,
                showRefreshIndexAlert: $showRefreshIndexAlert,
                showResetDefaultsAlert: $showResetDefaultsAlert,
                showClearHistoryAlert: $showClearHistoryAlert,
                showClearWatchlistAlert: $showClearWatchlistAlert,
                showClearCacheAlert: $showClearCacheAlert,
                showGenerateMacAlert: $showGenerateMacAlert,
                showGenerateManifestAlert: $showGenerateManifestAlert,
                showDebugStaleCacheAlert: $showDebugStaleCacheAlert,
                showResetSetupAlert: $showResetSetupAlert,
                resetDefaults: resetDefaults,
                generateNewMac: generateNewMac,
                simulateStaleCache: simulateStaleCache,
                logout: logout
            )
            .unlockAlert(isPresented: $showUnlockAlert, isError: $showUnlockError, password: $unlockPasswordInput) {
                isAdvancedToolsUnlocked = true
                showUnlockError = false // Clear error on success
                pendingAction?()
                pendingAction = nil
            }
        }
    }
    
    // MARK: - Logic
    
    private func initializeTempBuffers() {
        tempProviderURL = providerURL.isEmpty ? portalURL : providerURL
        tempMacAddress = macAddress
        tempSerialNumber = serialNumber
        tempDeviceId = deviceId
        tempDeviceId2 = deviceId2
        tempSignature = signature
        tempUserAgent = userAgent
    }
    
    private func resolvePortalURL() {
        guard URL(string: providerURL) != nil else { return }
        isResolvingURL = true
        Task {
            let cleanURL = providerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = await StalkerClient.resolveURL(cleanURL)
            await MainActor.run {
                self.portalURL = resolved
                if let url = URL(string: resolved) {
                    self.client.portalURL = url
                }
                self.isResolvingURL = false
            }
        }
    }
    
    private func handleMacChange(_ newMac: String) {
        let identity = IdentityGenerator.generate(for: newMac)
        
        // 1. Sync AppStorage (for UI and persistence)
        serialNumber = identity.serialNumber
        deviceId = identity.deviceId
        deviceId2 = identity.deviceId2
        signature = identity.signature
        
        // 2. Sync Client (Network Engine)
        client.macAddress = newMac
        client.serialNumber = identity.serialNumber
        client.deviceId = identity.deviceId
        client.deviceId2 = identity.deviceId2
        client.signature = identity.signature
        
        // 3. Force Re-Configuration of Session/Cookies
        client.configure(url: portalURL, mac: newMac)
        
        print("Settings: Identity re-synchronized for MAC \(newMac)")
    }
    
    private func generateNewMac() {
        let prefix = "00:1A:79"
        let suffix = (0..<3).map { _ in String(format: "%02X", Int.random(in: 0...255)) }.joined(separator: ":")
        let newMac = "\(prefix):\(suffix)"
        tempMacAddress = newMac
        macAddress = newMac
        handleMacChange(newMac)
    }
    
    private func resetDefaults() {
        macAddress = "00:1A:79:7D:7B:F4"
        portalURL = "https://ipro4k.rocd.cc"
        providerURL = ""
        serialNumber = StalkerClient.defaultSerialNumber
        deviceId = StalkerClient.defaultDeviceId
        deviceId2 = StalkerClient.defaultDeviceId2
        signature = StalkerClient.defaultSignature
        userAgent = StalkerClient.defaultUserAgent
        initializeTempBuffers()
    }
    
    private func simulateStaleCache() {
        // Set timestamp to 49 hours ago (safe margin for >24h check)
        let staleDate = Date().addingTimeInterval(-49 * 3600)
        
        // CRITICAL: Update keys (Indexer uses date via StalkerClient property)
        client.lastIndexDate = staleDate
        
        // ALSO Update the key used by the Indexer logic (StalkerClient.swift:892)
        UserDefaults.standard.set(staleDate, forKey: "last_index_date")
        
        // Re-calculate UI timestamp keys if needed, though client.lastIndexDate setter handles objectWillChange
        print("DEBUG: Set last_index_timestamp AND last_index_date to \(staleDate)")
    }
    
    private func logout() {
        print("iOSSettingsView: Performing Log Out / Reset.")
        
        // 1. Reset Client State (Clears Token -> Triggers RootView change)
        client.logout()
        
        // 2. Clear Persistence
        UserDefaults.standard.removeObject(forKey: "settings_portal_url")
        UserDefaults.standard.removeObject(forKey: "settings_provider_url")
        
        // 3. Clear Local AppStorage bindings
        portalURL = ""
        providerURL = ""
    }
    
    enum EmulationProfile { case legacy, modern, ultra }
    private func updateEmulationProfile(_ profile: EmulationProfile) {
        let ua: String
        switch profile {
        case .legacy: ua = StalkerClient.legacyUserAgent
        case .modern: ua = StalkerClient.defaultUserAgent
        case .ultra: ua = StalkerClient.mag324UserAgent
        }
        userAgent = ua
        client.userAgent = ua
        tempUserAgent = ua
    }
    
    private var currentProfileName: String {
        if userAgent.contains("MAG324") { return "Ultra (MAG324)" }
        if userAgent.contains("MAG322") { return "Modern (MAG322)" }
        return "Legacy (MAG200)"
    }
    
    private func performProtectedAction(action: @escaping () -> Void) {
        if isAdvancedToolsUnlocked {
            action()
        } else {
            pendingAction = action
            unlockPasswordInput = ""
            showUnlockAlert = true
        }
    }
}

// MARK: - Sub-Components

struct ContentManagementSection: View {
    @ObservedObject var client: StalkerClient
    @ObservedObject var prefs: PreferenceManager
    @Binding var showRefreshIndexAlert: Bool
    
    // Helper function to avoid ViewBuilder issues with local variables
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        formatter.timeZone = TimeZone(abbreviation: "EST")
        return formatter.string(from: date)
    }
    

    
    var body: some View {
        Section(header: Text("Content")) {
            NavigationLink(destination: iOSContentPreferencesView(client: client)) {
                Label("Content Preferences", systemImage: "slider.horizontal.3")
            }
            
            NavigationLink(destination: iOSIndexSettingsView(client: client)) {
                Label("Indexing Preferences", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
            }
            
            Picker(selection: $prefs.globalSortOption) {
                ForEach(PreferenceManager.GlobalSortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            } label: {
                Label("Sort Content", systemImage: "arrow.up.arrow.down")
            }
            
            Button(action: { showRefreshIndexAlert = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Refresh Library", systemImage: "arrow.clockwise")
                            .foregroundColor(.primary)
                        
                        if let date = client.lastIndexDate {
                            Text("Last Refreshed: \(formatDate(date)) EST")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            
                            if client.lastIndexDuration > 0 {
                                Text(client.lastIndexDurationString)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    if client.isIndexing {
                        Spacer()
                        ProgressView()
                            .tint(.blue)
                    } else {
                        Spacer()
                    }
                }
            }
        }
    }
}

struct ConnectionSection: View {
    @ObservedObject var client: StalkerClient
    @Binding var providerURL: String
    @Binding var portalURL: String
    @Binding var macAddress: String
    @Binding var tempProviderURL: String
    @Binding var tempMacAddress: String
    @Binding var isResolvingURL: Bool
    @Binding var showAdvancedIdentity: Bool
    
    let resolvePortalURL: () -> Void
    let handleMacChange: (String) -> Void
    
    var body: some View {
        Section(header: Text("Connection")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Provider URL")
                    .font(.caption)
                    .foregroundColor(.gray)
                TextField("Enter Provider URL (e.g. ipro.gol.ci)", text: $tempProviderURL, onEditingChanged: { editing in
                    if !editing && tempProviderURL != providerURL {
                        providerURL = tempProviderURL
                        resolvePortalURL()
                    }
                })
                .keyboardType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Resolved System URL")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    if isResolvingURL {
                        ProgressView().controlSize(.mini)
                    }
                }
                
                Text(portalURL.isEmpty ? "Not resolved" : portalURL)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(portalURL.isEmpty ? .red : .blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Virtual MAC")
                    .font(.caption)
                    .foregroundColor(.gray)
                TextField("MAC Address", text: $tempMacAddress, onEditingChanged: { editing in
                    if !editing && tempMacAddress != macAddress {
                        macAddress = tempMacAddress
                        handleMacChange(tempMacAddress)
                    }
                })
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
            }
            
            Toggle(isOn: $showAdvancedIdentity.animation()) {
                Label("Advanced Identity", systemImage: "person.badge.key")
            }
        }
    }
}

struct IdentitySection: View {
    @ObservedObject var client: StalkerClient
    @Binding var serialNumber: String
    @Binding var deviceId: String
    @Binding var deviceId2: String
    @Binding var signature: String
    @Binding var userAgent: String
    
    @Binding var tempSerialNumber: String
    @Binding var tempDeviceId: String
    @Binding var tempDeviceId2: String
    @Binding var tempSignature: String
    @Binding var tempUserAgent: String
    
    @Binding var showResetDefaultsAlert: Bool
    
    let updateEmulationProfile: (iOSSettingsView.EmulationProfile) -> Void
    let currentProfileName: String
    
    var body: some View {
        Section(header: Text("Identity")) {
            Group {
                IdentityField(label: "Serial Number", text: $tempSerialNumber) {
                    serialNumber = tempSerialNumber
                    client.serialNumber = tempSerialNumber
                }
                IdentityField(label: "Device ID", text: $tempDeviceId) {
                    deviceId = tempDeviceId
                    client.deviceId = tempDeviceId
                }
                IdentityField(label: "Device ID 2", text: $tempDeviceId2) {
                    deviceId2 = tempDeviceId2
                    client.deviceId2 = tempDeviceId2
                }
                IdentityField(label: "Signature", text: $tempSignature) {
                    signature = tempSignature
                    client.signature = tempSignature
                }
                
                Menu {
                    Button("Legacy (MAG200)") { updateEmulationProfile(.legacy) }
                    Button("Modern (MAG322)") { updateEmulationProfile(.modern) }
                    Button("Ultra (MAG324)") { updateEmulationProfile(.ultra) }
                } label: {
                    HStack {
                        Text("Emulation Profile")
                        Spacer()
                        Text(currentProfileName)
                            .foregroundColor(.blue)
                    }
                }
                
                Button("Reset Defaults", role: .destructive) {
                    showResetDefaultsAlert = true
                }
            }
            .font(.subheadline)
        }
    }
}

struct IdentityField: View {
    let label: String
    @Binding var text: String
    let onCommit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            TextField(label, text: $text, onEditingChanged: { editing in
                if !editing { onCommit() }
            })
        }
    }
}

struct CleanupSection: View {
    @ObservedObject var client: StalkerClient
    let playbackManager: PlaybackManager
    let watchlistManager: WatchlistManager
    @Binding var showClearHistoryAlert: Bool
    @Binding var showClearWatchlistAlert: Bool
    let showClearCacheAlert: () -> Void
    
    var body: some View {
        Section(header: Text("Cleanup")) {
            Button(action: { showClearHistoryAlert = true }) {
                Label("Clear Watch History", systemImage: "clock.arrow.2.circlepath")
                    .foregroundColor(.red)
            }
            
            Button(action: { showClearWatchlistAlert = true }) {
                Label("Clear My List", systemImage: "trash")
                    .foregroundColor(.red)
            }
            
            Button(action: showClearCacheAlert) {
                HStack {
                    Label("Clear App Cache", systemImage: "internaldrive")
                        .foregroundColor(.red)
                    Spacer()
                    Text(client.cacheSizeString)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

struct AdvancedToolsSection: View {
    @ObservedObject var manifestGen: ManifestGenerator
    let isAdvancedToolsUnlocked: Bool
    let showGenerateMacAlert: () -> Void
    let showGenerateManifestAlert: () -> Void
    let showDebugStaleCacheAlert: () -> Void
    @ObservedObject var client: StalkerClient
    
    var body: some View {
        Section(header: Text("Advanced Tools")) {
            Button(action: showGenerateMacAlert) {
                Label("Generate New Virtual MAC", systemImage: isAdvancedToolsUnlocked ? "sparkles" : "lock.fill")
            }
            
            Button(action: showGenerateManifestAlert) {
                Label("Generate Logo Manifest", systemImage: isAdvancedToolsUnlocked ? "doc.text.magnifyingglass" : "lock.fill")
            }
            .disabled(manifestGen.isGenerating)
            
            Button(action: { showDebugStaleCacheAlert() }) {
                Label("Debug: Simulate Stale Cache", systemImage: isAdvancedToolsUnlocked ? "clock.arrow.2.circlepath" : "lock.fill")
                    .foregroundColor(.orange)
            }
            
            if manifestGen.isGenerating {
                HStack {
                    ProgressView()
                    Text(manifestGen.progressMessage)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

struct SupportInfoSection: View {
    @ObservedObject var client: StalkerClient
    @Binding var showResetSetupAlert: Bool
    
    var body: some View {
        Section(header: Text("Support & Info")) {
            NavigationLink(destination: iOSFAQView()) {
                Label("Help & FAQ", systemImage: "questionmark.circle")
            }
            
            if let expiry = client.subscriptionExpiration {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Subscription Expires")
                        Spacer()
                        Text(expiry.formatted(date: .long, time: .omitted))
                            .foregroundColor(.gray)
                    }
                    Text("Renewable on this date if on an annual subscription.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .italic()
                }
            }
            
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.gray)
            }
            
            Button(role: .destructive, action: { showResetSetupAlert = true }) {
                Label("Log Out / Reset App", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
}

// MARK: - View Modifiers

extension View {
    func settingsAlerts(
        client: StalkerClient,
        playbackManager: PlaybackManager,
        watchlistManager: WatchlistManager,
        manifestGen: ManifestGenerator,
        showRefreshIndexAlert: Binding<Bool>,
        showResetDefaultsAlert: Binding<Bool>,
        showClearHistoryAlert: Binding<Bool>,
        showClearWatchlistAlert: Binding<Bool>,
        showClearCacheAlert: Binding<Bool>,
        showGenerateMacAlert: Binding<Bool>,
        showGenerateManifestAlert: Binding<Bool>,
        showDebugStaleCacheAlert: Binding<Bool>,
        showResetSetupAlert: Binding<Bool>,
        resetDefaults: @escaping () -> Void,
        generateNewMac: @escaping () -> Void,
        simulateStaleCache: @escaping () -> Void,
        logout: @escaping () -> Void
    ) -> some View {
        self
            .alert("Refresh Database?", isPresented: showRefreshIndexAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Refresh") { Task { client.buildSearchIndex(force: true) } }
            } message: {
                Text("Scan for library updates?")
            }
            .alert("Reset Identity?", isPresented: showResetDefaultsAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) { resetDefaults() }
            }
            .alert("Clear History?", isPresented: showClearHistoryAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { playbackManager.clearHistory() }
            }
            .alert("Clear My List?", isPresented: showClearWatchlistAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { watchlistManager.clearWatchlist() }
            }
            .alert("Clear Cache?", isPresented: showClearCacheAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { client.clearCache() }
            }
            .alert("Generate New MAC?", isPresented: showGenerateMacAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Generate", role: .destructive) { generateNewMac() }
            }
            .alert("Logo Manifest", isPresented: showGenerateManifestAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Generate") { Task { await manifestGen.generateManifest(client: client) } }
            }
            .alert("Simulate Stale Cache?", isPresented: showDebugStaleCacheAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Simulate", role: .destructive) { simulateStaleCache() }
            } message: {
                Text("This will set your database age to 48+ hours to test auto-refresh logic.")
            }
            .alert("Reset App?", isPresented: showResetSetupAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) { logout() }
            }
    }
}

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
                } else {
                    // Feedback Logic:
                    // 1. Set Error State
                    isError.wrappedValue = true
                    
                    // 2. Clear Password? (Optional, maybe keep for correction)
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
                .foregroundColor(isError.wrappedValue ? .red : .primary) // Note: Alert text color support varies
        }
    }
}

#endif
