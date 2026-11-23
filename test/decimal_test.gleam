import gleam/list
import gleam/order
import gleam/result
import gleeunit/should

import finanza/decimal
import support

// --- Constructors --------------------------------------------------------

pub fn zero_is_zero_test() -> Nil {
  decimal.is_zero(decimal.zero())
  |> should.be_true
}

pub fn one_is_one_test() -> Nil {
  decimal.equal(decimal.one(), support.int(1))
  |> should.be_true
}

pub fn from_int_test() -> Nil {
  let value = support.int(42)
  decimal.coefficient(value)
  |> should.equal(42)
  decimal.exponent(value)
  |> should.equal(0)
}

pub fn from_float_half_test() -> Nil {
  let assert Ok(value) = decimal.from_float(0.5)
  decimal.equal(value, support.new(coefficient: 5, exponent: -1))
  |> should.be_true
}

pub fn from_float_zero_test() -> Nil {
  let assert Ok(value) = decimal.from_float(0.0)
  decimal.is_zero(value)
  |> should.be_true
}

pub fn from_float_negative_test() -> Nil {
  let assert Ok(value) = decimal.from_float(-1.25)
  decimal.equal(value, support.new(coefficient: -125, exponent: -2))
  |> should.be_true
}

pub fn parse_accepts_lowercase_e_test() -> Nil {
  let assert Ok(d) = decimal.parse("1e10")
  decimal.to_string(d) |> should.equal("10000000000")
}

pub fn parse_accepts_uppercase_e_test() -> Nil {
  let assert Ok(d) = decimal.parse("1E10")
  decimal.to_string(d) |> should.equal("10000000000")
}

pub fn parse_accepts_positive_exponent_test() -> Nil {
  let assert Ok(d) = decimal.parse("1.5e+2")
  decimal.to_string(d) |> should.equal("150")
}

pub fn parse_accepts_negative_exponent_test() -> Nil {
  let assert Ok(d) = decimal.parse("1e-10")
  decimal.to_string(d) |> should.equal("0.0000000001")
}

pub fn parse_accepts_fractional_with_exponent_test() -> Nil {
  let assert Ok(d) = decimal.parse("3.14e2")
  decimal.to_string(d) |> should.equal("314")
}

pub fn parse_rejects_empty_exponent_test() -> Nil {
  decimal.parse("1e")
  |> should.equal(Error(decimal.InvalidCharacter(character: "e", position: 1)))
}

pub fn parse_rejects_garbage_exponent_test() -> Nil {
  decimal.parse("1eXYZ")
  |> should.equal(Error(decimal.InvalidCharacter(character: "e", position: 1)))
}

pub fn divide_at_max_safe_digits_for_one_over_seven_succeeds_test() -> Nil {
  // Unit-magnitude operands at the documented ceiling round-trip
  // without `PrecisionExceeded`.
  let assert Ok(result) =
    decimal.divide(
      support.int(1),
      support.int(7),
      digits: 15,
      rounding: decimal.HalfEven,
    )
  decimal.to_string(result)
  |> should.equal("0.142857142857143")
}

pub fn divide_above_max_safe_digits_exceeds_precision_test() -> Nil {
  // 1/7 at 16 places is 1428571428571429, within 2^53 - 1; at 17 places
  // the coefficient passes it.
  case
    decimal.divide(
      support.int(1),
      support.int(7),
      digits: 17,
      rounding: decimal.HalfEven,
    )
  {
    Error(decimal.PrecisionExceeded) -> Nil
    _ -> should.fail()
  }
}

pub fn new_explicit_test() -> Nil {
  let value = support.new(coefficient: 12_345, exponent: -2)
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
    let assert Ok(d) = decimal.parse(input)
    support.round(d, digits, decimal.HalfEven)
    |> decimal.to_string
    |> should.equal(expected)
  })
}

pub fn round_result_exponent_is_negative_digits_test() -> Nil {
  let assert Ok(d) = decimal.parse("1")
  let rounded = support.round(d, 2, decimal.HalfEven)
  decimal.exponent(rounded) |> should.equal(-2)
}

// round is the non-failing form of rescale targeting exponent -digits;
// for any in-range value the two must agree, so they cannot drift apart.
pub fn round_agrees_with_rescale_for_padding_test() -> Nil {
  let assert Ok(d) = decimal.parse("7")
  let assert Ok(via_rescale) =
    decimal.round(d, digits: 3, rounding: decimal.HalfEven)
  support.round(d, 3, decimal.HalfEven)
  |> decimal.to_string
  |> should.equal(decimal.to_string(via_rescale))
}

