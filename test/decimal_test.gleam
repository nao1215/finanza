import gleam/list
import gleam/order
import gleam/string
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

pub fn from_float_half_test() -> Nil {
  let assert Ok(value) = decimal.from_float(0.5)
  decimal.equal(value, decimal.new(coefficient: 5, exponent: -1))
  |> should.be_true
}

pub fn from_float_zero_test() -> Nil {
  let assert Ok(value) = decimal.from_float(0.0)
  decimal.is_zero(value)
  |> should.be_true
}

pub fn from_float_negative_test() -> Nil {
  let assert Ok(value) = decimal.from_float(-1.25)
  decimal.equal(value, decimal.new(coefficient: -125, exponent: -2))
  |> should.be_true
}

pub fn from_string_accepts_lowercase_e_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1e10")
  decimal.to_string(d) |> should.equal("10000000000")
}

pub fn from_string_accepts_uppercase_e_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1E10")
  decimal.to_string(d) |> should.equal("10000000000")
}

pub fn from_string_accepts_positive_exponent_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1.5e+2")
  decimal.to_string(d) |> should.equal("150")
}

pub fn from_string_accepts_negative_exponent_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1e-10")
  decimal.to_string(d) |> should.equal("0.0000000001")
}

pub fn from_string_accepts_fractional_with_exponent_test() -> Nil {
  let assert Ok(d) = decimal.from_string("3.14e2")
  decimal.to_string(d) |> should.equal("314")
}

pub fn from_string_rejects_empty_exponent_test() -> Nil {
  decimal.from_string("1e")
  |> should.equal(Error(decimal.InvalidCharacter(char: "e", position: 1)))
}

pub fn from_string_rejects_garbage_exponent_test() -> Nil {
  decimal.from_string("1eXYZ")
  |> should.equal(Error(decimal.InvalidCharacter(char: "e", position: 1)))
}

pub fn max_safe_digits_is_at_least_15_test() -> Nil {
  // The documented unit-magnitude precision ceiling.
  { decimal.max_safe_digits >= 15 }
  |> should.be_true
}

pub fn divide_at_max_safe_digits_for_one_over_seven_succeeds_test() -> Nil {
  // Unit-magnitude operands at the documented ceiling round-trip
  // without `PrecisionExceeded`.
  let assert Ok(result) =
    decimal.divide(
      a: decimal.from_int(1),
      b: decimal.from_int(7),
      digits: decimal.max_safe_digits,
      mode: rounding.HalfEven,
    )
  decimal.to_string(result)
  |> should.equal("0.142857142857143")
}

pub fn divide_above_max_safe_digits_exceeds_precision_test() -> Nil {
  // Documented failure mode: `digits = max_safe_digits + 1` already
  // exceeds the safe coefficient bound for unit-magnitude operands.
  case
    decimal.divide(
      a: decimal.from_int(1),
      b: decimal.from_int(7),
      digits: decimal.max_safe_digits + 1,
      mode: rounding.HalfEven,
    )
  {
    Error(decimal.PrecisionExceeded) -> Nil
    _ -> should.fail()
  }
}

pub fn format_checked_multi_char_thousands_rejected_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1234.5")
  decimal.format_checked(d: d, thousands: "ab", decimal_separator: ".")
  |> should.equal(
    Error(decimal.MultiCharSeparator(field: "thousands", value: "ab")),
  )
}

pub fn format_checked_multi_char_decimal_rejected_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1234.5")
  decimal.format_checked(d: d, thousands: ",", decimal_separator: ",,")
  |> should.equal(
    Error(decimal.MultiCharSeparator(field: "decimal", value: ",,")),
  )
}

pub fn format_checked_colliding_separators_rejected_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1234.5")
  decimal.format_checked(d: d, thousands: ".", decimal_separator: ".")
  |> should.equal(Error(decimal.SeparatorsCollide(value: ".")))
}

pub fn format_checked_empty_decimal_separator_rejected_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1234.5")
  decimal.format_checked(d: d, thousands: ",", decimal_separator: "")
  |> should.equal(Error(decimal.EmptyDecimalSeparator))
}

pub fn format_checked_accepts_standard_locale_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1234567.89")
  decimal.format_checked(d: d, thousands: ",", decimal_separator: ".")
  |> should.equal(Ok("1,234,567.89"))
  decimal.format_checked(d: d, thousands: ".", decimal_separator: ",")
  |> should.equal(Ok("1.234.567,89"))
}

