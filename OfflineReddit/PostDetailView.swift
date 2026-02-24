import SwiftUI
import SwiftData
import SafariServices

// MARK: - Zoomable Image Component
struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    var body: some View {
        Image(uiImage: image).resizable().scaledToFit().scaleEffect(scale)
            .gesture(MagnificationGesture().onChanged { scale = $0 }.onEnded { _ in if scale < 1 { scale = 1.0 } })
    }
}

// MARK: - Fullscreen Multi-Image Viewer
struct FullScreenGalleryView: View {
    let fileNames: [String]
    @State var currentIndex: Int
    @Environment(\.dismiss) var dismiss
    @State private var dragOffset: CGFloat = 0
    var docDir: URL? { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first }
    
    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(fileNames.enumerated()), id: \.offset) { index, fileName in
                    if let dir = docDir, let uiImage = UIImage(contentsOfFile: dir.appendingPathComponent(fileName).path) {
                        ZoomableImage(image: uiImage).tag(index)
                    }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .background(Color.black.ignoresSafeArea())
            .offset(y: dragOffset)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Track both up and down swipes by using the absolute value
                        if abs(value.translation.height) > abs(value.translation.width) {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        // Dismiss if swiped far enough up OR down
                        if abs(dragOffset) > 100 { dismiss() }
                        else { withAnimation(.spring()) { dragOffset = 0 } }
                    }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !fileNames.isEmpty, let dir = docDir {
                        ShareLink(item: dir.appendingPathComponent(fileNames[currentIndex])) { Image(systemName: "square.and.arrow.up").foregroundColor(.white) }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Close") { dismiss() }.foregroundColor(.white).bold() }
            }.toolbarBackground(.black, for: .navigationBar)
        }
    }
}

// MARK: - Post Detail View
struct PostDetailView: View {
    let post: RedditPost
    @Environment(\.modelContext) private var context
    @Query private var allComments: [RedditComment]
    
    @AppStorage("readingFontSize") private var readingFontSize: Double = 16.0
    @AppStorage("isZenMode") private var isZenMode = false
    
    @State private var isLoading = false
    @State private var collapsedCommentIDs: Set<String> = []
    @State private var currentTopLevelIndex = -1
    
    @State private var showingFullscreen = false
    @State private var tappedImageIndex = 0
    @State private var safariURL: IdentifiableURL? = nil
    
    var visibleComments: [RedditComment] {
        let postComments = allComments.filter { $0.postID == post.id }.sorted { $0.orderIndex < $1.orderIndex }
        var result: [RedditComment] = []
        var hideDepth = Int.max
        for comment in postComments {
            if comment.depth <= hideDepth {
                hideDepth = Int.max
                result.append(comment)
                if collapsedCommentIDs.contains(comment.id) { hideDepth = comment.depth }
            }
        }
        return result
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey(post.title.cleanRedditText()))
                        .font(.system(size: readingFontSize + 4, weight: .bold))
                    
                    if !isZenMode { Text("u/\(post.author)").font(.subheadline).foregroundColor(.secondary) }
                    
                    if !post.selftext.isEmpty {
                        Text(LocalizedStringKey(post.selftext.cleanRedditText()))
                            .font(.system(size: readingFontSize)).tint(.blue)
                    }
                    
