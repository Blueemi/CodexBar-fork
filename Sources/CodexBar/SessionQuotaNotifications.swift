import CodexBarCore
import Foundation
import OSLog
@preconcurrency import UserNotifications

enum SessionQuotaTransition: Equatable, Sendable {
    case none
    case depleted
    case restored
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
    private let logger = Logger(subsystem: "com.steipete.codexbar", category: "sessionQuotaNotifications")

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
        case let .smartWarning(usedPercent, daysRemaining):
            self.smartWarningContent(provider: providerName, usedPercent: usedPercent, daysRemaining: daysRemaining)
        }

        let providerText = provider.rawValue
        let transitionText = switch transition {
        case .none: "none"
        case .depleted: "depleted"
        case .restored: "restored"
        case .smartWarning: "smartWarning"
        }
        let idPrefix = "session-\(providerText)-\(transitionText)"
        self.logger.info("enqueuing: prefix=\(idPrefix, privacy: .public)")
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
