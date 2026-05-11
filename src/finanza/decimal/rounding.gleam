//// Rounding modes for decimal arithmetic.
////
//// Every operation in [`finanza/decimal`](../decimal.html) that can
//// reduce precision takes a `Mode` so the rounding behaviour is
//// explicit. The seven modes match the IBM General Decimal Arithmetic
//// specification (see `doc/reference/specs/ibm-decimal-arithmetic.md`).

/// The rounding mode applied when a decimal operation must drop digits.
///
/// `HalfEven` is the canonical financial default ("banker's rounding"):
/// it rounds half-way values to the nearest even digit, which avoids
/// the systematic upward bias of `HalfUp` when many roundings are
/// summed.
pub type Mode {
  /// Round half-way values to the nearest even digit.
  /// `2.5 -> 2`, `3.5 -> 4`, `-2.5 -> -2`.
  HalfEven
  /// Round half-way values away from zero.
  /// `2.5 -> 3`, `-2.5 -> -3`.
  HalfUp
  /// Round half-way values toward zero.
  /// `2.5 -> 2`, `-2.5 -> -2`.
  HalfDown
  /// Always round away from zero. `2.1 -> 3`, `-2.1 -> -3`.
  Up
  /// Always round toward zero (truncate). `2.9 -> 2`, `-2.9 -> -2`.
  Down
  /// Always round toward +∞. `2.1 -> 3`, `-2.9 -> -2`.
  Ceiling
  /// Always round toward -∞. `2.9 -> 2`, `-2.1 -> -3`.
  Floor
}
