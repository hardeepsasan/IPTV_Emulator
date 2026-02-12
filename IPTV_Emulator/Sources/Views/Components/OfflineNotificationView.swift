import SwiftUI

struct OfflineNotificationView: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 24, weight: .bold)) // Larger Icon
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("No Network Detected")
                    .font(.system(size: 16, weight: .bold)) // Larger Text
                    .foregroundColor(.white)
                
                Text("Check your connection")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    ZStack {
        Color.blue
        OfflineNotificationView()
    }
}
