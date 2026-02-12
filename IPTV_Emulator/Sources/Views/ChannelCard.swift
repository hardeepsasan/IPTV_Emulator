import SwiftUI

struct ChannelCard: View {
    let channel: Channel
    @ObservedObject var client: StalkerClient
    let categoryTitle: String? // [NEW] Pass genre info
    var isFocused: Bool
    var isFavorite: Bool = false
    
    // Deterministic Gradient Color based on Channel ID
    private var cardGradient: LinearGradient {
        let hue = Double(abs(channel.id.hash) % 100) / 100.0
        let color1 = Color(hue: hue, saturation: 0.6, brightness: 0.3)
        let color2 = Color(hue: hue, saturation: 0.8, brightness: 0.1)
        return LinearGradient(colors: [color1, color2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    // Fallback Initial
    private var channelInitial: String {
        guard let first = channel.name.first else { return "?" }
        return String(first).uppercased()
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            
            // 1. Content (Smart Logo handles background AND overlay)
            SmartChannelLogo(
                channel: channel, 
                client: client, 
                categoryName: categoryTitle,
                fallbackBackground: AnyView(RoundedRectangle(cornerRadius: 12).fill(cardGradient)),
                fallbackOverlay: AnyView(
                    // 3. Info Overlay (Passed as fallback)
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        
                        // Channel Number Pill
                        Text(channel.number)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Capsule())
                            .foregroundColor(.white)
                        
                        // Name
                        Text(channel.name)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                            .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
                    )
                )
            )
            .overlay(
                 Group {
                     if isFavorite {
                         Image(systemName: "heart.fill")
                             .foregroundColor(.red)
                             .padding(8)
                             .background(Color.black.opacity(0.5))
                             .clipShape(Circle())
                             .padding(8)
                             .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                     }
                 }
            )
        }
        .frame(height: 150)
        // Focus Effects
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow) // The Glow
                .blur(radius: isFocused ? 15 : 0) // Softer, premium glow
                .opacity(isFocused ? 0.5 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: isFocused ? 4 : 0) // White border looks more premium than yellow on color
                .shadow(color: .black, radius: 2)
        )
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .zIndex(isFocused ? 1 : 0) // Bring to front
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
    }
}

// Helper for rounded corners override
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
