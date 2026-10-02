import CoreML
import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct CoreMLRestorationTileProcessorTests {
    @Test func acceptsOnlyExplicitSDFrameContract() throws {
        _ = try RestorationModelContract(
            input: feature("input", shape: [1, 3, 384, 656]),
            output: feature("output", shape: [1, 3, 768, 1312]), layout: .sdFrame
        )
        #expect(throws: CoreMLRestorationError.invalidInputShape(actual: [1, 3, 384, 656])) {
            try RestorationModelContract(
                input: feature("input", shape: [1, 3, 384, 656]),
                output: feature("output", shape: [1, 3, 768, 1312])
            )
        }
    }
    @Test func acceptsExactPinnedModelContract() throws {
        let contract = try RestorationModelContract(
            input: feature("input", shape: [1, 3, 522, 522]),
            output: feature("output", shape: [1, 3, 1044, 1044])
        )

        #expect(contract.input.name == "input")
        #expect(contract.output.name == "output")
    }

    @Test func rejectsUnexpectedInputShape() {
        #expect(throws: CoreMLRestorationError.invalidInputShape(actual: [1, 3, 256, 256])) {
            try RestorationModelContract(
                input: feature("input", shape: [1, 3, 256, 256]),
                output: feature("output", shape: [1, 3, 1044, 1044])
            )
        }
    }

    @Test func rejectsUnexpectedOutputShape() {
        #expect(throws: CoreMLRestorationError.invalidOutputShape(actual: [1, 3, 522, 522])) {
            try RestorationModelContract(
                input: feature("input", shape: [1, 3, 522, 522]),
                output: feature("output", shape: [1, 3, 522, 522])
            )
        }
    }

    @Test func loadsResearchModelAndRunsFiniteZeroTileWhenAvailable() async throws {
        let modelURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/restoration-evaluation/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage")
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return }

        let processor = try CoreMLRestorationTileProcessor(modelURL: modelURL)
        let input = try MLMultiArray(
            shape: RestorationModelContract.expectedInputShape.map(NSNumber.init),
            dataType: .float16
        )
        input.dataPointer.initializeMemory(as: Float16.self, repeating: 0, count: input.count)
        let output = try await processor.process(RestorationTileTensor(values: input))

        #expect(output.values.shape.map(\.intValue) == RestorationModelContract.expectedOutputShape)
        #expect(output.values.dataType == .float16)
    }

    private func feature(_ name: String, shape: [Int]) -> RestorationModelFeature {
        RestorationModelFeature(name: name, shape: shape, dataType: .float16)
    }
}
