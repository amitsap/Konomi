import Foundation
import SwiftData

enum CoverImageService {
    private static let memoryCache = NSCache<NSString, NSData>()

    static func fetchImageData(from urlString: String) async throws -> Data {
        let cacheKey = urlString as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return Data(referencing: cached)
        }

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        memoryCache.setObject(data as NSData, forKey: cacheKey)
        return data
    }

    @MainActor
    static func cacheIfNeeded(for item: MediaItem) async {
        guard item.coverImageData == nil,
              let urlString = item.coverURLString else { return }
        do {
            item.coverImageData = try await fetchImageData(from: urlString)
        } catch {
            // Silently fail — will retry next time
        }
    }

    @MainActor
    static func cacheIfNeeded(for recommendation: Recommendation) async {
        guard recommendation.coverImageData == nil,
              let urlString = recommendation.coverURLString else { return }
        do {
            recommendation.coverImageData = try await fetchImageData(from: urlString)
        } catch {
            // Silently fail
        }
    }
}
