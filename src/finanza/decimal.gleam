//// Fixed-point decimal numbers with explicit rounding.
////
//// A `Decimal` is a coefficient and a base-10 exponent, so `12.30` is
//// the coefficient `1230` with the exponent `-2`. Operations that can
//// lose digits take a `RoundingMode`.
////
//// ## Range
////
//// Every `Decimal` is in this range, on both targets:
////
//// - The exponent is between -28 and 15, so a decimal has at most 28
////   places after the point. Currencies use 0 to 4 places and interest
////   rates rarely need more than 10, and 28 is the largest scale of
////   rust_decimal and .NET `System.Decimal`. 15 is the largest exponent
////   at which a non-zero coefficient fits the bound below.
//// - The coefficient, and the integer a positive exponent stands for,
////   are within ±9,007,199,254,740,991 (2^53 − 1), the largest integer
////   JavaScript represents exactly, so Erlang and JavaScript give the
////   same results.
////
//// Together these keep `to_string` at 31 characters or fewer, so a short
//// input such as `"1e-999999999"` cannot become a long string.
////
//// `new` returns `Error(Nil)` outside the range, `parse` returns
//// `ParsedValueTooLarge`, and arithmetic returns `PrecisionExceeded`,
//// also when `round` or `divide` is asked for more than 28 places.
//// `parse` rejects input over 1,000 bytes with `InputTooLong` before
//// reading it, the same limit as the default number length of Jackson's
//// `StreamReadConstraints`.

import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

/// A fixed-point decimal number.
///
pub opaque type Decimal {
  // |coefficient| <= max_safe_coefficient, and when exponent > 0 the
  // rendered integer |coefficient| * 10^exponent is within it too.
  Decimal(coefficient: Int, exponent: Int)
}

/// How to round when an operation drops digits.
///
/// `HalfEven` (banker's rounding) is the usual choice for money.
///
pub type RoundingMode {
  /// Round half-way values to the even neighbour: 2.5 to 2, 3.5 to 4.
  HalfEven
  /// Round half-way values away from zero: 2.5 to 3, -2.5 to -3.
  HalfUp
  /// Round half-way values toward zero: 2.5 to 2, -2.5 to -2.
  HalfDown
  /// Round away from zero: 2.1 to 3, -2.1 to -3.
  Up
  /// Round toward zero: 2.9 to 2, -2.9 to -2.
  Down
  /// Round toward positive infinity: 2.1 to 3, -2.9 to -2.
  Ceiling
  /// Round toward negative infinity: 2.9 to 2, -2.1 to -3.
  Floor
}

/// Why `parse` rejected its input.
///
pub type ParseError {
  /// The input was empty or only whitespace.
  EmptyInput
  /// The input has a character that is not a digit, a sign, a `.` or
  /// an exponent marker. `position` counts graphemes from 0 after the
  /// surrounding whitespace is trimmed.
  InvalidCharacter(character: String, position: Int)
  /// The input has more than one `.`.
  MultipleDecimalPoints
  /// The input has more than one sign, or a sign after the first
  /// character.
  MultipleSigns
  /// The input has no digits, such as `"+"` or `"."`.
  NoDigits
  /// The value is outside the supported range: more than 2^53 − 1 in
  /// the coefficient, or an exponent outside -28 to 15. The exponent is
  /// kept, so `"1e-29"` and `"0.10000000000000000000000000000"` are both
  /// out of range.
  ParsedValueTooLarge
  /// The input is longer than 1,000 bytes, counted before trimming.
  InputTooLong
}

/// Why an arithmetic operation failed.
///
pub type ArithmeticError {
  /// The divisor was zero.
  DivisionByZero
  /// The result does not fit in the supported range.
  PrecisionExceeded
}

const max_safe_coefficient: Int = 9_007_199_254_740_991

const min_exponent: Int = -28

const max_exponent: Int = 15

const max_input_bytes: Int = 1000

// Construction ---------------------------------------------------------------

/// Returns the decimal 0.
///
pub fn zero() -> Decimal {
  Decimal(0, 0)
}

/// Returns the decimal 1.
///
pub fn one() -> Decimal {
  Decimal(1, 0)
}

