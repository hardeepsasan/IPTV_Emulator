#if os(iOS)
import SwiftUI

struct iOSWelcomeView: View {
    @AppStorage("settings_portal_url") private var portalURL: String = ""
    @AppStorage("settings_mac_address") private var macAddress: String = "00:1A:79:7D:7B:F4"
    
    @State private var showLoginForm = false
    @State private var inputURL: String = "http://"
    
    var body: some View {
        ZStack {
            // LAYER 0: Deep Background
            Color(red: 0.1, green: 0.1, blue: 0.15)
                .ignoresSafeArea()
            
            // LAYER 1: Dynamic Poster Grid (Shared Logic)
            PosterGridBackground()
                .opacity(0.6)
                .blur(radius: showLoginForm ? 8 : 0)
                .animation(.easeInOut(duration: 0.6), value: showLoginForm)
            
            // LAYER 2: Gradient Overlay
            LinearGradient(
                gradient: Gradient(colors: [
                    .clear,
                    .black.opacity(0.4),
                    .black.opacity(0.9)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // LAYER 3: Content
            VStack {
                if !showLoginForm {
                    VStack(spacing: 20) {
                        Spacer()
                        
                        // Logo
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                        
                        VStack(spacing: 8) {
                            Text("Welcome to IPTV Link")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Your TV and Movie experience deserves an upgrade!")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                showLoginForm = true
                            }
                        }) {
                            Text("Add Account")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .shadow(radius: 5)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 60)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                } else {
                    iOSLoginView(onBack: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            showLoginForm = false
                        }
                    })
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
            }
        }
        .statusBarHidden(!showLoginForm)
    }
}

// MARK: - Reusable Components (Ported from tvOS WelcomeView)

struct iOSPosterGridBackground: View { // Renamed slightly to avoid potential conflicts if shared
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                MarqueeColumn(offsetIndex: 0, speed: 100, reverse: false)
                MarqueeColumn(offsetIndex: 5, speed: 140, reverse: true)
                MarqueeColumn(offsetIndex: 10, speed: 120, reverse: false)
                MarqueeColumn(offsetIndex: 3, speed: 150, reverse: true)
            }
            .rotationEffect(.degrees(-8))
            .scaleEffect(1.3)
            .offset(x: -20, y: -40)
        }
        .ignoresSafeArea()
    }
}

// Note: MarqueeColumn and helper components will be defined here or shared.
// For now, I'll include them locally for safety since I can't easily check target memberships.

struct MarqueeColumn: View {
    let offsetIndex: Int
    let speed: Double
    let reverse: Bool
    
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    let count = 15 
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                ForEach(0..<count * 3, id: \.self) { index in
                    let actualIndex = ((index + offsetIndex) % count) + 1
                    let assetName = "poster_\(actualIndex)"
                    
                    PosterOrGradientView(assetName: assetName, fallbackIndex: (index + offsetIndex))
                        .frame(width: geo.size.width)
                        .aspectRatio(2/3, contentMode: .fill)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { old, newHeight in contentHeight = newHeight }
                }
            )
            .offset(y: reverse ? -offset : offset - (contentHeight / 3))
            .task(id: contentHeight) {
                if contentHeight > 0 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
                        offset = contentHeight / 3
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct PosterOrGradientView: View {
    let assetName: String
    let fallbackIndex: Int
    
    var body: some View {
        Image(assetName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            // If the image is missing, it will show as an empty space or can be caught with a ZStack
            .background(DefaultPosterCard(index: fallbackIndex))
    }
}

struct DefaultPosterCard: View {
    let index: Int
    
    var gradient: LinearGradient {
        let colors: [[Color]] = [
            [.blue, .purple], [.red, .orange], [.green, .mint],
            [.pink, .purple], [.indigo, .blue], [.orange, .yellow]
        ]
        let pair = colors[index % colors.count]
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var body: some View {
        ZStack {
            gradient
            Image(systemName: "play.tv")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

// Map PosterGridBackground to iOSPosterGridBackground for this file
typealias PosterGridBackground = iOSPosterGridBackground

#Preview {
    iOSWelcomeView()
}
#endif