pub fn rescale_pads_when_input_is_coarser_test() -> Nil {
  let assert Ok(two_k_padded) =
    decimal.round(support.int(2000), digits: 2, rounding: decimal.HalfEven)
  decimal.to_string(two_k_padded)
  |> should.equal("2000.00")
  let assert Ok(one_padded) =
    decimal.round(decimal.one(), digits: 4, rounding: decimal.HalfEven)
  decimal.to_string(one_padded)
  |> should.equal("1.0000")
}

// Issue #23: try_new rejects coefficients whose rendered form would
// exceed max_safe_coefficient. Without this guard, to_string(new(c, e))
// could produce a digit string that parse refuses to parse,
// breaking the round-trip property.
//
// The "coefficient exactly one above the safe ceiling" probe is only
// meaningful on Erlang: on JavaScript the literal is itself outside
// the IEEE 754 safe-integer range, and the Gleam compiler refuses it
// at warnings-as-errors. The rendered-overflow probes (next test)
// cover both targets because they multiply small literals at runtime.
@target(erlang)
pub fn try_new_rejects_overlarge_coefficient_test() -> Nil {
  decimal.from_int(9_007_199_254_740_992)
  |> should.equal(Error(Nil))
  decimal.new(coefficient: 9_007_199_254_740_992, exponent: 0)
  |> should.equal(Error(Nil))
  decimal.new(coefficient: -9_007_199_254_740_992, exponent: 0)
  |> should.equal(Error(Nil))
}

pub fn try_new_rejects_overlarge_rendered_value_test() -> Nil {
  // |c| * 10^e exceeds max_safe_coefficient (9_007_199_254_740_991 ≈ 9e15)
  decimal.new(coefficient: 1, exponent: 20)
  |> should.equal(Error(Nil))
  decimal.new(coefficient: 5, exponent: 16)
  |> should.equal(Error(Nil))
  decimal.new(coefficient: 1, exponent: 16)
  |> should.equal(Error(Nil))
}

@target(erlang)
pub fn try_new_accepts_boundary_values_test() -> Nil {
  let assert Ok(_) =
    decimal.new(coefficient: 9_007_199_254_740_991, exponent: 0)
  let assert Ok(_) =
    decimal.new(coefficient: -9_007_199_254_740_991, exponent: 0)
  // 1 * 10^15 = 1_000_000_000_000_000 ≤ max
  let assert Ok(_) = decimal.new(coefficient: 1, exponent: 15)
  // 9 * 10^15 = 9_000_000_000_000_000 ≤ max
  let assert Ok(_) = decimal.new(coefficient: 9, exponent: 15)
  // The smallest exponent is -28.
  let assert Ok(_) =
    decimal.new(coefficient: 9_007_199_254_740_991, exponent: -28)
  Nil
}

pub fn round_trip_holds_for_every_try_new_test() -> Nil {
  // For any Decimal built through try_new, parse(to_string(d))
  // returns the same Decimal.
  let cases = [
    decimal.new(coefficient: 1, exponent: 15),
    decimal.new(coefficient: 9_007_199_254_740_991, exponent: 0),
    decimal.new(coefficient: -9_007_199_254_740_991, exponent: -3),
    decimal.new(coefficient: 12_345, exponent: -2),
    decimal.from_int(0),
    decimal.from_int(9_007_199_254_740_991),
  ]
  list.each(cases, fn(result) {
    let assert Ok(d) = result
    let assert Ok(parsed) = decimal.parse(decimal.to_string(d))
    decimal.equal(d, parsed)
    |> should.be_true
  })
}

// --- Parser --------------------------------------------------------------

pub fn parse_integer_test() -> Nil {
  let assert Ok(value) = decimal.parse("123")
  decimal.coefficient(value)
  |> should.equal(123)
  decimal.exponent(value)
  |> should.equal(0)
}

pub fn parse_decimal_test() -> Nil {
  let assert Ok(value) = decimal.parse("3.14")
  decimal.coefficient(value)
  |> should.equal(314)
  decimal.exponent(value)
  |> should.equal(-2)
}

