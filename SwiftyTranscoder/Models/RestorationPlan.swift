import Foundation

enum RestorationMethod: String, Equatable, Sendable {
    case realESRGANX2Plus = "Real-ESRGAN x2plus"
}

struct RestorationPlan: Equatable, Sendable {
    let method: RestorationMethod
    let sourceWidth: Int
    let sourceHeight: Int
    let outputWidth: Int
    let outputHeight: Int
    let frameRate: String
    let colorRange: String
    let colorSpace: String
    let colorTransfer: String
    let colorPrimaries: String

    var scaleDescription: String {
        let scale = Double(outputWidth) / Double(sourceWidth)
        return String(format: "%.2f×", scale)
    }
}

enum RestorationEligibility: Equatable, Sendable {
    case eligible(RestorationPlan)
    case unavailable(String)
}

struct RestorationPlanner: Sendable {
    private let maximumWidth = 1_920
    private let maximumHeight = 1_080

    func plan(for inspection: MediaInspection) -> RestorationEligibility {
        guard inspection.videoStreams.count == 1, let video = inspection.videoStreams.first else {
            return .unavailable("AI restoration requires exactly one video stream.")
        }
        guard video.codecName?.lowercased() == "h264" || video.codecName?.lowercased() == "hevc" else {
            return .unavailable("AI restoration currently supports H.264 or HEVC video only.")
        }
        guard video.pixelFormat?.lowercased() == "yuv420p" else {
            return .unavailable("AI restoration currently supports 8-bit 4:2:0 SDR video only.")
        }
        guard let width = video.width, let height = video.height, width > 0, height > 0 else {
            return .unavailable("AI restoration requires known source dimensions.")
        }
        guard width < maximumWidth, height < maximumHeight else {
            return .unavailable("This source is already at or above the 1080p restoration limit.")
        }
        guard let frameRate = video.averageFrameRate, Self.isValidFrameRate(frameRate) else {
            return .unavailable("AI restoration requires a known, valid frame rate.")
        }
        guard video.colorRange?.lowercased() == "tv",
              let colorSpace = video.colorSpace?.lowercased(), ["bt709", "smpte170m"].contains(colorSpace),
              let colorTransfer = video.colorTransfer?.lowercased(), ["bt709", "smpte170m"].contains(colorTransfer),
              let colorPrimaries = video.colorPrimaries?.lowercased(), ["bt709", "smpte170m"].contains(colorPrimaries)
        else {
            return .unavailable("AI restoration requires identified limited-range SDR color metadata.")
        }

        let dimensions = outputDimensions(width: width, height: height)
        return .eligible(RestorationPlan(
            method: .realESRGANX2Plus,
            sourceWidth: width,
            sourceHeight: height,
            outputWidth: dimensions.width,
            outputHeight: dimensions.height,
            frameRate: frameRate,
            colorRange: "tv",
            colorSpace: colorSpace,
            colorTransfer: colorTransfer,
            colorPrimaries: colorPrimaries
        ))
    }

    private func outputDimensions(width: Int, height: Int) -> (width: Int, height: Int) {
        let scale = min(
            2.0,
            Double(maximumWidth) / Double(width),
            Double(maximumHeight) / Double(height)
        )
        let outputWidth = min(maximumWidth, Self.nearestEven(Double(width) * scale))
        let outputHeight = min(maximumHeight, Self.nearestEven(Double(height) * scale))
        return (outputWidth, outputHeight)
    }

    private static func nearestEven(_ value: Double) -> Int {
        Int((value / 2.0).rounded()) * 2
    }

    private static func isValidFrameRate(_ value: String) -> Bool {
        let parts = value.split(separator: "/", maxSplits: 1).compactMap { Double($0) }
        return parts.count == 2 && parts[0] > 0 && parts[1] > 0
    }
}
