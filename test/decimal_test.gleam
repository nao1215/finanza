import gleam/order
import gleeunit/should

import finanza/decimal
import finanza/decimal/rounding

// --- Constructors --------------------------------------------------------

pub fn zero_is_zero_test() -> Nil {
  decimal.is_zero(decimal.zero())
  |> should.be_true
}

pub fn one_is_one_test() -> Nil {
  decimal.equal(decimal.one(), decimal.from_int(1))
  |> should.be_true
}

pub fn from_int_test() -> Nil {
  let value = decimal.from_int(42)
  decimal.coefficient(value)
  |> should.equal(42)
  decimal.exponent(value)
  |> should.equal(0)
}

pub fn new_explicit_test() -> Nil {
  let value = decimal.new(coefficient: 12_345, exponent: -2)
  decimal.coefficient(value)
  |> should.equal(12_345)
  decimal.exponent(value)
  |> should.equal(-2)
}

// --- Parser --------------------------------------------------------------

pub fn parse_integer_test() -> Nil {
  let assert Ok(value) = decimal.from_string("123")
  decimal.coefficient(value)
  |> should.equal(123)
  decimal.exponent(value)
  |> should.equal(0)
}

pub fn parse_decimal_test() -> Nil {
  let assert Ok(value) = decimal.from_string("3.14")
  decimal.coefficient(value)
  |> should.equal(314)
  decimal.exponent(value)
  |> should.equal(-2)
}

pub fn parse_negative_test() -> Nil {
  let assert Ok(value) = decimal.from_string("-0.5")
  decimal.coefficient(value)
  |> should.equal(-5)
  decimal.exponent(value)
  |> should.equal(-1)
}

pub fn parse_positive_sign_test() -> Nil {
  let assert Ok(value) = decimal.from_string("+42.0")
  decimal.coefficient(value)
  |> should.equal(420)
  decimal.exponent(value)
  |> should.equal(-1)
}

pub fn parse_trailing_zeros_preserved_test() -> Nil {
  let assert Ok(value) = decimal.from_string("1.50")
  decimal.coefficient(value)
  |> should.equal(150)
  decimal.exponent(value)
  |> should.equal(-2)
}

pub fn parse_empty_test() -> Nil {
  decimal.from_string("")
  |> should.equal(Error(decimal.EmptyInput))
}

pub fn parse_whitespace_only_test() -> Nil {
  decimal.from_string("   ")
  |> should.equal(Error(decimal.EmptyInput))
}

pub fn parse_double_decimal_test() -> Nil {
  decimal.from_string("1.2.3")
  |> should.equal(Error(decimal.MultipleDecimalPoints))
}

pub fn parse_double_sign_test() -> Nil {
  decimal.from_string("-1-2")
  |> should.equal(Error(decimal.MultipleSigns))
}

pub fn parse_invalid_character_test() -> Nil {
  decimal.from_string("12a3")
  |> should.equal(Error(decimal.InvalidCharacter(char: "a", position: 2)))
}

// --- Rendering -----------------------------------------------------------

pub fn render_integer_test() -> Nil {
  decimal.to_string(decimal.from_int(42))
  |> should.equal("42")
}

pub fn render_zero_test() -> Nil {
  decimal.to_string(decimal.zero())
  |> should.equal("0")
}

pub fn render_zero_with_fraction_test() -> Nil {
  decimal.to_string(decimal.new(coefficient: 0, exponent: -3))
  |> should.equal("0.000")
}

pub fn render_simple_fraction_test() -> Nil {
  decimal.to_string(decimal.new(coefficient: 314, exponent: -2))
  |> should.equal("3.14")
}

pub fn render_small_fraction_test() -> Nil {
  decimal.to_string(decimal.new(coefficient: 5, exponent: -3))
  |> should.equal("0.005")
}

pub fn render_negative_test() -> Nil {
  decimal.to_string(decimal.new(coefficient: -125, exponent: -2))
  |> should.equal("-1.25")
}

