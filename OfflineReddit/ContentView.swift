import SwiftUI
import SwiftData
import SafariServices

// MARK: - In-App Safari Browser
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Debugger UI
struct DebugConsoleView: View {
    @ObservedObject var logger = AppLogger.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List(logger.logs, id: \.self) { log in
                Text(log).font(.system(.caption, design: .monospaced))
                    .foregroundColor(log.contains("🔴") || log.contains("🛑") ? .red : (log.contains("⚠️") ? .orange : .primary))
            }
            .navigationTitle("Network Debugger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Clear") { logger.clear() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { dismiss() }.bold() }
            }
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SubredditSubscription.name) private var subscriptions: [SubredditSubscription]
    @Query private var allPosts: [RedditPost]
    @Query private var allComments: [RedditComment]
    
    @AppStorage("appColorScheme") private var appColorScheme: Int = 0
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore: Bool = false
    
    @State private var showingAddDialog = false
    @State private var showingDebugger = false
    @State private var newSubredditName = ""
    
    @State private var isCheckingSubreddit = false
    @State private var showingSuggestionAlert = false
    @State private var showingNotFoundAlert = false
    @State private var suggestionName = ""
    @State private var notFoundMessage = ""
    
    @State private var isRefreshingAll = false
    @State private var refreshProgressText = ""
    @State private var timeRemainingText = ""
    @State private var refreshCurrentStep: Double = 0
    @State private var refreshTotalSteps: Double = 1
    
    @State private var showingSmartSyncAlert = false
    @State private var smartSyncLimit = 10
    @State private var recentlySyncedSubs: [String] = []
    
    @State private var subProgressMap: [String: String] = [:]
    @State private var activeSyncs: Set<String> = []
    @State private var cancelTokens: Set<String> = []
    @State private var currentPostLimit: Int = 10
    
    var body: some View {
        NavigationStack {
            ZStack {
                ZStack(alignment: .bottom) {
                    List {
                        if subscriptions.isEmpty {
                            Text("Tap '+' to add a subreddit!").foregroundColor(.secondary)
                        }
                        ForEach(subscriptions) { sub in
                            NavigationLink(destination: SubredditFeedView(initialSubreddit: sub.name)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("r/\(sub.name)").font(.headline)
                                        if let status = subProgressMap[sub.name] {
                                            Text(status)
                                                .font(.caption2)
                                                .foregroundColor(status == "Cancelled" ? .red : .blue)
                                                .bold()
                                        } else {
                                            let postCount = allPosts.filter { $0.subreddit.lowercased() == sub.name.lowercased() }.count
                                            Text("\(postCount) saved").font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    
                                    if subProgressMap[sub.name] == "Waiting in queue..." || activeSyncs.contains(sub.name) {
                                        HStack(spacing: 12) {
                                            if activeSyncs.contains(sub.name) { ProgressView().progressViewStyle(.circular).scaleEffect(0.8) }
                                            Button(action: {
                                                cancelTokens.insert(sub.name)
                                                if subProgressMap[sub.name] == "Waiting in queue..." {
                                                    subProgressMap[sub.name] = "Cancelled"
                                                    refreshCurrentStep += Double(1 + currentPostLimit)
                                                    updateTimeRemaining()
                                                }
                                            }) {
                                                Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.title3)
                                            }.buttonStyle(.borderless)
                                        }
                                    } else {
                                        Button(action: { Task { await runSingleSync(for: sub.name, postLimit: 10) } }) {
                                            Image(systemName: "icloud.and.arrow.down").foregroundColor(.blue).font(.title3)
                                        }.buttonStyle(.borderless).disabled(isRefreshingAll)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteSubscription)
                    }
                    .refreshable {
                        currentPostLimit = 10
                        checkSmartSync(limit: currentPostLimit)
                    }
                    
                    if isRefreshingAll {
                        HStack(spacing: 16) {
                            VStack(spacing: 12) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(UIColor.secondarySystemFill))
                                        Capsule().fill(Color.accentColor)
                                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(refreshCurrentStep / max(1, refreshTotalSteps)))))
                                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: refreshCurrentStep)
                                    }
                                }.frame(height: 6)
                                
                                HStack {
                                    Text(refreshProgressText).font(.caption).bold()
                                    Spacer()
                                    Text(timeRemainingText).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            
                            Button(action: {
                                cancelTokens.insert("MASTER")
                                refreshProgressText = "Cancelling..."
                                for sub in subscriptions where subProgressMap[sub.name] == "Waiting in queue..." {
                                    subProgressMap[sub.name] = "Cancelled"
                                    refreshCurrentStep += Double(1 + currentPostLimit)
                                }
                                updateTimeRemaining()
                            }) { Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundColor(.red) }
                        }
                        .padding().background(.ultraThinMaterial)
                        .cornerRadius(16).shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4).padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
                if isCheckingSubreddit {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text("Verifying...").font(.headline)
                    }
                    .padding(32)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                    .transition(.opacity)
                }
            }
            .navigationTitle("My Subreddits")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Menu {
                        Menu {
                            Button("System Default") { appColorScheme = 0 }
                            Button("Light Mode") { appColorScheme = 1 }
                            Button("Dark Mode") { appColorScheme = 2 }
                        } label: { Label("App Theme", systemImage: "moon.stars") }
                        
                        Button(role: .destructive, action: manualClearCache) { Label("Clear All Cached Data", systemImage: "trash") }
                    } label: { Image(systemName: "gear") }
                    .disabled(isRefreshingAll || !activeSyncs.isEmpty)
                    
                    Menu {
                        Button("Quick Sync (Top 10)") { currentPostLimit = 10; checkSmartSync(limit: 10) }
                        Button("Deep Sync (Top 25)") { currentPostLimit = 25; checkSmartSync(limit: 25) }
                    } label: { Image(systemName: "arrow.clockwise.circle") }.disabled(isRefreshingAll || subscriptions.isEmpty || !activeSyncs.isEmpty)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showingDebugger = true }) { Image(systemName: "ladybug") }
                    Button(action: { showingAddDialog = true }) { Image(systemName: "plus") }.disabled(isRefreshingAll)
                }
            }
            .alert("Add Subreddit", isPresented: $showingAddDialog) {
                TextField("e.g. technology", text: $newSubredditName).autocapitalization(.none).disableAutocorrection(true)
                Button("Cancel", role: .cancel) { newSubredditName = "" }
                Button("Add") { addSubredditTapped() }
            } message: { Text("Enter the name of the subreddit without the 'r/'") }
            
            // FEATURE: Suggestion Alert with "Add Anyway" Override
            .alert("Did you mean r/\(suggestionName)?", isPresented: $showingSuggestionAlert) {
                Button("Yes, add r/\(suggestionName)") {
                    context.insert(SubredditSubscription(name: suggestionName.lowercased()))
                    newSubredditName = ""
                }
                Button("No, add r/\(newSubredditName) anyway") {
                    context.insert(SubredditSubscription(name: newSubredditName.lowercased()))
                    newSubredditName = ""
                }
                Button("Cancel", role: .cancel) { }
            } message: { Text("We couldn't find r/\(newSubredditName).") }
            
            // FEATURE: Not Found Alert with "Add Anyway" Override
            .alert("Subreddit Not Found", isPresented: $showingNotFoundAlert) {
                Button("Add Anyway") {
                    context.insert(SubredditSubscription(name: newSubredditName.lowercased()))
                    newSubredditName = ""
                }
                Button("Cancel", role: .cancel) { }
            } message: { Text(notFoundMessage) }
            
            .alert("Skip Recent Subreddits?", isPresented: $showingSmartSyncAlert) {
                Button("Skip \(recentlySyncedSubs.count) Recent") { Task { await runMasterSync(postLimit: smartSyncLimit, skipList: recentlySyncedSubs) } }
                Button("Sync All Anyway") { Task { await runMasterSync(postLimit: smartSyncLimit, skipList: []) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("\(recentlySyncedSubs.count) subreddits were synced in the last 15 minutes. Would you like to skip them to save time?") }
            .sheet(isPresented: $showingDebugger) { DebugConsoleView() }
            .task {
                if !hasLaunchedBefore {
                    context.insert(SubredditSubscription(name: "askreddit"))
                    context.insert(SubredditSubscription(name: "askscience+explainlikeimfive+askengineers"))
                    try? context.save()
                    hasLaunchedBefore = true
                }
                autoCleanupStorage()
            }
        }
        .preferredColorScheme(appColorScheme == 1 ? .light : (appColorScheme == 2 ? .dark : nil))
    }
    
    // MARK: - Validation Actions
    private func addSubredditTapped() {
        let cleanName = newSubredditName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "").lowercased()
        if cleanName.isEmpty { return }
        if subscriptions.contains(where: { $0.name.lowercased() == cleanName }) {
            newSubredditName = ""
            return
        }
        Task { await validateAndAddSubreddit(name: cleanName) }
    }
    
    // FEATURE: Multi-Reddit Iterator Support
    private func validateAndAddSubreddit(name: String) async {
        await MainActor.run { isCheckingSubreddit = true }
        
        do {
            let individualSubs = name.split(separator: "+").map { String($0) }
            var allValid = true
            var failedSub = ""
            
            // 1. Loop through and validate every subreddit in the string individually
            for sub in individualSubs {
                let safeName = sub.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sub
                guard let url = URL(string: "https://www.reddit.com/r/\(safeName)/about.json") else { throw URLError(.badURL) }
                
                var request = URLRequest(url: url)
                request.setValue("ios:OfflineRedditReader:v1.0", forHTTPHeaderField: "User-Agent")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       json["kind"] as? String == "t5" {
                        continue // Success, move to the next one
                    } else {
                        allValid = false; failedSub = sub; break
                    }
                } else {
                    allValid = false; failedSub = sub; break
                }
            }
            
            // 2. If all subreddits passed, save the original multi-reddit string
            if allValid {
                await MainActor.run {
                    context.insert(SubredditSubscription(name: name))
                    newSubredditName = ""
                    isCheckingSubreddit = false
                }
                return
            }
            
            // 3. If it is a multi-reddit and validation failed, bypass the suggestion engine
            if individualSubs.count > 1 {
                await MainActor.run {
                    isCheckingSubreddit = false
                    notFoundMessage = "We couldn't verify r/\(failedSub) inside your multi-reddit string."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingNotFoundAlert = true }
                }
                return
            }
            
            // 4. If it's a single subreddit, hit Reddit's GLOBAL search engine to utilize typo-correction
            let safeName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            guard let searchUrl = URL(string: "https://www.reddit.com/search.json?q=\(safeName)&type=sr&limit=1") else { throw URLError(.badURL) }
            var searchReq = URLRequest(url: searchUrl)
            searchReq.setValue("ios:OfflineRedditReader:v1.0", forHTTPHeaderField: "User-Agent")
            
            let (sData, _) = try await URLSession.shared.data(for: searchReq)
            if let sJson = try JSONSerialization.jsonObject(with: sData) as? [String: Any],
               let dataDict = sJson["data"] as? [String: Any],
               let children = dataDict["children"] as? [[String: Any]],
               let firstChild = children.first,
               let childData = firstChild["data"] as? [String: Any],
               let suggestion = childData["display_name"] as? String,
               suggestion.lowercased() != name.lowercased() {
                
                await MainActor.run {
                    isCheckingSubreddit = false
                    suggestionName = suggestion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingSuggestionAlert = true }
                }
                return
            }
            
            // 5. Total gibberish fallback
            await MainActor.run {
                isCheckingSubreddit = false
                notFoundMessage = "We couldn't find a subreddit named r/\(name)."
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingNotFoundAlert = true }
            }
            
        } catch {
            await MainActor.run {
                isCheckingSubreddit = false
                notFoundMessage = "Network error. Please check your connection."
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingNotFoundAlert = true }
            }
        }
    }
    
    // MARK: - Standard Actions
    private func deleteSubscription(offsets: IndexSet) {
        for index in offsets {
            let subToDelete = subscriptions[index]
            context.delete(subToDelete)
            let postsToDelete = allPosts.filter { $0.subreddit.lowercased() == subToDelete.name.lowercased() }
            for post in postsToDelete { context.delete(post) }
        }
    }
    
    private func checkSmartSync(limit: Int) {
        let fifteenMinsAgo = Date().addingTimeInterval(-15 * 60)
        let recentPosts = allPosts.filter { $0.fetchDate > fifteenMinsAgo }
        let recentSubNames = Set(recentPosts.map { $0.subreddit.lowercased() })
        
        var recent: [String] = []
        for sub in subscriptions {
            if recentSubNames.contains(sub.name.lowercased()) { recent.append(sub.name) }
        }
        
        if recent.isEmpty { Task { await runMasterSync(postLimit: limit, skipList: []) } }
        else { recentlySyncedSubs = recent; smartSyncLimit = limit; showingSmartSyncAlert = true }
    }
    
    private func runSingleSync(for subName: String, postLimit: Int) async {
        cancelTokens.remove(subName)
        currentPostLimit = postLimit
        await syncSubreddit(name: subName, postLimit: postLimit, isMasterSync: false)
        
        if !cancelTokens.contains(subName) { subProgressMap[subName] = "Up to date!" }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        withAnimation { subProgressMap[subName] = nil }
        cancelTokens.remove(subName)
    }
    
    private func runMasterSync(postLimit: Int, skipList: [String]) async {
        let subsToSync = subscriptions.filter { !skipList.contains($0.name) }
        if subsToSync.isEmpty { return }
        
        cancelTokens.removeAll()
        withAnimation { isRefreshingAll = true }
        refreshCurrentStep = 0
        refreshTotalSteps = Double(subsToSync.count) * Double(1 + postLimit)
        updateTimeRemaining()
        
        for sub in subsToSync { subProgressMap[sub.name] = "Waiting in queue..." }
        for sub in subsToSync {
            if cancelTokens.contains("MASTER") { break }
            if cancelTokens.contains(sub.name) { continue }
            
            await syncSubreddit(name: sub.name, postLimit: postLimit, isMasterSync: true)
            if !cancelTokens.contains(sub.name) && !cancelTokens.contains("MASTER") { subProgressMap[sub.name] = "Up to date!" }
        }
        
        withAnimation { isRefreshingAll = false }
        refreshProgressText = ""
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        withAnimation {
            subProgressMap.removeAll()
            cancelTokens.removeAll()
        }
    }
    
    private func syncSubreddit(name: String, postLimit: Int, isMasterSync: Bool) async {
        activeSyncs.insert(name)
        subProgressMap[name] = "Fetching latest feed..."
        if isMasterSync { refreshProgressText = "Fetching posts for r/\(name)..." }
        
        AppLogger.shared.log("🟢 Started syncing r/\(name)...")
        let expectedSteps = isMasterSync ? Double(1 + postLimit) : 0
        var stepsTaken: Double = 0
        var insertedPosts: [RedditPost] = []
        
        do {
            if cancelTokens.contains("MASTER") || cancelTokens.contains(name) { throw URLError(.cancelled) }
            
            let fetchedPosts = try await NetworkManager.shared.fetchPosts(for: name)
            for (index, dto) in fetchedPosts.enumerated() {
                if cancelTokens.contains("MASTER") || cancelTokens.contains(name) { throw URLError(.cancelled) }
                
                if let existingPost = allPosts.first(where: { $0.id == dto.id }) {
                    existingPost.sortOrder = index
                } else {
                    let newPost = RedditPost(id: dto.id, title: dto.title, author: dto.author, selftext: dto.selftext, mediaURL: dto.url, subreddit: name, sortOrder: index)
                    context.insert(newPost)
                    insertedPosts.append(newPost)
                    
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
            if isMasterSync { refreshCurrentStep += 1; stepsTaken += 1; updateTimeRemaining() }
            
            let topPosts = Array(fetchedPosts.prefix(postLimit))
            if isMasterSync {
                let missingPosts = postLimit - topPosts.count
                if missingPosts > 0 { refreshTotalSteps -= Double(missingPosts) }
            }
            
            for (index, postDTO) in topPosts.enumerated() {
                if cancelTokens.contains("MASTER") || cancelTokens.contains(name) { throw URLError(.cancelled) }
                
                subProgressMap[name] = "Caching comments (\(index + 1)/\(topPosts.count))..."
                if isMasterSync { refreshProgressText = "Caching comments for \(postDTO.title.prefix(15))..." }
                
                do {
                    let fetchedComments = try await NetworkManager.shared.fetchComments(for: postDTO.id, subreddit: name, postTitle: postDTO.title)
                    for (cIndex, cDTO) in fetchedComments.enumerated() {
                        if let id = cDTO.id, let author = cDTO.author, let body = cDTO.body {
                            if !allComments.contains(where: { $0.id == id }) {
                                context.insert(RedditComment(id: id, postID: postDTO.id, author: author, body: body, depth: cDTO.depth ?? 0, orderIndex: cIndex))
                            }
                        }
                    }
                    try context.save()
                    AppLogger.shared.log("✅ Cached \(fetchedComments.count) comments for: \(postDTO.title.prefix(20))...")
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                } catch {
                    if (error as? URLError)?.code == .userAuthenticationRequired {
                        subProgressMap[name] = "Rate Limit Hit! Pausing 5s..."
                        AppLogger.shared.log("🛑 Rate Limit Hit! Pausing...")
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                    }
                }
                if isMasterSync { refreshCurrentStep += 1; stepsTaken += 1; updateTimeRemaining() }
            }
        } catch {
            if (error as? URLError)?.code == .cancelled {
                subProgressMap[name] = "Cancelled"
                AppLogger.shared.log("⚠️ Sync cancelled for r/\(name)")
                for p in insertedPosts { context.delete(p) }
                try? context.save()
            } else {
                subProgressMap[name] = "Network Error"
                AppLogger.shared.log("🔴 Network error for r/\(name)")
            }
            if isMasterSync { refreshCurrentStep += (expectedSteps - stepsTaken); updateTimeRemaining() }
        }
        activeSyncs.remove(name)
    }
    
    private func updateTimeRemaining() {
        let stepsLeft = refreshTotalSteps - refreshCurrentStep
        let estimatedSeconds = Int(stepsLeft * 1.5)
        if estimatedSeconds <= 0 { timeRemainingText = "Finishing up..." }
        else if estimatedSeconds > 60 { timeRemainingText = "Estimated time: \(estimatedSeconds / 60)m \(estimatedSeconds % 60)s" }
        else { timeRemainingText = "Estimated time: \(estimatedSeconds)s" }
    }
    
    private func autoCleanupStorage() {
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        for sub in subscriptions {
            let subPosts = allPosts.filter { $0.subreddit.lowercased() == sub.name.lowercased() }.sorted { $0.fetchDate < $1.fetchDate }
            for (index, post) in subPosts.enumerated() {
                if post.fetchDate < tenDaysAgo && (subPosts.count - index) > 20 { context.delete(post) }
            }
        }
    }
    
    private func manualClearCache() {
        try? context.delete(model: RedditPost.self)
        try? context.delete(model: RedditComment.self)
        NetworkManager.shared.clearLocalMediaCache()
        AppLogger.shared.clear()
        AppLogger.shared.log("🗑️ Cache Cleared")
    }
}
