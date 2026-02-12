import SwiftUI

struct RollingText: View {
    let text: String
    let isActive: Bool
    let maxWidth: CGFloat
    
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    
    var body: some View {
        Group {
            if isActive {
                GeometryReader { outer in
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(text)
                            .font(.caption)
                            .lineLimit(1)
                            .fixedSize()
                            .background(
                                GeometryReader { inner in
                                    Color.clear
                                        .onAppear { contentWidth = inner.size.width }
                                        .onChange(of: text) { _ in contentWidth = inner.size.width }
                                }
                            )
                            .offset(x: offset)
                    }
                    .disabled(true)
                    .onAppear { startScrolling(outerWidth: outer.size.width) }
                    .onChange(of: isActive) { active in
                         if active { startScrolling(outerWidth: outer.size.width) } 
                         else { stopScrolling() }
                    }
                }
            } else {
                let components = text.split(separator: " ", maxSplits: 1).map(String.init)
                if components.count == 2 {
                    VStack(spacing: -5) {
                        Text(components[0])
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(components[1])
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(text)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .frame(width: maxWidth, height: 45) // Increased height from 35 to 45 for 2 lines
    }
    
    private func startScrolling(outerWidth: CGFloat) {
        let gap = contentWidth - outerWidth
        guard gap > 0 else { return }
        
        // Initial delay then scroll
        withAnimation(.linear(duration: Double(gap) / 20).delay(1.0).repeatForever(autoreverses: true)) {
            offset = -gap - 10 // Extra buffer
        }
    }
    
    private func stopScrolling() {
        withAnimation {
            offset = 0
        }
    }
}
