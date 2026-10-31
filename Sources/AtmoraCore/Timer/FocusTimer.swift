import Foundation
import Observation

public enum FocusTimerPhase: String, Codable, Sendable, Equatable {
    case idle
    case running
    case paused
    case finished
}

/// Pure, wall-clock based focus timer state. It deliberately does not own a
/// `Timer`: the app ticks it while running, and tests advance an injected
/// clock. Because remaining time is derived from an end date, a delayed or
/// coalesced UI tick can never make the countdown drift.
@MainActor
@Observable
public final class FocusTimer {
    public private(set) var phase: FocusTimerPhase = .idle
    public private(set) var duration: TimeInterval = 25 * 60
    public private(set) var remaining: TimeInterval = 0

    /// Called exactly once when a running session reaches its end.
    public var onFinished: (() -> Void)?

    private let now: () -> Date
    private var endDate: Date?

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var isActive: Bool {
        phase == .running || phase == .paused
    }

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - remaining / duration, 0), 1)
    }

    public var remainingSeconds: Int {
        Int(ceil(max(remaining, 0)))
    }

    public func start(minutes: Int) {
        start(duration: TimeInterval(max(minutes, 1)) * 60)
    }

    public func start(duration newDuration: TimeInterval) {
        guard newDuration > 0 else { return }
        duration = newDuration
        remaining = newDuration
        endDate = now().addingTimeInterval(newDuration)
        phase = .running
    }

    public func pause() {
        guard phase == .running else { return }
        refresh(allowFinishing: true)
        guard phase == .running else { return }
        phase = .paused
        endDate = nil
    }

    public func resume() {
        guard phase == .paused, remaining > 0 else { return }
        endDate = now().addingTimeInterval(remaining)
        phase = .running
    }

    public func cancel() {
        phase = .idle
        endDate = nil
        remaining = 0
    }

    public func dismissFinished() {
        guard phase == .finished else { return }
        phase = .idle
        remaining = 0
    }

    /// Updates the displayed remainder and completes the timer when the wall
    /// clock has passed the end date. Safe to call repeatedly.
    public func refresh(allowFinishing: Bool = true) {
        guard phase == .running, let endDate else { return }
        let secondsLeft = endDate.timeIntervalSince(now())
        if secondsLeft <= 0 {
            remaining = 0
            if allowFinishing {
                finish()
            } else {
                self.endDate = nil
            }
        } else {
            remaining = secondsLeft
        }
    }

    private func finish() {
        guard phase == .running else { return }
        phase = .finished
        remaining = 0
        endDate = nil
        onFinished?()
    }

    // MARK: - Lifecycle persistence

    public var snapshot: FocusTimerSnapshot? {
        switch phase {
        case .running:
            return FocusTimerSnapshot(phase: .running, endDate: endDate, remaining: remaining, duration: duration)
        case .paused:
            return FocusTimerSnapshot(phase: .paused, endDate: nil, remaining: remaining, duration: duration)
        case .idle, .finished:
            return nil
        }
    }

    /// Restores a session saved before the app quit. Returns `true` when an
    /// active or paused session was restored. An expired running session is
    /// shown as finished without invoking `onFinished`, so relaunching the app
    /// never unexpectedly changes audio.
    @discardableResult
    public func restore(_ snapshot: FocusTimerSnapshot) -> Bool {
        duration = max(snapshot.duration, 0)
        switch snapshot.phase {
        case .running:
            guard let endDate = snapshot.endDate else {
                phase = .idle
                remaining = 0
                return false
            }
            let secondsLeft = endDate.timeIntervalSince(now())
            if secondsLeft <= 0 {
                phase = .finished
                remaining = 0
                self.endDate = nil
                return false
            }
            self.endDate = endDate
            remaining = secondsLeft
            phase = .running
            return true
        case .paused:
            guard snapshot.remaining > 0 else {
                phase = .idle
                remaining = 0
                return false
            }
            remaining = min(snapshot.remaining, max(snapshot.duration, snapshot.remaining))
            phase = .paused
            endDate = nil
            return true
        case .idle, .finished:
            phase = .idle
            remaining = 0
            return false
        }
    }

    /// Test and preview helper: set a deterministic remaining time without
    /// starting a wall-clock session.
    public func configureForPreview(duration: TimeInterval, remaining: TimeInterval, phase: FocusTimerPhase) {
        self.duration = max(duration, 0)
        self.remaining = max(remaining, 0)
        self.phase = phase
        self.endDate = nil
    }
}
