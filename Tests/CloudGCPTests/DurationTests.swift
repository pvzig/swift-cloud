import Testing

@testable import CloudGCP

struct DurationTests {
    @Test("Protobuf duration strings preserve fractional seconds")
    func fractionalSeconds() {
        #expect(Duration.milliseconds(500).protobufString == "0.5s")
        #expect(Duration.microseconds(500).protobufString == "0.0005s")
        #expect(Duration.nanoseconds(500).protobufString == "0.0000005s")
        #expect((Duration.seconds(1) + .milliseconds(250)).protobufString == "1.25s")
    }

    @Test(
        "Floating-point duration factories round representation noise to nanoseconds",
        arguments: [1.1, 2.7, 100.1]
    )
    func floatingPointFactories(value: Double) {
        let duration = value == 100.1 ? Duration.milliseconds(value) : .seconds(value)
        let expected = value == 100.1 ? "0.1001s" : "\(value)s"
        #expect(duration.protobufString == expected)
    }

    @Test("Computed fractional durations do not trap")
    func computedFraction() {
        #expect((Duration.seconds(10) / 3).protobufString == "3.333333333s")
    }
}