pub fn format_checked_accepts_empty_thousands_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1234.5")
  decimal.format_checked(d: d, thousands: "", decimal_separator: ".")
  |> should.equal(Ok("1234.5"))
}

pub fn new_explicit_test() -> Nil {
  let value = decimal.new(coefficient: 12_345, exponent: -2)
  decimal.coefficient(value)
  |> should.equal(12_345)
  decimal.exponent(value)
  |> should.equal(-2)
}

// Issue #75 (re-verification of #25): round must pad to exactly `digits`
// decimal places. A coarser-precision input is zero-padded so the rendered
// form always carries `digits` fractional places — the only useful contract
// for monetary formatting (`to_string(round(d, 2)) == "12.30"`, never "12.3").
// Regression guard: these cases come straight from the issue's Definition of
// Done and pin the padding behaviour so the trim-only contract cannot creep
// back in.
pub fn round_pads_to_requested_digits_test() -> Nil {
  let cases = [
    #("1", 2, "1.00"),
    #("1", 4, "1.0000"),
    #("100", 2, "100.00"),
    #("0.1", 4, "0.1000"),
    #("1.5", 4, "1.5000"),
    #("1.5", 0, "2"),
    #("1.50", 2, "1.50"),
    #("0", 3, "0.000"),
    #("2000", 2, "2000.00"),
  ]
  list.each(cases, fn(c) {
    let #(input, digits, expected) = c
    let assert Ok(d) = decimal.from_string(input)
    decimal.round(d, digits, rounding.HalfEven)
    |> decimal.to_string
    |> should.equal(expected)
  })
}

pub fn round_result_exponent_is_negative_digits_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1")
  let rounded = decimal.round(d, 2, rounding.HalfEven)
  decimal.exponent(rounded) |> should.equal(-2)
}

// round is the non-failing form of rescale targeting exponent -digits;
// for any in-range value the two must agree, so they cannot drift apart.
pub fn round_agrees_with_rescale_for_padding_test() -> Nil {
  let assert Ok(d) = decimal.from_string("7")
  let assert Ok(via_rescale) = decimal.rescale(d, -3, rounding.HalfEven)
  decimal.round(d, 3, rounding.HalfEven)
  |> decimal.to_string
  |> should.equal(decimal.to_string(via_rescale))
}

pub fn rescale_pads_when_input_is_coarser_test() -> Nil {
  let assert Ok(two_k_padded) =
    decimal.rescale(
      d: decimal.from_int(2000),
      target_exponent: -2,
      mode: rounding.HalfEven,
    )
  decimal.to_string(two_k_padded)
  |> should.equal("2000.00")
  let assert Ok(one_padded) =
    decimal.rescale(
      d: decimal.one(),
      target_exponent: -4,
      mode: rounding.HalfEven,
    )
  decimal.to_string(one_padded)
  |> should.equal("1.0000")
}

// Issue #23: try_new rejects coefficients whose rendered form would
// exceed max_safe_coefficient. Without this guard, to_string(new(c, e))
// could produce a digit string that from_string refuses to parse,
// breaking the round-trip property.
//
// The "coefficient exactly one above the safe ceiling" probe is only
// meaningful on Erlang: on JavaScript the literal is itself outside
// the IEEE 754 safe-integer range, and the Gleam compiler refuses it
// at warnings-as-errors. The rendered-overflow probes (next test)
// cover both targets because they multiply small literals at runtime.
@target(erlang)
pub fn try_new_rejects_overlarge_coefficient_test() -> Nil {
  decimal.try_from_int(n: 9_007_199_254_740_992)
  |> should.equal(Error(decimal.CoefficientTooLarge))
  decimal.try_new(coefficient: 9_007_199_254_740_992, exponent: 0)
  |> should.equal(Error(decimal.CoefficientTooLarge))
  decimal.try_new(coefficient: -9_007_199_254_740_992, exponent: 0)
  |> should.equal(Error(decimal.CoefficientTooLarge))
}