/// Creates the decimal `coefficient × 10^exponent`.
///
/// Returns `Error(Nil)` when the value is outside the supported range:
/// the exponent must be between -28 and 15, and the coefficient, times
/// `10^exponent` when the exponent is positive, within ±(2^53 − 1).
///
/// ## Examples
///
/// ```gleam
/// decimal.new(coefficient: 1234, exponent: -2) |> result.map(decimal.to_string)
/// // -> Ok("12.34")
/// ```
///
/// ```gleam
/// decimal.new(coefficient: 1, exponent: 16)
/// // -> Error(Nil)
/// ```
///
pub fn new(
  coefficient coefficient: Int,
  exponent exponent: Int,
) -> Result(Decimal, Nil) {
  checked(coefficient, exponent) |> result.replace_error(Nil)
}

/// Creates a decimal from an integer.
///
/// Returns `Error(Nil)` when the integer is outside
/// ±9,007,199,254,740,991.
///
pub fn from_int(value: Int) -> Result(Decimal, Nil) {
  new(coefficient: value, exponent: 0)
}

/// Creates a decimal from the text `float.to_string` gives for a float.
///
/// `0.5` becomes `0.5`, and `0.1 +. 0.2` becomes
/// `0.30000000000000004`. Prefer `parse` or `new` when the value is
/// not already a float.
///
pub fn from_float(value: Float) -> Result(Decimal, ParseError) {
  value |> float.to_string |> parse
}

/// Parses a decimal such as `"12.30"`, `"-0.5"`, `"+7"` or `"1.5e-3"`.
///
/// Leading and trailing Unicode whitespace is ignored, including
/// no-break spaces. The exponent is kept, so `"12.30"` and `"12.3"`
/// parse to different representations of the same number.
///
/// Returns `Error(InputTooLong)` for input over 1,000 bytes and
/// `Error(ParsedValueTooLarge)` for a value outside the range in the
/// module documentation, such as `"1e-29"` or `"1e16"`.
///
/// ## Examples
///
/// ```gleam
/// decimal.parse(" 12.30 ") |> result.map(decimal.to_string)
/// // -> Ok("12.30")
/// ```
///
/// ```gleam
/// decimal.parse("1.2.3")
/// // -> Error(decimal.MultipleDecimalPoints)
/// ```
///
pub fn parse(input: String) -> Result(Decimal, ParseError) {
  use <- bool.guard(
    when: string.byte_size(input) > max_input_bytes,
    return: Error(InputTooLong),
  )
  let trimmed = trim_unicode_whitespace(input)
  use <- bool.guard(when: trimmed == "", return: Error(EmptyInput))
  use #(mantissa, shift) <- result.try(split_scientific_notation(trimmed))
  use base <- result.try(parse_plain_decimal(mantissa))
  checked(base.coefficient, base.exponent + shift)
  |> result.replace_error(ParsedValueTooLarge)
}

fn trim_unicode_whitespace(input: String) -> String {
  input
  |> string.to_graphemes
  |> list.drop_while(is_unicode_whitespace)
  |> list.reverse
  |> list.drop_while(is_unicode_whitespace)
  |> list.reverse
  |> string.concat
}

// The Unicode White_Space property, plus the byte order mark.
fn is_unicode_whitespace(grapheme: String) -> Bool {
  case grapheme {
    " "
    | "\t"
    | "\n"
    | "\r"
    | "\r\n"
    | "\f"
    | "\u{000B}"
    | "\u{0085}"
    | "\u{00A0}"
    | "\u{1680}"
    | "\u{2000}"
    | "\u{2001}"
    | "\u{2002}"
    | "\u{2003}"
    | "\u{2004}"
    | "\u{2005}"
    | "\u{2006}"
    | "\u{2007}"
    | "\u{2008}"
    | "\u{2009}"
    | "\u{200A}"
    | "\u{2028}"
    | "\u{2029}"
    | "\u{202F}"
    | "\u{205F}"
    | "\u{3000}"
    | "\u{FEFF}" -> True
    _ -> False
  }
}

