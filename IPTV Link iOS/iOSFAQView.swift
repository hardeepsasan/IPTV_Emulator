#if os(iOS)
import SwiftUI

struct FAQItem: Identifiable {
    var id: String { question }
    let question: String
    let answer: String
}

struct iOSFAQView: View {
    private static let faqs: [FAQItem] = [
        FAQItem(
            question: "How do I connect to my provider?",
            answer: "Enter your Portal URL (provided by your service) in the 'Portal URL' field on the Welcome Screen or Settings. You must also share the 'Virtual MAC' address shown on the screen with your provider for registration."
        ),
        FAQItem(
            question: "Why are some categories empty?",
            answer: "The app builds a search index in the background to make browsing fast. It may take a few minutes for all content to appear initially. You can check the 'Indexer Status' toggle in Settings to see if it is running."
        ),
        FAQItem(
            question: "How do I force a refresh?",
            answer: "Go to Settings > Content Preferences and click 'Clear Cache'. This will force the app to re-scan the server for the latest content."
        ),
        FAQItem(
            question: "What is a 'Virtual MAC'?",
            answer: "This is a unique, safe device identity generated for this specific app installation. It mimics a set-top box so you can register with your provider without exposing your real device hardware."
        ),
        FAQItem(
            question: "My playlist isn't loading / generic error?",
            answer: "1. Ensure your provider supports 'Stalker Portal' (MAG) connections.\n2. Verify you have registered the correct MAC address.\n3. Check your internet connection."
        ),
        FAQItem(
            question: "Why does the indexer stop?",
            answer: "To save bandwidth, the indexer uses 'Smart Sync'. If it sees a page of movies that are already in your cache, it stops downloading automatically because it knows your list is up to date."
        ),
        FAQItem(
            question: "Developer: What does 'Debug: Simulate Stale Cache' do?",
            answer: "This tool manually expires the database timestamp (sets it to 48 hours ago). It is used to verify that the app correctly detects an old database and triggers an auto-refresh on launch."
        ),
        FAQItem(
            question: "Developer: What does 'Clear Movie Cache' do?",
            answer: "This completely wipes the local database of movies and resets the indexing status. Use this if you are experiencing data corruption, missing entries, or want to start fresh."
        ),
        FAQItem(
            question: "Developer: What does 'Generate Logo Manifest' do?",
            answer: "This developer tool scans your current playlist and creates a JSON file mapping channel names to their logo URLs. It is used for creating logo packs or debugging missing assets."
        ),
        FAQItem(
            question: "What does 'Reset to Defaults' do?",
            answer: "This restores the advanced identity fields (Serial Number, Device IDs, Signature) to their initial values. It is useful if you have manually changed them and messed up your connection."
        ),
        FAQItem(
            question: "What does 'Reset Setup (Logout)' do?",
            answer: "This completely logs you out by removing the saved Portal URL and MAC Address. You will be returned to the Welcome screen to start over."
        )
    ]
    
    var body: some View {
        List {
            Section(header: Text("FAQ & Troubleshooting")) {
                ForEach(iOSFAQView.faqs) { item in
                    DisclosureGroup {
                        Text(item.answer)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 5)
                    } label: {
                        Text(item.question)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
            }
            
            Section(header: Text("Contact Us")) {
                HStack {
                    Text("Support Email")
                    Spacer()
                    Text("infotainment.dr@gmail.com")
                        .foregroundColor(.gray)
                }
                .textSelection(.enabled)
            }
        }
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}
#endif
