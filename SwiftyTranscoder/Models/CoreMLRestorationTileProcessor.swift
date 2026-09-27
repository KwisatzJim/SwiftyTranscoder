import CoreML
import Foundation

struct RestorationModelFeature: Equatable, Sendable {
    let name: String
    let shape: [Int]
    let dataType: MLMultiArrayDataType
}

struct RestorationModelContract: Equatable, Sendable {
    static let expectedInputShape = [1, 3, 522, 522]
    static let expectedOutputShape = [1, 3, 1044, 1044]

    let input: RestorationModelFeature
    let output: RestorationModelFeature

    init(input: RestorationModelFeature, output: RestorationModelFeature) throws {
        guard input.shape == Self.expectedInputShape else {
            throw CoreMLRestorationError.invalidInputShape(actual: input.shape)
        }
        guard output.shape == Self.expectedOutputShape else {
            throw CoreMLRestorationError.invalidOutputShape(actual: output.shape)
        }
        guard input.dataType == .float16, output.dataType == .float16 else {
            throw CoreMLRestorationError.invalidDataType
        }
        self.input = input
        self.output = output
    }

    static func inspect(_ description: MLModelDescription) throws -> Self {
        let inputs = try multiArrayFeatures(in: description.inputDescriptionsByName)
        let outputs = try multiArrayFeatures(in: description.outputDescriptionsByName)
        guard inputs.count == 1, outputs.count == 1 else {
            throw CoreMLRestorationError.invalidFeatureCount(
                inputs: inputs.count,
                outputs: outputs.count
            )
        }
        return try Self(input: inputs[0], output: outputs[0])
    }

    private static func multiArrayFeatures(
        in descriptions: [String: MLFeatureDescription]
    ) throws -> [RestorationModelFeature] {
        try descriptions.map { name, description in
            guard description.type == .multiArray,
                  let constraint = description.multiArrayConstraint else {
                throw CoreMLRestorationError.featureIsNotMultiArray(name: name)
            }
            return RestorationModelFeature(
                name: name,
                shape: constraint.shape.map(\.intValue),
                dataType: constraint.dataType
            )
        }
    }
}

final class RestorationTileTensor: @unchecked Sendable {
    let values: MLMultiArray

    init(values: MLMultiArray) {
        self.values = values
    }
}

protocol RestorationTileProcessing: Sendable {
    func process(_ input: RestorationTileTensor) async throws -> RestorationTileTensor
    func cancel() async
}

actor CoreMLRestorationTileProcessor: RestorationTileProcessing {
    let contract: RestorationModelContract

    private let model: MLModel
    private var cancellationRequested = false

    init(modelURL: URL, computeUnits: MLComputeUnits = .all) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path(percentEncoded: false)) else {
            throw CoreMLRestorationError.modelMissing
        }

        let compiledURL: URL
        do {
            compiledURL = modelURL.pathExtension == "mlmodelc"
                ? modelURL
                : try MLModel.compileModel(at: modelURL)
        } catch {
            throw CoreMLRestorationError.couldNotCompile(reason: error.localizedDescription)
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        do {
            model = try MLModel(contentsOf: compiledURL, configuration: configuration)
            contract = try RestorationModelContract.inspect(model.modelDescription)
        } catch let error as CoreMLRestorationError {
            throw error
        } catch {
            throw CoreMLRestorationError.couldNotLoad(reason: error.localizedDescription)
        }
    }

    func process(_ input: RestorationTileTensor) throws -> RestorationTileTensor {
        cancellationRequested = false
        try checkCancellation()
        guard input.values.shape.map(\.intValue) == RestorationModelContract.expectedInputShape,
              input.values.dataType == contract.input.dataType else {
            throw CoreMLRestorationError.invalidInputTensor
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            contract.input.name: MLFeatureValue(multiArray: input.values),
        ])
        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: provider)
        } catch {
            if cancellationRequested || Task.isCancelled { throw CancellationError() }
            throw CoreMLRestorationError.predictionFailed(reason: error.localizedDescription)
        }

        try checkCancellation()
        guard let output = prediction.featureValue(for: contract.output.name)?.multiArrayValue,
              output.shape.map(\.intValue) == contract.output.shape,
              output.dataType == contract.output.dataType else {
            throw CoreMLRestorationError.invalidOutputTensor
        }
        guard Self.containsOnlyFiniteValues(output) else {
            throw CoreMLRestorationError.nonFiniteOutput
        }
        return RestorationTileTensor(values: output)
    }

    func cancel() {
        cancellationRequested = true
    }

    private func checkCancellation() throws {
        if cancellationRequested || Task.isCancelled {
            throw CancellationError()
        }
    }

    private static func containsOnlyFiniteValues(_ values: MLMultiArray) -> Bool {
        switch values.dataType {
        case .float16:
            let pointer = values.dataPointer.bindMemory(to: Float16.self, capacity: values.count)
            return (0..<values.count).allSatisfy { pointer[$0].isFinite }
        case .float32:
            let pointer = values.dataPointer.bindMemory(to: Float.self, capacity: values.count)
            return (0..<values.count).allSatisfy { pointer[$0].isFinite }
        case .double:
            let pointer = values.dataPointer.bindMemory(to: Double.self, capacity: values.count)
            return (0..<values.count).allSatisfy { pointer[$0].isFinite }
        default:
            return false
        }
    }
}

enum CoreMLRestorationError: LocalizedError, Equatable {
    case modelMissing
    case couldNotCompile(reason: String)
    case couldNotLoad(reason: String)
    case invalidFeatureCount(inputs: Int, outputs: Int)
    case featureIsNotMultiArray(name: String)
    case invalidInputShape(actual: [Int])
    case invalidOutputShape(actual: [Int])
    case invalidDataType
    case invalidInputTensor
    case predictionFailed(reason: String)
    case invalidOutputTensor
    case nonFiniteOutput

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            "The selected restoration model is unavailable."
        case .couldNotCompile(let reason):
            "The restoration model could not be compiled: \(reason)"
        case .couldNotLoad(let reason):
            "The restoration model could not be loaded: \(reason)"
        case .invalidFeatureCount(let inputs, let outputs):
            "The restoration model has \(inputs) inputs and \(outputs) outputs; exactly one of each is required."
        case .featureIsNotMultiArray(let name):
            "The restoration model feature \(name) is not a numeric tensor."
        case .invalidInputShape(let actual):
            "The restoration model input shape \(actual) does not match [1, 3, 522, 522]."
        case .invalidOutputShape(let actual):
            "The restoration model output shape \(actual) does not match [1, 3, 1044, 1044]."
        case .invalidDataType:
            "The restoration model must use Float16 input and output tensors."
        case .invalidInputTensor:
            "The restoration tile does not match the approved model input contract."
        case .predictionFailed(let reason):
            "Core ML restoration failed: \(reason)"
        case .invalidOutputTensor:
            "Core ML returned an output that does not match the approved model contract."
        case .nonFiniteOutput:
            "Core ML returned invalid non-finite pixel values."
        }
    }
}