pub fn parse_negative_test() -> Nil {
  let assert Ok(value) = decimal.parse("-0.5")
  decimal.coefficient(value)
  |> should.equal(-5)
  decimal.exponent(value)
  |> should.equal(-1)
}

pub fn parse_positive_sign_test() -> Nil {
  let assert Ok(value) = decimal.parse("+42.0")
  decimal.coefficient(value)
  |> should.equal(420)
  decimal.exponent(value)
  |> should.equal(-1)
}

pub fn parse_trailing_zeros_preserved_test() -> Nil {
  let assert Ok(value) = decimal.parse("1.50")
  decimal.coefficient(value)
  |> should.equal(150)
  decimal.exponent(value)
  |> should.equal(-2)
}

pub fn parse_empty_test() -> Nil {
  decimal.parse("")
  |> should.equal(Error(decimal.EmptyInput))
}

pub fn parse_whitespace_only_test() -> Nil {
  decimal.parse("   ")
  |> should.equal(Error(decimal.EmptyInput))
}

// Issue #74: parse trims leading/trailing *Unicode* whitespace, not
// only ASCII. Real-world inputs — copy/paste from web pages, locale currency
// formatting, CSV/Excel exports — carry NO-BREAK SPACE (U+00A0), NARROW NBSP
// (U+202F), IDEOGRAPHIC SPACE (U+3000) and friends; the old ASCII-only trim
// rejected them with a confusing InvalidCharacter that rendered the offending
// codepoint as a plain space. These pin the documented lenient contract so the
// ASCII-only surprise cannot return.
pub fn parse_trims_ascii_whitespace_test() -> Nil {
  let assert Ok(value) = decimal.parse(" \t1.5\n ")
  decimal.to_string(value) |> should.equal("1.5")
}

pub fn parse_trims_nbsp_test() -> Nil {
  let assert Ok(value) = decimal.parse("\u{00a0}1.5\u{00a0}")
  decimal.to_string(value) |> should.equal("1.5")
}

pub fn parse_trims_narrow_nbsp_test() -> Nil {
  let assert Ok(value) = decimal.parse("\u{202f}1.5\u{202f}")
  decimal.to_string(value) |> should.equal("1.5")
}

pub fn parse_trims_ideographic_space_test() -> Nil {
  let assert Ok(value) = decimal.parse("\u{3000}42\u{3000}")
  decimal.to_string(value) |> should.equal("42")
}

pub fn parse_trims_mixed_unicode_whitespace_test() -> Nil {
  // en/em/thin spaces (U+2002/U+2003/U+2009) and a line separator (U+2028).
  let assert Ok(value) = decimal.parse("\u{2002}\u{2003}\u{2009}-0.25\u{2028}")
  decimal.to_string(value) |> should.equal("-0.25")
}

pub fn parse_all_unicode_whitespace_is_empty_input_test() -> Nil {
  decimal.parse("\u{00a0}\u{3000}\u{202f}")
  |> should.equal(Error(decimal.EmptyInput))
}

pub fn parse_inner_unicode_whitespace_still_rejected_test() -> Nil {
  // Trimming is leading/trailing only — an inner NBSP is still invalid,
  // surfaced at its grapheme position rather than silently stripped.
  decimal.parse("1\u{00a0}5")
  |> should.equal(
    Error(decimal.InvalidCharacter(character: "\u{00a0}", position: 1)),
  )
}

pub fn parse_double_decimal_test() -> Nil {
  decimal.parse("1.2.3")
  |> should.equal(Error(decimal.MultipleDecimalPoints))
}

pub fn parse_double_sign_test() -> Nil {
  decimal.parse("-1-2")
  |> should.equal(Error(decimal.MultipleSigns))
}

pub fn parse_invalid_character_test() -> Nil {
  decimal.parse("12a3")
  |> should.equal(Error(decimal.InvalidCharacter(character: "a", position: 2)))
}

// --- Rendering -----------------------------------------------------------

pub fn render_integer_test() -> Nil {
  decimal.to_string(support.int(42))
  |> should.equal("42")
}

pub fn render_zero_test() -> Nil {
  decimal.to_string(decimal.zero())
  |> should.equal("0")
}

pub fn render_zero_with_fraction_test() -> Nil {
  decimal.to_string(support.new(coefficient: 0, exponent: -3))
  |> should.equal("0.000")
}

