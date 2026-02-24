import Foundation
import SwiftData

@Model
class SubredditSubscription {
    @Attribute(.unique) var name: String
    init(name: String) { self.name = name }
}

@Model
class RedditPost {
    @Attribute(.unique) var id: String
    var title: String
    var author: String
    var selftext: String
    var mediaURL: String?
    var localImageFileNames: [String] // CHANGED: Now an array to hold multiple gallery images!
    var subreddit: String
    var fetchDate: Date
    var sortOrder: Int

    init(id: String, title: String, author: String, selftext: String, mediaURL: String?, subreddit: String, sortOrder: Int = 0, fetchDate: Date = Date(), localImageFileNames: [String] = []) {
        self.id = id
        self.title = title
        self.author = author
        self.selftext = selftext
        self.mediaURL = mediaURL
        self.subreddit = subreddit
        self.sortOrder = sortOrder
        self.fetchDate = fetchDate
        self.localImageFileNames = localImageFileNames
    }
}

@Model
class RedditComment {
    @Attribute(.unique) var id: String
    var postID: String
    var author: String
    var body: String
    var depth: Int
    var orderIndex: Int
    
    init(id: String, postID: String, author: String, body: String, depth: Int, orderIndex: Int) {
        self.id = id
        self.postID = postID
        self.author = author
        self.body = body
        self.depth = depth
        self.orderIndex = orderIndex
    }
}

extension String {
    func cleanRedditText() -> String {
        return self.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x200B;", with: "")
    }
}

struct RedditResponse: Codable { let data: RedditData }
struct RedditData: Codable { let children: [RedditChild] }
struct RedditChild: Codable { let data: RedditPostDTO }

struct RedditPostDTO: Codable {
    let id: String
    let title: String
    let author: String
    let selftext: String
    let url: String?
    let is_gallery: Bool?
    let gallery_data: GalleryData?
    let media_metadata: [String: MediaMetadata]?
}
struct GalleryData: Codable { let items: [GalleryItem]? }
struct GalleryItem: Codable { let media_id: String? }
struct MediaMetadata: Codable { let s: MediaS? }
struct MediaS: Codable { let u: String? }

struct CommentResponse: Codable { let data: CommentData }
struct CommentData: Codable { let children: [CommentChild] }
struct CommentChild: Codable {
    let kind: String
    let data: CommentDTO
}
struct CommentDTO: Codable {
    let id: String?
    let author: String?
    let body: String?
    let depth: Int?
    var replies: Replies?
    enum CodingKeys: String, CodingKey { case id, author, body, depth, replies }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        author = try? container.decodeIfPresent(String.self, forKey: .author)
        body = try? container.decodeIfPresent(String.self, forKey: .body)
        depth = try? container.decodeIfPresent(Int.self, forKey: .depth)
        do { replies = try container.decodeIfPresent(Replies.self, forKey: .replies) } catch { replies = nil }
    }
}
enum Replies: Codable {
    case string(String)
    case listing(CommentResponse)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { self = .string(str) }
        else if let listing = try? container.decode(CommentResponse.self) { self = .listing(listing) }
        else { self = .string("") }
    }
}
