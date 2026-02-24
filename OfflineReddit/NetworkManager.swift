import Foundation
import Combine

class AppLogger: ObservableObject {
    static let shared = AppLogger()
    @Published var logs: [String] = []
    
    func log(_ message: String) {
        DispatchQueue.main.async {
            let time = Date().formatted(date: .omitted, time: .standard)
            self.logs.insert("[\(time)] \(message)", at: 0)
            print("[\(time)] \(message)")
        }
    }
    
    func clear() { DispatchQueue.main.async { self.logs.removeAll() } }
}

class NetworkManager {
    static let shared = NetworkManager()
    let userAgent = "ios:com.offlinereddit.app:v1.0 (by /u/dhjkashdkjsa)"
    
    func fetchPosts(for subreddit: String) async throws -> [RedditPostDTO] {
        guard let url = URL(string: "https://www.reddit.com/r/\(subreddit)/hot.json") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(RedditResponse.self, from: data)
        return decoded.data.children.map { $0.data }
    }
    
    func fetchComments(for postID: String, subreddit: String, postTitle: String) async throws -> [CommentDTO] {
        guard let url = URL(string: "https://www.reddit.com/r/\(subreddit)/comments/\(postID).json") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                AppLogger.shared.log("🛑 RATE LIMIT on: \(postTitle.prefix(30))...")
                throw URLError(.userAuthenticationRequired)
            }
        }
        
        let jsonArray = try JSONDecoder().decode([CommentResponse].self, from: data)
        guard jsonArray.count > 1 else { return [] }
        return flattenComments(from: jsonArray[1].data.children)
    }
    
    private func flattenComments(from children: [CommentChild]) -> [CommentDTO] {
        var all: [CommentDTO] = []
        for child in children where child.kind == "t1" {
            all.append(child.data)
            if let replies = child.data.replies, case .listing(let listing) = replies {
                all.append(contentsOf: flattenComments(from: listing.data.children))
            }
        }
        return all
    }
    
    func extractAllMediaURLs(from dto: RedditPostDTO) -> [String] {
        var urls: [String] = []
        if dto.is_gallery == true, let items = dto.gallery_data?.items, let metadata = dto.media_metadata {
            for item in items {
                if let mediaId = item.media_id, let mediaUrl = metadata[mediaId]?.s?.u {
                    urls.append(mediaUrl.replacingOccurrences(of: "&amp;", with: "&"))
                }
            }
        } else if let singleUrl = dto.url {
            urls.append(singleUrl)
        }
        return urls
    }
    
    func downloadAndSaveImage(from urlString: String, id: String) async -> String? {
        let clean = urlString.replacingOccurrences(of: "&amp;", with: "&")
        let urlWithoutQuery = clean.components(separatedBy: "?").first ?? clean
        
        guard let url = URL(string: clean), let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        
        let ext = URL(string: urlWithoutQuery)?.pathExtension.lowercased() ?? ""
        if !["jpg", "jpeg", "png", "gif", "webp"].contains(ext) { return nil }
        
        let fileName = "\(id).\(ext)"
        let fileURL = docDir.appendingPathComponent(fileName)
        
        do {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try data.write(to: fileURL)
                return fileName
            }
            return nil
        } catch { return nil }
    }
    
    func clearLocalMediaCache() {
        guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let files = try? FileManager.default.contentsOfDirectory(at: docDir, includingPropertiesForKeys: nil)
        files?.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
