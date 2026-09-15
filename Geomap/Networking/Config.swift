import Foundation

enum Config {
    static var apiBaseURL: URL {
        #if DEBUG
        URL(string: "http://localhost:8080")!
        #else
        URL(string: "https://api.geomap.app")!
        #endif
    }
}
