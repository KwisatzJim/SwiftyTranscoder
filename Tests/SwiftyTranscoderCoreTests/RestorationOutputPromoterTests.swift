import Foundation
import Testing
@testable import SwiftyTranscoderCore

struct RestorationOutputPromoterTests {
    @Test func stagesBesideDestinationThenPromotesWithoutOverwriting() throws {
        let fixture = try PromotionFixture()
        defer { fixture.remove() }
        let promoter = RestorationOutputPromoter(availableCapacity: { _ in Int64.max })

        let partial = try promoter.stage(fixture.request)

        #expect(partial == fixture.request.partialOutputURL)
        #expect(FileManager.default.fileExists(atPath: partial.path))
        #expect(FileManager.default.fileExists(atPath: fixture.request.validatedOutputURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.request.finalOutputURL.path))

        let final = try promoter.promote(fixture.request)

        #expect(final == fixture.request.finalOutputURL)
        #expect(try Data(contentsOf: final) == fixture.contents)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test func destinationAppearingAfterStagingIsPreserved() throws {
        let fixture = try PromotionFixture()
        defer { fixture.remove() }
        let promoter = RestorationOutputPromoter(availableCapacity: { _ in Int64.max })
        _ = try promoter.stage(fixture.request)
        try Data("existing destination".utf8).write(to: fixture.request.finalOutputURL)

        #expect(throws: RestorationOutputPromoterError.outputAppeared(
            file: fixture.request.finalOutputURL.lastPathComponent
        )) {
            try promoter.promote(fixture.request)
        }
        #expect(try String(contentsOf: fixture.request.finalOutputURL, encoding: .utf8)
            == "existing destination")
        #expect(FileManager.default.fileExists(atPath: fixture.request.partialOutputURL.path))
    }

    @Test func refusesAnyWorkspaceFileOtherThanValidatedAudioOutput() throws {
        let fixture = try PromotionFixture()
        defer { fixture.remove() }

        #expect(throws: RestorationOutputPromoterError.unapprovedValidatedOutput) {
            try RestorationOutputPromotion(
                validatedOutputURL: fixture.workspaceURL.appendingPathComponent(
                    "restored-silent.partial.mp4"
                ),
                workspaceURL: fixture.workspaceURL,
                sourceURL: fixture.sourceURL,
                finalOutputURL: fixture.finalURL
            )
        }
    }

    @Test func refusesToStartDestinationCopyWithoutEnoughFreeSpace() throws {
        let fixture = try PromotionFixture()
        defer { fixture.remove() }
        let promoter = RestorationOutputPromoter(availableCapacity: { _ in 1 })

        #expect(throws: RestorationOutputPromoterError.insufficientDestinationSpace(
            available: 1,
            required: Int64(fixture.contents.count)
                + RestorationOutputPromoter.destinationReserveBytes
        )) {
            try promoter.stage(fixture.request)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.request.partialOutputURL.path))
    }
}

private struct PromotionFixture {
    let rootURL: URL
    let workspaceURL: URL
    let sourceURL: URL
    let finalURL: URL
    let contents = Data("validated restoration".utf8)
    let request: RestorationOutputPromotion

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwiftyTranscoder-Restoration-Promotion-\(UUID().uuidString)"
        )
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        let destinationURL = rootURL.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        sourceURL = rootURL.appendingPathComponent("source.m4v")
        finalURL = destinationURL.appendingPathComponent("restored.mp4")
        try Data("source".utf8).write(to: sourceURL)
        let validatedURL = workspaceURL.appendingPathComponent("restored-audio.partial.mp4")
        try contents.write(to: validatedURL)
        request = try RestorationOutputPromotion(
            validatedOutputURL: validatedURL,
            workspaceURL: workspaceURL,
            sourceURL: sourceURL,
            finalOutputURL: finalURL
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
