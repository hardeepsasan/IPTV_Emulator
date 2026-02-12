import SwiftUI

struct WelcomeView: View {
    @AppStorage("settings_portal_url") private var portalURL: String = ""
    @AppStorage("settings_mac_address") private var macAddress: String = ""
    
    @State private var inputURL: String = "http://"
    @FocusState private var isFocused: Bool
    @State private var isResolving = false
    @State private var showLoginForm = false
    
    var body: some View {
        ZStack {
            // LAYER 0: ABSOLUTE FALLBACK BACKGROUND (Safe Base)
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.25), // Deep Blue/Black
                    Color(red: 0.15, green: 0.05, blue: 0.25) // Deep Slate
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            
            // LAYER 1: Dynamic Local Poster Grid
            PosterGridBackground()
                .opacity(0.8) // Let deep background blend slightly
                .blur(radius: showLoginForm ? 10 : 0)
                .animation(.easeInOut(duration: 0.5), value: showLoginForm)
            
            // LAYER 2: Overlay Content
            VStack {
                if !showLoginForm {
                    LandingView(onAddAccount: {
                        withAnimation(.spring()) {
                            showLoginForm = true
                            isFocused = true
                        }
                    })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    LoginForm(
                        inputURL: $inputURL,
                        isResolving: $isResolving,
                        isFocused: $isFocused,
                        macAddress: macAddress,
                        onConnect: {
                            Task { await connect() }
                        },
                        onDemo: {
                            Task { await startDemoMode() }
                        },
                        onBack: {
                            withAnimation(.spring()) {
                                showLoginForm = false
                                isFocused = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding() // Add padding ONLY to LoginForm
                }
            }
            // Removed global .padding() here
        }
    }
    
    private func connect() async {
        isResolving = true
        var cleanURL = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURL.lowercased().hasPrefix("http") { cleanURL = "http://" + cleanURL }
        
        let resolvedURL = await StalkerClient.resolveURL(cleanURL)
        print("WelcomeView: Resolved \(cleanURL) -> \(resolvedURL)")
        UserDefaults.standard.set(cleanURL, forKey: "settings_provider_url")
        portalURL = resolvedURL
    }
    
    private func startDemoMode() async {
        let demoURL = "mock://demo"
        UserDefaults.standard.set(demoURL, forKey: "settings_provider_url")
        portalURL = demoURL
    }
}

// MARK: - Branding


// MARK: - Subviews

struct LandingView: View {
    var onAddAccount: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            Spacer()
            
            // Text & Button & Logo (Full Width Bottom Sheet)
            VStack(spacing: 15) {
                // Logo (Moved inside bottom section)
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 140)
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
                    .padding(.top, 40)
                
                Text("Welcome to IPTV Link")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2, x: 0, y: 2)
                    .padding(.top, 10)
                
                Text("Your TV and Movie experience deserves an upgrade!")
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
                
                Button(action: onAddAccount) {
                    Text("Add Account")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.black.opacity(0.8))
                        .frame(width: 400, height: 60)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Capsule())
                }
                .buttonStyle(.card)
                .padding(.bottom, 60) // Extra padding for safe area at bottom
            }
            .padding(.top, 60) // Add top padding to start gradient fade earlier
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.6),
                        Color.black.opacity(1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .edgesIgnoringSafeArea([.bottom, .horizontal]) // Force background to edges
        }
    }
}

struct LoginForm: View {
    @Binding var inputURL: String
    @Binding var isResolving: Bool
    var isFocused: FocusState<Bool>.Binding
    var macAddress: String
    var onConnect: () -> Void
    var onDemo: () -> Void
    var onBack: () -> Void
    
