import SwiftUI

struct AuthenticatedImage: View {
    let url: URL?
    let targetSize: CGSize? // Optional specific size for downsampling
    let client: StalkerClient // [PERFORMANCE] No longer ObservedObject
    
    init(url: URL?, targetSize: CGSize? = nil, client: StalkerClient) {
        self.url = url
        self.targetSize = targetSize
        self.client = client
    }
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.clear // Transparent fallback to avoid grey artifacts
                    .allowsHitTesting(false) // Pass touches through
                // ProgressView removed to prevent persistent spinner artifact
            }
        }

        // Fix: Use .task(id:) for structured concurrency
        // This automatically cancels the download if the view disappears or URL changes.
        .task(id: url) {
            await loadImage()
        }
    }
    
    // Marked MainActor to ensure UI updates are safe, though called from .task which inherits context
    @MainActor
    private func loadImage() async {
        guard let url = url else { return }
        
        isLoading = true
        
        do {
            if let uiImage = try await client.fetchImage(url: url, targetSize: targetSize) {
                self.image = uiImage
                self.isLoading = false
            }
        } catch {
            if error is CancellationError {
                // print("DEBUG: ⏭️ DISCARDED \(url.lastPathComponent)")
            } else {
                print("DEBUG: ❌ ERROR \(url.lastPathComponent): \(error)")
            }
            self.isLoading = false
        }
    }
}