pub fn render_simple_fraction_test() -> Nil {
  decimal.to_string(support.new(coefficient: 314, exponent: -2))
  |> should.equal("3.14")
}

pub fn render_small_fraction_test() -> Nil {
  decimal.to_string(support.new(coefficient: 5, exponent: -3))
  |> should.equal("0.005")
}

pub fn render_negative_test() -> Nil {
  decimal.to_string(support.new(coefficient: -125, exponent: -2))
  |> should.equal("-1.25")
}

pub fn render_negative_small_test() -> Nil {
  decimal.to_string(support.new(coefficient: -5, exponent: -3))
  |> should.equal("-0.005")
}

pub fn render_padded_integer_test() -> Nil {
  decimal.to_string(support.new(coefficient: 12, exponent: 3))
  |> should.equal("12000")
}

pub fn render_preserves_trailing_zeros_test() -> Nil {
  decimal.to_string(support.new(coefficient: 150, exponent: -2))
  |> should.equal("1.50")
}

// --- decimal.format ------------------------------------------------------

pub fn format_basic_test() -> Nil {
  let d = support.new(coefficient: 1_234_567, exponent: -2)
  decimal.format(d, thousands: ",", decimal_separator: ".")
  |> should.equal("12,345.67")
}

pub fn format_integer_only_test() -> Nil {
  let d = support.int(1_234_567)
  decimal.format(d, thousands: ",", decimal_separator: ".")
  |> should.equal("1,234,567")
}

pub fn format_negative_test() -> Nil {
  let d = support.new(coefficient: -1_234_567, exponent: -2)
  decimal.format(d, thousands: ",", decimal_separator: ".")
  |> should.equal("-12,345.67")
}

pub fn format_german_style_test() -> Nil {
  let d = support.new(coefficient: 1_234_567, exponent: -2)
  decimal.format(d, thousands: ".", decimal_separator: ",")
  |> should.equal("12.345,67")
}

pub fn format_no_thousands_separator_test() -> Nil {
  let d = support.new(coefficient: 1_234_567, exponent: -2)
  decimal.format(d, thousands: "", decimal_separator: ".")
  |> should.equal("12345.67")
}

pub fn format_short_integer_test() -> Nil {
  let d = support.int(42)
  decimal.format(d, thousands: ",", decimal_separator: ".")
  |> should.equal("42")
}

pub fn format_zero_test() -> Nil {
  decimal.format(decimal.zero(), thousands: ",", decimal_separator: ".")
  |> should.equal("0")
}

// --- Sign predicates -----------------------------------------------------

pub fn is_positive_test() -> Nil {
  decimal.is_positive(support.int(3))
  |> should.be_true
  decimal.is_positive(support.int(-3))
  |> should.be_false
  decimal.is_positive(decimal.zero())
  |> should.be_false
}

pub fn is_negative_test() -> Nil {
  decimal.is_negative(support.int(-3))
  |> should.be_true
  decimal.is_negative(support.int(3))
  |> should.be_false
  decimal.is_negative(decimal.zero())
  |> should.be_false
}

pub fn negate_test() -> Nil {
  let n = decimal.negate(support.int(5))
  decimal.coefficient(n)
  |> should.equal(-5)
}

pub fn absolute_test() -> Nil {
  let a = decimal.absolute(support.int(-7))
  decimal.coefficient(a)
  |> should.equal(7)
}

// --- Arithmetic ----------------------------------------------------------

pub fn add_basic_test() -> Nil {
  let assert Ok(sum) = decimal.add(support.int(2), support.int(3))
  decimal.equal(sum, support.int(5))
  |> should.be_true
}

pub fn add_aligns_exponents_test() -> Nil {
  let assert Ok(a) = decimal.parse("0.1")
  let assert Ok(b) = decimal.parse("0.2")
  let assert Ok(sum) = decimal.add(a, b)
  decimal.to_string(sum)
  |> should.equal("0.3")
}

pub fn add_mixed_precision_test() -> Nil {
  let assert Ok(a) = decimal.parse("1.50")
  let assert Ok(b) = decimal.parse("0.005")
  let assert Ok(sum) = decimal.add(a, b)
  decimal.to_string(sum)
  |> should.equal("1.505")
}