    @FocusState private var isBackFocused: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 100)
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
            
            HStack {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(isBackFocused ? .black : .white.opacity(0.7)) // High contrast on focus
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .focused($isBackFocused)
                Spacer()
            }
            
            VStack(spacing: 8) {
                Text("Register this MAC: \(macAddress)")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Enter Portal URL")
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.gray)
                    
                    TextField("http://your-provider.com", text: $inputURL)
                        .font(.system(size: 24))
                        .textFieldStyle(.plain)
                        .focused(isFocused)
                        .submitLabel(.go)
                        .onSubmit(onConnect)
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isFocused.wrappedValue ? Color.blue : Color.white.opacity(0.2), lineWidth: 2))
            }
            
            Button(action: onConnect) {
                HStack {
                    if isResolving {
                        ProgressView().tint(.white)
                        Text("Checking...")
                    } else {
                        Text("Connect")
                            .font(.title3.bold())
                        Image(systemName: "arrow.right.circle.fill")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(inputURL.count > 10 ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(inputURL.count < 10 || isResolving)
            .buttonStyle(.plain)
            
            Button(action: onDemo) {
                Text("Try Demo Mode")
                    .font(.subheadline)
                    .foregroundColor(.blue.opacity(0.8))
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .background(Color.black.opacity(0.8))
        .background(.ultraThinMaterial)
        .cornerRadius(24)
        .frame(maxWidth: 700)
    }
}

// MARK: - Local Poster Implementation

struct PosterGridBackground: View {
    // Generate 5 columns locally for smaller posters
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 16) {
                // Slower speeds (Higher duration value = slower movement)
                MarqueeColumn(offsetIndex: 0, speed: 180, reverse: false)
                MarqueeColumn(offsetIndex: 5, speed: 420, reverse: true)  // Reduced by 50% (Slower)
                MarqueeColumn(offsetIndex: 10, speed: 160, reverse: false)
                MarqueeColumn(offsetIndex: 3, speed: 375, reverse: true)  // Reduced by 50% (Slower)
                MarqueeColumn(offsetIndex: 7, speed: 200, reverse: false)
            }
            .rotationEffect(.degrees(-8))
            .scaleEffect(1.1) // Slightly reduced from 1.2
            .offset(x: -20)
        }
        .ignoresSafeArea()
    }
}

struct MarqueeColumn: View {
    let offsetIndex: Int
    let speed: Double
    let reverse: Bool
    
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    let count = 15 // Check up to 15 posters
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 16) {
                // Triple list loop for infinite scroll
                ForEach(0..<count * 3, id: \.self) { index in
                    let actualIndex = ((index + offsetIndex) % count) + 1 // Use offset to shift start
                    let assetName = "poster_\(actualIndex)"
                    
                    PosterOrGradientView(assetName: assetName, fallbackIndex: (index + offsetIndex))
                        .frame(width: geo.size.width)
                        .aspectRatio(2/3, contentMode: .fill)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 5)
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { newHeight in contentHeight = newHeight }
                }
            )
            .offset(y: reverse ? -offset : offset - (contentHeight / 3))
            .task(id: contentHeight) {
                if contentHeight > 0 {
                    // Reset and start animation whenever height is ready
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay to ensure layout stable
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
        // Try exact name, then with .webp, then with .jpg
        if let uiImage = UIImage(named: assetName) ?? UIImage(named: "\(assetName).webp") ?? UIImage(named: "\(assetName).jpg") {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            MoviePosterCard(index: fallbackIndex)
        }
    }
}

struct MoviePosterCard: View {
    let index: Int
    
    // Deterministic selection based on index
    var gradient: LinearGradient {
        let colors: [[Color]] = [
            [.red, .orange], [.blue, .purple], [.cyan, .blue], [.green, .mint],
            [.pink, .red], [.purple, .indigo], [.yellow, .orange], [.teal, .cyan],
            [.black, .gray], [.indigo, .pink]
        ]
        let pair = colors[index % colors.count]
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    var content: (icon: String, title: String) {
        let items: [(String, String)] = [
            ("film.fill", "Action"), ("bolt.fill", "Sci-Fi"), ("heart.fill", "Romance"),
            ("star.fill", "Top Rated"), ("play.tv.fill", "Series"), ("flame.fill", "Trending"),
            ("moon.fill", "Night TV"), ("sun.max.fill", "Morning Show"), ("tv.fill", "Live TV"),
            ("popcorn.fill", "Comedy")
        ]
        return items[index % items.count]
    }
    
    var body: some View {
        ZStack {
            gradient
            
            VStack {
                Spacer()
                Image(systemName: content.icon)
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(radius: 5)
                Spacer()
                
                HStack {
                    Text(content.title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Material.ultraThin)
                        .cornerRadius(4)
                }
                .padding(.bottom, 10)
            }
        }
    }
}
