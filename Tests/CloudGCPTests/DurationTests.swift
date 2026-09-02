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
}
