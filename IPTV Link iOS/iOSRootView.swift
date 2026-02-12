#if os(iOS)
//
//  iOSRootView.swift
//  IPTV Link iOS
//
//  Created by hardeepsasan on 2/9/26.
//

import SwiftUI

struct iOSRootView: View {
    @ObservedObject private var client = StalkerClient.shared
    
    @AppStorage("settings_portal_url") private var portalURL: String = ""
    @AppStorage("settings_mac_address") private var macAddress: String = ""
    
    var body: some View {
        Group {
            if portalURL.isEmpty {
                // Phase 1: Welcome & Login (Only if no URL is set)
                iOSWelcomeView()
                    .transition(.opacity)
            } else if !client.hasShownDisclaimer {
                // Phase 2: Disclaimer & Pre-loading
                iOSDisclaimerLoadingView()
                    .transition(.opacity)
            } else {
                // Phase 3: Main App (Land here if URL exists, even if auth fails)
                iOSHomeView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.1)),
                        removal: .opacity
                    ))
            }
        }
        .id(portalURL + macAddress) // Forces full view tree recreation on connection change
        .animation(.easeInOut(duration: 0.8), value: client.isAuthenticated)
        .animation(.easeInOut(duration: 1.0), value: client.hasShownDisclaimer)
        .onChange(of: portalURL) { newValue in
            handleConnectionChange()
        }
        .onChange(of: macAddress) { newValue in
            handleConnectionChange()
        }
        .onAppear {
            configureClient()
        }
    }
    
    private func configureClient() {
        if !portalURL.isEmpty {
            print("iOSRootView: Initializing shared client with saved settings.")
            client.configure(url: portalURL, mac: macAddress)
        }
    }
    
    private func handleConnectionChange() {
        print("iOSRootView: Connection parameters changed. Resetting session.")
        // Only trigger if we aren't already logged out (to avoid loops)
        if client.isAuthenticated {
            client.logout()
            client.configure(url: portalURL, mac: macAddress)
        }
    }
}

#Preview {
    iOSRootView()
}
#endif
