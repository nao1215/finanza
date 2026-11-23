//// `decimal.multiply` on products whose coefficient passes 2^53 - 1
//// before the trailing zeros are dropped.
////
//// The product of two coefficients can have up to 32 digits, which
//// JavaScript cannot hold exactly, so it is computed in small limbs.
//// These tests pin products that fit once their trailing zeros are
//// dropped, the bounds of the result on both sides, every sign
//// combination, and fixed products that both targets must agree on.
//// The properties are in `test/property/decimal_multiply_test.gleam`.

import gleam/result

import finanza/decimal
import finanza/interest
import support

// 2^53 - 1.
const max = 9_007_199_254_740_991

// 2^52.
const half = 4_503_599_627_370_496

fn text(value: Result(decimal.Decimal, a)) -> Result(String, a) {
  result.map(value, decimal.to_string)
}

fn parts(value: Result(decimal.Decimal, a)) -> Result(#(Int, Int), a) {
  result.map(value, fn(d) { #(decimal.coefficient(d), decimal.exponent(d)) })
}

// --- the reported products ---------------------------------------------------

pub fn product_below_the_smallest_exponent_drops_zeros_test() {
  // 9007199254741000e-29 does not fit, 900719925474100e-28 does.
  let a = support.new(coefficient: 900_719_925_474_100, exponent: -14)
  let b = support.new(coefficient: 10, exponent: -15)
  assert decimal.multiply(a, b) |> parts == Ok(#(900_719_925_474_100, -28))
}

pub fn product_in_the_exponent_range_drops_zeros_test() {
  // 2^52 × 0.10 is 45035996273704960e-2, which is 4503599627370496e-1.
  let a = support.int(half)
  let b = support.new(coefficient: 10, exponent: -2)
  assert decimal.multiply(a, b) |> parts == Ok(#(half, -1))
  assert decimal.multiply(a, b) |> text == Ok("450359962737049.6")
}

pub fn product_drops_only_the_zeros_it_needs_test() {
  // 2^52 × 1.000 is 4503599627370496000e-3. Three zeros go, the
  // fewest that fit 2^53 - 1.
  let a = support.int(half)
  let b = support.new(coefficient: 1000, exponent: -3)
  assert decimal.multiply(a, b) |> parts == Ok(#(half, 0))
  let c = support.new(coefficient: 1_000_000_000_000_000, exponent: -15)
  let d = support.new(coefficient: 1_000_000_000_000_000, exponent: -15)
  // 10^30e-30: two zeros to reach -28, then 13 more to fit 2^53 - 1.
  assert decimal.multiply(c, d) |> parts == Ok(#(1_000_000_000_000_000, -15))
}

// --- bounds of the result ----------------------------------------------------

pub fn result_coefficient_at_the_largest_test() {
  let ten_tenths = support.new(coefficient: 10, exponent: -1)
  assert decimal.multiply(support.int(max), ten_tenths) |> parts
    == Ok(#(max, 0))
  let a = support.new(coefficient: max, exponent: -14)
  let b = support.new(coefficient: 10, exponent: -15)
  assert decimal.multiply(a, b) |> parts == Ok(#(max, -28))
}

pub fn result_coefficient_one_past_the_largest_test() {
  // 2^52 × 2.0 is 2^53 with any number of zeros dropped.
  let two = support.new(coefficient: 20, exponent: -1)
  assert decimal.multiply(support.int(half), two)
    == Error(decimal.PrecisionExceeded)
  let a = support.new(coefficient: half, exponent: -14)
  let b = support.new(coefficient: 20, exponent: -15)
  assert decimal.multiply(a, b) == Error(decimal.PrecisionExceeded)
}

pub fn result_exponent_at_the_smallest_test() {
  // 10^30e-43 drops 15 zeros, which reaches -28 and fits at once.
  let a = support.new(coefficient: 1_000_000_000_000_000, exponent: -28)
  let b = support.new(coefficient: 1_000_000_000_000_000, exponent: -15)
  assert decimal.multiply(a, b) |> parts == Ok(#(1_000_000_000_000_000, -28))
  // One non-zero digit past -28 is out of range.
  let c = support.new(coefficient: 1_000_000_000_000_001, exponent: -28)
  let d = support.new(coefficient: 100_000_000_000_000, exponent: -15)
  assert decimal.multiply(c, d) == Error(decimal.PrecisionExceeded)
}

pub fn result_exponent_at_the_largest_test() {
  let a = support.new(coefficient: 3, exponent: 15)
  assert decimal.multiply(a, support.int(3)) |> parts == Ok(#(9, 15))
  // 10^16 is out of range however it is written.
  assert decimal.multiply(a, support.new(coefficient: 4, exponent: 0))
    == Error(decimal.PrecisionExceeded)
  let one = support.new(coefficient: 1, exponent: 15)
  assert decimal.multiply(one, support.new(coefficient: 1, exponent: 1))
    == Error(decimal.PrecisionExceeded)
  // A large product at the largest exponent is out of range too.
  let large = support.new(coefficient: 1_000_000_000_000_000, exponent: 0)
  assert decimal.multiply(one, large) == Error(decimal.PrecisionExceeded)
}

pub fn product_with_a_digit_that_cannot_be_dropped_test() {
  // 2^52 + 1 times 3 needs 54 bits and has no zero to drop.
  let a = support.int(half + 1)
  let b = support.new(coefficient: 30, exponent: -1)
  assert decimal.multiply(a, b) == Error(decimal.PrecisionExceeded)
  let c = support.int(max)
  assert decimal.multiply(c, c) == Error(decimal.PrecisionExceeded)
}

// --- signs and zero ----------------------------------------------------------

pub fn product_signs_test() {
  let a = support.int(half)
  let b = support.new(coefficient: 10, exponent: -2)
  let negative_a = decimal.negate(a)
  let negative_b = decimal.negate(b)
  assert decimal.multiply(a, b) |> parts == Ok(#(half, -1))
  assert decimal.multiply(negative_a, b) |> parts == Ok(#(0 - half, -1))
  assert decimal.multiply(a, negative_b) |> parts == Ok(#(0 - half, -1))
  assert decimal.multiply(negative_a, negative_b) |> parts == Ok(#(half, -1))
  let c = support.new(coefficient: 900_719_925_474_100, exponent: -14)
  let d = support.new(coefficient: -10, exponent: -15)
  assert decimal.multiply(c, d) |> parts == Ok(#(-900_719_925_474_100, -28))
  assert decimal.multiply(decimal.negate(c), d) |> parts
    == Ok(#(900_719_925_474_100, -28))
}

pub fn product_with_zero_test() {
  let zero = support.new(coefficient: 0, exponent: -20)
  let large = support.new(coefficient: max, exponent: -15)
  assert decimal.multiply(zero, large) |> parts == Ok(#(0, -28))
  assert decimal.multiply(large, zero) |> parts == Ok(#(0, -28))
  assert decimal.multiply(decimal.negate(large), decimal.zero()) |> parts
    == Ok(#(0, -15))
}

// --- same results on both targets --------------------------------------------

pub fn fixed_products_match_on_both_targets_test() {
  let cases = [
    #(#(max, 0), #(max, 0), Error(decimal.PrecisionExceeded)),
    #(#(max, -14), #(10, -15), Ok("0.0000000000009007199254740991")),
    #(#(1_234_567_890_123_456, -15), #(100_000, -2), Ok("1234.567890123456")),
    #(
      #(2_500_000_000_000_000, -15),
      #(4_000_000_000, -9),
      Ok("10.00000000000000"),
    ),
    #(
      #(-8_000_000_000_000_000, -16),
      #(125_000_000_000, -12),
      Ok("-0.1000000000000000"),
    ),
    #(#(999_999_999_999_999, 0), #(9_000_000_000, -10), Ok("899999999999999.1")),
    #(
      #(999_999_999_999_999, 0),
      #(9_000_000_001, -10),
      Error(decimal.PrecisionExceeded),
    ),
  ]
  assert_cases(cases)
}

fn assert_cases(
  cases: List(
    #(#(Int, Int), #(Int, Int), Result(String, decimal.ArithmeticError)),
  ),
) -> Nil {
  case cases {
    [] -> Nil
    [#(#(ca, ea), #(cb, eb), expected), ..rest] -> {
      let a = support.new(coefficient: ca, exponent: ea)
      let b = support.new(coefficient: cb, exponent: eb)
      assert decimal.multiply(a, b) |> text == expected
      assert decimal.multiply(b, a) |> text == expected
      assert_cases(rest)
    }
  }
}

// --- callers -----------------------------------------------------------------

pub fn future_value_ignores_trailing_zeros_in_the_rate_test() {
  // The growth loop used to shrink the accumulator until the raw
  // coefficients multiplied within 2^53 - 1, so 1.05000000 ran out of
  // places that 1.05 did not need.
  let present = support.parse("1000000")
  let grow = fn(rate) {
    interest.future_value(
      present:,
      rate_per_period: support.parse(rate),
      periods: 120,
      digits: 2,
    )
    |> text
  }
  assert grow("0.05") == Ok("348911985.67")
  assert grow("0.05000000") == Ok("348911985.67")
}
