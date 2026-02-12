import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let startDelay: Double
    let alignment: Alignment
    var isFocused: Bool
    
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    
    // Configuration
    private let speed: Double = 50.0 // Pixels per second
    
    init(text: String, font: Font, startDelay: Double = 1.5, alignment: Alignment = .topLeading, isFocused: Bool = true) {
        self.text = text
        self.font = font
        self.startDelay = startDelay
        self.alignment = alignment
        self.isFocused = isFocused
    }
    
    var body: some View {
        Group {
            if isFocused {
                GeometryReader { geo in
                    let containerWidth = geo.size.width
                    
                    ZStack(alignment: alignment) {
                        Text(text)
                            .font(font)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .background(
                                GeometryReader { textGeo in
                                    Color.clear
                                        .onAppear { contentWidth = textGeo.size.width }
                                        .onChange(of: textGeo.size.width) { contentWidth = $0 }
                                }
                            )
                            .offset(x: offset)
                    }
                    .frame(width: containerWidth, alignment: alignment)
                    .clipped()
                    .task(id: contentWidth) {
                        // Reset
                        offset = 0
                        
                        // Wait for layout
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        
                        // Check conditions
                        let distance = contentWidth - containerWidth
                        guard distance > 2 else { return }
                        
                        // Calculate duration
                        let duration = max(Double(distance) / speed, 2.0)
                        
                        // Delay before start
                        try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
                        
                        // Animate
                        withAnimation(Animation.linear(duration: duration).repeatForever(autoreverses: true)) {
                            offset = -distance
                        }
                    }
                }
            } else {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
    }
}
