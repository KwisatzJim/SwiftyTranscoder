@testable import SwiftyTranscoderCore

func mediaStream(
    index: Int = 0,
    codecName: String? = nil,
    codecType: String,
    width: Int? = nil,
    height: Int? = nil,
    pixelFormat: String? = nil,
    colorRange: String? = nil,
    colorSpace: String? = nil,
    colorTransfer: String? = nil,
    colorPrimaries: String? = nil,
    averageFrameRate: String? = nil,
    numberOfFrames: String? = nil,
    channels: Int? = nil,
    channelLayout: String? = nil,
    sampleRate: String? = nil,
    tags: [String: String]? = nil,
    forced: Int? = nil,
    hearingImpaired: Int? = nil,
    profile: String? = nil
) -> MediaStream {
    MediaStream(
        index: index, codecName: codecName, codecLongName: nil, codecTagString: nil,
        profile: profile, codecType: codecType, width: width, height: height,
        pixelFormat: pixelFormat, colorRange: colorRange, colorSpace: colorSpace,
        colorTransfer: colorTransfer, colorPrimaries: colorPrimaries,
        averageFrameRate: averageFrameRate, numberOfFrames: numberOfFrames, channels: channels,
        channelLayout: channelLayout, sampleRate: sampleRate, bitRate: nil, tags: tags,
        disposition: StreamDisposition(
            isDefault: nil, forced: forced, hearingImpaired: hearingImpaired, attachedPicture: nil
        )
    )
}
