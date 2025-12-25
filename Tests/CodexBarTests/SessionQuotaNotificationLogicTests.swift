import Foundation
import Testing
@testable import CodexBar

@Suite
struct SessionQuotaNotificationLogicTests {
    @Test
    func doesNothingWithoutPreviousValue() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: nil, currentRemaining: 0)
        #expect(transition == .none)
    }

    @Test
    func detectsDepletedTransition() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: 12, currentRemaining: 0)
        #expect(transition == .depleted)
    }

    @Test
    func detectsRestoredTransition() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: 0, currentRemaining: 5)
        #expect(transition == .restored)
    }

    @Test
    func ignoresNonTransitions() {
        #expect(SessionQuotaNotificationLogic.transition(previousRemaining: 0, currentRemaining: 0) == .none)
        #expect(SessionQuotaNotificationLogic.transition(previousRemaining: 10, currentRemaining: 10) == .none)
        #expect(SessionQuotaNotificationLogic.transition(previousRemaining: 10, currentRemaining: 9) == .none)
    }

    @Test
    func treatsTinyPositiveRemainingAsDepleted() {
        let transition = SessionQuotaNotificationLogic.transition(previousRemaining: 0, currentRemaining: 0.00001)
        #expect(transition == .none)
    }

    // MARK: - Smart Warning Tests

    @Test
    func smartWarningTriggersWhenThresholdCrossed() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3 * 24 * 60 * 60) // 3 days from now

        let warning = SessionQuotaNotificationLogic.smartWarningTransition(
            previousUsedPercent: 75,
            currentUsedPercent: 82,
            threshold: 80,
            resetsAt: resetsAt,
            now: now)

        #expect(warning == .smartWarning(usedPercent: 82, daysRemaining: 3))
    }

    @Test
    func smartWarningDoesNotTriggerBelowThreshold() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3 * 24 * 60 * 60)

        let warning = SessionQuotaNotificationLogic.smartWarningTransition(
            previousUsedPercent: 70,
            currentUsedPercent: 75,
            threshold: 80,
            resetsAt: resetsAt,
            now: now)

        #expect(warning == nil)
    }

    @Test
    func smartWarningDoesNotTriggerIfAlreadyAboveThreshold() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3 * 24 * 60 * 60)

        let warning = SessionQuotaNotificationLogic.smartWarningTransition(
            previousUsedPercent: 85,
            currentUsedPercent: 90,
            threshold: 80,
            resetsAt: resetsAt,
            now: now)

        #expect(warning == nil)
    }

    @Test
    func smartWarningCalculatesDaysCorrectly() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(1 * 24 * 60 * 60 + 3600) // 1 day + 1 hour

        let warning = SessionQuotaNotificationLogic.smartWarningTransition(
            previousUsedPercent: 70,
            currentUsedPercent: 85,
            threshold: 80,
            resetsAt: resetsAt,
            now: now)

        #expect(warning == .smartWarning(usedPercent: 85, daysRemaining: 2)) // ceil rounds up
    }

    @Test
    func smartWarningWorksWithNilPreviousPercent() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(2 * 24 * 60 * 60)

        // nil previous treated as 0, so crossing from 0 to 85 should trigger at 80 threshold
        let warning = SessionQuotaNotificationLogic.smartWarningTransition(
            previousUsedPercent: nil,
            currentUsedPercent: 85,
            threshold: 80,
            resetsAt: resetsAt,
            now: now)

        #expect(warning == .smartWarning(usedPercent: 85, daysRemaining: 2))
    }
}
