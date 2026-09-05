extension Duration {
    /// Encodes a nonnegative duration using Google APIs' protobuf duration syntax.
    ///
    /// Protobuf durations preserve up to nanosecond precision. Swift's floating-
    /// point duration factories can contain sub-nanosecond representation noise,
    /// so values are rounded to the closest representable protobuf duration.
    var protobufString: String {
        precondition(self >= .zero, "protobuf durations must not be negative")

        let components = components
        let attosecondsPerNanosecond: Int64 = 1_000_000_000
        var seconds = components.seconds
        let quotient = components.attoseconds / attosecondsPerNanosecond
        let remainder = components.attoseconds % attosecondsPerNanosecond
        var nanoseconds = quotient + (remainder >= attosecondsPerNanosecond / 2 ? 1 : 0)
        if nanoseconds == 1_000_000_000 {
            seconds += 1
            nanoseconds = 0
        }
        guard nanoseconds != 0 else {
            return "\(seconds)s"
        }

        var fraction = String(nanoseconds)
        fraction = String(repeating: "0", count: 9 - fraction.count) + fraction
        while fraction.last == "0" {
            fraction.removeLast()
        }
        return "\(seconds).\(fraction)s"
    }
}
