#if os(iOS)
import BackgroundTasks
import Foundation

/// Registers and schedules Acai's `BGAppRefreshTask`, handing each wake to
/// `ScheduledRefreshCoordinator.refreshNext()` — one GitHub-backed codebase per invocation, sized
/// for iOS's few-seconds-to-tens-of-seconds background execution budget rather than sweeping every
/// codebase in a single wake (`ScheduledRefreshCoordinator.startPeriodicSweep` is macOS's
/// equivalent, which can afford exactly that). `register()` must run before the app can be
/// suspended — see `AcaiRootScene.init()`, which calls it during app launch.
///
/// The identifier must be declared under `BGTaskSchedulerPermittedIdentifiers` in `Info.plist`
/// (`App/iOS/Info.plist`) — `BGTaskScheduler` rejects `register`/`submit` for any identifier not
/// listed there.
@MainActor
final class ScheduledRefreshTaskRunner {
    static let taskIdentifier = "de.kraftsoftware.Acai.refresh"
    private static let steadyStateInterval: TimeInterval = 15 * 60
    /// How soon to re-request a wake when `refreshNext()` reports more codebases remain — short
    /// enough that a monorepo with several tracked codebases finishes its round-robin in a handful
    /// of wakes rather than one per `steadyStateInterval`.
    private static let continuationInterval: TimeInterval = 5

    private let coordinator: ScheduledRefreshCoordinator

    init(coordinator: ScheduledRefreshCoordinator) {
        self.coordinator = coordinator
    }

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(refreshTask)
        }
    }

    func scheduleNext(interval: TimeInterval = steadyStateInterval) {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Exactly one place calls `setTaskCompleted` — from inside `work`, after it returns either
    /// because it finished or because `expirationHandler` cancelled it. `expirationHandler` only
    /// cancels; it never itself completes the task, which would otherwise race a `work` that
    /// finishes at the same moment (`BGTaskScheduler` treats a second `setTaskCompleted` call as a
    /// programmer error).
    private func handle(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            let hasMore = await coordinator.refreshNext()
            guard !Task.isCancelled else {
                task.setTaskCompleted(success: false)
                return
            }
            scheduleNext(interval: hasMore ? Self.continuationInterval : Self.steadyStateInterval)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
#endif
