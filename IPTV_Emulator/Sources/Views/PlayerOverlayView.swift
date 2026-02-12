import SwiftUI

struct PlayerOverlayView: View {
    let relatedEpisodes: [Movie]
    let client: StalkerClient
    let onSelectEpisode: (Movie) -> Void
    let onMoreEpisodes: () -> Void
    
    // Focus State
    @FocusState private var focusedEpisode: String?
    @FocusState private var isMoreButtonFocused: Bool
    
    var body: some View {
        VStack {
            Spacer()
            
            // "Drawer" Container
            VStack(alignment: .leading, spacing: 20) {
                
                // Header
                HStack {
                    Text("Up Next")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        onMoreEpisodes()
                    }) {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("More Episodes")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .background(isMoreButtonFocused ? Color.white : Color.white.opacity(0.1))
                    .foregroundColor(isMoreButtonFocused ? .black : .white)
                    .cornerRadius(8)
                    .focused($isMoreButtonFocused)
                }
                .padding(.horizontal, 60)
                
                // Horizontal Episodes List
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40) {
                        ForEach(relatedEpisodes) { episode in
                            Button {
                                onSelectEpisode(episode)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Thumbnail
                                    AuthenticatedImage(
                                        url: episode.getPosterURL(baseURL: URL(string: "https://ipro4k.rocd.cc/stalker_portal/misc/logos/320/")!),
                                        client: client
                                    )
                                        .frame(width: 300, height: 169)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.white, lineWidth: focusedEpisode == episode.id ? 4 : 0)
                                        )
                                        .scaleEffect(focusedEpisode == episode.id ? 1.05 : 1.0)
                                        .animation(.easeInOut(duration: 0.2), value: focusedEpisode)
                                    
                                    // Title
                                    Text(episode.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .frame(width: 300, alignment: .leading)
                                        .foregroundColor(focusedEpisode == episode.id ? .white : .secondary)
                                }
                            }
                            .buttonStyle(.card)
                            .focused($focusedEpisode, equals: episode.id)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 60)
                }
            }
            .background(
                LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.8), Color.black]), startPoint: .top, endPoint: .bottom)
                    .edgesIgnoringSafeArea(.bottom)
            )
        }
    }
}
