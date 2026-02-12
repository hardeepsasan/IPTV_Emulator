import Foundation

final class DemoData: @unchecked Sendable {
    // MARK: - Mock Categories
    static let mockCategories: [Category] = [
        Category(id: "mock_movie_cat", title: "Movies", alias: "movies"),
        Category(id: "mock_series_cat", title: "TV Shows", alias: "series"),
        Category(id: "mock_live_cat", title: "Live TV", alias: "live")
    ]
    
    // MARK: - Mock Movies (Public Domain)
    static let mockMovies: [Movie] = [
        Movie(
            id: "mock_m_1",
            name: "Big Buck Bunny",
            description: "A large and lovable rabbit deals with three bullies, led by a flying squirrel, who are determined to squelch his happiness.",
            comm: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            poster: "https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg",
            year: "2008",
            rating: "8.5",
            categoryId: "mock_movie_cat",
            isSeries: 0,
            director: "Sacha Goedegebure",
            actors: "Big Buck Bunny, Rodents, Squirrel",
            genresStr: "Animation, Short, Comedy",
            added: "2023-01-01"
        ),
        Movie(
            id: "mock_m_2",
            name: "Sintel",
            description: "A lonely young woman, Sintel, helps and befriends a dragon, whom she names Scales. But when he is kidnapped by an adult dragon, Sintel decides to embark on a dangerous quest to find her lost friend.",
            comm: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
            poster: "https://image.tmdb.org/t/p/w500/4BMG9hk9NvSBeQvC82sVmVRK140.jpg",
            year: "2010",
            rating: "7.8",
            categoryId: "mock_movie_cat",
            isSeries: 0,
            director: "Colin Levy",
            actors: "Halina Reijn, Thom Hoffman",
            genresStr: "Animation, Fantasy",
            added: "2023-02-15"
        ),
        Movie(
            id: "mock_m_3",
            name: "Tears of Steel",
            description: "In a dystopian future, a group of resistance fighters attempt to capture a robot to restart the simulation.",
            comm: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
            poster: "https://image.tmdb.org/t/p/w500/8qy3jRmaHR7f8VZh3iXCqCWfFsH.jpg",
            year: "2012",
            rating: "7.0",
            categoryId: "mock_movie_cat",
            isSeries: 0,
            director: "Ian Hubert",
            actors: "Derek de Lint, Sergio Hasselbaink",
            genresStr: "Sci-Fi, Short",
            added: "2023-03-10"
        )
    ]
    
    // MARK: - Mock Live Channels
    static let mockChannels: [Channel] = [
        Channel(
            id: "mock_ch_1",
            number: "1",
            name: "News 24",
            cmd: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", // Loop video for preview
            logo: "news_icon", // Placeholder local asset name if available
            categoryId: "mock_live_cat",
            curPlaying: nil
        ),
        Channel(
            id: "mock_ch_2",
            number: "2",
            name: "Sports HD",
            cmd: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
            logo: "sports_icon",
            categoryId: "mock_live_cat",
            curPlaying: nil
        ),
        Channel(
            id: "mock_ch_3",
            number: "3",
            name: "Nature TV",
            cmd: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
            logo: "nature_icon",
            categoryId: "mock_live_cat",
            curPlaying: nil
        )
    ]
    
    // MARK: - Mock Series
    static let mockSeries: [Movie] = [
        Movie(
            id: "mock_s_1",
            name: "Blender Open Projects",
            description: "A collection of open movie projects made with Blender.",
            comm: "",
            poster: "https://image.tmdb.org/t/p/w500/i9jJzvoXET4D9pOkoEwncSdNNER.jpg",
            year: "2008-2023",
            rating: "9.0",
            categoryId: "mock_series_cat",
            isSeries: 1,
            director: "Blender Foundation",
            actors: "Various Artists",
            genresStr: "Animation, Open Source",
            added: "2023-01-01"
        )
    ]
    
    static let mockSeasons: [Movie] = [
        Movie(
            id: "mock_season_1",
            name: "Season 1",
            comm: "",
            categoryId: "mock_s_1",
            seasonId: "mock_season_1"
        )
    ]
    
