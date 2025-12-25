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
        let crossed = SessionQuotaNotificationLogic.crossedThresholds(
            previousRemaining: 60,
            currentRemaining: 45,
            enabledThresholds: [50, 75, 90],
            alreadyNotified: [])
        #expect(crossed == [50])
    }

    @Test
    func detectsThreshold75Crossed() {
        // remaining 30% -> remaining 20% means used went from 70% to 80%, crossing 75%
        let crossed = SessionQuotaNotificationLogic.crossedThresholds(
            previousRemaining: 30,
            currentRemaining: 20,
            enabledThresholds: [50, 75, 90],
            alreadyNotified: [50])
        #expect(crossed == [75])
    }

    @Test
    func detectsThreshold90Crossed() {
        // remaining 15% -> remaining 5% means used went from 85% to 95%, crossing 90%
        let crossed = SessionQuotaNotificationLogic.crossedThresholds(
            previousRemaining: 15,
            currentRemaining: 5,
            enabledThresholds: [50, 75, 90],
            alreadyNotified: [50, 75])
        #expect(crossed == [90])
    }

    @Test
    func detectsMultipleThresholdsCrossed() {
        // remaining 95% -> remaining 40% means used went from 5% to 60%, crossing 50%
        // (75 and 90 are not crossed because usage is only at 60%)
        let crossed = SessionQuotaNotificationLogic.crossedThresholds(
            previousRemaining: 95,
            currentRemaining: 40,
            enabledThresholds: [50, 75, 90],
            alreadyNotified: [])
        #expect(crossed == [50])
    }

    @Test
    func detectsMultipleThresholdsInBigDrop() {
        // remaining 95% -> remaining 5% means used went from 5% to 95%, crossing 50%, 75%, and 90%
        let crossed = SessionQuotaNotificationLogic.crossedThresholds(
            previousRemaining: 95,
            currentRemaining: 5,
            enabledThresholds: [50, 75, 90],
            alreadyNotified: [])
        #expect(crossed == [50, 75, 90])
    }

    @Test
    func ignoresAlreadyNotifiedThresholds() {
        // Should not notify for 50% again if already notified
        let crossed = SessionQuotaNotificationLogic.crossedThresholds(
            previousRemaining: 60,
            currentRemaining: 45,
            enabledThresholds: [50, 75, 90],
            alreadyNotified: [50])
        #expect(crossed == [])
    }

    @Test
    func ignoresThresholdNotCrossed() {
        // remaining 55% -> remaining 52% means used went from 45% to 48%, not crossing 50%
        let crossed = SessionQuotaNotificationLogic.crossedThresholds(
            previousRemaining: 55,
            currentRemaining: 52,
            enabledThresholds: [50, 75, 90],
            alreadyNotified: [])
        #expect(crossed == [])
    }

    @Test
    func ignoresWhenUsageDecreases() {
        // remaining goes up (usage goes down), should not trigger
        let crossed = SessionQuotaNotificationLogic.crossedThresholds(
            previousRemaining: 40,
            currentRemaining: 60,
            enabledThresholds: [50, 75, 90],
            alreadyNotified: [])
        #expect(crossed == [])
    }

    // MARK: - Threshold Clearing Tests

    @Test
    func clearsThresholdWhenUsageDrops() {
        // remaining 60% means used 40%, which is below 50%, so clear 50%
        let cleared = SessionQuotaNotificationLogic.clearedThresholds(
            previousRemaining: 45,
            currentRemaining: 60,
            alreadyNotified: [50])
        #expect(cleared == [50])
    }

    @Test
    func clearsMultipleThresholds() {
        // Usage dropping from 95% remaining to put used way below thresholds
        let cleared = SessionQuotaNotificationLogic.clearedThresholds(
            previousRemaining: 5,
            currentRemaining: 95,
            alreadyNotified: [50, 75, 90])
        #expect(cleared == [50, 75, 90])
    }

    @Test
    func doesNotClearThresholdStillExceeded() {
        // remaining 40% = 60% used, 50% threshold is still exceeded
        let cleared = SessionQuotaNotificationLogic.clearedThresholds(
            previousRemaining: 30,
            currentRemaining: 40,
            alreadyNotified: [50, 75])
        #expect(cleared == [75])
    }
}
