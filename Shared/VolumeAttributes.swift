import ActivityKit
import Foundation

struct VolumeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var volume: Float
        var isMuted: Bool
    }

    var name: String = "Volume"
}
