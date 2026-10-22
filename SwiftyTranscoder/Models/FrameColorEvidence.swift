import Foundation

struct ColorSideData: Decodable, Sendable {
    let type: String
    enum CodingKeys: String, CodingKey { case type = "side_data_type" }

    var indicatesHDR: Bool {
        let value = type.lowercased()
        return ["mastering display", "content light level", "dovi", "dolby vision", "hdr dynamic"].contains { value.contains($0) }
    }
}

struct FrameColorEvidence: Decodable, Sendable {
    struct Frame: Decodable, Sendable {
        let colorRange: String?
        let colorSpace: String?
        let colorTransfer: String?
        let colorPrimaries: String?
        let sideData: [ColorSideData]?
        enum CodingKeys: String, CodingKey {
            case colorRange = "color_range", colorSpace = "color_space"
            case colorTransfer = "color_transfer", colorPrimaries = "color_primaries"
            case sideData = "side_data_list"
        }
    }
    let frames: [Frame]

    static func known(_ value: String?) -> String? {
        guard let value = value?.lowercased(), !["", "unknown", "unspecified", "reserved"].contains(value) else { return nil }
        return value
    }

    func applying(to original: MediaStream, sampleDescription: String = "near the start") -> MediaStream {
        var stream = original
        guard !frames.isEmpty else {
            stream.colorInspectionNote = "Deeper color check decoded no frames; no color assumptions were made."
            return stream
        }
        let hdrData = (original.sideDataList ?? []) + frames.flatMap { $0.sideData ?? [] }.filter(\.indicatesHDR)
        if hdrData.contains(where: \.indicatesHDR) {
            stream.sideDataList = hdrData
            stream.colorInspectionNote = "Explicit HDR side metadata found in the stream or sampled frames; SDR must not be assumed."
            return stream
        }
        let transfers = frames.compactMap { Self.known($0.colorTransfer) } + [Self.known(original.colorTransfer)].compactMap { $0 }
        if let hdrTransfer = transfers.first(where: { ["smpte2084", "arib-std-b67"].contains($0) }) {
            stream.colorTransfer = hdrTransfer
            stream.colorInspectionNote = "Explicit HDR transfer tag found in stream/frame metadata; SDR must not be assumed."
            return stream
        }
        let fields: [WritableKeyPath<MediaStream, String?>] = [\.colorRange, \.colorSpace, \.colorTransfer, \.colorPrimaries]
        let frameFields: [KeyPath<Frame, String?>] = [\.colorRange, \.colorSpace, \.colorTransfer, \.colorPrimaries]
        var recovered = 0
        for (field, frameField) in zip(fields, frameFields) {
            let values = Set(frames.compactMap { Self.known($0[keyPath: frameField]) })
            let existing = Self.known(original[keyPath: field])
            if values.count > 1 || (existing != nil && !values.isEmpty && !values.contains(existing!)) {
                // Conflicting evidence must not unlock automatic SDR handling.
                stream = original
                stream.colorTransfer = "conflicting"
                stream.colorInspectionNote = "Conflicting stream/frame color tags found; automatic color identification is unavailable. Review the source."
                return stream
            }
            // Require every sampled frame to carry the same explicit value.
            if existing == nil, values.count == 1,
               frames.allSatisfy({ Self.known($0[keyPath: frameField]) != nil }) {
                stream[keyPath: field] = values.first
                recovered += 1
            }
        }
        stream.colorInspectionNote = recovered > 0
            ? "Recovered \(recovered) missing color tag(s) from \(frames.count) decoded frames \(sampleDescription). This is a metadata sample, not a full-video color analysis."
            : "Checked \(frames.count) decoded frames \(sampleDescription); no additional consistent color tags found. Missing metadata remains unknown."
        return stream
    }
}
