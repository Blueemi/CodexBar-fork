import CodexBarCore
import Foundation
@preconcurrency import UserNotifications

enum SessionQuotaTransition: Equatable, Sendable {
    case none
    case depleted
    case restored
    case crossedThreshold(percent: Int)
    case windowReset
    case smartWarning(usedPercent: Int, daysRemaining: Int)
}

enum SessionQuotaNotificationLogic {
    static let depletedThreshold: Double = 0.0001

    static func isDepleted(_ remaining: Double?) -> Bool {
        guard let remaining else { return false }
        return remaining <= Self.depletedThreshold
    }

    static func transition(previousRemaining: Double?, currentRemaining: Double?) -> SessionQuotaTransition {
        guard let currentRemaining else { return .none }
        guard let previousRemaining else { return .none }

        let wasDepleted = previousRemaining <= Self.depletedThreshold
        let isDepleted = currentRemaining <= Self.depletedThreshold

        if !wasDepleted, isDepleted { return .depleted }
        if wasDepleted, !isDepleted { return .restored }
        return .none
    }

    /// Returns true if the single threshold was crossed going from previousRemaining to currentRemaining.
    /// A threshold is "crossed" when previous was above it and current is at or below it.
    /// Note: remaining is in percent (0-100), threshold is usage percent (e.g., 75 = 75% used = 25% remaining).
    static func crossedThreshold(
        previousRemaining: Double?,
        currentRemaining: Double?,
        threshold: Int,
        alreadyNotified: Bool) -> Bool
    {
        guard !alreadyNotified else { return false }
        guard let currentRemaining, let previousRemaining else { return false }
        guard currentRemaining < previousRemaining else { return false }

        // Convert "remaining percent" to "used percent" for threshold comparison
        // remaining 50% = used 50%, remaining 25% = used 75%, remaining 10% = used 90%
        let previousUsed = 100.0 - previousRemaining
        let currentUsed = 100.0 - currentRemaining
        let thresholdDouble = Double(threshold)

        // Crossed if we went from below threshold to at or above it
        return previousUsed < thresholdDouble && currentUsed >= thresholdDouble
    }

    /// Returns true if the threshold should be cleared (user is now below it).
    /// The threshold can be notified again if usage increases past it.
    static func clearedThreshold(
        previousRemaining: Double?,
        currentRemaining: Double?,
        threshold: Int,
        alreadyNotified: Bool) -> Bool
    {
        guard alreadyNotified else { return false }
        guard let currentRemaining else { return false }
        let currentUsed = 100.0 - currentRemaining
        // If current usage is now below this threshold, clear it
        return currentUsed < Double(threshold)
    }

    /// Detects when a limit window has reset.
    /// Returns true when the previous resetsAt was in the past (or nil on first fetch but usage jumped up),
    /// and the new resetsAt is in the future, indicating a new window started.
    static func detectWindowReset(
        previousResetsAt: Date?,
        currentResetsAt: Date?,
        previousRemaining: Double?,
        currentRemaining: Double?,
        now: Date = Date()) -> Bool
    {
        // Must have a current reset time in the future
        guard let currentResetsAt, currentResetsAt > now else { return false }

        // If we had a previous reset time that's now in the past, window reset occurred
        if let previousResetsAt, previousResetsAt <= now {
            return true
        }

        // Also detect if remaining jumped significantly up (refilled), indicating reset
        // This catches cases where we didn't have resetsAt previously
        if let previousRemaining, let currentRemaining,
           previousRemaining < 50, currentRemaining >= 90 {
            return true
        }

        return false
    }

    /// Returns a smart warning transition if weekly usage crossed the threshold, nil otherwise.
    static func smartWarningTransition(
        previousUsedPercent: Double?,
        currentUsedPercent: Double,
        threshold: Int,
        resetsAt: Date?,
        now: Date = .init()
    ) -> SessionQuotaTransition? {
        let thresholdDouble = Double(threshold)

        // Only trigger if we just crossed the threshold
        let wasBelowThreshold = (previousUsedPercent ?? 0) < thresholdDouble
        let isAtOrAboveThreshold = currentUsedPercent >= thresholdDouble

        guard wasBelowThreshold, isAtOrAboveThreshold else { return nil }

        // Calculate days remaining
        let daysRemaining: Int
        if let resetsAt {
            let secondsRemaining = resetsAt.timeIntervalSince(now)
            daysRemaining = max(0, Int(ceil(secondsRemaining / 86400)))
        } else {
            daysRemaining = 0
        }

        return .smartWarning(usedPercent: Int(currentUsedPercent.rounded()), daysRemaining: daysRemaining)
    }
}

@MainActor
final class SessionQuotaNotifier {
    private let logger = CodexBarLog.logger("sessionQuotaNotifications")

    init() {}

    func post(transition: SessionQuotaTransition, provider: UsageProvider, badge: NSNumber? = nil) {
        guard transition != .none else { return }

        let providerName = switch provider {
        case .codex: "Codex"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .antigravity: "Antigravity"
        }

        let (title, body) = switch transition {
        case .none:
            ("", "")
        case .depleted:
            ("\(providerName) session depleted", "0% left. Will notify when it's available again.")
        case .restored:
            ("\(providerName) session restored", "Session quota is available again.")
        case let .crossedThreshold(percent):
            ("\(providerName) at \(percent)% usage", "\(100 - percent)% of session quota remaining.")
        case .windowReset:
            ("\(providerName) limit reset", "Your quota window has reset. Full capacity available.")
        case let .smartWarning(usedPercent, daysRemaining):
            self.smartWarningContent(provider: providerName, usedPercent: usedPercent, daysRemaining: daysRemaining)
        }

        let providerText = provider.rawValue
        let transitionText = switch transition {
        case .none: "none"
        case .depleted: "depleted"
        case .restored: "restored"
        case let .crossedThreshold(percent): "threshold-\(percent)"
        case .windowReset: "window-reset"
        case .smartWarning: "smartWarning"
        }
        let idPrefix = "session-\(providerText)-\(transitionText)"
        self.logger.info("enqueuing", metadata: ["prefix": idPrefix])
        AppNotifications.shared.post(idPrefix: idPrefix, title: title, body: body, badge: badge)
    }

    private func smartWarningContent(
        provider: String,
        usedPercent: Int,
        daysRemaining: Int
    ) -> (String, String) {
        let title = "\(provider) usage running high"
        let daysText = daysRemaining == 1 ? "1 day" : "\(daysRemaining) days"
        let body = "You've used \(usedPercent)% of your weekly limit with \(daysText) remaining."
        return (title, body)
    }
}