pub fn add_large_negative_exponent_plus_zero_returns_operand_test() -> Nil {
  let tiny = support.new(coefficient: 1, exponent: -20)
  let assert Ok(sum) = decimal.add(tiny, decimal.zero())
  decimal.equal(sum, tiny)
  |> should.be_true
}

pub fn subtract_test() -> Nil {
  let assert Ok(a) = decimal.parse("10.00")
  let assert Ok(b) = decimal.parse("2.50")
  let assert Ok(diff) = decimal.subtract(a, b)
  decimal.to_string(diff)
  |> should.equal("7.50")
}

pub fn multiply_basic_test() -> Nil {
  let assert Ok(a) = decimal.parse("1.5")
  let assert Ok(b) = decimal.parse("2")
  let assert Ok(product) = decimal.multiply(a, b)
  decimal.equal(product, support.int(3))
  |> should.be_true
}

pub fn multiply_fractions_test() -> Nil {
  let assert Ok(a) = decimal.parse("0.1")
  let assert Ok(b) = decimal.parse("0.2")
  let assert Ok(product) = decimal.multiply(a, b)
  decimal.to_string(product)
  |> should.equal("0.02")
}

// --- Division and rounding ----------------------------------------------

pub fn divide_exact_test() -> Nil {
  let assert Ok(quotient) =
    decimal.divide(support.int(10), support.int(4), 2, decimal.HalfEven)
  decimal.to_string(quotient)
  |> should.equal("2.50")
}

pub fn divide_rounding_half_even_to_even_test() -> Nil {
  // 7 / 4 = 1.75; rounded to 1 dp via HalfEven → 1.8 (away from 1.7
  // since 1.75 is half between 1.7 (odd) and 1.8 (even)).
  let assert Ok(q) =
    decimal.divide(support.int(7), support.int(4), 1, decimal.HalfEven)
  decimal.to_string(q)
  |> should.equal("1.8")
}

pub fn divide_half_even_ties_to_even_2_test() -> Nil {
  // 5/2 = 2.5 → HalfEven → 2 (even); HalfUp → 3
  let assert Ok(even) =
    decimal.divide(support.int(5), support.int(2), 0, decimal.HalfEven)
  decimal.to_string(even)
  |> should.equal("2")
}

pub fn divide_half_up_test() -> Nil {
  let assert Ok(up) =
    decimal.divide(support.int(5), support.int(2), 0, decimal.HalfUp)
  decimal.to_string(up)
  |> should.equal("3")
}

pub fn divide_by_zero_test() -> Nil {
  decimal.divide(support.int(1), decimal.zero(), 2, decimal.HalfEven)
  |> should.equal(Error(decimal.DivisionByZero))
}

pub fn divide_repeating_test() -> Nil {
  // 1/3 to 4 decimal places: 0.3333
  let assert Ok(q) =
    decimal.divide(support.int(1), support.int(3), 4, decimal.HalfEven)
  decimal.to_string(q)
  |> should.equal("0.3333")
}

pub fn divide_negative_test() -> Nil {
  let assert Ok(q) =
    decimal.divide(support.int(-5), support.int(2), 0, decimal.HalfUp)
  decimal.to_string(q)
  |> should.equal("-3")
}

// --- Round / truncate / rescale -----------------------------------------

pub fn round_half_even_test() -> Nil {
  // 2.5 → 2 (round to even)
  let value = support.new(coefficient: 25, exponent: -1)
  support.round(value, 0, decimal.HalfEven)
  |> decimal.to_string
  |> should.equal("2")
}

pub fn round_half_even_other_tie_test() -> Nil {
  // 3.5 → 4 (round to even)
  let value = support.new(coefficient: 35, exponent: -1)
  support.round(value, 0, decimal.HalfEven)
  |> decimal.to_string
  |> should.equal("4")
}

pub fn round_half_up_test() -> Nil {
  let value = support.new(coefficient: 25, exponent: -1)
  support.round(value, 0, decimal.HalfUp)
  |> decimal.to_string
  |> should.equal("3")
}

pub fn round_half_down_test() -> Nil {
  let value = support.new(coefficient: 25, exponent: -1)
  support.round(value, 0, decimal.HalfDown)
  |> decimal.to_string
  |> should.equal("2")
}

pub fn round_up_away_from_zero_test() -> Nil {
  let value = support.new(coefficient: 21, exponent: -1)
  support.round(value, 0, decimal.Up)
  |> decimal.to_string
  |> should.equal("3")
  let negative = support.new(coefficient: -21, exponent: -1)
  support.round(negative, 0, decimal.Up)
  |> decimal.to_string
  |> should.equal("-3")
}

