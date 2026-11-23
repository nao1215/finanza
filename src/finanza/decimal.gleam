//// Fixed-point decimal numbers with explicit rounding.
////
//// A `Decimal` is a coefficient and a base-10 exponent, so `12.30` is
//// the coefficient `1230` with the exponent `-2`. Operations that can
//// lose digits take a `RoundingMode`.
////
//// The coefficient, and the integer a positive exponent stands for,
//// stay within ±9,007,199,254,740,991 (2^53 − 1) on both targets, so
//// results are the same on Erlang and JavaScript. Results outside
//// that range are `PrecisionExceeded` errors.

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
  /// The value is outside the supported range.
  ParsedValueTooLarge
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
/// Returns `Error(Nil)` when the value is outside the supported range.
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
/// Returns `Error(PrecisionExceeded)` when the product is out of range.
///
pub fn multiply(a: Decimal, b: Decimal) -> Result(Decimal, ArithmeticError) {
  checked(a.coefficient * b.coefficient, a.exponent + b.exponent)
}

/// Divides `a` by `b` and rounds the quotient to `digits` places after
/// the decimal point.
///
/// Returns `Error(DivisionByZero)` when `b` is zero, and
/// `Error(PrecisionExceeded)` when the quotient at that many places is
/// out of range, which happens from about 15 places for `1 / 3`.
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
  use <- bool.guard(when: a.coefficient == 0, return: checked(0, -digits))
  let sign = sign_of(a.coefficient) * sign_of(b.coefficient)
  let numerator = int.absolute_value(a.coefficient)
  let denominator = int.absolute_value(b.coefficient)
  let shift = a.exponent - b.exponent + digits
  case shift >= 0 {
    True -> {
      use numerator <- result.try(scale_up(numerator, shift))
      round_quotient(numerator, denominator, sign, mode)
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
/// so on. Returns `Error(PrecisionExceeded)` when the padded or rounded
/// value is out of range.
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
  let quotient = numerator / denominator
  let remainder = numerator - quotient * denominator
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
    0, _ -> True
    _, False -> magnitude <= max_safe_coefficient
    _, True ->
      exponent <= 15 && magnitude * pow_10(exponent) <= max_safe_coefficient
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
