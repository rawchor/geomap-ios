import Foundation

enum Config {
    static var apiBaseURL: URL {
        #if DEBUG
        // Set via GEOMAP_API_BASE_URL in Config/*.xcconfig so a real device can
        // point at the Mac running the backend instead of its own localhost.
        if let value = Bundle.main.object(forInfoDictionaryKey: "GeomapAPIBaseURL") as? String,
           !value.isEmpty,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "http://localhost:8080")!
        #else
        URL(string: "https://api.geomap.app")!
        #endif
    }

    /// Derived from `apiBaseURL` by swapping the scheme (http→ws, https→wss)
    /// rather than hardcoded separately, so the two can never drift apart.
    static var wsBaseURL: URL {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        return components.url!
    }
}
