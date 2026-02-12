import SwiftUI

struct UpNextOverlay: View {
    let nextEpisode: Movie
    let client: StalkerClient
    let remainingSeconds: Double
    let onPlayNow: () -> Void
    let onCancel: () -> Void
    
    // Total duration for the countdown (used for progress calculation)
    private let totalCountdown: Double = 15.0
    
    @FocusState private var focusedField: FocusField?
    
    enum FocusField {
        case cancel
        case play
    }
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 20) {
                Spacer()
                
                // "Watch Credits" Button
                Button(action: onCancel) {
                    Text("Watch Credits")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(focusedField == .cancel ? .black : .white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(focusedField == .cancel ? Color.white : Color.gray.opacity(0.4))
                        .cornerRadius(4)
                        .scaleEffect(focusedField == .cancel ? 1.1 : 1.0)
                        .animation(.spring(), value: focusedField)
                }
                #if os(tvOS)
                .buttonStyle(.card)
                #endif
                .focused($focusedField, equals: .cancel)
                
                // "Next Episode" Button with Timer Fill
                Button(action: onPlayNow) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                        Text("Next Episode")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(focusedField == .play ? .white : .black) // Text Color Flipped
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background Color (Changes on Focus)
                                if focusedField == .play {
                                    Color.red // Highlight color
                                } else {
                                    Color.white // Base Background
                                }
                                
                                // Progress Bar (Visible in both states)
                                Rectangle()
                                    .fill(focusedField == .play ? Color.white.opacity(0.3) : Color.gray.opacity(0.3))
                                    .frame(width: geometry.size.width * progress(), height: geometry.size.height)
                                    .animation(.linear(duration: 1.0), value: remainingSeconds)
                            }
                        }
                    )
                    .cornerRadius(4)
                    .scaleEffect(focusedField == .play ? 1.1 : 1.0)
                    .clipped()
                    .animation(.spring(), value: focusedField)
                }
                #if os(tvOS)
                .buttonStyle(.card)
                #endif
                .focused($focusedField, equals: .play)
                .onAppear {
                    // Auto-focus the Play button when view appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = .play
                    }
                }
            }
            .padding(.bottom, 250)
            .padding(.trailing, 40)
        }
        .transition(.opacity)
    }
    
    private func progress() -> CGFloat {
        // Calculate progress (0.0 to 1.0)
        // remaining approaches 0, so (total - remaining) / total goes 0 -> 1
        let p = (totalCountdown - remainingSeconds) / totalCountdown
        return max(0, min(1, CGFloat(p)))
    }
}
