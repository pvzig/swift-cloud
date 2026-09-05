extension GCP.SQLDatabase {
    /// The edition used by the primary instance and its read replicas.
    ///
    /// Enterprise supports the default custom tier. Enterprise Plus requires a
    /// compatible predefined tier, such as `db-perf-optimized-N-2`.
    public enum Edition: String, Sendable {
        case enterprise = "ENTERPRISE"
        case enterprisePlus = "ENTERPRISE_PLUS"
    }
}
