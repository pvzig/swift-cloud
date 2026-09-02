extension Duration {
    /// Encodes a nonnegative duration using Google APIs' protobuf duration syntax.
    ///
    /// Protobuf durations preserve up to nanosecond precision. Rejecting finer
    /// values avoids silently changing retry, retention, or timeout behavior.
    var protobufString: String {
        precondition(self >= .zero, "protobuf durations must not be negative")

        let components = components
        let attosecondsPerNanosecond: Int64 = 1_000_000_000
        precondition(
            components.attoseconds.isMultiple(of: attosecondsPerNanosecond),
            "protobuf durations must not be more precise than one nanosecond"
        )

        let nanoseconds = components.attoseconds / attosecondsPerNanosecond
        guard nanoseconds != 0 else {
            return "\(components.seconds)s"
        }

        var fraction = String(nanoseconds)
        fraction = String(repeating: "0", count: 9 - fraction.count) + fraction
        while fraction.last == "0" {
            fraction.removeLast()
        }
        return "\(components.seconds).\(fraction)s"
    }
}