pub fn render_negative_small_test() -> Nil {
  decimal.to_string(decimal.new(coefficient: -5, exponent: -3))
  |> should.equal("-0.005")
}

pub fn render_padded_integer_test() -> Nil {
  decimal.to_string(decimal.new(coefficient: 12, exponent: 3))
  |> should.equal("12000")
}

pub fn render_preserves_trailing_zeros_test() -> Nil {
  decimal.to_string(decimal.new(coefficient: 150, exponent: -2))
  |> should.equal("1.50")
}

// --- Sign predicates -----------------------------------------------------

pub fn is_positive_test() -> Nil {
  decimal.is_positive(decimal.from_int(3))
  |> should.be_true
  decimal.is_positive(decimal.from_int(-3))
  |> should.be_false
  decimal.is_positive(decimal.zero())
  |> should.be_false
}

pub fn is_negative_test() -> Nil {
  decimal.is_negative(decimal.from_int(-3))
  |> should.be_true
  decimal.is_negative(decimal.from_int(3))
  |> should.be_false
  decimal.is_negative(decimal.zero())
  |> should.be_false
}

pub fn negate_test() -> Nil {
  let n = decimal.negate(decimal.from_int(5))
  decimal.coefficient(n)
  |> should.equal(-5)
}

pub fn absolute_test() -> Nil {
  let a = decimal.absolute(decimal.from_int(-7))
  decimal.coefficient(a)
  |> should.equal(7)
}

// --- Arithmetic ----------------------------------------------------------

pub fn add_basic_test() -> Nil {
  let assert Ok(sum) = decimal.add(decimal.from_int(2), decimal.from_int(3))
  decimal.equal(sum, decimal.from_int(5))
  |> should.be_true
}

pub fn add_aligns_exponents_test() -> Nil {
  let assert Ok(a) = decimal.from_string("0.1")
  let assert Ok(b) = decimal.from_string("0.2")
  let assert Ok(sum) = decimal.add(a, b)
  decimal.to_string(sum)
  |> should.equal("0.3")
}

pub fn add_mixed_precision_test() -> Nil {
  let assert Ok(a) = decimal.from_string("1.50")
  let assert Ok(b) = decimal.from_string("0.005")
  let assert Ok(sum) = decimal.add(a, b)
  decimal.to_string(sum)
  |> should.equal("1.505")
}

pub fn subtract_test() -> Nil {
  let assert Ok(a) = decimal.from_string("10.00")
  let assert Ok(b) = decimal.from_string("2.50")
  let assert Ok(diff) = decimal.subtract(a, b)
  decimal.to_string(diff)
  |> should.equal("7.50")
}

pub fn multiply_basic_test() -> Nil {
  let assert Ok(a) = decimal.from_string("1.5")
  let assert Ok(b) = decimal.from_string("2")
  let assert Ok(product) = decimal.multiply(a, b)
  decimal.equal(product, decimal.from_int(3))
  |> should.be_true
}

pub fn multiply_fractions_test() -> Nil {
  let assert Ok(a) = decimal.from_string("0.1")
  let assert Ok(b) = decimal.from_string("0.2")
  let assert Ok(product) = decimal.multiply(a, b)
  decimal.to_string(product)
  |> should.equal("0.02")
}

// --- Division and rounding ----------------------------------------------

pub fn divide_exact_test() -> Nil {
  let assert Ok(quotient) =
    decimal.divide(
      decimal.from_int(10),
      decimal.from_int(4),
      2,
      rounding.HalfEven,
    )
  decimal.to_string(quotient)
  |> should.equal("2.50")
}

pub fn divide_rounding_half_even_to_even_test() -> Nil {
  // 7 / 4 = 1.75; rounded to 1 dp via HalfEven → 1.8 (away from 1.7
  // since 1.75 is half between 1.7 (odd) and 1.8 (even)).
  let assert Ok(q) =
    decimal.divide(
      decimal.from_int(7),
      decimal.from_int(4),
      1,
      rounding.HalfEven,
    )
  decimal.to_string(q)
  |> should.equal("1.8")
}

