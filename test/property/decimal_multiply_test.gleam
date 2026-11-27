//// Properties of `decimal.multiply` on products whose coefficient
//// passes 2^53 - 1 before the trailing zeros are dropped.
////
//// One property runs on both targets: the product is the same both
//// ways and divides back to a factor exactly. The other compares the
//// product with an oracle written with Erlang's bignums, so it runs on
//// Erlang only.

import gleam/int
import metamon
import metamon/generator.{type Generator}

import finanza/decimal
import support

// 2^53 - 1.
const max = 9_007_199_254_740_991

// 2^52.
const half = 4_503_599_627_370_496

@target(erlang)
fn map_nil_error(
  value: Result(#(Int, Int), Nil),
) -> Result(#(Int, Int), decimal.ArithmeticError) {
  case value {
    Ok(pair) -> Ok(pair)
    Error(Nil) -> Error(decimal.PrecisionExceeded)
  }
}

@target(erlang)
fn parts(value: Result(decimal.Decimal, a)) -> Result(#(Int, Int), a) {
  case value {
    Ok(d) -> Ok(#(decimal.coefficient(d), decimal.exponent(d)))
    Error(error) -> Error(error)
  }
}

fn pow10(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> 10 * pow10(n - 1)
  }
}

/// Coefficients with many trailing zeros, near 2^53 and near 10^k, so
/// products often pass 2^53 and still fit once their zeros go.
fn coefficient_generator() -> Generator(Int) {
  generator.one_of([
    generator.int(generator.range(from: 0 - max, to: max)),
    generator.map2(
      generator.int(generator.range(from: -999_999, to: 999_999)),
      generator.int(generator.range(from: 0, to: 9)),
      fn(digits, zeros) { digits * pow10(zeros) },
    ),
    generator.element_of([
      0,
      1,
      -1,
      10,
      max,
      0 - max,
      half,
      half + 1,
      1_000_000_000_000_000,
      2_500_000_000_000_000,
      8_000_000_000_000_000,
      999_999_999_999_999,
    ]),
  ])
}

/// Decimals across the whole range, often with products past 2^53.
/// Also used by `test/property/rounded_multiply_test.gleam`.
pub fn decimal_generator() -> Generator(decimal.Decimal) {
  generator.map2(
    coefficient_generator(),
    generator.int(generator.range(from: -28, to: 15)),
    fn(coefficient, exponent) {
      case decimal.new(coefficient:, exponent:) {
        Ok(value) -> value
        // Move a large exponent down until the value is in range.
        Error(Nil) -> support.new(coefficient:, exponent: int.min(exponent, 0))
      }
    },
  )
}

/// The product is the same both ways, and dividing it by one factor
/// gives the other back exactly. Runs on both targets.
pub fn product_divides_back_to_the_factor_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 1000),
    generator.tuple2(decimal_generator(), decimal_generator()),
    fn(input) {
      let #(a, b) = input
      let product = decimal.multiply(a, b)
      let swapped = decimal.multiply(b, a)
      assert product == swapped
      case product, decimal.is_zero(b) {
        Ok(_), True -> Nil
        Ok(p), False -> {
          let assert Ok(quotient) =
            decimal.divide(
              p,
              b,
              digits: 0 - decimal.exponent(a),
              rounding: decimal.Down,
            )
          assert decimal.equal(quotient, a)
        }
        Error(_), _ -> Nil
      }
    },
  )
}

// The product drops the fewest trailing zeros that bring the exponent
// to -28 or more and the coefficient within 2^53 - 1, computed here
// with Erlang's bignums.
@target(erlang)
fn oracle(
  a: decimal.Decimal,
  b: decimal.Decimal,
) -> Result(#(Int, Int), decimal.ArithmeticError) {
  let product = decimal.coefficient(a) * decimal.coefficient(b)
  let exponent = decimal.exponent(a) + decimal.exponent(b)
  case product {
    0 -> Ok(#(0, int.clamp(exponent, min: -28, max: 15)))
    _ -> oracle_drop(product, exponent, int.max(0, -28 - exponent))
  }
}

@target(erlang)
fn oracle_drop(
  product: Int,
  exponent: Int,
  drop: Int,
) -> Result(#(Int, Int), decimal.ArithmeticError) {
  let divisor = pow10(drop)
  case product % divisor == 0 {
    False -> Error(decimal.PrecisionExceeded)
    True -> {
      let coefficient = product / divisor
      case int.absolute_value(coefficient) > max {
        True -> oracle_drop(product, exponent, drop + 1)
        False ->
          decimal.new(coefficient:, exponent: exponent + drop)
          |> parts
          |> map_nil_error
      }
    }
  }
}

@target(erlang)
pub fn product_matches_the_bignum_oracle_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 1000),
    generator.tuple2(decimal_generator(), decimal_generator()),
    fn(input) {
      let #(a, b) = input
      assert decimal.multiply(a, b) |> parts == oracle(a, b)
    },
  )
}
