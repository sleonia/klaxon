import Foundation

/// Thin, wake-safe one-shot timer. The owner recomputes the plan and calls
/// `schedule` again after every state change; intervals are always derived
/// from the target `Date` at arm time, never carried over (plan.md §3b).
@MainActor
public final class MeetingScheduler {

    private var timer: DispatchSourceTimer?

    public init() {}

    public func schedule(fireAt date: Date, handler: @escaping @MainActor () -> Void) {
        cancel()
        let interval = max(0, date.timeIntervalSince(Date()))
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, leeway: .seconds(1))
        timer.setEventHandler {
            // The timer runs on the main queue.
            MainActor.assumeIsolated { handler() }
        }
        timer.resume()
        self.timer = timer
    }

    public func cancel() {
        timer?.cancel()
        timer = nil
    }
}
