import SwiftUI

struct MovieInfoTray: View {
    let movie: Movie?
    let client: StalkerClient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // NO SPACING between Spacer and Content
            
            // 1. RIGID SPACE RESERVER
            // This ensures the content ALWAYS starts exactly at 820px down.
            Rectangle()
                .fill(Color.clear)
                .frame(height: 40) // Reduced to pull title up (was 60)
            
            // 2. CONTENT BLOCK
            VStack(alignment: .leading, spacing: 2) {
                if let movie = movie {
                    // Title
                    Text(movie.cleanName)
                        .font(.system(size: 40, weight: .heavy, design: .rounded)) // Reduced font from 50 to 40
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(height: 50, alignment: .bottomLeading) // Reduced height
                        .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
                    
                    // Metadata Row (Rating, Year, Quality Badges)
                    HStack(spacing: 12) {
                        if let rating = movie.rating, !rating.isEmpty, rating != "0" {
                             Text("★ \(rating)")
                                 .font(.subheadline)
                                 .foregroundColor(.green)
                        }
                        
                         if let year = movie.year, !year.isEmpty {
                            Text(year)
                                .font(.caption) 
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // QUALITY BADGES
                        ForEach(movie.qualityTags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            tag == "4K" || tag == "HDR" || tag == "Dolby" ? Color.yellow :
                                            tag == "CAM" ? Color.orange :
                                            Color.white.opacity(0.6),
                                            lineWidth: 1
                                        )
                                        .background(
                                            tag == "CAM" ? Color.orange.opacity(0.2) : Color.clear
                                        )
                                )
                                .foregroundColor(
                                    tag == "4K" || tag == "HDR" || tag == "Dolby" ? Color.yellow :
                                    tag == "CAM" ? Color.orange :
                                    Color.white.opacity(0.9)
                                )
                        }
                        
                        if let genre = movie.genresStr, !genre.isEmpty {
                            Text("•  \(genre)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                    
                    // Description
                    Text(movie.sanitizedDescription)
                        .font(.system(size: 26)) // Increased to 26 per user request
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3) // Max 3 lines
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    // Cast & Director
                    VStack(alignment: .leading, spacing: 2) {
                        if let actors = movie.actors, !actors.isEmpty, actors != "0" {
                             Text("Cast: \(actors)")
                                .font(.system(size: 22, weight: .semibold).italic()) // Size 22 + Italic
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        
                        if let director = movie.director, !director.isEmpty, director != "0" {
                             Text("Director: \(director)")
                                .font(.system(size: 22, weight: .semibold).italic()) // Size 22 + Italic
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 12) // Increased spacing from description
                }
            }
            .frame(height: 280, alignment: .topLeading) // INCREASED HEIGHT: Increased to 280 to prevent clipping
            .animation(nil, value: UUID()) // DISABLE ANIMATION: Prevents "tweening" wobble on text change
        }
        .padding(.horizontal, 80)
        .frame(maxWidth: .infinity, alignment: .topLeading) // Full Width
        // Add a gradient background to ensure text readability vs the backdrop image
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.9), // Top is Black
                    Color.black.opacity(0.4),
                    Color.clear // Bottom is Clear
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -200) // Ensure it covers status bar area
        )
        .frame(height: 320, alignment: .top) // FORCE STRUCTURAL HEIGHT: Increased to 320
        .clipped() // Ensure no overflow
    }
}