pub fn divide_half_even_ties_to_even_2_test() -> Nil {
  // 5/2 = 2.5 → HalfEven → 2 (even); HalfUp → 3
  let assert Ok(even) =
    decimal.divide(
      decimal.from_int(5),
      decimal.from_int(2),
      0,
      rounding.HalfEven,
    )
  decimal.to_string(even)
  |> should.equal("2")
}

pub fn divide_half_up_test() -> Nil {
  let assert Ok(up) =
    decimal.divide(decimal.from_int(5), decimal.from_int(2), 0, rounding.HalfUp)
  decimal.to_string(up)
  |> should.equal("3")
}

pub fn divide_by_zero_test() -> Nil {
  decimal.divide(decimal.from_int(1), decimal.zero(), 2, rounding.HalfEven)
  |> should.equal(Error(decimal.DivisionByZero))
}

pub fn divide_repeating_test() -> Nil {
  // 1/3 to 4 decimal places: 0.3333
  let assert Ok(q) =
    decimal.divide(
      decimal.from_int(1),
      decimal.from_int(3),
      4,
      rounding.HalfEven,
    )
  decimal.to_string(q)
  |> should.equal("0.3333")
}

pub fn divide_negative_test() -> Nil {
  let assert Ok(q) =
    decimal.divide(
      decimal.from_int(-5),
      decimal.from_int(2),
      0,
      rounding.HalfUp,
    )
  decimal.to_string(q)
  |> should.equal("-3")
}

// --- Round / truncate / rescale -----------------------------------------

pub fn round_half_even_test() -> Nil {
  // 2.5 → 2 (round to even)
  let value = decimal.new(coefficient: 25, exponent: -1)
  decimal.round(value, 0, rounding.HalfEven)
  |> decimal.to_string
  |> should.equal("2")
}

pub fn round_half_even_other_tie_test() -> Nil {
  // 3.5 → 4 (round to even)
  let value = decimal.new(coefficient: 35, exponent: -1)
  decimal.round(value, 0, rounding.HalfEven)
  |> decimal.to_string
  |> should.equal("4")
}

pub fn round_half_up_test() -> Nil {
  let value = decimal.new(coefficient: 25, exponent: -1)
  decimal.round(value, 0, rounding.HalfUp)
  |> decimal.to_string
  |> should.equal("3")
}

pub fn round_half_down_test() -> Nil {
  let value = decimal.new(coefficient: 25, exponent: -1)
  decimal.round(value, 0, rounding.HalfDown)
  |> decimal.to_string
  |> should.equal("2")
}

pub fn round_up_away_from_zero_test() -> Nil {
  let value = decimal.new(coefficient: 21, exponent: -1)
  decimal.round(value, 0, rounding.Up)
  |> decimal.to_string
  |> should.equal("3")
  let negative = decimal.new(coefficient: -21, exponent: -1)
  decimal.round(negative, 0, rounding.Up)
  |> decimal.to_string
  |> should.equal("-3")
}

pub fn round_down_toward_zero_test() -> Nil {
  let value = decimal.new(coefficient: 29, exponent: -1)
  decimal.round(value, 0, rounding.Down)
  |> decimal.to_string
  |> should.equal("2")
  let negative = decimal.new(coefficient: -29, exponent: -1)
  decimal.round(negative, 0, rounding.Down)
  |> decimal.to_string
  |> should.equal("-2")
}

pub fn round_ceiling_test() -> Nil {
  // 2.1 → 3 (toward +∞)
  let value = decimal.new(coefficient: 21, exponent: -1)
  decimal.round(value, 0, rounding.Ceiling)
  |> decimal.to_string
  |> should.equal("3")
  // -2.9 → -2 (toward +∞)
  let negative = decimal.new(coefficient: -29, exponent: -1)
  decimal.round(negative, 0, rounding.Ceiling)
  |> decimal.to_string
  |> should.equal("-2")
}

