import Foundation
import zlib

/// Lossless, speed-first PNGs for temporary restoration frames, not archival images.
enum RestorationPNGEncoder {
    // Signature, IHDR, sRGB, one IDAT header/CRC, and IEND.
    private static let containerBytes: Int64 = 70

    static func maximumFileBytes(width: Int, height: Int) -> Int64? {
        guard let size = scanlineSize(width: width, height: height) else { return nil }
        return Int64(compressBound(uLong(size))) + containerBytes
    }

    static func encode(_ rgba: [UInt8], width: Int, height: Int) throws -> Data {
        guard let size = scanlineSize(width: width, height: height),
              rgba.count == size - height else {
            throw RestorationFrameProcessorError.invalidDimensions
        }
        let rowBytes = width * 4
        var filtered = [UInt8](repeating: 0, count: size)
        // Temporary frames are short-lived. Store scanlines without PNG filtering
        // or DEFLATE compression to avoid spending CPU time minimizing their size.
        filtered.withUnsafeMutableBufferPointer { destination in
            rgba.withUnsafeBufferPointer { source in
                for y in 0..<height {
                    destination.baseAddress!.advanced(by: y * (rowBytes + 1) + 1)
                        .update(from: source.baseAddress!.advanced(by: y * rowBytes), count: rowBytes)
                }
            }
        }
        var compressedSize = compressBound(uLong(size))
        var compressed = Data(count: Int(compressedSize))
        let status = compressed.withUnsafeMutableBytes { destination in
            filtered.withUnsafeBufferPointer { source in
                compress2(destination.bindMemory(to: UInt8.self).baseAddress, &compressedSize,
                          source.baseAddress, uLong(size), Z_NO_COMPRESSION)
            }
        }
        guard status == Z_OK else { throw RestorationFrameProcessorError.couldNotEncode }
        compressed.count = Int(compressedSize)
        var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        var header = Data()
        appendUInt32(UInt32(width), to: &header)
        appendUInt32(UInt32(height), to: &header)
        header.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit RGBA, no interlace.
        appendChunk("IHDR", data: header, to: &png)
        // Match the sRGB/perceptual declaration from the existing AppKit encoder.
        appendChunk("sRGB", data: Data([0]), to: &png)
        appendChunk("IDAT", data: compressed, to: &png)
        appendChunk("IEND", data: Data(), to: &png)
        return png
    }

    private static func scanlineSize(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0, width <= Int(Int32.max), height <= Int(Int32.max) else { return nil }
        let row = width.multipliedReportingOverflow(by: 4)
        guard !row.overflow else { return nil }
        let stride = row.partialValue.addingReportingOverflow(1)
        guard !stride.overflow else { return nil }
        let size = stride.partialValue.multipliedReportingOverflow(by: height)
        // Keep compressed data and its single chunk within PNG's signed 31-bit limit.
        guard !size.overflow, size.partialValue < Int(Int32.max),
              compressBound(uLong(size.partialValue)) <= uLong(Int32.max) else { return nil }
        return size.partialValue
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func appendChunk(_ name: String, data: Data, to png: inout Data) {
        let type = Data(name.utf8)
        appendUInt32(UInt32(data.count), to: &png)
        png.append(type)
        png.append(data)
        var checksum = type.withUnsafeBytes {
            crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(type.count))
        }
        if !data.isEmpty {
            checksum = data.withUnsafeBytes {
                crc32(checksum, $0.bindMemory(to: UInt8.self).baseAddress, uInt(data.count))
            }
        }
        appendUInt32(UInt32(checksum), to: &png)
    }
}
