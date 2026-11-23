import Foundation
import Testing
@testable import ScrobbleCore

@Suite struct BackoffTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [(1, 60.0), (2, 120.0), (3, 240.0), (6, 1920.0), (7, 3600.0), (20, 3600.0)])
    func delayDoublesAndCapsAtOneHour(attempt: Int, seconds: Double) {
        #expect(Backoff.delay(attempt: attempt, random: 0.5) == seconds)
    }

    @Test func jitterIsPlusMinusTwentyPercent() {
        #expect(Backoff.delay(attempt: 1, random: 0) == 48)
        #expect(abs(Backoff.delay(attempt: 1, random: 0.999_999) - 72) < 0.001)
    }

    @Test func nextUTCMidnight() {
        // 2027-01-15 10:00 UTC → 2027-01-16 00:00 UTC
        let d = Date(timeIntervalSince1970: 1_800_007_200)
        let midnight = Backoff.nextUTCMidnight(after: d)
        #expect(midnight.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) == 0)
        #expect(midnight > d && midnight.timeIntervalSince(d) <= 86_400)
    }

    @Test func policyMapsErrorsToStates() {
        #expect(DeliveryPolicy.state(after: .signedOut, previous: .waiting, now: now, random: 0.5) == .held(.signedOut))
        #expect(DeliveryPolicy.state(after: .keyUnusable(code: 26), previous: nil, now: now, random: 0.5) == .held(.keyUnusable))
        #expect(DeliveryPolicy.state(after: .permanent("Bad"), previous: .waiting, now: now, random: 0.5) == .ignored("Bad"))
        #expect(DeliveryPolicy.state(after: .transient("x"), previous: .waiting, now: now, random: 0.5)
                == .retry(attempt: 1, nextAt: now + 60))
        #expect(DeliveryPolicy.state(after: .transient("x"), previous: .retry(attempt: 2, nextAt: now), now: now, random: 0.5)
                == .retry(attempt: 3, nextAt: now + 240))
        #expect(DeliveryPolicy.state(after: .rateLimited(retryAfter: 17), previous: nil, now: now, random: 0.5)
                == .retry(attempt: 1, nextAt: now + 17))
    }

    @Test func serverRetryAfterIsClampedToSaneRange() {
        #expect(DeliveryPolicy.state(after: .rateLimited(retryAfter: 0), previous: nil, now: now, random: 0.5)
                == .retry(attempt: 1, nextAt: now + 5))
        #expect(DeliveryPolicy.state(after: .rateLimited(retryAfter: 99_999), previous: nil, now: now, random: 0.5)
                == .retry(attempt: 1, nextAt: now + 3600))
    }

    @Test func nonFiniteRetryAfterFallsBackToBackoff() {
        for bad in [Double.nan, .infinity, -.infinity] {
            #expect(DeliveryPolicy.state(after: .rateLimited(retryAfter: bad), previous: nil, now: now, random: 0.5)
                    == .retry(attempt: 1, nextAt: now + 60))
        }
    }

    @Test func problemsOnlyForAccountErrors() {
        #expect(DeliveryPolicy.problem(for: .signedOut) == .signedOut)
        #expect(DeliveryPolicy.problem(for: .keyUnusable(code: 10)) == .keyUnusable)
        #expect(DeliveryPolicy.problem(for: .transient("x")) == nil)
    }

    @Test func unknownErrorsBecomeTransient() {
        struct Other: Error {}
        #expect(Other().asScrobbleError == .transient("Other()"))
        #expect((ScrobbleError.signedOut as Error).asScrobbleError == .signedOut)
    }
}