pub fn round_floor_test() -> Nil {
  // 2.9 → 2 (toward -∞)
  let value = decimal.new(coefficient: 29, exponent: -1)
  decimal.round(value, 0, rounding.Floor)
  |> decimal.to_string
  |> should.equal("2")
  // -2.1 → -3 (toward -∞)
  let negative = decimal.new(coefficient: -21, exponent: -1)
  decimal.round(negative, 0, rounding.Floor)
  |> decimal.to_string
  |> should.equal("-3")
}

pub fn truncate_test() -> Nil {
  let value = decimal.new(coefficient: 29, exponent: -1)
  decimal.truncate(value, 0)
  |> decimal.to_string
  |> should.equal("2")
}

pub fn round_no_op_when_already_coarser_test() -> Nil {
  let value = decimal.from_int(5)
  // rounding to 3 dp shouldn't add zeros
  decimal.round(value, 3, rounding.HalfEven)
  |> decimal.to_string
  |> should.equal("5")
}

pub fn rescale_expand_test() -> Nil {
  let assert Ok(rescaled) =
    decimal.rescale(decimal.from_int(5), -2, rounding.HalfEven)
  decimal.to_string(rescaled)
  |> should.equal("5.00")
}

pub fn rescale_truncate_test() -> Nil {
  // 12.345 → 1 dp via HalfEven → 12.3 (remainder 45 of 100 is below half).
  let assert Ok(rescaled) =
    decimal.rescale(
      decimal.new(coefficient: 12_345, exponent: -3),
      -1,
      rounding.HalfEven,
    )
  decimal.to_string(rescaled)
  |> should.equal("12.3")
}

pub fn rescale_half_even_tie_test() -> Nil {
  // 12.35 → 1 dp via HalfEven → 12.4 (tie, 3 is odd, round to even).
  let assert Ok(rescaled) =
    decimal.rescale(
      decimal.new(coefficient: 1235, exponent: -2),
      -1,
      rounding.HalfEven,
    )
  decimal.to_string(rescaled)
  |> should.equal("12.4")
}

// --- Compare / equal -----------------------------------------------------

pub fn equal_across_representations_test() -> Nil {
  decimal.equal(decimal.new(coefficient: 100, exponent: -2), decimal.one())
  |> should.be_true
}

pub fn equal_distinct_values_test() -> Nil {
  decimal.equal(decimal.from_int(1), decimal.from_int(2))
  |> should.be_false
}

pub fn compare_orders_test() -> Nil {
  decimal.compare(decimal.from_int(1), decimal.from_int(2))
  |> should.equal(order.Lt)
  decimal.compare(decimal.from_int(3), decimal.from_int(1))
  |> should.equal(order.Gt)
  decimal.compare(
    decimal.new(coefficient: 200, exponent: -2),
    decimal.from_int(2),
  )
  |> should.equal(order.Eq)
}

pub fn compare_mixed_signs_test() -> Nil {
  decimal.compare(decimal.from_int(-5), decimal.from_int(1))
  |> should.equal(order.Lt)
}

// --- Round-trip property -------------------------------------------------

pub fn from_to_string_round_trip_test() -> Nil {
  let inputs = ["0", "1", "-1", "3.14", "-0.005", "1234.5678", "0.0"]
  inputs
  |> list_iter(fn(s) {
    let assert Ok(parsed) = decimal.from_string(s)
    decimal.to_string(parsed)
    |> should.equal(s)
  })
}

fn list_iter(items: List(a), f: fn(a) -> Nil) -> Nil {
  case items {
    [] -> Nil
    [head, ..tail] -> {
      f(head)
      list_iter(tail, f)
    }
  }
}
