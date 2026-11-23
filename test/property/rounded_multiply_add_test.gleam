//// Properties of the multiply-and-add with rounding that the interest
//// functions compound with.
////
//// On both targets, `x × r + x` rounded at the most places that fit is
//// `x × (1 + r)` rounded the same way, whenever `1 + r` is a `Decimal`.
//// On Erlang, `a × b + c + d` is compared with an oracle written with
//// bignums, which covers sums no `Decimal` can hold before rounding.

import metamon
import metamon/generator
import metamon/generator/range

import finanza/decimal
import finanza/internal/rounded
import property/decimal_multiply_test

// The rounded product at the most places up to `places` that fit, the
// way the interest functions used to compound.
fn multiply_at_most(
  a: decimal.Decimal,
  b: decimal.Decimal,
  places: Int,
) -> Result(decimal.Decimal, decimal.ArithmeticError) {
  case rounded.multiply(a, b, digits: places, rounding: decimal.HalfEven) {
    Ok(value) -> Ok(value)
    Error(error) ->
      case places > 0 {
        True -> multiply_at_most(a, b, places - 1)
        False -> Error(error)
      }
  }
}

/// `x × r + x` is `x × (1 + r)` whenever `1 + r` fits. Runs on both
/// targets.
pub fn growth_matches_the_product_with_one_plus_the_rate_test() {
  metamon.forall_with(
    metamon.with_runs_or_panic(metamon.default_config(), 2000),
    generator.tuple3(
      decimal_multiply_test.decimal_generator(),
      decimal_multiply_test.decimal_generator(),
      generator.int(range.constant(0, 28)),
    ),
    fn(input) {
      let #(x, rate, places) = input
      case decimal.add(decimal.one(), rate) {
        Ok(base) ->
          rounded.multiply_add(x, rate, plus: [x], at_most: places)
          == multiply_at_most(x, base, places)
        Error(_) -> True
      }
    },
  )
}

// 2^53 - 1.
@target(erlang)
const max = 9_007_199_254_740_991

@target(erlang)
fn pow10(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> 10 * pow10(n - 1)
  }
}

@target(erlang)
fn lower(a: Int, b: Int) -> Int {
  case a < b {
    True -> a
    False -> b
  }
}

// `value × 10^shift`, rounded half-even when `shift` is negative.
@target(erlang)
fn round_half_even(value: Int, shift: Int) -> Int {
  case shift >= 0 {
    True -> value * pow10(shift)
    False -> {
      let divisor = pow10(0 - shift)
      let magnitude = case value < 0 {
        True -> 0 - value
        False -> value
      }
      let quotient = magnitude / divisor
      let remainder = magnitude % divisor
      let rounded = case
        2 * remainder > divisor
        || { 2 * remainder == divisor && quotient % 2 == 1 }
      {
        True -> quotient + 1
        False -> quotient
      }
      case value < 0 {
        True -> 0 - rounded
        False -> rounded
      }
    }
  }
}

// The exact `a × b + c + d` with Erlang's bignums, rounded half-even at
// `places`, or at fewer places down to 0 until the coefficient fits.
@target(erlang)
fn oracle(
  a: decimal.Decimal,
  b: decimal.Decimal,
  c: decimal.Decimal,
  d: decimal.Decimal,
  places: Int,
) -> Result(#(Int, Int), Nil) {
  let product_exponent = decimal.exponent(a) + decimal.exponent(b)
  let exponent =
    lower(product_exponent, lower(decimal.exponent(c), decimal.exponent(d)))
  let total =
    decimal.coefficient(a)
    * decimal.coefficient(b)
    * pow10(product_exponent - exponent)
    + decimal.coefficient(c)
    * pow10(decimal.exponent(c) - exponent)
    + decimal.coefficient(d)
    * pow10(decimal.exponent(d) - exponent)
  oracle_places(total, exponent, places)
}

@target(erlang)
fn oracle_places(
  total: Int,
  exponent: Int,
  places: Int,
) -> Result(#(Int, Int), Nil) {
  let coefficient = round_half_even(total, exponent + places)
  case coefficient > max || coefficient < 0 - max, places > 0 {
    False, _ -> Ok(#(coefficient, 0 - places))
    True, True -> oracle_places(total, exponent, places - 1)
    True, False -> Error(Nil)
  }
}

@target(erlang)
pub fn multiply_add_matches_the_bignum_oracle_test() {
  metamon.forall_with(
    metamon.with_runs_or_panic(metamon.default_config(), 2000),
    generator.tuple2(
      generator.tuple4(
        decimal_multiply_test.decimal_generator(),
        decimal_multiply_test.decimal_generator(),
        decimal_multiply_test.decimal_generator(),
        decimal_multiply_test.decimal_generator(),
      ),
      generator.int(range.constant(0, 28)),
    ),
    fn(input) {
      let #(#(a, b, c, d), places) = input
      let actual = case
        rounded.multiply_add(a, b, plus: [c, d], at_most: places)
      {
        Ok(value) -> Ok(#(decimal.coefficient(value), decimal.exponent(value)))
        Error(_) -> Error(Nil)
      }
      actual == oracle(a, b, c, d, places)
    },
  )
}
