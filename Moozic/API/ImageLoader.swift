import UIKit

/// Loads cover art through the authenticated API client (AsyncImage can't send headers),
/// with an in-memory cache and de-duplication of concurrent requests.
actor ImageLoader {
    private let api: APIClient
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Error>] = [:]
    /// Paths that answered 404, so artwork-less albums aren't re-requested on every scroll.
    private var missing = Set<String>()

    init(api: APIClient) {
        self.api = api
        cache.countLimit = 300
    }

    nonisolated func cached(_ path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    func image(for path: String) async -> UIImage? {
        if let image = cache.object(forKey: path as NSString) { return image }
        if missing.contains(path) { return nil }
        if let task = inFlight[path] { return try? await task.value }

        let api = self.api
        let task = Task<UIImage?, Error> {
            guard let data = try await api.data(path) else { return nil }
            return UIImage(data: data)?.preparingForDisplay()
        }
        inFlight[path] = task
        defer { inFlight[path] = nil }
        do {
            if let image = try await task.value {
                cache.setObject(image, forKey: path as NSString)
                return image
            }
            missing.insert(path)
            return nil
        } catch {
            return nil  // transient: try again next time
        }
    }
}
