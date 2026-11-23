//// Properties of the multiplication with rounding that `money.multiply`
//// and the interest functions use.
////
//// On both targets, the rounded product is the exact product rounded
//// with `decimal.round` whenever `decimal.multiply` can hold the exact
//// product. On Erlang, it is also compared with an oracle written with
//// bignums, which covers the products `decimal.multiply` cannot hold.

import metamon
import metamon/generator.{type Generator}
import metamon/generator/range

import finanza/decimal
import finanza/internal/rounded
import finanza/money
import property/decimal_multiply_test

fn mode_generator() -> Generator(decimal.RoundingMode) {
  generator.element_of([
    decimal.HalfEven,
    decimal.HalfUp,
    decimal.HalfDown,
    decimal.Up,
    decimal.Down,
    decimal.Ceiling,
    decimal.Floor,
  ])
}

fn input_generator() -> Generator(
  #(decimal.Decimal, decimal.Decimal, Int, decimal.RoundingMode),
) {
  generator.tuple4(
    decimal_multiply_test.decimal_generator(),
    decimal_multiply_test.decimal_generator(),
    generator.int(range.constant(-15, 28)),
    mode_generator(),
  )
}

/// When the exact product is in range, rounding it afterwards gives the
/// same decimal, and so does `money.multiply` for a currency with that
/// many places. Runs on both targets.
pub fn rounded_product_matches_round_of_the_exact_product_test() {
  metamon.forall_with(
    metamon.with_runs_or_panic(metamon.default_config(), 2000),
    input_generator(),
    fn(input) {
      let #(a, b, digits, mode) = input
      let actual = rounded.multiply(a, b, digits:, rounding: mode)
      case decimal.multiply(a, b) {
        Error(_) -> True
        Ok(exact) -> {
          let expected = decimal.round(exact, digits:, rounding: mode)
          let currency = money.Currency(..money.usd, exponent: digits)
          let via_money = case digits >= 0 {
            True ->
              money.multiply(
                money.Money(amount: a, currency:),
                by: b,
                rounding: mode,
              )
              == case expected {
                Ok(amount) -> Ok(money.Money(amount:, currency:))
                Error(error) -> Error(money.ArithmeticFailed(error))
              }
            False -> True
          }
          actual == expected && via_money
        }
      }
    },
  )
}

// The exact product with Erlang's bignums, rounded to `digits` places
// by integer division, then checked against the range.
@target(erlang)
fn oracle(
  a: decimal.Decimal,
  b: decimal.Decimal,
  digits: Int,
  mode: decimal.RoundingMode,
) -> Result(#(Int, Int), Nil) {
  let product = decimal.coefficient(a) * decimal.coefficient(b)
  let shift = decimal.exponent(a) + decimal.exponent(b) + digits
  let coefficient = case shift >= 0 {
    True -> product * pow10(shift)
    False -> {
      let divisor = pow10(0 - shift)
      let magnitude = case product < 0 {
        True -> 0 - product
        False -> product
      }
      let quotient = magnitude / divisor
      let remainder = magnitude % divisor
      let bump = case remainder == 0 {
        True -> False
        False ->
          case mode {
            decimal.HalfEven ->
              2 * remainder > divisor
              || { 2 * remainder == divisor && quotient % 2 == 1 }
            decimal.HalfUp -> 2 * remainder >= divisor
            decimal.HalfDown -> 2 * remainder > divisor
            decimal.Up -> True
            decimal.Down -> False
            decimal.Ceiling -> product > 0
            decimal.Floor -> product < 0
          }
      }
      let rounded = case bump {
        True -> quotient + 1
        False -> quotient
      }
      case product < 0 {
        True -> 0 - rounded
        False -> rounded
      }
    }
  }
  case decimal.new(coefficient:, exponent: 0 - digits) {
    Ok(value) -> Ok(#(decimal.coefficient(value), decimal.exponent(value)))
    Error(Nil) -> Error(Nil)
  }
}

@target(erlang)
fn pow10(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> 10 * pow10(n - 1)
  }
}

@target(erlang)
pub fn rounded_product_matches_the_bignum_oracle_test() {
  metamon.forall_with(
    metamon.with_runs_or_panic(metamon.default_config(), 2000),
    input_generator(),
    fn(input) {
      let #(a, b, digits, mode) = input
      let actual = case rounded.multiply(a, b, digits:, rounding: mode) {
        Ok(value) -> Ok(#(decimal.coefficient(value), decimal.exponent(value)))
        Error(_) -> Error(Nil)
      }
      actual == oracle(a, b, digits, mode)
    },
  )
}
