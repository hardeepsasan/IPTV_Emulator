import SwiftUI

struct DisclaimerLoadingView: View {
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                    .padding(.bottom, 20)
                
                Text("Please note that IPTV Link is an application to establish only the interconnect function between your TV and your own TV provider.\n\nIPTV Link has nothing to do or has any relationship with TV content providers of any nature, and you have to make your own provisioning arrangements, as clearly set out in our Terms of Service.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .fixedSize(horizontal: false, vertical: true)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
            .padding()
            // ZStack centers by default. Removing Spacers prevents layout thrashing.
        }
    }
}

#Preview {
    DisclaimerLoadingView()
}
