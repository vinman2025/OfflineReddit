import SwiftUI
import SwiftData

@main
struct OfflineRedditApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // NEW: Added SubredditSubscription.self to the database
        .modelContainer(for: [SubredditSubscription.self, RedditPost.self, RedditComment.self])
    }
}