                    if !isZenMode {
                        if !post.localImageFileNames.isEmpty, let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            TabView {
                                ForEach(Array(post.localImageFileNames.enumerated()), id: \.offset) { index, fileName in
                                    let fileURL = docDir.appendingPathComponent(fileName)
                                    if let uiImage = UIImage(contentsOfFile: fileURL.path) {
                                        Image(uiImage: uiImage).resizable().scaledToFit()
                                            .onTapGesture { self.tappedImageIndex = index; self.showingFullscreen = true }
                                    }
                                }
                            }
                            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                            .frame(height: 350).cornerRadius(8)
                            
                            HStack(spacing: 16) {
                                let fileURLs = post.localImageFileNames.map { docDir.appendingPathComponent($0) }
                                if post.localImageFileNames.count > 1 {
                                    ShareLink(items: fileURLs) { Label("Share Gallery", systemImage: "photo.on.rectangle") }.buttonStyle(.bordered)
                                } else if let singleURL = fileURLs.first {
                                    ShareLink(item: singleURL) { Label("Share Image", systemImage: "photo") }.buttonStyle(.bordered)
                                }
                                if let postURL = URL(string: "https://www.reddit.com/r/\(post.subreddit)/comments/\(post.id)") {
                                    ShareLink(item: postURL) { Label("Share Post", systemImage: "link") }.buttonStyle(.bordered)
                                }
                            }
                        } else if let link = post.mediaURL, let url = URL(string: link), link.hasPrefix("http") {
                            Button(action: { safariURL = IdentifiableURL(url: url) }) {
                                HStack {
                                    Image(systemName: "safari"); Text("Open Link / Video"); Spacer(); Image(systemName: "chevron.right").font(.caption)
                                }.padding().background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(8)
                            }.buttonStyle(.plain)
                            
                            if let postURL = URL(string: "https://www.reddit.com/r/\(post.subreddit)/comments/\(post.id)") {
                                ShareLink(item: postURL) { Label("Share Reddit Post", systemImage: "link") }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(.vertical).id("post_header")
                
                Section(header: Text(isZenMode ? "" : "Comments")) {
                    if isLoading { ProgressView() }
                    else {
                        ForEach(visibleComments) { comment in
                            HStack(alignment: .top, spacing: 8) {
                                if comment.depth > 0 {
                                    Spacer().frame(width: CGFloat(comment.depth * 12))
                                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 2)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    if !isZenMode { Text("u/\(comment.author)").font(.caption).bold().foregroundColor(.blue) }
                                    if !collapsedCommentIDs.contains(comment.id) {
                                        Text(LocalizedStringKey(comment.body.cleanRedditText()))
                                            .font(.system(size: readingFontSize)).tint(.blue)
                                    }
                                }
                            }
                            .padding(.vertical, 4).contentShape(Rectangle()).id(comment.id)
                            .onTapGesture {
                                withAnimation {
                                    if collapsedCommentIDs.contains(comment.id) {
                                        collapsedCommentIDs.remove(comment.id)
                                    } else {
                                        collapsedCommentIDs.insert(comment.id)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    collapseThreadAndJump(from: comment, proxy: proxy)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }.tint(.orange)
                            }
                        }
                    }
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                safariURL = IdentifiableURL(url: url)
                return .handled
            })
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await fetchCommentsIfNeeded(forceRefresh: true) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { readingFontSize += 2 }) { Label("Increase Text Size", systemImage: "plus.magnifyingglass") }
                        Button(action: { if readingFontSize > 10 { readingFontSize -= 2 } }) { Label("Decrease Text Size", systemImage: "minus.magnifyingglass") }
                        Button(action: { readingFontSize = 16.0 }) { Label("Default Text Size", systemImage: "textformat") }
                        Divider()
                        Button(action: { withAnimation { isZenMode.toggle() } }) { Label(isZenMode ? "Exit Zen Mode" : "Enter Zen Mode", systemImage: isZenMode ? "eye.slash.fill" : "eye") }
                    } label: { Image(systemName: "textformat.size") }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: { jumpToNextTopLevelComment(proxy: proxy) }) {
                    Image(systemName: "chevron.down.circle.fill").resizable().frame(width: 44, height: 44).foregroundColor(.blue).background(Circle().fill(.white)).shadow(radius: 2)
                }.padding()
            }
            .task { await fetchCommentsIfNeeded() }
            .sheet(item: $safariURL) { ident in SafariView(url: ident.url).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showingFullscreen) { FullScreenGalleryView(fileNames: post.localImageFileNames, currentIndex: tappedImageIndex) }
        }
    }
    
    private func fetchCommentsIfNeeded(forceRefresh: Bool = false) async {
        if !forceRefresh { guard allComments.filter({ $0.postID == post.id }).isEmpty else { return } }
        isLoading = true
        do {
            let fetched = try await NetworkManager.shared.fetchComments(for: post.id, subreddit: post.subreddit, postTitle: post.title)
            if forceRefresh {
                let oldComments = allComments.filter { $0.postID == post.id }
                for c in oldComments { context.delete(c) }
            }
            for (index, dto) in fetched.enumerated() {
                if let id = dto.id, let author = dto.author, let body = dto.body {
                    context.insert(RedditComment(id: id, postID: post.id, author: author, body: body, depth: dto.depth ?? 0, orderIndex: index))
                }
            }
            try? context.save()
        } catch { }
        isLoading = false
    }
    
    private func jumpToNextTopLevelComment(proxy: ScrollViewProxy) {
        let topLevel = allComments.filter { $0.postID == post.id && $0.depth == 0 }.sorted { $0.orderIndex < $1.orderIndex }
        currentTopLevelIndex += 1
        if currentTopLevelIndex >= topLevel.count { currentTopLevelIndex = -1; withAnimation { proxy.scrollTo("post_header") }; return }
        withAnimation { proxy.scrollTo(topLevel[currentTopLevelIndex].id, anchor: .top) }
    }
    
    private func collapseThreadAndJump(from comment: RedditComment, proxy: ScrollViewProxy) {
        let postComments = allComments.filter { $0.postID == post.id }
        if let topParent = postComments.filter({ $0.depth == 0 && $0.orderIndex <= comment.orderIndex }).max(by: { $0.orderIndex < $1.orderIndex }) {
            collapsedCommentIDs.insert(topParent.id)
        } else {
            collapsedCommentIDs.insert(comment.id)
        }
        
        jumpToNextTopLevelComment(proxy: proxy)
    }
}
