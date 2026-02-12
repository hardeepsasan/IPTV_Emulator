#if os(iOS)
import SwiftUI

struct MobileMovieCard: View {
    let movie: Movie
    @EnvironmentObject var playbackManager: PlaybackManager
    
    var progress: Double {
        playbackManager.getProgress(for: movie)
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Poster
            ZStack(alignment: .bottom) {
                AuthenticatedImage(url: movie.getPosterURL(baseURL: StalkerClient.shared.portalURL), targetSize: CGSize(width: 120, height: 180), client: StalkerClient.shared)
                    .frame(width: 120, height: 180)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
                
                if progress > 0 {
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(height: 3)
                        
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 120 * progress, height: 3)
                    }
                    .frame(width: 120)
                }
            }
            
            Text(movie.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
        }
    }
}
#endif
