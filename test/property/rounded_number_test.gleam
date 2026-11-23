//// The exact numbers the interest functions compute with, against
//// oracles written with Erlang's bignums, so these run on Erlang only.
////
//// `times` and `plus` must be exact, `round` and `divide_round` must
//// round the exact value in every mode, `quotient` and `truncate` must
//// bound the exact value from the side they are asked for, and
//// `limb.divide` must give the integer quotient and remainder of
//// numbers of any size.

@target(erlang)
import gleam/int
@target(erlang)
import gleam/list
import gleam/order
@target(erlang)
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range

@target(erlang)
import finanza/decimal
import finanza/internal/limb
@target(erlang)
import finanza/internal/rounded.{type Number}
@target(erlang)
import property/decimal_multiply_test

/// On both targets, `limb.divide` gives a quotient and remainder that
/// multiply back to the dividend, with the remainder below the divisor,
/// for dividends far past 2^53.
pub fn limb_divide_multiplies_back_test() {
  metamon.forall_with(
    metamon.with_runs_or_panic(metamon.default_config(), 1000),
    generator.tuple4(
      generator.int(range.constant(0, 9_007_199_254_740_991)),
      generator.int(range.constant(0, 9_007_199_254_740_991)),
      generator.int(range.constant(1, 9_007_199_254_740_991)),
      generator.int(range.constant(0, 40)),
    ),
    fn(input) {
      let #(x, y, z, zeros) = input
      let a = limb.shift(limb.multiply(limb.limbs(x), limb.limbs(y)), zeros:)
      let b = limb.multiply(limb.limbs(z), limb.limbs(y + 1))
      let #(quotient, remainder) = limb.divide(a, b)
      let back = limb.add(#(1, limb.multiply(quotient, b)), #(1, remainder)).1
      limb.compare_values(back, a) == order.Eq
      && limb.compare_values(remainder, b) == order.Lt
    },
  )
}

@target(erlang)
fn pow10(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> 10 * pow10(n - 1)
  }
}

// The value of limbs, least significant first.
@target(erlang)
fn value_of(limbs: List(Int)) -> Int {
  list.fold(list.reverse(limbs), 0, fn(total, limb) {
    total * 10_000_000 + limb
  })
}

@target(erlang)
fn limbs_of(value: Int) -> List(Int) {
  value
  |> int.to_string
  |> string.to_graphemes
  |> list.reverse
  |> list.map(fn(digit) {
    case int.parse(digit) {
      Ok(value) -> value
      Error(Nil) -> 0
    }
  })
  |> limb.from_digits
}

// A fraction numerator / denominator with a positive denominator.
@target(erlang)
fn fraction(value: Number) -> #(Int, Int) {
  let magnitude = value.sign * value_of(value.limbs)
  case value.exponent >= 0 {
    True -> #(magnitude * pow10(value.exponent), 1)
    False -> #(magnitude, pow10(0 - value.exponent))
  }
}

@target(erlang)
fn floor_divide(a: Int, b: Int) -> Int {
  let q = a / b
  case a % b < 0 {
    True -> q - 1
    False -> q
  }
}

// numerator / denominator rounded to `digits` places with `mode`.
@target(erlang)
fn oracle_round(
  numerator: Int,
  denominator: Int,
  digits: Int,
  mode: decimal.RoundingMode,
) -> Result(#(Int, Int), Nil) {
  let #(numerator, denominator) = case digits >= 0 {
    True -> #(numerator * pow10(digits), denominator)
    False -> #(numerator, denominator * pow10(0 - digits))
  }
  let floor = floor_divide(numerator, denominator)
  let remainder = numerator - floor * denominator
  let twice = 2 * remainder
  let negative = numerator < 0
  // Rounding toward zero from below is floor for positive values and
  // floor + 1 for negative ones with a remainder.
  let toward_zero = case negative && remainder != 0 {
    True -> floor + 1
    False -> floor
  }
  let away = case remainder != 0 {
    True ->
      case negative {
        True -> floor
        False -> floor + 1
      }
    False -> floor
  }
  let nearest_up = case twice > denominator {
    True -> floor + 1
    False -> floor
  }
  let coefficient = case remainder == 0 {
    True -> floor
    False ->
      case mode {
        decimal.Down -> toward_zero
        decimal.Up -> away
        decimal.Ceiling -> floor + 1
        decimal.Floor -> floor
        decimal.HalfUp ->
          case twice == denominator {
            True -> away
            False -> nearest_up
          }
        decimal.HalfDown ->
          case twice == denominator {
            True -> toward_zero
            False -> nearest_up
          }
        decimal.HalfEven ->
          case twice == denominator {
            True ->
              case floor % 2 == 0 {
                True -> floor
                False -> floor + 1
              }
            False -> nearest_up
          }
      }
  }
  case decimal.new(coefficient:, exponent: 0 - digits) {
    Ok(_) -> Ok(#(coefficient, 0 - digits))
    Error(Nil) -> Error(Nil)
  }
}

