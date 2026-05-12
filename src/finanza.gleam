//// Top-level entry point for the `finanza` package.
////
//// The package is organised by domain:
////
//// - [`finanza/decimal`](./finanza/decimal.html) — fixed-point decimal type
////   and arithmetic with explicit rounding.
//// - [`finanza/currency`](./finanza/currency.html) — opaque `Currency` and
////   `Money` types, allocation, and formatting.
//// - [`finanza/interest`](./finanza/interest.html) — time-value-of-money
////   helpers (simple/compound interest, FV/PV/PMT, EAR).
//// - [`finanza/card`](./finanza/card.html) — payment-card primitives:
////   Luhn check, brand detection, masking, and expiry parsing.

/// The package version string. Useful for runtime diagnostics and
/// version reporting in dependent applications.
pub fn version() -> String {
  "0.2.0"
}