pub fn try_new_rejects_overlarge_rendered_value_test() -> Nil {
  // |c| * 10^e exceeds max_safe_coefficient (9_007_199_254_740_991 ≈ 9e15)
  decimal.try_new(coefficient: 1, exponent: 20)
  |> should.equal(Error(decimal.CoefficientTooLarge))
  decimal.try_new(coefficient: 5, exponent: 16)
  |> should.equal(Error(decimal.CoefficientTooLarge))
  decimal.try_new(coefficient: 1, exponent: 16)
  |> should.equal(Error(decimal.CoefficientTooLarge))
}

// Issue #67: the panic message from `decimal.new` used to always
// claim `|coefficient| > 9007199254740991`, even on the
// rendered-overflow path where `|coefficient|` was demonstrably tiny
// (e.g. `new(1, 19)`). The message now distinguishes the two paths.
// The panic itself can't be asserted directly with gleeunit; the
// `new_overflow_message/2` helper is exposed `@internal` precisely so
// the message construction is covered.
pub fn new_overflow_message_rendered_path_omits_coefficient_claim_test() -> Nil {
  let msg = decimal.new_overflow_message(coefficient: 1, exponent: 19)
  string.contains(msg, "|coefficient| > 9007199254740991")
  |> should.be_false
}

pub fn new_overflow_message_rendered_path_names_rendered_value_test() -> Nil {
  let msg = decimal.new_overflow_message(coefficient: 1, exponent: 19)
  string.contains(msg, "rendered value") |> should.be_true
  string.contains(msg, "10^19") |> should.be_true
}

@target(erlang)
pub fn new_overflow_message_coefficient_path_unchanged_test() -> Nil {
  let msg =
    decimal.new_overflow_message(
      coefficient: 9_007_199_254_740_992,
      exponent: 0,
    )
  string.contains(msg, "|coefficient| > 9007199254740991")
  |> should.be_true
  string.contains(msg, "rendered value") |> should.be_false
}

pub fn new_overflow_message_negative_coefficient_uses_absolute_value_test() -> Nil {
  // -1 × 10^19 also overflows the rendered range — the message should
  // talk about the rendered path and report the absolute value.
  let msg = decimal.new_overflow_message(coefficient: -1, exponent: 19)
  string.contains(msg, "rendered value") |> should.be_true
  string.contains(msg, "1 × 10^19") |> should.be_true
}

pub fn try_new_accepts_boundary_values_test() -> Nil {
  let assert Ok(_) =
    decimal.try_new(coefficient: 9_007_199_254_740_991, exponent: 0)
  let assert Ok(_) =
    decimal.try_new(coefficient: -9_007_199_254_740_991, exponent: 0)
  // 1 * 10^15 = 1_000_000_000_000_000 ≤ max
  let assert Ok(_) = decimal.try_new(coefficient: 1, exponent: 15)
  // 9 * 10^15 = 9_000_000_000_000_000 ≤ max
  let assert Ok(_) = decimal.try_new(coefficient: 9, exponent: 15)
  // Negative exponents are unaffected — only |coefficient| is bounded.
  let assert Ok(_) =
    decimal.try_new(coefficient: 9_007_199_254_740_991, exponent: -100)
  Nil
}

