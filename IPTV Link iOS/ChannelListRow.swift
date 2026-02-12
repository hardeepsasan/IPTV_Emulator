#if os(iOS)
import SwiftUI

struct ChannelListRow: View {
    let channel: Channel
    @ObservedObject var client: StalkerClient
    let action: () -> Void
    
    @AppStorage("favorite_channels_json_v1") private var favoriteChannelsJSON: Data = Data()
    
    var isFavorite: Bool {
        let favorites = (try? JSONDecoder().decode([Channel].self, from: favoriteChannelsJSON)) ?? []
        return favorites.contains(where: { $0.id == channel.id })
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Channel Number
                Text(channel.number)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .frame(width: 30)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(4)
                
                // Logo
                if let logoURL = channel.getLogoURL(baseURL: client.portalURL) {
                    AuthenticatedImage(url: logoURL, targetSize: CGSize(width: 40, height: 40), client: client)
                        .frame(width: 40, height: 40)
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "tv")
                                .font(.caption)
                                .foregroundColor(.gray)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(channel.name)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                    
                    if let playing = channel.curPlaying, !playing.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                            Text(playing)
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.8))
                                .lineLimit(1)
                        }
                    } else {
                        Text("No EPG data available")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                toggleFavorite()
            } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", 
                      systemImage: isFavorite ? "heart.slash" : "heart")
            }
        }
    }
    
    private func toggleFavorite() {
        var favorites = (try? JSONDecoder().decode([Channel].self, from: favoriteChannelsJSON)) ?? []
        if let index = favorites.firstIndex(where: { $0.id == channel.id }) {
            favorites.remove(at: index)
        } else {
            favorites.append(channel)
        }
        if let encoded = try? JSONEncoder().encode(favorites) {
            favoriteChannelsJSON = encoded
        }
    }
}
#endif
