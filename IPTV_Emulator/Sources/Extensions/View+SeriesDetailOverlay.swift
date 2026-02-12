import SwiftUI

extension View {
    func seriesDetailOverlay(isFetching: Bool) -> some View {
        self.overlay(
             Group {
                 if isFetching {
                     ZStack {
                         Color.black.opacity(0.7).ignoresSafeArea()
                         VStack(spacing: 20) {
                             ProgressView()
                                 .scaleEffect(2.0)
                                 .progressViewStyle(CircularProgressViewStyle(tint: .white))

                         }
                     }
                     .transition(.opacity)
                     .zIndex(100)
                 }
             }
        )
    }
}