pub fn round_trip_holds_for_every_try_new_test() -> Nil {
  // For any Decimal built through try_new, from_string(to_string(d))
  // returns the same Decimal.
  let cases = [
    decimal.try_new(coefficient: 1, exponent: 15),
    decimal.try_new(coefficient: 9_007_199_254_740_991, exponent: 0),
    decimal.try_new(coefficient: -9_007_199_254_740_991, exponent: -3),
    decimal.try_new(coefficient: 12_345, exponent: -2),
    decimal.try_from_int(n: 0),
    decimal.try_from_int(n: 9_007_199_254_740_991),
  ]
  list.each(cases, fn(result) {
    let assert Ok(d) = result
    let assert Ok(parsed) = decimal.from_string(decimal.to_string(d))
    decimal.equal(d, parsed)
    |> should.be_true
  })
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

// --- decimal.format ------------------------------------------------------

pub fn format_basic_test() -> Nil {
  let d = decimal.new(coefficient: 1_234_567, exponent: -2)
  decimal.format(d: d, thousands: ",", decimal_separator: ".")
  |> should.equal("12,345.67")
}

pub fn format_integer_only_test() -> Nil {
  let d = decimal.from_int(n: 1_234_567)
  decimal.format(d: d, thousands: ",", decimal_separator: ".")
  |> should.equal("1,234,567")
}

pub fn format_negative_test() -> Nil {
  let d = decimal.new(coefficient: -1_234_567, exponent: -2)
  decimal.format(d: d, thousands: ",", decimal_separator: ".")
  |> should.equal("-12,345.67")
}

pub fn format_german_style_test() -> Nil {
  let d = decimal.new(coefficient: 1_234_567, exponent: -2)
  decimal.format(d: d, thousands: ".", decimal_separator: ",")
  |> should.equal("12.345,67")
}

pub fn format_no_thousands_separator_test() -> Nil {
  let d = decimal.new(coefficient: 1_234_567, exponent: -2)
  decimal.format(d: d, thousands: "", decimal_separator: ".")
  |> should.equal("12345.67")
}

pub fn format_short_integer_test() -> Nil {
  let d = decimal.from_int(n: 42)
  decimal.format(d: d, thousands: ",", decimal_separator: ".")
  |> should.equal("42")
}

pub fn format_zero_test() -> Nil {
  decimal.format(d: decimal.zero(), thousands: ",", decimal_separator: ".")
  |> should.equal("0")
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

pub fn add_large_negative_exponent_plus_zero_returns_operand_test() -> Nil {
  let tiny = decimal.new(coefficient: 1, exponent: -20)
  let assert Ok(sum) = decimal.add(tiny, decimal.zero())
  decimal.equal(sum, tiny)
  |> should.be_true
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

pub fn round_pads_integer_to_requested_dp_test() -> Nil {
  let value = decimal.from_int(5)
  // rounding an integer to 3 dp pads to exactly 3 fractional places (#75)
  decimal.round(value, 3, rounding.HalfEven)
  |> decimal.to_string
  |> should.equal("5.000")
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

// --- to_int / to_int_truncated / to_int_rounded -------------------------

pub fn to_int_integer_valued_test() -> Nil {
  decimal.to_int(decimal.from_int(7))
  |> should.equal(Ok(7))
}

pub fn to_int_trailing_zeros_succeed_test() -> Nil {
  // "12.00" → coefficient 1200, exponent -2; cleanly divisible.
  let assert Ok(d) = decimal.from_string("12.00")
  decimal.to_int(d)
  |> should.equal(Ok(12))
}

pub fn to_int_fractional_part_rejected_test() -> Nil {
  let assert Ok(d) = decimal.from_string("12.34")
  decimal.to_int(d)
  |> should.equal(Error(decimal.PrecisionExceeded))
}

pub fn to_int_negative_value_test() -> Nil {
  let assert Ok(d) = decimal.from_string("-7")
  decimal.to_int(d)
  |> should.equal(Ok(-7))
}

pub fn to_int_truncated_drops_positive_fraction_test() -> Nil {
  let assert Ok(d) = decimal.from_string("1.9")
  decimal.to_int_truncated(d)
  |> should.equal(Ok(1))
}

pub fn to_int_truncated_drops_negative_fraction_test() -> Nil {
  // Round toward zero — `-1.9` becomes `-1`, not `-2`.
  let assert Ok(d) = decimal.from_string("-1.9")
  decimal.to_int_truncated(d)
  |> should.equal(Ok(-1))
}

pub fn to_int_rounded_half_even_test() -> Nil {
  let value = decimal.new(coefficient: 25, exponent: -1)
  decimal.to_int_rounded(d: value, mode: rounding.HalfEven)
  |> should.equal(Ok(2))
}

pub fn to_int_rounded_half_up_test() -> Nil {
  let value = decimal.new(coefficient: 25, exponent: -1)
  decimal.to_int_rounded(d: value, mode: rounding.HalfUp)
  |> should.equal(Ok(3))
}

pub fn to_int_rounded_matches_rescale_pattern_test() -> Nil {
  // The rounded integer should match the coefficient of a manual
  // rescale to exponent 0 with the same mode.
  let assert Ok(d) = decimal.from_string("3.14159")
  let assert Ok(rescaled) = decimal.rescale(d, 0, rounding.HalfEven)
  let via_to_int =
    decimal.to_int_rounded(d: d, mode: rounding.HalfEven)
    |> should.be_ok
  via_to_int |> should.equal(decimal.coefficient(rescaled))
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