fn split_scientific_notation(
  trimmed: String,
) -> Result(#(String, Int), ParseError) {
  case find_exponent_marker(trimmed) {
    Error(Nil) -> Ok(#(trimmed, 0))
    Ok(#(mantissa, marker, exponent_text)) ->
      case int.parse(exponent_text) {
        Ok(shift) -> Ok(#(mantissa, shift))
        Error(Nil) ->
          Error(InvalidCharacter(
            character: marker,
            position: string.length(mantissa),
          ))
      }
  }
}

fn find_exponent_marker(
  trimmed: String,
) -> Result(#(String, String, String), Nil) {
  case string.split_once(trimmed, on: "e") {
    Ok(#(mantissa, exponent_text)) -> Ok(#(mantissa, "e", exponent_text))
    Error(Nil) ->
      case string.split_once(trimmed, on: "E") {
        Ok(#(mantissa, exponent_text)) -> Ok(#(mantissa, "E", exponent_text))
        Error(Nil) -> Error(Nil)
      }
  }
}

fn parse_plain_decimal(mantissa: String) -> Result(Decimal, ParseError) {
  use <- bool.guard(when: mantissa == "", return: Error(EmptyInput))
  parse_loop(ParseState(
    characters: string.to_graphemes(mantissa),
    position: 0,
    sign: 1,
    digits: 0,
    fraction_digits: 0,
    saw_dot: False,
    saw_sign: False,
    saw_digit: False,
  ))
}

type ParseState {
  ParseState(
    characters: List(String),
    position: Int,
    sign: Int,
    digits: Int,
    fraction_digits: Int,
    saw_dot: Bool,
    saw_sign: Bool,
    saw_digit: Bool,
  )
}

fn parse_loop(state: ParseState) -> Result(Decimal, ParseError) {
  case state.characters {
    [] -> finish_parse(state)
    [character, ..rest] -> {
      let next =
        ParseState(..state, characters: rest, position: state.position + 1)
      case character {
        "+" -> parse_sign(state, next, 1)
        "-" -> parse_sign(state, next, -1)
        "." -> parse_dot(state, next)
        _ ->
          case digit_value(character) {
            Ok(value) -> parse_digit(next, value)
            Error(Nil) ->
              Error(InvalidCharacter(character:, position: state.position))
          }
      }
    }
  }
}

fn finish_parse(state: ParseState) -> Result(Decimal, ParseError) {
  use <- bool.guard(when: !state.saw_digit, return: Error(NoDigits))
  use <- bool.guard(
    when: state.digits > max_safe_coefficient,
    return: Error(ParsedValueTooLarge),
  )
  Ok(Decimal(state.sign * state.digits, -state.fraction_digits))
}

fn parse_sign(
  state: ParseState,
  next: ParseState,
  sign: Int,
) -> Result(Decimal, ParseError) {
  use <- bool.guard(
    when: state.position != 0 || state.saw_sign,
    return: Error(MultipleSigns),
  )
  parse_loop(ParseState(..next, sign:, saw_sign: True))
}

fn parse_dot(
  state: ParseState,
  next: ParseState,
) -> Result(Decimal, ParseError) {
  use <- bool.guard(when: state.saw_dot, return: Error(MultipleDecimalPoints))
  parse_loop(ParseState(..next, saw_dot: True))
}

fn parse_digit(next: ParseState, value: Int) -> Result(Decimal, ParseError) {
  let fraction_digits = case next.saw_dot {
    True -> next.fraction_digits + 1
    False -> next.fraction_digits
  }
  // Stop accumulating once the digits are out of range so that a long
  // input does not build a huge integer.
  let digits = case next.digits > max_safe_coefficient {
    True -> next.digits
    False -> next.digits * 10 + value
  }
  parse_loop(ParseState(..next, digits:, fraction_digits:, saw_digit: True))
}

fn digit_value(character: String) -> Result(Int, Nil) {
  case character {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    _ -> Error(Nil)
  }
}

// Inspection -----------------------------------------------------------------

/// Returns the coefficient, so `12.30` gives `1230`.
///
pub fn coefficient(decimal: Decimal) -> Int {
  decimal.coefficient
}

/// Returns the base-10 exponent, so `12.30` gives `-2`.
///
pub fn exponent(decimal: Decimal) -> Int {
  decimal.exponent
}

/// Returns `True` when the decimal is zero.
///
pub fn is_zero(decimal: Decimal) -> Bool {
  decimal.coefficient == 0
}

/// Returns `True` when the decimal is greater than zero.
///
pub fn is_positive(decimal: Decimal) -> Bool {
  decimal.coefficient > 0
}

/// Returns `True` when the decimal is less than zero.
///
pub fn is_negative(decimal: Decimal) -> Bool {
  decimal.coefficient < 0
}

/// Converts a whole-number decimal to an `Int`.
///
/// Returns `Error(Nil)` when the decimal has a non-zero fractional
/// part. Use `round` with `digits: 0` first to drop it.
///
/// ## Examples
///
/// ```gleam
/// decimal.parse("12.00") |> result.try(decimal.to_int)
/// // -> Ok(12)
/// ```
///
/// ```gleam
/// decimal.parse("12.34") |> result.try(decimal.to_int)
/// // -> Error(Nil)
/// ```
///
pub fn to_int(decimal: Decimal) -> Result(Int, Nil) {
  case decimal.coefficient, decimal.exponent {
    0, _ -> Ok(0)
    _, exponent if exponent >= 0 ->
      Ok(decimal.coefficient * pow_10(decimal.exponent))
    // A coefficient below 10^16 with 16 or more places is not whole.
    _, exponent if exponent < -15 -> Error(Nil)
    _, _ -> {
      let divisor = pow_10(-decimal.exponent)
      case decimal.coefficient % divisor {
        0 -> Ok(decimal.coefficient / divisor)
        _ -> Error(Nil)
      }
    }
  }
}

/// Renders the decimal with every digit of its exponent, so
/// `new(coefficient: 100, exponent: -2)` is `"1.00"` and
/// `new(coefficient: 12, exponent: 2)` is `"1200"`.
///
pub fn to_string(decimal: Decimal) -> String {
  let digits = int.to_string(int.absolute_value(decimal.coefficient))
  let sign = case decimal.coefficient < 0 {
    True -> "-"
    False -> ""
  }
  case decimal.exponent >= 0 {
    True if decimal.coefficient == 0 -> "0"
    True -> sign <> digits <> string.repeat("0", decimal.exponent)
    False -> {
      let places = -decimal.exponent
      let padded =
        string.repeat("0", int.max(0, places + 1 - string.length(digits)))
        <> digits
      let split = string.length(padded) - places
      sign
      <> string.slice(padded, 0, split)
      <> "."
      <> string.slice(padded, split, places)
    }
  }
}

/// Renders the decimal like `to_string`, with `thousands` between
/// groups of three integer digits and `decimal_separator` in place of
/// the `.`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(price) = decimal.parse("1234567.5")
/// decimal.format(price, thousands: ".", decimal_separator: ",")
/// // -> "1.234.567,5"
/// ```
///
pub fn format(
  decimal: Decimal,
  thousands thousands: String,
  decimal_separator decimal_separator: String,
) -> String {
  let sign = case decimal.coefficient < 0 {
    True -> "-"
    False -> ""
  }
  let unsigned = to_string(absolute(decimal))
  case string.split_once(unsigned, on: ".") {
    Ok(#(integer, fraction)) ->
      sign
      <> group_thousands(integer, thousands)
      <> decimal_separator
      <> fraction
    Error(Nil) -> sign <> group_thousands(unsigned, thousands)
  }
}

fn group_thousands(digits: String, separator: String) -> String {
  use <- bool.guard(when: separator == "", return: digits)
  digits
  |> string.to_graphemes
  |> list.reverse
  |> list.sized_chunk(into: 3)
  |> list.map(fn(group) { group |> list.reverse |> string.concat })
  |> list.reverse
  |> string.join(with: separator)
}

// Arithmetic -----------------------------------------------------------------

/// Returns the decimal with its sign flipped.
///
pub fn negate(decimal: Decimal) -> Decimal {
  Decimal(..decimal, coefficient: -decimal.coefficient)
}

/// Returns the decimal without its sign.
///
pub fn absolute(decimal: Decimal) -> Decimal {
  Decimal(..decimal, coefficient: int.absolute_value(decimal.coefficient))
}

/// Adds two decimals. The result has the smaller of the two exponents,
/// except that adding zero returns the other decimal unchanged.
///
/// Returns `Error(PrecisionExceeded)` when the sum is out of range.
///
pub fn add(a: Decimal, b: Decimal) -> Result(Decimal, ArithmeticError) {
  case a.coefficient, b.coefficient {
    0, 0 -> Ok(Decimal(0, int.min(a.exponent, b.exponent)))
    0, _ -> Ok(b)
    _, 0 -> Ok(a)
    _, _ -> {
      let exponent = int.min(a.exponent, b.exponent)
      use left <- result.try(scale_up(a.coefficient, a.exponent - exponent))
      use right <- result.try(scale_up(b.coefficient, b.exponent - exponent))
      checked(left + right, exponent)
    }
  }
}

/// Subtracts `b` from `a`. The result has the smaller of the two
/// exponents.
///
pub fn subtract(a: Decimal, b: Decimal) -> Result(Decimal, ArithmeticError) {
  add(a, negate(b))
}

/// Multiplies two decimals without rounding. The exponents add up, so
/// `1.5 × 0.25` is `0.375`.
///
/// The product is exact before it is fitted into the range, even when
/// the coefficients multiply past 2^53. When the exponents add up to
/// less than -28, or the coefficient passes 2^53 − 1, the product drops
/// the fewest trailing zeros that bring it into range, so `0.10 × 1e-27`
/// is `1e-28` and `4503599627370496 × 0.10` is `450359962737049.6`. A
/// zero product has its exponent moved into -28 to 15.
///
/// Returns `Error(PrecisionExceeded)` when the product is out of range,
/// including a product with a non-zero digit past 28 places or one that
/// needs more than 2^53 − 1 in its coefficient after its zeros go.
///
pub fn multiply(a: Decimal, b: Decimal) -> Result(Decimal, ArithmeticError) {
  let exponent = a.exponent + b.exponent
  let left = int.absolute_value(a.coefficient)
  let right = int.absolute_value(b.coefficient)
  use <- bool.lazy_guard(when: left == 0 || right == 0, return: fn() {
    checked(0, int.clamp(exponent, min: min_exponent, max: max_exponent))
  })
  let sign = sign_of(a.coefficient) * sign_of(b.coefficient)
  let at_least = int.max(0, min_exponent - exponent)
  use #(magnitude, dropped) <- result.try(
    case left <= max_safe_coefficient / right {
      True -> drop_small_zeros(left * right, at_least)
      False -> drop_zeros(product_digits(left, right), 0, at_least)
    },
  )
  checked(sign * magnitude, exponent + dropped)
}

// Drops `count` trailing zeros from a product within 2^53 - 1, which
// both targets compute exactly. Such a product has at most 15 trailing
// zeros.
fn drop_small_zeros(
  product: Int,
  count: Int,
) -> Result(#(Int, Int), ArithmeticError) {
  use <- bool.guard(when: count > 15, return: Error(PrecisionExceeded))
  let divisor = pow_10(count)
  case product % divisor {
    0 -> Ok(#(product / divisor, count))
    _ -> Error(PrecisionExceeded)
  }
}

// Drops trailing zeros from `digits`, the least significant digit
// first: at least `at_least` of them, and then as few more as bring the
// value within 2^53 - 1. Returns the value and how many were dropped.
// The list has 35 digits, so this takes at most 35 steps of at most 35
// digits each.
fn drop_zeros(
  digits: List(Int),
  dropped: Int,
  at_least: Int,
) -> Result(#(Int, Int), ArithmeticError) {
  let value = case dropped >= at_least {
    True -> digits_value(digits)
    False -> Error(Nil)
  }
  case value, digits {
    Ok(value), _ -> Ok(#(value, dropped))
    Error(Nil), [0, ..rest] -> drop_zeros(rest, dropped + 1, at_least)
    Error(Nil), _ -> Error(PrecisionExceeded)
  }
}

// The value of digits listed least significant first, or `Error(Nil)`
// when it passes 2^53 - 1. Each step checks before it multiplies, so no
// intermediate value passes 2^53 - 1 either.
fn digits_value(digits: List(Int)) -> Result(Int, Nil) {
  digits
  |> list.reverse
  |> list.try_fold(0, fn(value, digit) {
    case value > { max_safe_coefficient - digit } / 10 {
      True -> Error(Nil)
      False -> Ok(value * 10 + digit)
    }
  })
}

// Base of the limbs a product is computed in. Every coefficient is
// below 10^16, so it splits into three limbs, the top one at most 90.
// A product of two limbs is below 10^14, and a sum of three of them
// plus a carry stays below 2^53, so both targets compute every step
// exactly.
const limb_base: Int = 10_000_000

const limb_digits: Int = 7

// The exact product of two magnitudes within 2^53 - 1, as its 35
// decimal digits, the least significant first.
fn product_digits(a: Int, b: Int) -> List(Int) {
  let #(a0, a1, a2) = split_limbs(a)
  let #(b0, b1, b2) = split_limbs(b)
  let c0 = a0 * b0
  let c1 = a0 * b1 + a1 * b0 + c0 / limb_base
  let c2 = a0 * b2 + a1 * b1 + a2 * b0 + c1 / limb_base
  let c3 = a1 * b2 + a2 * b1 + c2 / limb_base
  // At most 90 × 90 plus a carry of at most 181, so below the base.
  let c4 = a2 * b2 + c3 / limb_base
  [c0, c1, c2, c3]
  |> list.map(fn(limb) { limb % limb_base })
  |> list.append([c4])
  |> list.flat_map(limb_to_digits(_, limb_digits))
}

fn split_limbs(value: Int) -> #(Int, Int, Int) {
  #(
    value % limb_base,
    value / limb_base % limb_base,
    value / { limb_base * limb_base },
  )
}

fn limb_to_digits(limb: Int, count: Int) -> List(Int) {
  case count {
    0 -> []
    _ -> [limb % 10, ..limb_to_digits(limb / 10, count - 1)]
  }
}

/// Divides `a` by `b` and rounds the quotient to `digits` places after
/// the decimal point.
///
/// Returns `Error(DivisionByZero)` when `b` is zero, and
/// `Error(PrecisionExceeded)` when `digits` is outside -15 to 28 or the
/// quotient at that many places is out of range, which happens from
/// 17 places for `1 / 3`. The quotient is exact before rounding
/// even when the scaled dividend would pass 2^53, so
/// `1 / 1.234567890123456` at 2 places is `0.81`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(ten) = decimal.from_int(10)
/// let assert Ok(three) = decimal.from_int(3)
/// decimal.divide(ten, three, digits: 2, rounding: decimal.HalfEven)
/// |> result.map(decimal.to_string)
/// // -> Ok("3.33")
/// ```
///
pub fn divide(
  a: Decimal,
  b: Decimal,
  digits digits: Int,
  rounding mode: RoundingMode,
) -> Result(Decimal, ArithmeticError) {
  use <- bool.guard(when: b.coefficient == 0, return: Error(DivisionByZero))
  use <- bool.guard(
    when: -digits < min_exponent || -digits > max_exponent,
    return: Error(PrecisionExceeded),
  )
  use <- bool.guard(when: a.coefficient == 0, return: checked(0, -digits))
  let sign = sign_of(a.coefficient) * sign_of(b.coefficient)
  let numerator = int.absolute_value(a.coefficient)
  let denominator = int.absolute_value(b.coefficient)
  // The bounds on the exponents and on digits keep shift within -58..71.
  let shift = a.exponent - b.exponent + digits
  case shift >= 0 {
    True -> {
      use #(quotient, remainder) <- result.try(long_division(
        numerator / denominator,
        numerator % denominator,
        denominator,
        shift,
      ))
      round_parts(quotient, remainder, denominator, sign, mode)
      |> checked(-digits)
    }
    False ->
      case scale_up(denominator, -shift) {
        Ok(denominator) ->
          round_quotient(numerator, denominator, sign, mode)
          |> checked(-digits)
        // The scaled divisor is out of range, so it is larger than the
        // numerator and the quotient is below 1. Compare twice the
        // numerator with the divisor as digit strings to round it.
        Error(PrecisionExceeded) | Error(DivisionByZero) -> {
          let #(remainder, divisor) = case
            compare_digits(
              int.to_string(2 * numerator),
              int.to_string(denominator) <> string.repeat("0", -shift),
            )
          {
            order.Lt -> #(1, 10)
            order.Eq -> #(1, 2)
            order.Gt -> #(9, 10)
          }
          round_quotient(remainder, divisor, sign, mode) |> checked(-digits)
        }
      }
  }
}

/// Rounds the decimal to `digits` places after the decimal point.
///
/// The result always has exactly `digits` places: `12.3` rounded to 2
/// places is `12.30`. A negative `digits` rounds to tens, hundreds and
/// so on. Returns `Error(PrecisionExceeded)` when `digits` is outside
/// -15 to 28 or the padded or rounded value is out of range.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(price) = decimal.parse("2.345")
/// decimal.round(price, digits: 2, rounding: decimal.HalfEven)
/// |> result.map(decimal.to_string)
/// // -> Ok("2.34")
/// ```
///
/// ```gleam
/// let assert Ok(price) = decimal.parse("2.345")
/// decimal.round(price, digits: 2, rounding: decimal.HalfUp)
/// |> result.map(decimal.to_string)
/// // -> Ok("2.35")
/// ```
///
pub fn round(
  decimal: Decimal,
  digits digits: Int,
  rounding mode: RoundingMode,
) -> Result(Decimal, ArithmeticError) {
  let target = -digits
  use <- bool.guard(
    when: target < min_exponent || target > max_exponent,
    return: Error(PrecisionExceeded),
  )
  case int.compare(target, decimal.exponent) {
    order.Eq -> Ok(decimal)
    order.Lt -> {
      use coefficient <- result.try(scale_up(
        decimal.coefficient,
        decimal.exponent - target,
      ))
      checked(coefficient, target)
    }
    order.Gt -> {
      let sign = sign_of(decimal.coefficient)
      let magnitude = int.absolute_value(decimal.coefficient)
      let dropped = target - decimal.exponent
      // A magnitude below 10^16 shifted by 17 or more places is below
      // 0.1, so it rounds like any other small non-zero remainder.
      let coefficient = case dropped > 16, magnitude {
        _, 0 -> 0
        True, _ -> round_quotient(1, 10, sign, mode)
        False, _ -> round_quotient(magnitude, pow_10(dropped), sign, mode)
      }
      checked(coefficient, target)
    }
  }
}

// Divides two non-negative integers and applies the rounding mode, then
// restores the sign.
fn round_quotient(
  numerator: Int,
  denominator: Int,
  sign: Int,
  mode: RoundingMode,
) -> Int {
  round_parts(
    numerator / denominator,
    numerator % denominator,
    denominator,
    sign,
    mode,
  )
}

// Applies the rounding mode to `quotient + remainder / denominator`,
// where `0 <= remainder < denominator`, then restores the sign. Doubling
// the remainder may pass 2^53, but a JavaScript float doubles exactly.
fn round_parts(
  quotient: Int,
  remainder: Int,
  denominator: Int,
  sign: Int,
  mode: RoundingMode,
) -> Int {
  let bump = case remainder {
    0 -> False
    _ ->
      case mode {
        HalfEven ->
          case int.compare(2 * remainder, denominator) {
            order.Gt -> True
            order.Lt -> False
            order.Eq -> quotient % 2 == 1
          }
        HalfUp -> 2 * remainder >= denominator
        HalfDown -> 2 * remainder > denominator
        Up -> True
        Down -> False
        Ceiling -> sign > 0
        Floor -> sign < 0
      }
  }
  case bump {
    True -> sign * { quotient + 1 }
    False -> sign * quotient
  }
}

// Comparison -----------------------------------------------------------------

/// Compares two decimals by value, so `1.0` and `1.00` are equal.
///
pub fn compare(a: Decimal, b: Decimal) -> order.Order {
  let exponent = int.min(a.exponent, b.exponent)
  case
    scale_up(a.coefficient, a.exponent - exponent),
    scale_up(b.coefficient, b.exponent - exponent)
  {
    Ok(left), Ok(right) -> int.compare(left, right)
    _, _ -> compare_by_magnitude(a, b)
  }
}

/// Returns `True` when two decimals have the same value. `==` compares
/// the representation instead, so `1.0 == 1.00` is `False` but
/// `equal(1.0, 1.00)` is `True`.
///
pub fn equal(a: Decimal, b: Decimal) -> Bool {
  compare(a, b) == order.Eq
}

// Used when aligning the exponents would overflow: compares the sign,
// then the position of the leading digit, then the digits themselves.
fn compare_by_magnitude(a: Decimal, b: Decimal) -> order.Order {
  case int.compare(sign_of(a.coefficient), sign_of(b.coefficient)) {
    order.Eq -> {
      let a_digits = int.to_string(int.absolute_value(a.coefficient))
      let b_digits = int.to_string(int.absolute_value(b.coefficient))
      let a_length = string.length(a_digits)
      let b_length = string.length(b_digits)
      let unsigned = case
        int.compare(a_length + a.exponent, b_length + b.exponent)
      {
        order.Eq -> {
          let width = int.max(a_length, b_length)
          string.compare(
            a_digits <> string.repeat("0", width - a_length),
            b_digits <> string.repeat("0", width - b_length),
          )
        }
        other -> other
      }
      case a.coefficient < 0 {
        True -> order.negate(unsigned)
        False -> unsigned
      }
    }
    other -> other
  }
}

// Internals ------------------------------------------------------------------

// Every Decimal is built here or by a constructor that keeps the
// invariant on the type.
fn checked(
  coefficient: Int,
  exponent: Int,
) -> Result(Decimal, ArithmeticError) {
  let magnitude = int.absolute_value(coefficient)
  let fits = case magnitude, exponent > 0 {
    _, _ if exponent < min_exponent || exponent > max_exponent -> False
    0, _ -> True
    _, False -> magnitude <= max_safe_coefficient
    _, True -> magnitude * pow_10(exponent) <= max_safe_coefficient
  }
  case fits {
    True -> Ok(Decimal(coefficient, exponent))
    False -> Error(PrecisionExceeded)
  }
}

fn scale_up(coefficient: Int, places: Int) -> Result(Int, ArithmeticError) {
  case coefficient, places {
    0, _ -> Ok(0)
    _, 0 -> Ok(coefficient)
    // Any non-zero coefficient times 10^16 is out of range.
    _, _ if places > 15 -> Error(PrecisionExceeded)
    _, _ -> {
      let scaled = coefficient * pow_10(places)
      case int.absolute_value(scaled) > max_safe_coefficient {
        True -> Error(PrecisionExceeded)
        False -> Ok(scaled)
      }
    }
  }
}

// Continues the division `numerator / denominator` for `places` more
// decimal places, one digit at a time, so that the scaled numerator
// `numerator × 10^places` is never built. Every intermediate value stays
// below the denominator or the quotient bound, so JavaScript computes it
// exactly. Fails as soon as the quotient passes 2^53 − 1.
fn long_division(
  quotient: Int,
  remainder: Int,
  denominator: Int,
  places: Int,
) -> Result(#(Int, Int), ArithmeticError) {
  use <- bool.guard(when: places <= 0, return: Ok(#(quotient, remainder)))
  let #(digit, remainder) = times_ten(remainder, denominator, 10, 0, 0)
  use <- bool.guard(
    when: quotient > { max_safe_coefficient - digit } / 10,
    return: Error(PrecisionExceeded),
  )
  long_division(quotient * 10 + digit, remainder, denominator, places - 1)
}

// Returns the quotient and remainder of `value × 10 / modulus`, for
// `0 <= value < modulus`, by adding `value` ten times modulo `modulus`.
// The running total stays below `modulus`.
fn times_ten(
  value: Int,
  modulus: Int,
  count: Int,
  carries: Int,
  total: Int,
) -> #(Int, Int) {
  use <- bool.guard(when: count == 0, return: #(carries, total))
  let room = modulus - value
  case total >= room {
    True -> times_ten(value, modulus, count - 1, carries + 1, total - room)
    False -> times_ten(value, modulus, count - 1, carries, total + value)
  }
}

fn sign_of(value: Int) -> Int {
  use <- bool.guard(when: value < 0, return: -1)
  1
}

// Compares two non-negative integers written without leading zeros.
fn compare_digits(a: String, b: String) -> order.Order {
  case int.compare(string.length(a), string.length(b)) {
    order.Eq -> string.compare(a, b)
    other -> other
  }
}

fn pow_10(places: Int) -> Int {
  int.product(list.repeat(10, places))
}
