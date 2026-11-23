import Foundation
import Testing
@testable import ScrobbleCore

@Suite struct RescanGateTests {
    actor Counter { var value = 0; func bump() { value += 1 } }

    @Test func coalescesTriggersDuringARun() async {
        let gate = RescanGate()
        let counter = Counter()
        let body: @Sendable () async -> Void = {
            await counter.bump()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        async let first: Void = gate.trigger(body)
        try? await Task.sleep(nanoseconds: 20_000_000)
        await gate.trigger(body)
        await gate.trigger(body)
        await gate.trigger(body)
        await first
        #expect(await counter.value == 2)
    }
}
