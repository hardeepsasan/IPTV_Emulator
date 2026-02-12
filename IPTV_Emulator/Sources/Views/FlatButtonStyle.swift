import SwiftUI

// Custom Button Style to remove all system focus effects/rings
struct FlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
