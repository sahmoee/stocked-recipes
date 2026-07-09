// RemoteRecipeFeed.swift — DROP-IN REPLACEMENT for the Stocked app.
// Same as before, but the refresh interval is no longer hardcoded to 6 hours: it reads
// feed_config.json (published next to recipes.json by the Recipe Manager's "Set Interval")
// and uses its refreshHours value. Falls back to 6 hours if the config is absent.
//
// Apply this to the Stocked app repo (replaces the existing RemoteRecipeFeed.swift).

import Foundation

enum RemoteRecipeFeed {

    static let feedURLString = "https://raw.githubusercontent.com/sahmoee/stocked-recipes/refs/heads/main/recipes.json"

    private static let cacheKey = "remoteRecipeFeed_v1"
    private static let defaultHours: Double = 6

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }()

    /// Reads refreshHours from feed_config.json sitting next to recipes.json.
    private static func refreshTTL() async -> TimeInterval {
        let cfgURLString = feedURLString.replacingOccurrences(of: RECIPES_FEED_FILENAME, with: "feed_config.json")
        guard cfgURLString != feedURLString, let url = URL(string: cfgURLString),
              let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hours = (obj["refreshHours"] as? NSNumber)?.doubleValue else {
            return defaultHours * 3600
        }
        return max(1, hours) * 3600
    }

    private static let RECIPES_FEED_FILENAME = "recipes.json"

    static func fetch() async -> [OnlineRecipe] {
        let trimmed = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return [] }

        if let cached = await APIResponseCache.shared.value(for: cacheKey, as: [OnlineRecipe].self) {
            return cached
        }
        guard let (data, resp) = try? await session.data(from: url),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let recipes = try? JSONDecoder().decode([OnlineRecipe].self, from: data) else {
            return []
        }
        let cleaned = recipes.filter {
            !$0.title.trimmingCharacters(in: .whitespaces).isEmpty &&
            !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let ttl = await refreshTTL()
        await APIResponseCache.shared.store(cleaned, for: cacheKey, ttl: ttl)
        return cleaned
    }
}
