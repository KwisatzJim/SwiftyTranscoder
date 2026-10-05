import CoreML
import Darwin
import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationPerformanceTests {
    // Opt in so ordinary regression runs do not perform a long hardware benchmark.
    @Test func profilesConsecutiveRestorationFrames() async throws {
        guard ProcessInfo.processInfo.environment["SWIFTY_RESTORATION_BENCHMARK"] == "1" else { return }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = root.appendingPathComponent("Alphas - s01e11 - Original Sin.m4v")
        let helpers = root.appendingPathComponent(".build/toolchain/stage/bin")
        let ffmpeg = helpers.appendingPathComponent("ffmpeg")
        let ffprobe = helpers.appendingPathComponent("ffprobe")
        let model = root.appendingPathComponent(
            ".build/restoration-evaluation/converter/weights/RealESRGAN_x2plus_522_fp16.mlpackage"
        )
        #expect(FileManager.default.fileExists(atPath: source.path))
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-Restoration-Benchmark-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let clock = { ProcessInfo.processInfo.systemUptime }
        // macOS reports ru_maxrss in bytes. This covers this test process only,
        // not FFmpeg children or allocations in external Core ML services.
        func reportPeakMemory(_ stage: String) {
            var usage = rusage()
            guard getrusage(RUSAGE_SELF, &usage) == 0 else { return }
            print(String(format: "Restoration benchmark process peak RSS after %@: %.1f MiB",
                         stage, Double(usage.ru_maxrss) / 1_048_576))
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS {
                print(String(format: "Restoration benchmark process live RSS after %@: %.1f MiB",
                             stage, Double(info.resident_size) / 1_048_576))
            }
        }
        reportPeakMemory("startup")
        let totalStarted = clock()
        var started = clock()
        let extraction = try RestorationFrameExtraction(
            sourceURL: source, workspaceURL: workspace, startSeconds: 600, frameCount: 120
        )
        let inputs = try await RestorationFrameExtractor(executableURL: ffmpeg).extract(extraction)
        let extractionSeconds = clock() - started
        reportPeakMemory("extraction")
        started = clock()
        let useGPU = ProcessInfo.processInfo.environment["SWIFTY_RESTORATION_COMPUTE"] == "gpu"
        print("Restoration benchmark compute units: \(useGPU ? "CPU and GPU" : "all")")
        let useSD = ProcessInfo.processInfo.environment["SWIFTY_RESTORATION_SD"] == "1"
        let processor: RestorationFrameProcessor
        if useSD {
            let sd = try CoreMLRestorationTileProcessor(
                modelURL: root.appendingPathComponent(".build/restoration-evaluation/sd-shape-experiment/RealESRGAN_x2plus_656x384_fp16.mlpackage"),
                computeUnits: useGPU ? .cpuAndGPU : .all,
                layout: .sdFrame
            )
            processor = RestorationFrameProcessor(sdFrameProcessor: sd)
        } else {
            let tiles = try CoreMLRestorationTileProcessor(
                modelURL: model, computeUnits: useGPU ? .cpuAndGPU : .all
            )
            processor = RestorationFrameProcessor(tileProcessor: tiles)
        }
        print("Restoration benchmark SD frame model: \(useSD)")
        let setupSeconds = clock() - started
        reportPeakMemory("model setup")
        let outputsDirectory = workspace.appendingPathComponent("restored-frames")
        try FileManager.default.createDirectory(at: outputsDirectory, withIntermediateDirectories: false)
        var outputs: [URL] = []
        var totals = RestorationFrameTimings()
        started = clock()
        for (index, input) in inputs.enumerated() {
            let output = outputsDirectory.appendingPathComponent(input.lastPathComponent)
            outputs.append(try await processor.process(
                sourceURL: input, outputURL: output, expectedWidth: 624, expectedHeight: 352
            ))
            let timings = await processor.latestTimings
            totals.decoding += timings.decoding
            totals.tensorPreparation += timings.tensorPreparation
            totals.inference += timings.inference
            totals.blending += timings.blending
            totals.output += timings.output
            if (index + 1).isMultiple(of: 30) {
                print(String(format: "Restoration benchmark: %d/120 frames, %.2fs", index + 1, clock() - started))
                reportPeakMemory("\(index + 1) restored frames")
            }
        }
        let restorationSeconds = clock() - started
        started = clock()
        let plan = RestorationPlan(
            method: .realESRGANX2Plus, sourceWidth: 624, sourceHeight: 352,
            outputWidth: 1248, outputHeight: 704, frameRate: "24000/1001",
            colorRange: "tv", colorSpace: "smpte170m", colorTransfer: "bt709",
            colorPrimaries: "smpte170m"
        )
        let assembly = try RestorationVideoAssembly(frameURLs: outputs, workspaceURL: workspace, plan: plan)
        let video = try await RestorationVideoAssembler(ffmpegURL: ffmpeg, ffprobeURL: ffprobe).assemble(assembly)
        let encodingSeconds = clock() - started
        reportPeakMemory("encoding and validation")
        #expect(outputs.count == 120)
        #expect(FileManager.default.fileExists(atPath: video.path))
        print(String(format:
            "Restoration benchmark totals: extraction %.3fs; setup %.3fs; restoration %.3fs; encoding and validation %.3fs; total %.3fs; seconds/frame %.4f",
            extractionSeconds, setupSeconds, restorationSeconds, encodingSeconds, clock() - totalStarted,
            restorationSeconds / Double(inputs.count)
        ))
        print(String(format:
            "Restoration frame totals: decode %.3fs; tensor %.3fs; model and validation %.3fs; blend %.3fs; output %.3fs",
            totals.decoding, totals.tensorPreparation, totals.inference, totals.blending, totals.output
        ))
    }
}
