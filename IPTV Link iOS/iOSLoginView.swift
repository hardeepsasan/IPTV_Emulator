#if os(iOS)
import SwiftUI

struct iOSLoginView: View {
    var onBack: () -> Void
    @ObservedObject private var client = StalkerClient.shared
    @EnvironmentObject var prefs: PreferenceManager
    
    @AppStorage("settings_provider_url") private var providerURL: String = ""
    @AppStorage("settings_portal_url") private var portalURL: String = ""
    @AppStorage("settings_mac_address") private var macAddress: String = "00:1A:79:7D:7B:F4"
    
    @State private var inputURL: String = ""
    @State private var isLoading = false
    @State private var resolutionStatus: String?
    @State private var errorMessage: String?
    
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
            }
            .padding(.horizontal)
            
            // MAC Info Card
            VStack(spacing: 8) {
                Text("Device Recognition")
                    .font(.caption.bold())
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Register this MAC:")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                        Text(macAddress)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Image(systemName: "cpu")
                        .foregroundColor(.blue.opacity(0.8))
                }
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            // Input Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Enter Portal URL")
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    
                    TextField("http://your-provider.com", text: $inputURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($isFieldFocused)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFieldFocused ? Color.blue : Color.white.opacity(0.15), lineWidth: 1.5)
                )
            }
            .padding(.horizontal)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }
            
            // Action Buttons
            VStack(spacing: 16) {
                Button(action: login) {
                    HStack {
                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text(resolutionStatus ?? "Connecting...")
                            }
                        } else {
                            Text("Connect")
                                .font(.headline)
                            Image(systemName: "arrow.right.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(canConnect ? Color.blue : Color.blue.opacity(0.3))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .disabled(!canConnect || isLoading)
                
                Button(action: tryDemo) {
                    Text("Try Demo Mode")
                        .font(.subheadline)
                        .foregroundColor(.blue.opacity(0.8))
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 30)
        .background(Color.black.opacity(0.85))
        .background(.ultraThinMaterial)
        .cornerRadius(32)
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        .onAppear {
            setupInitialState()
        }
    }
    
    private var canConnect: Bool {
        inputURL.count > 10 && !isLoading
    }
    
    private func setupInitialState() {
        if !providerURL.isEmpty {
            inputURL = providerURL
        } else if !portalURL.isEmpty {
            inputURL = portalURL
        }
    }
    
    private func login() {
        isLoading = true
        errorMessage = nil
        resolutionStatus = "Resolving URL..."
        
        // Hide keyboard
        isFieldFocused = false
        
        Task {
            // 1. Resolve URL (Handle redirects like ipro.gol.ci)
            var cleanURL = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanURL.lowercased().hasPrefix("http") { cleanURL = "http://" + cleanURL }
            
            let resolvedURL = await StalkerClient.resolveURL(cleanURL)
            print("iOSLoginView: Resolved \(cleanURL) -> \(resolvedURL)")
            
            await MainActor.run {
                // 2. Persist
                self.providerURL = cleanURL
                self.portalURL = resolvedURL
                self.resolutionStatus = "Authenticating..."
                
                // 3. Configure Client
                client.configure(url: resolvedURL, mac: macAddress)
                
                // 4. Authenticate
                client.login { success, error in
                    DispatchQueue.main.async {
                        isLoading = false
                        resolutionStatus = nil
                        if success {
                            // Success will be handled by RootView switching to disclaimer
                        } else {
                            errorMessage = error ?? "Connection failed. Please check the URL."
                        }
                    }
                }
            }
        }
    }
    
    private func tryDemo() {
        inputURL = "mock://demo"
        login()
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        iOSLoginView(onBack: {})
            .environmentObject(PreferenceManager.shared)
    }
}
#endif
