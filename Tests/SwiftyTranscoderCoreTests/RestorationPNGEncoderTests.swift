import AppKit
import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationPNGEncoderTests {
    @Test(arguments: [1, 7, 257, 4097])
    func preservesEveryPixelAndColorDeclaration(width: Int) throws {
        let height = 5
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var state: UInt64 = 113
        for index in bytes.indices where index % 4 != 3 {
            state = state &* 6364136223846793005 &+ 1
            bytes[index] = UInt8(truncatingIfNeeded: state >> 32)
        }
        let png = try RestorationPNGEncoder.encode(bytes, width: width, height: height)
        #expect(Int64(png.count) <= (try #require(RestorationPNGEncoder.maximumFileBytes(width: width, height: height))))
        let decoded = try #require(NSBitmapImageRep(data: png))
        #expect(decoded.pixelsWide == width && decoded.pixelsHigh == height)
        let original = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        ))
        let destination = try #require(original.bitmapData)
        bytes.withUnsafeBufferPointer { destination.update(from: $0.baseAddress!, count: bytes.count) }
        let oldPNG = try #require(original.representation(using: .png, properties: [:]))
        let reference = try #require(NSBitmapImageRep(data: oldPNG))
        #expect(decoded.colorSpace == reference.colorSpace)
        for y in 0..<height {
            for x in 0..<width {
                var pixel = [Int](repeating: 0, count: 4)
                var oldPixel = pixel
                decoded.getPixel(&pixel, atX: x, y: y)
                reference.getPixel(&oldPixel, atX: x, y: y)
                let offset = (y * width + x) * 4
                #expect(pixel == bytes[offset..<(offset + 4)].map(Int.init))
                #expect(pixel == oldPixel)
            }
        }
    }

    @Test func rejectsInvalidDimensionsAndByteCounts() {
        #expect(throws: RestorationFrameProcessorError.invalidDimensions) {
            try RestorationPNGEncoder.encode([], width: 1, height: 1)
        }
        #expect(RestorationPNGEncoder.maximumFileBytes(width: 0, height: 1) == nil)
        #expect(RestorationPNGEncoder.maximumFileBytes(width: .max, height: 2) == nil)
        #expect(RestorationPNGEncoder.maximumFileBytes(width: 2, height: .max) == nil)
    }
}
