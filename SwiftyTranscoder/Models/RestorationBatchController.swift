import Combine
import Foundation

struct ReviewedRestorationJob: Sendable {
    let sourceURL: URL
    let inspection: MediaInspection
    let outputURL: URL
    let plan: RestorationPlan
    let gainEnabled: Bool
    let aacStereoEnabled: Bool
    let subtitleSelection: SubtitleSelection
}

@MainActor
final class RestorationBatchController: ObservableObject {
    @Published private(set) var snapshot = RestorationBatchSnapshot()
    @Published private(set) var estimatedRemainingSeconds: Double?
    private let coordinator: RestorationBatchCoordinator
    private let temporaryDirectory: URL
    private var runTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    init(
        coordinator: RestorationBatchCoordinator = RestorationBatchCoordinator(),
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.coordinator = coordinator
        self.temporaryDirectory = temporaryDirectory
    }

    var isActive: Bool { snapshot.phase == .running || snapshot.phase == .cancelling }
    var hasStarted: Bool { snapshot.phase != .idle }

    func start(_ jobs: [ReviewedRestorationJob]) {
        guard !isActive else { return }
        do {
            let requests = try jobs.map { job in
                guard case .eligible(let currentPlan) = RestorationPlanner().plan(for: job.inspection, method: job.plan.method),
                      currentPlan == job.plan else {
                    throw RestorationBatchControllerError.ineligiblePlan(job.sourceURL.lastPathComponent)
                }
                return try FullVideoRestorationController.makeRequest(
                    sourceURL: job.sourceURL, inspection: job.inspection, outputURL: job.outputURL,
                    plan: job.plan, gainEnabled: job.gainEnabled, aacStereoEnabled: job.aacStereoEnabled,
                    subtitleSelection: job.subtitleSelection, temporaryDirectory: temporaryDirectory
                )
            }
            snapshot = RestorationBatchSnapshot(phase: .running, items: jobs.map { _ in .queued })
            let coordinator = self.coordinator
            monitorTask = Task { [weak self] in
                var estimate = RestorationTimeEstimate()
                var estimatedIndex: Int?
                while !Task.isCancelled {
                    let value = await coordinator.snapshot
                    guard let self, !Task.isCancelled else { return }
                    if value.phase == .running || value.phase == .cancelling {
                        var value = value
                        if self.snapshot.phase == .cancelling, value.phase == .running { value.phase = .cancelling }
                        if estimatedIndex != value.activeIndex {
                            estimate = RestorationTimeEstimate()
                            estimatedIndex = value.activeIndex
                        }
                        if let index = value.activeIndex, value.items.indices.contains(index),
                           case .running = value.items[index], value.phase == .running {
                            self.estimatedRemainingSeconds = estimate.update(
                                progress: value.activeProgress, now: ProcessInfo.processInfo.systemUptime
                            )
                        } else {
                            self.estimatedRemainingSeconds = nil
                        }
                        self.snapshot = value
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            runTask = Task { [weak self] in
                let result = await coordinator.run(requests)
                guard let self else { return }
                self.monitorTask?.cancel()
                self.monitorTask = nil
                self.snapshot = result
                self.estimatedRemainingSeconds = nil
                self.runTask = nil
            }
        } catch {
            snapshot = RestorationBatchSnapshot(
                phase: .rejected(error.localizedDescription), items: jobs.map { _ in .notRun }
            )
        }
    }

    func cancel() {
        guard isActive else { return }
        snapshot.phase = .cancelling
        runTask?.cancel()
        Task { await coordinator.cancel() }
    }

    func reset() {
        guard !isActive else { return }
        snapshot = RestorationBatchSnapshot()
        estimatedRemainingSeconds = nil
    }
}

enum RestorationBatchControllerError: LocalizedError {
    case ineligiblePlan(String)
    var errorDescription: String? {
        switch self {
        case .ineligiblePlan(let name): "The reviewed restoration plan for \(name) is no longer eligible."
        }
    }
}