    static let mockEpisodes: [Movie] = [
        Movie(
             id: "mock_ep_1",
             name: "Episode 1: Big Buck Bunny",
             comm: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
             poster: "https://image.tmdb.org/t/p/w500/i9jJzvoXET4D9pOkoEwncSdNNER.jpg",
             isSeries: 0,
             seasonId: "mock_season_1",
             isEpisode: true,
             added: "2023-01-01",
             seriesId: "mock_s_1"
        ),
        Movie(
             id: "mock_ep_2",
             name: "Episode 2: Sintel",
             comm: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
             poster: "https://image.tmdb.org/t/p/w500/4BMG9hk9NvSBeQvC82sVmVRK140.jpg",
             isSeries: 0,
             seasonId: "mock_season_1",
             isEpisode: true,
             added: "2023-01-01",
             seriesId: "mock_s_1"
        )
    ]
    // MARK: - Marketing Content (Real Posters for Welcome Screen Collage)
    static let marketingPosters: [String] = [
        "https://image.tmdb.org/t/p/w500/qA5kPYZA7FkVvqcEfJRoOy4k2xI.jpg", // Oppenheimer
        "https://image.tmdb.org/t/p/w500/8RpDCSfKTer8iboCuYLerHHOScO.jpg", // Mission Impossible
        "https://image.tmdb.org/t/p/w500/fcBdDuh6JXUjX2Wj2K06W1JZM3.jpg", // Dune 2
        "https://image.tmdb.org/t/p/w500/1E5baAaEse26fej7uHkjJDveYo3.jpg", // Wonka
        "https://image.tmdb.org/t/p/w500/qhb1qOilapbapxWQn9jtRCMwXJF.jpg", // Wonka
        "https://image.tmdb.org/t/p/w500/j9qix0Hj7lM7v8I81h7lV9h1X.jpg", // Godzilla x Kong
        "https://image.tmdb.org/t/p/w500/t6HIqrRAclMCA60NsSmeqe9RmPA.jpg", // Deadpool & Wolverine
        "https://image.tmdb.org/t/p/w500/z1p34vh7dEOnLDmyCrlUVLuoDzd.jpg", // Civil War
        "https://image.tmdb.org/t/p/w500/7WsyChQLEftFiDOVTGkv3hFpyyt.jpg", // Avengers Infinity War
        "https://image.tmdb.org/t/p/w500/or06FN3Dka5tukK1e9sl16pB3iy.jpg", // Avengers Endgame
        "https://image.tmdb.org/t/p/w500/8riWcADI1BdEiCNP9JeJ5f2k1wP.jpg", // Spider-Man No Way Home
        "https://image.tmdb.org/t/p/w500/cxevDYdeFkiixRShbObdwAHBZry.jpg", // The Batman
        "https://image.tmdb.org/t/p/w500/r2J02Z2OpNTctfOSN1Ydgii51I3.jpg", // Guardians of the Galaxy 3
        "https://image.tmdb.org/t/p/w500/fiVW06jE7z9YnO4trhaMEdclSiC.jpg", // Fast X
        "https://image.tmdb.org/t/p/w500/hr9rjR3J0xBBK981WkF3Qac9xKS.jpg", // Top Gun Maverick
        "https://image.tmdb.org/t/p/w500/pFlaoHTZeyNkG83vxsAJiGzfSsa.jpg", // Black Adam
        "https://image.tmdb.org/t/p/w500/y5Z0WesTjvn59jP6yo935Pm6962.jpg", // Avatar 2
        "https://image.tmdb.org/t/p/w500/vZloFAK7NmvMGKE7VkF5UHaz0I.jpg", // John Wick 4
        "https://image.tmdb.org/t/p/w500/h8gHn0OzSb8DS3VSEnTHq5rL9xM.jpg", // Mario Bros
        "https://image.tmdb.org/t/p/w500/bOGkgRGdhrBYJSLpXaxhXVstddV.jpg", // Little Mermaid
        "https://image.tmdb.org/t/p/w500/kuf6dutpsT0vSVehic3EZIqkOBt.jpg", // Puss in Boots
        "https://image.tmdb.org/t/p/w500/u3bZgnGQ9TWA75GkVPwgqaR5XL.jpg", // The Flash
        "https://image.tmdb.org/t/p/w500/gPbM0MK8CP8A174rmUwGsADNYKD.jpg", // Transformers
        "https://image.tmdb.org/t/p/w500/vOD25tq3yQ0F3e4q8d7h7e6q1.jpg", // Elemental
        "https://image.tmdb.org/t/p/w500/4m1Au3YkjMnmqTXQqGtBvA8p8c.jpg", // Indiana Jones
        "https://image.tmdb.org/t/p/w500/rKtDFPbfhfDayD8Ca069vScg36.jpg"  // Barbie
    ]
}
