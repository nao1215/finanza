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
import finanza/decimal/rounding
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range

fn mode_generator() -> Generator(rounding.Mode) {
  generator.element_of([
    rounding.HalfEven,
    rounding.HalfUp,
    rounding.HalfDown,
    rounding.Up,
    rounding.Down,
    rounding.Ceiling,
    rounding.Floor,
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
fn round_div(numerator: Int, denominator: Int, mode: rounding.Mode) -> Int {
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
        rounding.Down -> q
        rounding.Up -> q + sign
        rounding.Ceiling ->
          case sign > 0 {
            True -> q + 1
            False -> q
          }
        rounding.Floor ->
          case sign < 0 {
            True -> q - 1
            False -> q
          }
        rounding.HalfUp ->
          case twice >= denominator {
            True -> q + sign
            False -> q
          }
        rounding.HalfDown ->
          case twice > denominator {
            True -> q + sign
            False -> q
          }
        rounding.HalfEven ->
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
      let d = decimal.new(coefficient: coefficient, exponent: exponent)
      let rounded = decimal.round(d: d, digits: digits, mode: mode)
      let expected = case exponent >= 0 - digits {
        // Already at or coarser than the target: the value is kept.
        True -> d
        False ->
          decimal.new(
            coefficient: round_div(
              coefficient,
              pow10(0 - digits - exponent),
              mode,
            ),
            exponent: 0 - digits,
          )
      }
      decimal.equal(a: rounded, b: expected)
      && decimal.exponent(d: rounded) == 0 - digits
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
      let a = decimal.new(coefficient: ca, exponent: ea)
      let b = decimal.new(coefficient: cb, exponent: eb)
      case cb == 0 {
        True ->
          decimal.divide(a: a, b: b, digits: digits, mode: mode)
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
            decimal.new(
              coefficient: round_div(numerator, denominator, mode),
              exponent: 0 - digits,
            )
          case decimal.divide(a: a, b: b, digits: digits, mode: mode) {
            Ok(quotient) -> decimal.equal(a: quotient, b: expected)
            Error(_) -> False
          }
        }
      }
    },
  )
}
