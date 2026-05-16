//// Round 11: regression coverage for the `decimal.compare`
//// magnitude-fallback bug.
////
//// When `align/2` overflowed `max_safe_coefficient`, `compare/2`
//// fell back to `compare_by_magnitude` which used
//// `digit_count(coefficient) + exponent` as the ordering key. Two
//// distinct values whose magnitudes happened to tie were reported as
//// `Eq`. The fix in `compare_same_sign` adds a digit-string
//// tie-breaker, so this suite pins both the failing-before-fix case
//// and the previously-correct neighbouring cases.
////
//// The bug requires coefficients beyond `max_safe_coefficient` and is
//// only reachable from `decimal.new/2`. The reproduction literals
//// exceed JavaScript's `Number.MAX_SAFE_INTEGER`, which the Gleam
//// compiler flags as a warning-as-error on the JS lane. Since the bug
//// itself is not user-reachable on JavaScript (the same literal
//// truncation prevents construction), this suite is gated to the
//// Erlang target.

@target(erlang)
import finanza/decimal

@target(erlang)
import gleam/order

@target(erlang)
import gleeunit/should

pub fn main() -> Nil {
  Nil
}

@target(erlang)
pub fn compare_unequal_magnitude_tie_returns_gt_test() -> Nil {
  let a = decimal.new(coefficient: 5, exponent: 50)
  let b = decimal.new(coefficient: 123_456_789_012_345_678_901, exponent: 30)
  decimal.compare(a, b)
  |> should.equal(order.Gt)
}

@target(erlang)
pub fn compare_unequal_magnitude_tie_returns_lt_test() -> Nil {
  let a = decimal.new(coefficient: 1, exponent: 50)
  let b = decimal.new(coefficient: 999_999_999_999_999_999_999, exponent: 30)
  decimal.compare(a, b)
  |> should.equal(order.Lt)
}

@target(erlang)
pub fn compare_unequal_magnitude_tie_negative_test() -> Nil {
  let a = decimal.new(coefficient: -5, exponent: 50)
  let b = decimal.new(coefficient: -123_456_789_012_345_678_901, exponent: 30)
  // -5e50 vs -1.23e50: -5e50 < -1.23e50 → Lt.
  decimal.compare(a, b)
  |> should.equal(order.Lt)
}

@target(erlang)
pub fn compare_truly_equal_after_normalize_test() -> Nil {
  let a = decimal.new(coefficient: 1, exponent: 50)
  let b = decimal.new(coefficient: 100_000_000_000_000_000_000, exponent: 30)
  decimal.compare(a, b)
  |> should.equal(order.Eq)
}

@target(erlang)
pub fn compare_and_equal_consistent_on_unsafe_inputs_test() -> Nil {
  let a = decimal.new(coefficient: 5, exponent: 50)
  let b = decimal.new(coefficient: 123_456_789_012_345_678_901, exponent: 30)
  let cmp_eq = decimal.compare(a, b) == order.Eq
  let eq_eq = decimal.equal(a, b)
  cmp_eq
  |> should.equal(eq_eq)
}