pub fn round_down_toward_zero_test() -> Nil {
  let value = support.new(coefficient: 29, exponent: -1)
  support.round(value, 0, decimal.Down)
  |> decimal.to_string
  |> should.equal("2")
  let negative = support.new(coefficient: -29, exponent: -1)
  support.round(negative, 0, decimal.Down)
  |> decimal.to_string
  |> should.equal("-2")
}

pub fn round_ceiling_test() -> Nil {
  // 2.1 → 3 (toward +∞)
  let value = support.new(coefficient: 21, exponent: -1)
  support.round(value, 0, decimal.Ceiling)
  |> decimal.to_string
  |> should.equal("3")
  // -2.9 → -2 (toward +∞)
  let negative = support.new(coefficient: -29, exponent: -1)
  support.round(negative, 0, decimal.Ceiling)
  |> decimal.to_string
  |> should.equal("-2")
}

pub fn round_floor_test() -> Nil {
  // 2.9 → 2 (toward -∞)
  let value = support.new(coefficient: 29, exponent: -1)
  support.round(value, 0, decimal.Floor)
  |> decimal.to_string
  |> should.equal("2")
  // -2.1 → -3 (toward -∞)
  let negative = support.new(coefficient: -21, exponent: -1)
  support.round(negative, 0, decimal.Floor)
  |> decimal.to_string
  |> should.equal("-3")
}

pub fn truncate_test() -> Nil {
  let value = support.new(coefficient: 29, exponent: -1)
  support.round(value, digits: 0, rounding: decimal.Down)
  |> decimal.to_string
  |> should.equal("2")
}

pub fn round_pads_integer_to_requested_dp_test() -> Nil {
  let value = support.int(5)
  // rounding an integer to 3 dp pads to exactly 3 fractional places (#75)
  support.round(value, 3, decimal.HalfEven)
  |> decimal.to_string
  |> should.equal("5.000")
}

pub fn rescale_expand_test() -> Nil {
  let assert Ok(rescaled) =
    decimal.round(support.int(5), digits: 2, rounding: decimal.HalfEven)
  decimal.to_string(rescaled)
  |> should.equal("5.00")
}

pub fn rescale_truncate_test() -> Nil {
  // 12.345 → 1 dp via HalfEven → 12.3 (remainder 45 of 100 is below half).
  let assert Ok(rescaled) =
    decimal.round(
      support.new(coefficient: 12_345, exponent: -3),
      digits: 1,
      rounding: decimal.HalfEven,
    )
  decimal.to_string(rescaled)
  |> should.equal("12.3")
}

pub fn rescale_half_even_tie_test() -> Nil {
  // 12.35 → 1 dp via HalfEven → 12.4 (tie, 3 is odd, round to even).
  let assert Ok(rescaled) =
    decimal.round(
      support.new(coefficient: 1235, exponent: -2),
      digits: 1,
      rounding: decimal.HalfEven,
    )
  decimal.to_string(rescaled)
  |> should.equal("12.4")
}

// --- to_int / to_int_truncated / to_int_rounded -------------------------

pub fn to_int_integer_valued_test() -> Nil {
  decimal.to_int(support.int(7))
  |> should.equal(Ok(7))
}

pub fn to_int_trailing_zeros_succeed_test() -> Nil {
  // "12.00" → coefficient 1200, exponent -2; cleanly divisible.
  let assert Ok(d) = decimal.parse("12.00")
  decimal.to_int(d)
  |> should.equal(Ok(12))
}

pub fn to_int_fractional_part_rejected_test() -> Nil {
  let assert Ok(d) = decimal.parse("12.34")
  decimal.to_int(d)
  |> should.equal(Error(Nil))
}

pub fn to_int_negative_value_test() -> Nil {
  let assert Ok(d) = decimal.parse("-7")
  decimal.to_int(d)
  |> should.equal(Ok(-7))
}

// --- Compare / equal -----------------------------------------------------

pub fn equal_across_representations_test() -> Nil {
  decimal.equal(support.new(coefficient: 100, exponent: -2), decimal.one())
  |> should.be_true
}

pub fn equal_distinct_values_test() -> Nil {
  decimal.equal(support.int(1), support.int(2))
  |> should.be_false
}

