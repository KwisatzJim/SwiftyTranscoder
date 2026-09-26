import Foundation

struct CompatibilityAudioSettings: Sendable {
    let channels: Int
    let acceptedLayouts: Set<String>
    let bitRate: String
    let description: String

    init?(source: MediaStream) {
        switch (source.channels, source.channelLayout) {
        case (1, "mono"):
            channels = 1
            acceptedLayouts = ["mono"]
            bitRate = "96000"
            description = "mono at 96 kb/s"
        case (2, "stereo"):
            channels = 2
            acceptedLayouts = ["stereo"]
            bitRate = "192000"
            description = "stereo at 192 kb/s"
        case (6, "5.1"), (6, "5.1(side)"):
            channels = 6
            acceptedLayouts = ["5.1", "5.1(side)"]
            bitRate = "224000"
            description = "5.1 at 224 kb/s"
        default:
            return nil
        }
    }
}
