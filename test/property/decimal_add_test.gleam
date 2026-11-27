//// Properties of `decimal.add` and `subtract` on operands whose
//// exponents are far apart, so aligning them often passes 2^53 - 1.
////
//// Two properties run on both targets: the sum is the same both ways,
//// and subtracting one operand from the sum gives the other back
//// exactly, because the sum is exact. The third compares the sum with an
//// oracle written with Erlang's bignums, so it runs on Erlang only.

import metamon
import metamon/generator

import finanza/decimal
import property/decimal_multiply_test

// 2^53 - 1.
@target(erlang)
const max = 9_007_199_254_740_991

fn pairs() {
  generator.tuple2(
    decimal_multiply_test.decimal_generator(),
    decimal_multiply_test.decimal_generator(),
  )
}

/// `a + b` and `b + a` are the same, and `a - b` is `a + (-b)`.
pub fn sum_is_symmetric_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 2000),
    pairs(),
    fn(input) {
      let #(a, b) = input
      assert decimal.add(a, b) == decimal.add(b, a)
      assert decimal.subtract(a, b) == decimal.add(a, decimal.negate(b))
    },
  )
}

/// Whenever `a + b` succeeds, `(a + b) - b` succeeds too and equals `a`.
pub fn sum_subtracts_back_to_the_operand_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 2000),
    pairs(),
    fn(input) {
      let #(a, b) = input
      case decimal.add(a, b) {
        Ok(total) -> {
          let assert Ok(back) = decimal.subtract(total, b)
          assert decimal.equal(back, a)
        }
        Error(_) -> Nil
      }
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

// The exact sum at the smaller exponent, then the fewest trailing zeros
// dropped that bring the coefficient within 2^53 - 1, computed with
// Erlang's bignums. Zero follows the same rule, as in Python's decimal.
@target(erlang)
fn oracle(
  a: decimal.Decimal,
  b: decimal.Decimal,
) -> Result(#(Int, Int), decimal.ArithmeticError) {
  let exponent = case decimal.exponent(a) < decimal.exponent(b) {
    True -> decimal.exponent(a)
    False -> decimal.exponent(b)
  }
  case decimal.is_zero(a), decimal.is_zero(b) {
    True, True -> Ok(#(0, exponent))
    _, _ -> {
      let total =
        decimal.coefficient(a)
        * pow10(decimal.exponent(a) - exponent)
        + decimal.coefficient(b)
        * pow10(decimal.exponent(b) - exponent)
      oracle_drop(total, exponent)
    }
  }
}

@target(erlang)
fn oracle_drop(
  total: Int,
  exponent: Int,
) -> Result(#(Int, Int), decimal.ArithmeticError) {
  case total > max || total < 0 - max, total % 10 == 0 {
    False, _ ->
      case decimal.new(coefficient: total, exponent:) {
        Ok(value) -> Ok(#(decimal.coefficient(value), decimal.exponent(value)))
        Error(Nil) -> Error(decimal.PrecisionExceeded)
      }
    True, True -> oracle_drop(total / 10, exponent + 1)
    True, False -> Error(decimal.PrecisionExceeded)
  }
}

@target(erlang)
fn parts(
  value: Result(decimal.Decimal, decimal.ArithmeticError),
) -> Result(#(Int, Int), decimal.ArithmeticError) {
  case value {
    Ok(d) -> Ok(#(decimal.coefficient(d), decimal.exponent(d)))
    Error(error) -> Error(error)
  }
}

@target(erlang)
pub fn sum_matches_the_bignum_oracle_test() {
  metamon.forall_with(
    metamon.Config(..metamon.default_config(), runs: 2000),
    pairs(),
    fn(input) {
      let #(a, b) = input
      assert parts(decimal.add(a, b)) == oracle(a, b)
      assert parts(decimal.subtract(a, b)) == oracle(a, decimal.negate(b))
    },
  )
}