@target(erlang)
fn parts(value: Result(decimal.Decimal, a)) -> Result(#(Int, Int), Nil) {
  case value {
    Ok(d) -> Ok(#(decimal.coefficient(d), decimal.exponent(d)))
    Error(_) -> Error(Nil)
  }
}

@target(erlang)
fn mode_generator() -> generator.Generator(decimal.RoundingMode) {
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

@target(erlang)
fn triples() {
  generator.tuple3(
    decimal_multiply_test.decimal_generator(),
    decimal_multiply_test.decimal_generator(),
    decimal_multiply_test.decimal_generator(),
  )
}

// a × b × c + a, a value no Decimal holds in general.
@target(erlang)
fn combined(a, b, c) -> Number {
  let a = rounded.from_decimal(a)
  rounded.plus(
    rounded.times(
      rounded.times(a, rounded.from_decimal(b)),
      rounded.from_decimal(c),
    ),
    a,
  )
}

@target(erlang)
fn config() {
  metamon.with_runs_or_panic(metamon.default_config(), 1000)
}

@target(erlang)
pub fn round_matches_the_bignum_oracle_test() {
  metamon.forall_with(
    config(),
    generator.tuple3(
      triples(),
      generator.int(range.constant(-16, 29)),
      mode_generator(),
    ),
    fn(input) {
      let #(#(a, b, c), digits, mode) = input
      let value = combined(a, b, c)
      let #(numerator, denominator) = fraction(value)
      let expected = case digits < -15 || digits > 28 {
        True -> Error(Nil)
        False -> oracle_round(numerator, denominator, digits, mode)
      }
      parts(rounded.round(value, digits:, rounding: mode)) == expected
    },
  )
}

@target(erlang)
pub fn divide_round_matches_the_bignum_oracle_test() {
  metamon.forall_with(
    config(),
    generator.tuple3(
      triples(),
      generator.int(range.constant(-15, 28)),
      mode_generator(),
    ),
    fn(input) {
      let #(#(a, b, c), digits, mode) = input
      case decimal.is_zero(c) {
        True -> True
        False -> {
          let top = combined(a, b, b)
          let bottom = rounded.from_decimal(c)
          let #(tn, td) = fraction(top)
          let #(bn, bd) = fraction(bottom)
          let #(numerator, denominator) = case bn < 0 {
            True -> #(0 - tn * bd, 0 - td * bn)
            False -> #(tn * bd, td * bn)
          }
          parts(rounded.divide_round(top, bottom, digits:, rounding: mode))
          == oracle_round(numerator, denominator, digits, mode)
        }
      }
    },
  )
}

// a / b <= c / d for positive denominators.
@target(erlang)
fn at_most(a: #(Int, Int), b: #(Int, Int)) -> Bool {
  a.0 * b.1 <= b.0 * a.1
}

@target(erlang)
pub fn quotient_and_truncate_bound_the_exact_value_test() {
  metamon.forall_with(
    config(),
    generator.tuple2(triples(), generator.int(range.constant(1, 6))),
    fn(input) {
      let #(#(a, b, c), precision) = input
      let value = rounded.absolute(combined(a, b, c))
      let divisor = rounded.absolute(rounded.from_decimal(b))
      let exact = fraction(value)
      let truncated =
        at_most(
          fraction(rounded.truncate(value, limbs: precision, up: False)),
          exact,
        )
        && at_most(
          exact,
          fraction(rounded.truncate(value, limbs: precision, up: True)),
        )
        && list.length(
          rounded.truncate(value, limbs: precision, up: False).limbs,
        )
        <= precision
      let divided = case rounded.is_zero(divisor) {
        True -> True
        False -> {
          let #(vn, vd) = exact
          let #(dn, dd) = fraction(divisor)
          let quotient = #(vn * dd, vd * dn)
          let low =
            rounded.quotient(value, divisor, limbs: precision, up: False)
          let high =
            rounded.quotient(value, divisor, limbs: precision, up: True)
          at_most(fraction(low), quotient) && at_most(quotient, fraction(high))
        }
      }
      truncated && divided
    },
  )
}

@target(erlang)
pub fn limb_divide_matches_integer_division_test() {
  metamon.forall_with(
    config(),
    generator.tuple4(
      generator.int(range.constant(0, 9_007_199_254_740_991)),
      generator.int(range.constant(0, 9_007_199_254_740_991)),
      generator.int(range.constant(1, 9_007_199_254_740_991)),
      generator.int(range.constant(0, 40)),
    ),
    fn(input) {
      let #(x, y, z, zeros) = input
      let a = x * y * pow10(zeros) + y
      let b = z * { y + 1 }
      let #(quotient, remainder) = limb.divide(limbs_of(a), limbs_of(b))
      value_of(quotient) == a / b && value_of(remainder) == a % b
    },
  )
}
