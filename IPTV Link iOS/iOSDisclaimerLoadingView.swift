#if os(iOS)
import SwiftUI

struct iOSDisclaimerLoadingView: View {
    @ObservedObject private var client = StalkerClient.shared
    @State private var progressText = "Establishing secure connection..."
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Shield Icon with Pulse Animation
                Image(systemName: "shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(color: .blue.opacity(0.5), radius: 20)
                    .scaleEffect(opacity == 1 ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: opacity)
                
                VStack(spacing: 20) {
                    Text("Legal Disclaimer")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text("Please note that IPTV Link is an application to establish only the interconnect function between your device and your own TV provider.\n\nIPTV Link has no relationship with TV content providers of any nature. You must make your own provisioning arrangements, as set out in our Terms of Service.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 30)
                        .lineSpacing(4)
                }
                
                Spacer()
                
                // Progress Section
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                    
                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .italic()
                }
                .padding(.bottom, 50)
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.8)) {
                opacity = 1
            }
            startPreloading()
        }
    }
    
    private func startPreloading() {
        Task {
            // 1. Ensure authenticated (Handshake)
            do {
                try await client.authenticate()
            } catch {
                print("iOSDisclaimerLoadingView: Initial handshake failed: \(error)")
                // Note: ConnectionStatus will be .failed, handled by HomeView capsule
            }

            // 2. Minimum duration to show disclaimer
            let minDisplayTask = Task { try? await Task.sleep(nanoseconds: 3_500_000_000) } // 3.5s
            
            // 2. Preload Critical Data
            progressText = "Synchronizing categories..."
            _ = try? await client.getCategories(type: "vod")
            
            progressText = "Fetching live channels..."
            // Assuming getCategories(type: "itv") is the way to get genres/categories for TV
            _ = try? await client.getCategories(type: "itv")
            
            progressText = "Preparing your experience..."
            
            // Wait for min duration if not met
            await minDisplayTask.value
            
            // 3. Mark as done to trigger RootView switch
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 0
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                client.hasShownDisclaimer = true
            }
        }
    }
}

#Preview {
    iOSDisclaimerLoadingView()
}
#endif
