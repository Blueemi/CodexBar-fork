import CodexBarCore
import Foundation
@preconcurrency import UserNotifications

enum SessionQuotaTransition: Equatable, Sendable {
    case none
    case depleted
    case restored
    case crossedThreshold(percent: Int)
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

    /// Returns thresholds that were crossed going from previousRemaining to currentRemaining.
    /// A threshold is "crossed" when previous was above it and current is at or below it.
    /// Note: remaining is in percent (0-100), thresholds are usage percent (e.g., 50 = 50% used = 50% remaining).
    static func crossedThresholds(
        previousRemaining: Double?,
        currentRemaining: Double?,
        enabledThresholds: Set<Int>,
        alreadyNotified: Set<Int>) -> [Int]
    {
        guard let currentRemaining, let previousRemaining else { return [] }
        guard currentRemaining < previousRemaining else { return [] }

        // Convert "remaining percent" to "used percent" for threshold comparison
        // remaining 50% = used 50%, remaining 25% = used 75%, remaining 10% = used 90%
        let previousUsed = 100.0 - previousRemaining
        let currentUsed = 100.0 - currentRemaining

        var crossed: [Int] = []
        for threshold in enabledThresholds.sorted() {
            let thresholdDouble = Double(threshold)
            // Crossed if we went from below threshold to at or above it
            if previousUsed < thresholdDouble, currentUsed >= thresholdDouble {
                if !alreadyNotified.contains(threshold) {
                    crossed.append(threshold)
                }
            }
        }
        return crossed
    }

    /// Returns thresholds that should be cleared (user is now below them).
    /// These can be notified again if usage increases past them.
    static func clearedThresholds(
        previousRemaining: Double?,
        currentRemaining: Double?,
        alreadyNotified: Set<Int>) -> Set<Int>
    {
        guard let currentRemaining else { return [] }
        let currentUsed = 100.0 - currentRemaining

        var cleared: Set<Int> = []
        for threshold in alreadyNotified {
            // If current usage is now below this threshold, clear it
            if currentUsed < Double(threshold) {
                cleared.insert(threshold)
            }
        }
        return cleared
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
        }

        let providerText = provider.rawValue
        let transitionText = switch transition {
        case .none: "none"
        case .depleted: "depleted"
        case .restored: "restored"
        case let .crossedThreshold(percent): "threshold-\(percent)"
        }
        let idPrefix = "session-\(providerText)-\(transitionText)"
        self.logger.info("enqueuing", metadata: ["prefix": idPrefix])
        AppNotifications.shared.post(idPrefix: idPrefix, title: title, body: body, badge: badge)
    }
}
