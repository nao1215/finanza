//// Differential tests for `decimal.round` and `decimal.divide` against
//// an oracle written with plain integer arithmetic.
////
//// A decimal is `coefficient * 10^exponent`, so rounding to `digits`
//// places is one integer division by a power of ten and dividing two
//// decimals is one integer division of scaled coefficients. The oracle
//// does that division and applies each rounding mode to the remainder
//// directly, independently of the library's rescale code. The ranges
//// keep every intermediate value inside JavaScript's safe integers, so
//// the relation runs on both targets.

import finanza/decimal
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range
import support

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

/// Coefficients near the rounding boundaries (…5, …50, …49) are
/// mixed in with uniform values so ties are common.
fn coefficient_generator() -> Generator(Int) {
  generator.one_of([
    generator.int(range.constant(-10_000, 10_000)),
    generator.element_of([5, -5, 15, -15, 25, -25, 50, -50, 149, -151, 250]),
  ])
}

fn pow10(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> 10 * pow10(n - 1)
  }
}

fn abs(n: Int) -> Int {
  case n < 0 {
    True -> 0 - n
    False -> n
  }
}

/// `numerator / denominator` rounded with `mode`; `denominator > 0`.
fn round_div(
  numerator: Int,
  denominator: Int,
  mode: decimal.RoundingMode,
) -> Int {
  let q = numerator / denominator
  let r = numerator - q * denominator
  let sign = case numerator < 0 {
    True -> -1
    False -> 1
  }
  let twice = 2 * abs(r)
  case r == 0 {
    True -> q
    False ->
      case mode {
        decimal.Down -> q
        decimal.Up -> q + sign
        decimal.Ceiling ->
          case sign > 0 {
            True -> q + 1
            False -> q
          }
        decimal.Floor ->
          case sign < 0 {
            True -> q - 1
            False -> q
          }
        decimal.HalfUp ->
          case twice >= denominator {
            True -> q + sign
            False -> q
          }
        decimal.HalfDown ->
          case twice > denominator {
            True -> q + sign
            False -> q
          }
        decimal.HalfEven ->
          case twice > denominator, twice == denominator {
            True, _ -> q + sign
            _, True ->
              case q % 2 == 0 {
                True -> q
                False -> q + sign
              }
            _, _ -> q
          }
      }
  }
}

pub fn round_matches_the_integer_oracle_test() -> Nil {
  metamon.forall(
    generator.tuple4(
      coefficient_generator(),
      generator.int(range.constant(-5, 2)),
      generator.int(range.constant(0, 4)),
      mode_generator(),
    ),
    fn(input) {
      let #(coefficient, exponent, digits, mode) = input
      let d = support.new(coefficient: coefficient, exponent: exponent)
      let rounded = support.round(d, digits: digits, rounding: mode)
      let expected = case exponent >= 0 - digits {
        // Already at or coarser than the target: the value is kept.
        True -> d
        False ->
          support.new(
            coefficient: round_div(
              coefficient,
              pow10(0 - digits - exponent),
              mode,
            ),
            exponent: 0 - digits,
          )
      }
      decimal.equal(rounded, expected)
      && decimal.exponent(rounded) == 0 - digits
    },
  )
}

pub fn divide_matches_the_integer_oracle_test() -> Nil {
  metamon.forall(
    generator.tuple6(
      coefficient_generator(),
      generator.int(range.constant(-3, 1)),
      coefficient_generator(),
      generator.int(range.constant(-3, 1)),
      generator.int(range.constant(0, 3)),
      mode_generator(),
    ),
    fn(input) {
      let #(ca, ea, cb, eb, digits, mode) = input
      let a = support.new(coefficient: ca, exponent: ea)
      let b = support.new(coefficient: cb, exponent: eb)
      case cb == 0 {
        True ->
          decimal.divide(a, b, digits: digits, rounding: mode)
          == Error(decimal.DivisionByZero)
        False -> {
          // a / b * 10^digits = ca * 10^(ea - eb + digits) / cb
          let shift = ea - eb + digits
          let #(numerator, denominator) = case shift >= 0 {
            True -> #(ca * pow10(shift), cb)
            False -> #(ca, cb * pow10(0 - shift))
          }
          let #(numerator, denominator) = case denominator < 0 {
            True -> #(0 - numerator, 0 - denominator)
            False -> #(numerator, denominator)
          }
          let expected =
            support.new(
              coefficient: round_div(numerator, denominator, mode),
              exponent: 0 - digits,
            )
          case decimal.divide(a, b, digits: digits, rounding: mode) {
            Ok(quotient) -> decimal.equal(quotient, expected)
            Error(_) -> False
          }
        }
      }
    },
  )
}
