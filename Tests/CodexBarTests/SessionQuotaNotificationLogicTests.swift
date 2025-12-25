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
}
