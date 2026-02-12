import SwiftUI

struct PlayerEpisodesView: View {
    let episodes: [Movie]
    let client: StalkerClient
    let onSelect: (Movie) -> Void
    let onMoreEpisodes: () -> Void
    
    // Environment to dismiss the sheet
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            // Light dimming of the video behind
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture {
                    presentationMode.wrappedValue.dismiss()
                }
            
            HStack {
                Spacer()
                
                VStack(spacing: 0) {
                    Text("Episodes")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.5))
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(episodes) { episode in
                                Button {
                                    onSelect(episode)
                                    presentationMode.wrappedValue.dismiss()
                                } label: {
                                    HStack(spacing: 16) {
                                        // Thumbnail
                                        AuthenticatedImage(url: episode.getPosterURL(baseURL: client.portalURL), 
                                                           targetSize: CGSize(width: 200, height: 112),
                                                           client: client)
                                            .aspectRatio(16/9, contentMode: .fill)
                                            .frame(width: 140, height: 80)
                                            .cornerRadius(8)
                                            .clipped()
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(episode.name)
                                                .font(.headline)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            
                                            if let desc = episode.description, !desc.isEmpty {
                                                Text(desc)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.1)) // Inner item transparency
                                    .cornerRadius(12)
                                }
                                #if os(tvOS)
                                .buttonStyle(.card)
                                #endif
                            }
                            
                            // "Other Episodes" Button
                            Button {
                                onMoreEpisodes()
                                presentationMode.wrappedValue.dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle")
                                    Text("Other Episodes")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #endif
                            .padding(.top, 8)
                        }
                        .padding()
                    }
                }
                .frame(width: 700) 
                .frame(maxHeight: .infinity) // Full height sidebar effect
                .background(Color.black.opacity(0.75)) // Desired transparency
                .cornerRadius(24)
                .padding(.trailing, 50) // "Towards right"
                .padding(.vertical, 40)
                .shadow(radius: 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
