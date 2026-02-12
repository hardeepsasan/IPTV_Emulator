import SwiftUI
import Combine

struct ChannelInfoTray: View {
    let channel: Channel?
    let client: StalkerClient
    var epgEvents: [EPGEvent] = []
    
    // Timer for updating progress bar (every 30s)
    @State private var now = Date()
    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 1. Rigidity Spacer
            Rectangle()
                .fill(Color.clear)
                .frame(height: 40)
            
            // 2. Content
            VStack(alignment: .leading, spacing: 6) {
                if let channel = channel {
                    
                    // --- ROW 1: Channel Name & Logo ---
                    HStack(spacing: 12) {
                        // Header Logo
                        SmartChannelLogo(
                            channel: channel,
                            client: client,
                            categoryName: nil, // We don't have category here, will fallback to initial
                            fallbackBackground: AnyView(Color.clear), // Transparent fallback
                            fallbackOverlay: AnyView(EmptyView()) // scNo text overlay
                        )
                        .frame(width: 80, height: 80)
                        .id(channel.id) // FORCE REFRESH: Destroy old state when channel changes
                        
                        Text(channel.name)
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
                    }
                    .frame(maxWidth: 700, alignment: .leading)
                    
                    let currentEvent = getCurrentEvent()
                    
                    // --- ROW 2: Program Title ---
                    if let event = currentEvent {
                        Text(event.name)
                            .font(.system(size: 28, weight: .medium)) // Larger, distinct
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(1)
                        
                        // --- ROW 3: Time Range Only ---
                        if let event = currentEvent {
                             Text(formatDuration(event)) // e.g., "60 min"
                                 .font(.caption)
                                 .foregroundColor(.gray)
                                 .padding(.top, 2)
                        }
                        
                        // --- ROW 4: Description ---
                        if let desc = event.descr, !desc.isEmpty {
                            Text(desc)
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(3)
                                .frame(maxWidth: 650, alignment: .leading) // Limit width to avoid overlap
                                .padding(.top, 4)
                        }
                        
                        // --- ROW 5: UPCOMING (Small List) ---
                        // Show next 2 events
                        let nextEvents = getNextEvents(count: 2)
                        if !nextEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(nextEvents) { next in
                                    HStack {
                                        Text(next.formattedTimeRange)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .frame(width: 160, alignment: .leading) // Widened to prevent wrapping
                                        Text(next.name)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.top, 8)
                        }
                        
                    } else {
                        // Fallback to Channel's internal 'curPlaying' if no EPG
                        if let playing = channel.curPlaying, !playing.isEmpty {
                            Text(playing)
                                .font(.system(size: 26))
                                .foregroundColor(.white.opacity(0.9))
                        } else {
                            Text("No Program Information")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
            }
            .frame(height: 350, alignment: .topLeading) // Increased height for EPG
            .onReceive(timer) { input in
                self.now = input
            }
        }
        .padding(.horizontal, 80)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.95),
                    Color.black.opacity(0.5),
                    Color.clear
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -200)
        )
        .frame(height: 400, alignment: .top) // Increased container height
        .clipped()
    }
    
    // MARK: - Helpers
    
    private func getCurrentEvent() -> EPGEvent? {
        // Find event that contains 'now'
        return epgEvents.first { event in
            guard let start = event.startTimeDate, let end = event.endTimeDate else { return false }
            return now >= start && now < end
        }
    }
    
    private func getNextEvents(count: Int) -> [EPGEvent] {
         guard let current = getCurrentEvent() else { return [] }
         // Events sorted by time in `ChannelsView`.
         if let idx = epgEvents.firstIndex(where: { $0.id == current.id }) {
             let start = min(idx + 1, epgEvents.count)
             let end = min(idx + 1 + count, epgEvents.count)
             return Array(epgEvents[start..<end])
         }
         return []
    }
    
    private func getProgress(_ event: EPGEvent) -> Double {
        guard let start = event.startTimeDate, let end = event.endTimeDate else { return 0 }
        let total = end.timeIntervalSince(start)
        let elapsed = now.timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }
    
    private func formatDuration(_ event: EPGEvent) -> String {
        guard let duration = Double(event.duration) else { return "" }
        // Duration is usually in seconds
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}
