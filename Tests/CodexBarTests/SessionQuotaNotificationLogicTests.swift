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

    // MARK: - Threshold Crossing Tests

    @Test
    func detectsThreshold50Crossed() {
        // remaining 60% -> remaining 45% means used went from 40% to 55%, crossing 50%
        let crossed = SessionQuotaNotificationLogic.crossedThreshold(
            previousRemaining: 60,
            currentRemaining: 45,
            threshold: 50,
            alreadyNotified: false)
        #expect(crossed == true)
    }

    @Test
    func detectsThreshold75Crossed() {
        // remaining 30% -> remaining 20% means used went from 70% to 80%, crossing 75%
        let crossed = SessionQuotaNotificationLogic.crossedThreshold(
            previousRemaining: 30,
            currentRemaining: 20,
            threshold: 75,
            alreadyNotified: false)
        #expect(crossed == true)
    }

    @Test
    func detectsThreshold90Crossed() {
        // remaining 15% -> remaining 5% means used went from 85% to 95%, crossing 90%
        let crossed = SessionQuotaNotificationLogic.crossedThreshold(
            previousRemaining: 15,
            currentRemaining: 5,
            threshold: 90,
            alreadyNotified: false)
        #expect(crossed == true)
    }

    @Test
    func ignoresAlreadyNotifiedThreshold() {
        // Should not notify for 50% again if already notified
        let crossed = SessionQuotaNotificationLogic.crossedThreshold(
            previousRemaining: 60,
            currentRemaining: 45,
            threshold: 50,
            alreadyNotified: true)
        #expect(crossed == false)
    }

    @Test
    func ignoresThresholdNotCrossed() {
        // remaining 55% -> remaining 52% means used went from 45% to 48%, not crossing 50%
        let crossed = SessionQuotaNotificationLogic.crossedThreshold(
            previousRemaining: 55,
            currentRemaining: 52,
            threshold: 50,
            alreadyNotified: false)
        #expect(crossed == false)
    }

    @Test
    func ignoresWhenUsageDecreases() {
        // remaining goes up (usage goes down), should not trigger
        let crossed = SessionQuotaNotificationLogic.crossedThreshold(
            previousRemaining: 40,
            currentRemaining: 60,
            threshold: 50,
            alreadyNotified: false)
        #expect(crossed == false)
    }

    // MARK: - Threshold Clearing Tests

    @Test
    func clearsThresholdWhenUsageDrops() {
        // remaining 60% means used 40%, which is below 50%, so clear 50%
        let cleared = SessionQuotaNotificationLogic.clearedThreshold(
            previousRemaining: 45,
            currentRemaining: 60,
            threshold: 50,
            alreadyNotified: true)
        #expect(cleared == true)
    }

    @Test
    func doesNotClearThresholdIfNotNotified() {
        // If never notified, nothing to clear
        let cleared = SessionQuotaNotificationLogic.clearedThreshold(
            previousRemaining: 45,
            currentRemaining: 60,
            threshold: 50,
            alreadyNotified: false)
        #expect(cleared == false)
    }

    @Test
    func doesNotClearThresholdStillExceeded() {
        // remaining 40% = 60% used, 50% threshold is still exceeded
        let cleared = SessionQuotaNotificationLogic.clearedThreshold(
            previousRemaining: 30,
            currentRemaining: 40,
            threshold: 50,
            alreadyNotified: true)
        #expect(cleared == false)
    }

    // MARK: - Window Reset Detection Tests

    @Test
    func detectsWindowResetWhenPreviousTimeExpired() {
        let now = Date()
        let previousResetsAt = now.addingTimeInterval(-60) // 1 minute ago (expired)
        let currentResetsAt = now.addingTimeInterval(3600) // 1 hour in future
        
        let isReset = SessionQuotaNotificationLogic.detectWindowReset(
            previousResetsAt: previousResetsAt,
            currentResetsAt: currentResetsAt,
            previousRemaining: 30,
            currentRemaining: 100,
            now: now)
        #expect(isReset == true)
    }

    @Test
    func detectsWindowResetFromUsageJump() {
        let now = Date()
        let currentResetsAt = now.addingTimeInterval(3600) // 1 hour in future
        
        // Previous remaining was low (40%), now it's high (95%) - quota refilled
        let isReset = SessionQuotaNotificationLogic.detectWindowReset(
            previousResetsAt: nil,
            currentResetsAt: currentResetsAt,
            previousRemaining: 40,
            currentRemaining: 95,
            now: now)
        #expect(isReset == true)
    }

    @Test
    func ignoresWindowResetWhenNoChange() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600) // Same reset time
        
        let isReset = SessionQuotaNotificationLogic.detectWindowReset(
            previousResetsAt: resetsAt,
            currentResetsAt: resetsAt,
            previousRemaining: 80,
            currentRemaining: 75,
            now: now)
        #expect(isReset == false)
    }

    @Test
    func ignoresWindowResetWhenBothNil() {
        let now = Date()
        
        let isReset = SessionQuotaNotificationLogic.detectWindowReset(
            previousResetsAt: nil,
            currentResetsAt: nil,
            previousRemaining: 80,
            currentRemaining: 75,
            now: now)
        #expect(isReset == false)
    }

    @Test
    func ignoresWindowResetWhenCurrentResetInPast() {
        let now = Date()
        let previousResetsAt = now.addingTimeInterval(-120) // 2 minutes ago
        let currentResetsAt = now.addingTimeInterval(-60) // 1 minute ago (still in past)
        
        let isReset = SessionQuotaNotificationLogic.detectWindowReset(
            previousResetsAt: previousResetsAt,
            currentResetsAt: currentResetsAt,
            previousRemaining: 30,
            currentRemaining: 100,
            now: now)
        #expect(isReset == false)
    }

    @Test
    func ignoresSmallUsageRecovery() {
        let now = Date()
        let currentResetsAt = now.addingTimeInterval(3600)
        
        // Previous was 55%, now 60% - small recovery, not a reset
        let isReset = SessionQuotaNotificationLogic.detectWindowReset(
            previousResetsAt: nil,
            currentResetsAt: currentResetsAt,
            previousRemaining: 55,
            currentRemaining: 60,
            now: now)
        #expect(isReset == false)
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
