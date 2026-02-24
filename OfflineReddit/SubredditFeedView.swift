import SwiftUI
import SwiftData

struct SubredditFeedView: View {
    @State private var activeSubreddit: String
    @Query(sort: \SubredditSubscription.name) private var subscriptions: [SubredditSubscription]
    @Environment(\.modelContext) private var context
    
    @Query(sort: \RedditPost.sortOrder, order: .forward)
    private var savedPosts: [RedditPost]
    
    init(initialSubreddit: String) {
        _activeSubreddit = State(initialValue: initialSubreddit)
    }
    
    var body: some View {
        List {
            let filtered = savedPosts.filter { $0.subreddit.lowercased() == activeSubreddit.lowercased() }
            
            if filtered.isEmpty {
                Text("No posts saved for r/\(activeSubreddit). Pull down to fetch!").foregroundColor(.secondary)
            }
            
            ForEach(filtered) { post in
                NavigationLink(destination: PostDetailView(post: post)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(post.title.cleanRedditText())).font(.headline)
                        
                        HStack {
                            Text("#\(post.sortOrder + 1)")
                                .font(.caption2).bold()
                                .padding(2).background(Color.gray.opacity(0.2)).cornerRadius(4)
                            Text("u/\(post.author)").font(.caption).foregroundColor(.secondary)
                        }
                        
                        if !post.selftext.isEmpty {
                            Text(LocalizedStringKey(post.selftext.cleanRedditText())).font(.body).lineLimit(4)
                        }
                        
                        if let firstFileName = post.localImageFileNames.first,
                           let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            let fileURL = docDir.appendingPathComponent(firstFileName)
                            
                            if let uiImage = UIImage(contentsOfFile: fileURL.path) {
                                Image(uiImage: uiImage).resizable().scaledToFit().frame(maxHeight: 250).cornerRadius(8)
                                    .overlay(alignment: .topTrailing) {
                                        if post.localImageFileNames.count > 1 {
                                            HStack(spacing: 4) {
                                                Image(systemName: "photo.on.rectangle.angled")
                                                Text("\(post.localImageFileNames.count)")
                                            }
                                            .font(.caption2).bold().foregroundColor(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Color.black.opacity(0.7)).clipShape(Capsule()).padding(8)
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // FIX: Pull to refresh local fetch
        .refreshable {
            await fetchAndSavePosts()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(subscriptions) { sub in
                        Button("r/\(sub.name)") { activeSubreddit = sub.name }
                    }
                } label: {
                    HStack {
                        Text("r/\(activeSubreddit)").font(.headline).foregroundColor(.primary)
                        Image(systemName: "chevron.down.circle.fill").font(.caption).foregroundColor(.gray)
                    }
                }
            }
        }
    }
    
    private func fetchAndSavePosts() async {
        do {
            let fetchedPosts = try await NetworkManager.shared.fetchPosts(for: activeSubreddit)
            for (index, dto) in fetchedPosts.enumerated() {
                if let existingPost = savedPosts.first(where: { $0.id == dto.id }) {
                    existingPost.sortOrder = index
                } else {
                    let newPost = RedditPost(id: dto.id, title: dto.title, author: dto.author, selftext: dto.selftext, mediaURL: dto.url, subreddit: activeSubreddit, sortOrder: index)
                    context.insert(newPost)
                    
                    let allMediaURLs = NetworkManager.shared.extractAllMediaURLs(from: dto)
                    var savedFileNames: [String] = []
                    for (urlIndex, bestURL) in allMediaURLs.enumerated() {
                        if let localFileName = await NetworkManager.shared.downloadAndSaveImage(from: bestURL, id: "\(dto.id)_\(urlIndex)") {
                            savedFileNames.append(localFileName)
                        }
                    }
                    newPost.localImageFileNames = savedFileNames
                }
            }
            try context.save()
        } catch { print("Error fetching active subreddit: \(error)") }
    }
}