pub fn compare_orders_test() -> Nil {
  decimal.compare(support.int(1), support.int(2))
  |> should.equal(order.Lt)
  decimal.compare(support.int(3), support.int(1))
  |> should.equal(order.Gt)
  decimal.compare(support.new(coefficient: 200, exponent: -2), support.int(2))
  |> should.equal(order.Eq)
}

pub fn compare_mixed_signs_test() -> Nil {
  decimal.compare(support.int(-5), support.int(1))
  |> should.equal(order.Lt)
}

// --- Round-trip property -------------------------------------------------

pub fn from_to_string_round_trip_test() -> Nil {
  let inputs = ["0", "1", "-1", "3.14", "-0.005", "1234.5678", "0.0"]
  inputs
  |> list_iter(fn(s) {
    let assert Ok(parsed) = decimal.parse(s)
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

// --- Range limits ---------------------------------------------------------

pub fn zero_with_a_huge_exponent_is_rejected_quickly_test() -> Nil {
  assert decimal.new(coefficient: 0, exponent: 1_000_000_000) == Error(Nil)
  assert decimal.parse("0e999999999") == Error(decimal.ParsedValueTooLarge)
}

pub fn products_obey_the_constructor_range_test() -> Nil {
  assert decimal.multiply(support.parse("1e15"), support.parse("1e15"))
    == Error(decimal.PrecisionExceeded)
  assert decimal.add(support.parse("9e15"), support.parse("1e15"))
    == Error(decimal.PrecisionExceeded)
  assert decimal.subtract(support.parse("-9e15"), support.parse("1e15"))
    == Error(decimal.PrecisionExceeded)
}

pub fn rounding_up_past_the_range_fails_test() -> Nil {
  assert decimal.round(
      support.parse("9007199254740991"),
      digits: -2,
      rounding: decimal.Up,
    )
    == Error(decimal.PrecisionExceeded)
}

pub fn dividing_a_tiny_value_rounds_to_zero_test() -> Nil {
  let tiny = support.parse("1e-28")
  assert decimal.divide(
      tiny,
      decimal.one(),
      digits: 0,
      rounding: decimal.HalfEven,
    )
    |> result.map(decimal.to_string)
    == Ok("0")
  assert decimal.divide(tiny, decimal.one(), digits: 2, rounding: decimal.Up)
    |> result.map(decimal.to_string)
    == Ok("0.01")
  assert decimal.divide(
      decimal.negate(tiny),
      decimal.one(),
      digits: 2,
      rounding: decimal.Floor,
    )
    |> result.map(decimal.to_string)
    == Ok("-0.01")
}

pub fn far_apart_exponents_do_not_hang_test() -> Nil {
  assert decimal.parse("1e-1000000") == Error(decimal.ParsedValueTooLarge)
  let tiny = support.parse("1e-28")
  assert decimal.compare(tiny, decimal.one()) == order.Lt
  assert decimal.to_int(tiny) == Error(Nil)
  assert decimal.round(tiny, digits: 2, rounding: decimal.HalfEven)
    |> result.map(decimal.to_string)
    == Ok("0.00")
  assert decimal.add(tiny, decimal.one()) == Error(decimal.PrecisionExceeded)
}

pub fn parse_trims_a_trailing_crlf_test() -> Nil {
  assert decimal.parse("12.5\r\n") |> result.map(decimal.to_string)
    == Ok("12.5")
}

pub fn dividing_with_an_out_of_range_divisor_scale_rounds_test() -> Nil {
  let nine_tenths = support.parse("0.9000000000000000")
  let half = support.parse("0.5000000000000000")
  let one = decimal.one()
  let to_text = result.map(_, decimal.to_string)
  assert to_text(decimal.divide(
      nine_tenths,
      one,
      digits: 0,
      rounding: decimal.HalfEven,
    ))
    == Ok("1")
  assert to_text(decimal.divide(
      half,
      one,
      digits: 0,
      rounding: decimal.HalfEven,
    ))
    == Ok("0")
  assert to_text(decimal.divide(half, one, digits: 0, rounding: decimal.HalfUp))
    == Ok("1")
  assert to_text(decimal.divide(
      decimal.negate(nine_tenths),
      one,
      digits: 0,
      rounding: decimal.Down,
    ))
    == Ok("0")
}
