//// Fixed-point decimal arithmetic with explicit rounding.
////
//// A [`Decimal`](#Decimal) is represented internally as a signed
//// integer `coefficient` and an `exponent`:
////
//// ```text
//// value = coefficient × 10^exponent
//// ```
////
//// `Decimal` is `pub opaque`; construct values through [`from_int`](#from_int),
//// [`from_string`](#from_string), or [`new`](#new), and inspect them through
//// [`coefficient`](#coefficient) and [`exponent`](#exponent).
////
//// ## Precision boundary
////
//// On the JavaScript target, Gleam's `Int` is a 64-bit IEEE 754 number,
//// so coefficients are limited to ±(2^53 − 1) = 9_007_199_254_740_991.
//// Operations that would produce a larger coefficient return
//// [`PrecisionExceeded`](#ArithmeticError). On the Erlang target,
//// integers are arbitrary precision; the same bound is enforced anyway
//// so behaviour is consistent across targets.

import gleam/bool
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

import finanza/decimal/rounding

/// Fixed-point decimal value. Construct via [`from_int`](#from_int),
/// [`from_string`](#from_string), or [`new`](#new).
pub opaque type Decimal {
  Decimal(coefficient: Int, exponent: Int)
}

/// Errors returned by [`from_string`](#from_string).
pub type ParseError {
  /// The input was the empty string or contained only whitespace.
  EmptyInput
  /// The input contained a character that is not a digit, sign, or
  /// decimal point.
  InvalidCharacter(char: String, position: Int)
  /// The input contained more than one decimal point.
  MultipleDecimalPoints
  /// The input contained more than one sign character.
  MultipleSigns
  /// The input contained no digits (e.g. `"+"`, `"."`, `"-."`).
  NoDigits
  /// The parsed coefficient would exceed `±9_007_199_254_740_991`
  /// (the JavaScript-safe integer ceiling). Such a value cannot be
  /// represented faithfully on the JavaScript target; rather than
  /// silently corrupt it (and emit unparseable strings from
  /// [`to_string`](#to_string)), parsing fails fast.
  ParsedValueTooLarge
}

/// Errors returned by arithmetic operations.
pub type ArithmeticError {
  /// The right-hand operand of a [`divide`](#divide) was zero.
  DivisionByZero
  /// The result would not fit in the supported precision window
  /// (±9_007_199_254_740_991). Reduce intermediate precision with
  /// [`round`](#round) and retry.
  PrecisionExceeded
}

/// Errors returned by validated constructors
/// ([`try_new`](#try_new), [`try_from_int`](#try_from_int)).
pub type ConstructError {
  /// The supplied coefficient — or the value implied once the
  /// exponent is applied (`|coefficient| × 10^exponent` for
  /// `exponent ≥ 0`) — would exceed `±9_007_199_254_740_991`
  /// (the JavaScript-safe integer ceiling). Such a value cannot
  /// round-trip through [`to_string`](#to_string) and
  /// [`from_string`](#from_string), so construction fails fast
  /// rather than producing a `Decimal` the library cannot read
  /// back.
  CoefficientTooLarge
}

/// 2^53 − 1. The largest absolute coefficient that remains exact on
/// JavaScript's `Number` representation. The Erlang target tolerates
/// larger values, but this bound is enforced everywhere so behaviour
/// matches across targets.
const max_safe_coefficient: Int = 9_007_199_254_740_991

// --- Constructors --------------------------------------------------------

/// The decimal value 0.
pub fn zero() -> Decimal {
  Decimal(0, 0)
}

/// The decimal value 1.
pub fn one() -> Decimal {
  Decimal(1, 0)
}

/// Build a `Decimal` from an integer.
///
/// Panics if `|n| > 9_007_199_254_740_991` (such a coefficient
/// cannot round-trip through [`to_string`](#to_string) and
/// [`from_string`](#from_string)). Use [`try_from_int`](#try_from_int)
/// when the input is supplied by a caller and might exceed the
/// safe range — that variant returns a `Result` instead of
/// panicking.
pub fn from_int(n n: Int) -> Decimal {
  let assert Ok(d) = try_from_int(n: n)
  d
}

/// Build a `Decimal` from an integer, returning a `Result`.
///
/// Returns `Error(CoefficientTooLarge)` when
/// `|n| > 9_007_199_254_740_991`, which is the threshold above
/// which the resulting `Decimal` cannot round-trip through
/// [`to_string`](#to_string) and [`from_string`](#from_string).
pub fn try_from_int(n n: Int) -> Result(Decimal, ConstructError) {
  use <- bool.guard(
    when: int.absolute_value(n) > max_safe_coefficient,
    return: Error(CoefficientTooLarge),
  )
  Ok(Decimal(n, 0))
}

/// Build a `Decimal` directly from a coefficient and exponent.
///
/// `new(coefficient: 1234, exponent: -2)` represents `12.34`.
///
/// Panics if the implied rendered value exceeds the safe range
/// (`|coefficient| > 9_007_199_254_740_991`, or — for non-negative
/// `exponent` — `|coefficient| × 10^exponent > 9_007_199_254_740_991`).
/// Use [`try_new`](#try_new) when the inputs are supplied by a
/// caller and might exceed the safe range — that variant returns
/// a `Result` instead of panicking.
pub fn new(coefficient coefficient: Int, exponent exponent: Int) -> Decimal {
  case try_new(coefficient: coefficient, exponent: exponent) {
    Ok(d) -> d
    Error(CoefficientTooLarge) -> {
      let msg =
        "finanza/decimal.new: coefficient "
        <> int.to_string(coefficient)
        <> " (exponent "
        <> int.to_string(exponent)
        <> ") would overflow the JS-safe range (|coefficient| > "
        <> int.to_string(max_safe_coefficient)
        <> "); use decimal.try_new for inputs that might exceed this bound"
      panic as msg
    }
  }
}

/// Build a `Decimal` from a coefficient and exponent, returning a
/// `Result`.
///
/// Returns `Error(CoefficientTooLarge)` when the rendered value
/// would overflow the safe range — either because
/// `|coefficient| > 9_007_199_254_740_991`, or because a positive
/// `exponent` would push the rendered integer
/// (`|coefficient| × 10^exponent`) past that bound. Such a value
/// cannot round-trip through [`to_string`](#to_string) and
/// [`from_string`](#from_string).
pub fn try_new(
  coefficient coefficient: Int,
  exponent exponent: Int,
) -> Result(Decimal, ConstructError) {
  let abs = int.absolute_value(coefficient)
  use <- bool.guard(
    when: abs > max_safe_coefficient,
    return: Error(CoefficientTooLarge),
  )
  case exponent > 0 {
    True ->
      case rendered_fits(abs: abs, zeros_remaining: exponent) {
        True -> Ok(Decimal(coefficient, exponent))
        False -> Error(CoefficientTooLarge)
      }
    False -> Ok(Decimal(coefficient, exponent))
  }
}

fn rendered_fits(abs abs: Int, zeros_remaining zeros_remaining: Int) -> Bool {
  case zeros_remaining {
    0 -> abs <= max_safe_coefficient
    _ -> {
      use <- bool.guard(when: abs > max_safe_coefficient, return: False)
      rendered_fits(abs: abs * 10, zeros_remaining: zeros_remaining - 1)
    }
  }
}

/// Parse a decimal from a string. Accepts an optional leading `+` or
/// `-`, decimal digits, and at most one `.` separator. Scientific
/// notation is not supported.
///
/// ```gleam
/// from_string("3.14")    // Ok(Decimal with coefficient=314, exponent=-2)
/// from_string("-0.5")    // Ok(Decimal with coefficient=-5, exponent=-1)
/// from_string("")        // Error(EmptyInput)
/// from_string("1.2.3")   // Error(MultipleDecimalPoints)
/// ```
pub fn from_string(input input: String) -> Result(Decimal, ParseError) {
  let trimmed = string.trim(input)
  use <- bool.guard(when: trimmed == "", return: Error(EmptyInput))
  parse_loop(state: ParseState(
    chars: string.to_graphemes(trimmed),
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
    chars: List(String),
    position: Int,
    sign: Int,
    digits: Int,
    fraction_digits: Int,
    saw_dot: Bool,
    saw_sign: Bool,
    saw_digit: Bool,
  )
}

fn parse_loop(state state: ParseState) -> Result(Decimal, ParseError) {
  case state.chars {
    [] -> finalize_parse(state)
    [head, ..tail] -> parse_step(state: state, char: head, rest: tail)
  }
}

fn finalize_parse(state: ParseState) -> Result(Decimal, ParseError) {
  use <- bool.guard(when: !state.saw_digit, return: Error(NoDigits))
  use <- bool.guard(
    when: int.absolute_value(state.digits) > max_safe_coefficient,
    return: Error(ParsedValueTooLarge),
  )
  Ok(Decimal(state.sign * state.digits, -state.fraction_digits))
}

fn parse_step(
  state state: ParseState,
  char char: String,
  rest rest: List(String),
) -> Result(Decimal, ParseError) {
  case classify(char) {
    SignChar(value) -> handle_sign(state: state, value: value, rest: rest)
    DotChar -> handle_dot(state: state, rest: rest)
    DigitChar(value) -> handle_digit(state: state, value: value, rest: rest)
    OtherChar -> Error(InvalidCharacter(char: char, position: state.position))
  }
}

type CharKind {
  SignChar(value: Int)
  DotChar
  DigitChar(value: Int)
  OtherChar
}

fn classify(char: String) -> CharKind {
  case char {
    "+" -> SignChar(1)
    "-" -> SignChar(-1)
    "." -> DotChar
    "0" -> DigitChar(0)
    "1" -> DigitChar(1)
    "2" -> DigitChar(2)
    "3" -> DigitChar(3)
    "4" -> DigitChar(4)
    "5" -> DigitChar(5)
    "6" -> DigitChar(6)
    "7" -> DigitChar(7)
    "8" -> DigitChar(8)
    "9" -> DigitChar(9)
    _ -> OtherChar
  }
}

fn handle_sign(
  state state: ParseState,
  value value: Int,
  rest rest: List(String),
) -> Result(Decimal, ParseError) {
  use <- bool.guard(
    when: state.position != 0 || state.saw_sign,
    return: Error(MultipleSigns),
  )
  parse_loop(
    state: ParseState(
      ..state,
      chars: rest,
      position: state.position + 1,
      sign: value,
      saw_sign: True,
    ),
  )
}

fn handle_dot(
  state state: ParseState,
  rest rest: List(String),
) -> Result(Decimal, ParseError) {
  use <- bool.guard(when: state.saw_dot, return: Error(MultipleDecimalPoints))
  parse_loop(
    state: ParseState(
      ..state,
      chars: rest,
      position: state.position + 1,
      saw_dot: True,
    ),
  )
}

fn handle_digit(
  state state: ParseState,
  value value: Int,
  rest rest: List(String),
) -> Result(Decimal, ParseError) {
  let new_fraction = case state.saw_dot {
    True -> state.fraction_digits + 1
    False -> state.fraction_digits
  }
  parse_loop(
    state: ParseState(
      ..state,
      chars: rest,
      position: state.position + 1,
      digits: state.digits * 10 + value,
      fraction_digits: new_fraction,
      saw_digit: True,
    ),
  )
}

// --- Accessors -----------------------------------------------------------

/// The signed coefficient component.
pub fn coefficient(d d: Decimal) -> Int {
  d.coefficient
}

/// The exponent component (base 10).
pub fn exponent(d d: Decimal) -> Int {
  d.exponent
}

/// Convert to a plain integer.
///
/// Succeeds only when `d` is *exactly* integer-valued — no fractional
/// part *and* the resulting integer fits within
/// `±max_safe_coefficient`. Both a non-zero fractional remainder and a
/// coefficient overflow produce `PrecisionExceeded`. Use
/// [`to_int_truncated`](#to_int_truncated) when the fractional part
/// should be dropped toward zero, or
/// [`to_int_rounded`](#to_int_rounded) when it should be rounded using
/// a specific [`rounding.Mode`](decimal/rounding.html#Mode).
///
/// ```gleam
/// to_int(from_int(7))                 // Ok(7)
/// let assert Ok(d) = from_string("12.34")
/// to_int(d)                           // Error(PrecisionExceeded)
/// let assert Ok(d) = from_string("12.00")
/// to_int(d)                           // Ok(12)
/// ```
pub fn to_int(d d: Decimal) -> Result(Int, ArithmeticError) {
  case int.compare(d.exponent, 0) {
    order.Eq -> Ok(d.coefficient)
    order.Gt -> scale_up(d.coefficient, d.exponent)
    order.Lt -> {
      let divisor = pow_10(-d.exponent)
      let abs_c = int.absolute_value(d.coefficient)
      let remainder = abs_c - abs_c / divisor * divisor
      case remainder {
        0 -> Ok(d.coefficient / divisor)
        _ -> Error(PrecisionExceeded)
      }
    }
  }
}

/// Truncate `d` toward zero (`rounding.Down`) and return the integer.
///
/// Drops the fractional part regardless of its size, so `-1.9` becomes
/// `-1` and `1.9` becomes `1`. Use
/// [`to_int_rounded`](#to_int_rounded) when a different rounding mode
/// is needed. Returns `PrecisionExceeded` only when the truncated
/// integer cannot fit within `±max_safe_coefficient` (a fractional
/// part on its own never causes a failure here, unlike
/// [`to_int`](#to_int)).
pub fn to_int_truncated(d d: Decimal) -> Result(Int, ArithmeticError) {
  to_int_rounded(d: d, mode: rounding.Down)
}

/// Round `d` to an integer using `mode` and return that integer.
///
/// `mode` is applied as if rounding to zero decimal places — so
/// `to_int_rounded(d, mode: rounding.HalfEven)` is the natural fit
/// for the "I rounded to N decimals, now give me the integer"
/// workflow. Returns `PrecisionExceeded` only when the rounded
/// integer cannot fit within `±max_safe_coefficient`.
pub fn to_int_rounded(
  d d: Decimal,
  mode mode: rounding.Mode,
) -> Result(Int, ArithmeticError) {
  use rescaled <- result.map(rescale(d: d, target_exponent: 0, mode: mode))
  rescaled.coefficient
}

/// Render a `Decimal` as a plain string. Preserves the encoded
/// exponent (`new(coefficient: 100, exponent: -2)` renders as `"1.00"`,
/// not `"1"`).
pub fn to_string(d d: Decimal) -> String {
  case d.coefficient {
    0 -> render_zero(d.exponent)
    _ -> render_nonzero(d.coefficient, d.exponent)
  }
}

/// Render a `Decimal` with custom thousands and decimal separators.
///
/// ```gleam
/// format(d, thousands: ",", decimal_separator: ".")  // "1,234.56"
/// format(d, thousands: ".", decimal_separator: ",")  // "1.234,56" (German)
/// format(d, thousands: "",  decimal_separator: ".")  // "1234.56"
/// ```
///
/// Equivalent to [`to_string`](#to_string) when `thousands` is empty
/// and `decimal_separator` is `"."`.
pub fn format(
  d d: Decimal,
  thousands thousands: String,
  decimal_separator decimal_separator: String,
) -> String {
  let raw = to_string(d: d)
  let sign_prefix = case d.coefficient < 0 {
    True -> "-"
    False -> ""
  }
  let unsigned = case sign_prefix {
    "" -> raw
    _ -> string.drop_start(raw, 1)
  }
  let body =
    inject_thousands(
      unsigned: unsigned,
      thousands: thousands,
      decimal_separator: decimal_separator,
    )
  sign_prefix <> body
}

fn inject_thousands(
  unsigned unsigned: String,
  thousands thousands: String,
  decimal_separator decimal_separator: String,
) -> String {
  case string.split(unsigned, ".") {
    [integer_part] -> group_integer(integer_part, thousands)
    [integer_part, fraction_part] ->
      group_integer(integer_part, thousands)
      <> decimal_separator
      <> fraction_part
    _ -> unsigned
  }
}

fn group_integer(digits: String, separator: String) -> String {
  use <- bool.guard(when: separator == "", return: digits)
  let chars = string.to_graphemes(digits)
  let length = list.length(chars)
  let groups = group_right(chars: chars, length: length, acc: [])
  groups
  |> list.map(string.concat)
  |> string.join(with: separator)
}

fn group_right(
  chars chars: List(String),
  length length: Int,
  acc acc: List(List(String)),
) -> List(List(String)) {
  use <- bool.guard(when: length <= 3, return: [chars, ..acc])
  let head_size = length - 3
  let head = list.take(chars, head_size)
  let tail = list.drop(chars, head_size)
  group_right(chars: head, length: head_size, acc: [tail, ..acc])
}

fn render_zero(exp: Int) -> String {
  use <- bool.guard(when: exp >= 0, return: "0")
  "0." <> string.repeat("0", -exp)
}

fn render_nonzero(coefficient: Int, exp: Int) -> String {
  let sign_prefix = case coefficient < 0 {
    True -> "-"
    False -> ""
  }
  let digits = int.to_string(int.absolute_value(coefficient))
  use <- bool.guard(
    when: exp >= 0,
    return: sign_prefix <> digits <> string.repeat("0", exp),
  )
  render_with_fraction(
    sign_prefix: sign_prefix,
    digits: digits,
    fraction_size: -exp,
  )
}

fn render_with_fraction(
  sign_prefix sign_prefix: String,
  digits digits: String,
  fraction_size fraction_size: Int,
) -> String {
  let digit_length = string.length(digits)
  use <- bool.guard(
    when: digit_length <= fraction_size,
    return: sign_prefix
      <> "0."
      <> string.repeat("0", fraction_size - digit_length)
      <> digits,
  )
  let integer_part = string.slice(digits, 0, digit_length - fraction_size)
  let fraction_part =
    string.slice(digits, digit_length - fraction_size, fraction_size)
  sign_prefix <> integer_part <> "." <> fraction_part
}

// --- Sign predicates -----------------------------------------------------

/// Test for the zero decimal.
pub fn is_zero(d d: Decimal) -> Bool {
  d.coefficient == 0
}

/// Test for a strictly positive decimal.
pub fn is_positive(d d: Decimal) -> Bool {
  d.coefficient > 0
}

/// Test for a strictly negative decimal.
pub fn is_negative(d d: Decimal) -> Bool {
  d.coefficient < 0
}

// --- Sign helpers --------------------------------------------------------

/// Negate the value. Always safe (the coefficient sign flips but
/// magnitude does not change).
pub fn negate(d d: Decimal) -> Decimal {
  Decimal(coefficient: -d.coefficient, exponent: d.exponent)
}

/// Absolute value. Always safe.
pub fn absolute(d d: Decimal) -> Decimal {
  Decimal(coefficient: int.absolute_value(d.coefficient), exponent: d.exponent)
}

// --- Arithmetic ----------------------------------------------------------

/// Add two decimals.
///
/// When one operand is zero the result is just the other operand —
/// we short-circuit without going through `align`. Without the
/// short-circuit, `align` would try to scale the smaller-exponent
/// operand up to the larger's exponent (e.g. `1 × 10^20` for
/// `new(1, 20) + zero()`), which can exceed `max_safe_coefficient`
/// and surface a spurious `PrecisionExceeded` despite the
/// mathematical result fitting trivially. When both operands are
/// zero we still return zero, but with the smaller of the two
/// exponents so that `add(a, b) == add(b, a)` holds at the level of
/// structural equality (the same invariant `align` provided before).
pub fn add(a a: Decimal, b b: Decimal) -> Result(Decimal, ArithmeticError) {
  case a.coefficient, b.coefficient {
    0, 0 ->
      Ok(Decimal(coefficient: 0, exponent: int.min(a.exponent, b.exponent)))
    0, _ -> Ok(b)
    _, 0 -> Ok(a)
    _, _ -> {
      use #(ac, bc, target) <- result.try(align(a, b))
      use sum <- result.map(check_precision(ac + bc))
      Decimal(coefficient: sum, exponent: target)
    }
  }
}

/// Subtract `b` from `a`.
pub fn subtract(a a: Decimal, b b: Decimal) -> Result(Decimal, ArithmeticError) {
  add(a: a, b: negate(d: b))
}

/// Multiply two decimals.
pub fn multiply(a a: Decimal, b b: Decimal) -> Result(Decimal, ArithmeticError) {
  use product <- result.map(check_precision(a.coefficient * b.coefficient))
  Decimal(coefficient: product, exponent: a.exponent + b.exponent)
}

/// Divide `a` by `b`, returning a result rounded to `digits` decimal
/// places using `mode`.
///
/// Returns [`DivisionByZero`](#ArithmeticError) when `b` is zero, or
/// [`PrecisionExceeded`](#ArithmeticError) when the intermediate
/// representation would exceed `±9_007_199_254_740_991`.
pub fn divide(
  a a: Decimal,
  b b: Decimal,
  digits digits: Int,
  mode mode: rounding.Mode,
) -> Result(Decimal, ArithmeticError) {
  use <- bool.guard(when: b.coefficient == 0, return: Error(DivisionByZero))
  divide_nonzero(a: a, b: b, digits: digits, mode: mode)
}

fn divide_nonzero(
  a a: Decimal,
  b b: Decimal,
  digits digits: Int,
  mode mode: rounding.Mode,
) -> Result(Decimal, ArithmeticError) {
  let result_sign = sign_of(a.coefficient) * sign_of(b.coefficient)
  let abs_a = int.absolute_value(a.coefficient)
  let abs_b = int.absolute_value(b.coefficient)
  let shift = a.exponent - b.exponent + digits
  use #(numerator, denominator) <- result.try(prepare_division(
    abs_a: abs_a,
    abs_b: abs_b,
    shift: shift,
  ))
  let q = numerator / denominator
  let r = numerator - q * denominator
  let bumped =
    apply_rounding(
      q: q,
      r: r,
      denominator: denominator,
      result_sign: result_sign,
      mode: mode,
    )
  use safe_q <- result.map(check_precision(bumped))
  Decimal(coefficient: result_sign * safe_q, exponent: -digits)
}

fn prepare_division(
  abs_a abs_a: Int,
  abs_b abs_b: Int,
  shift shift: Int,
) -> Result(#(Int, Int), ArithmeticError) {
  case shift >= 0 {
    True -> {
      use scaled_a <- result.map(scale_up(abs_a, shift))
      #(scaled_a, abs_b)
    }
    False -> {
      use scaled_b <- result.map(scale_up(abs_b, -shift))
      #(abs_a, scaled_b)
    }
  }
}

fn apply_rounding(
  q q: Int,
  r r: Int,
  denominator denominator: Int,
  result_sign result_sign: Int,
  mode mode: rounding.Mode,
) -> Int {
  use <- bool.guard(when: r == 0, return: q)
  case
    should_bump_up(
      r: r,
      denominator: denominator,
      q: q,
      result_sign: result_sign,
      mode: mode,
    )
  {
    True -> q + 1
    False -> q
  }
}

fn should_bump_up(
  r r: Int,
  denominator denominator: Int,
  q q: Int,
  result_sign result_sign: Int,
  mode mode: rounding.Mode,
) -> Bool {
  case mode {
    rounding.HalfEven -> half_even_bump(r: r, denominator: denominator, q: q)
    rounding.HalfUp -> 2 * r >= denominator
    rounding.HalfDown -> 2 * r > denominator
    rounding.Up -> True
    rounding.Down -> False
    rounding.Ceiling -> result_sign > 0
    rounding.Floor -> result_sign < 0
  }
}

fn half_even_bump(r r: Int, denominator denominator: Int, q q: Int) -> Bool {
  case int.compare(2 * r, denominator) {
    order.Gt -> True
    order.Lt -> False
    order.Eq -> q % 2 == 1
  }
}

// --- Rescaling -----------------------------------------------------------

/// Round to `digits` decimal places, **trim only**. When the input
/// is already at equal or coarser precision than `-digits` (e.g.
/// `Decimal(coefficient: 2000, exponent: 0)` against `digits: 2`),
/// the original `Decimal` is returned unchanged — `round` never
/// pads with zeros, so `to_string(round(from_int(2000), 2, _))` is
/// `"2000"`, not `"2000.00"`.
///
/// Use [`rescale`](#rescale) when the result must always have
/// exponent `-digits` (i.e. the rendered form must always have
/// exactly `digits` decimal places, including trailing zeros) —
/// `rescale` returns `Result` because the padding direction can
/// overflow `±9_007_199_254_740_991`.
pub fn round(
  d d: Decimal,
  digits digits: Int,
  mode mode: rounding.Mode,
) -> Decimal {
  let target_exponent = -digits
  use <- bool.guard(when: target_exponent <= d.exponent, return: d)
  drop_digits(d: d, target_exponent: target_exponent, mode: mode)
}

/// Truncate to `digits` decimal places (rounding toward zero), **trim
/// only**. Like [`round`](#round), the input is returned unchanged
/// when it is already at equal or coarser precision than `-digits`.
pub fn truncate(d d: Decimal, digits digits: Int) -> Decimal {
  round(d: d, digits: digits, mode: rounding.Down)
}

/// Force the decimal to a specific exponent. When the new exponent is
/// finer (smaller), the coefficient grows by zero-padding (may overflow).
/// When the new exponent is coarser (larger), digits are dropped using
/// `mode`.
pub fn rescale(
  d d: Decimal,
  target_exponent target_exponent: Int,
  mode mode: rounding.Mode,
) -> Result(Decimal, ArithmeticError) {
  case int.compare(target_exponent, d.exponent) {
    order.Eq -> Ok(d)
    order.Lt -> {
      use scaled <- result.map(scale_up(
        d.coefficient,
        d.exponent - target_exponent,
      ))
      Decimal(coefficient: scaled, exponent: target_exponent)
    }
    order.Gt ->
      Ok(drop_digits(d: d, target_exponent: target_exponent, mode: mode))
  }
}

fn drop_digits(
  d d: Decimal,
  target_exponent target_exponent: Int,
  mode mode: rounding.Mode,
) -> Decimal {
  let diff = target_exponent - d.exponent
  let divisor = pow_10(diff)
  let abs_c = int.absolute_value(d.coefficient)
  let q = abs_c / divisor
  let r = abs_c - q * divisor
  let sign = sign_of(d.coefficient)
  let bumped =
    apply_rounding(
      q: q,
      r: r,
      denominator: divisor,
      result_sign: sign,
      mode: mode,
    )
  Decimal(coefficient: sign * bumped, exponent: target_exponent)
}

// --- Comparison ----------------------------------------------------------

/// Total ordering. Two values with the same numeric value compare as
/// equal even when their exponents differ.
pub fn compare(a a: Decimal, b b: Decimal) -> order.Order {
  case align(a, b) {
    Ok(#(ac, bc, _)) -> int.compare(ac, bc)
    Error(PrecisionExceeded) -> compare_by_magnitude(a, b)
    Error(DivisionByZero) -> compare_by_magnitude(a, b)
  }
}

/// Equality test by numeric value, not by representation.
/// `equal(new(coefficient: 100, exponent: -2), one())` is `True`.
pub fn equal(a a: Decimal, b b: Decimal) -> Bool {
  let na = normalize(a)
  let nb = normalize(b)
  na.coefficient == nb.coefficient && na.exponent == nb.exponent
}

fn normalize(d: Decimal) -> Decimal {
  case d.coefficient {
    0 -> Decimal(coefficient: 0, exponent: 0)
    _ -> strip_trailing_zeros(d)
  }
}

fn strip_trailing_zeros(d: Decimal) -> Decimal {
  case d.coefficient % 10 {
    0 -> strip_trailing_zeros(Decimal(d.coefficient / 10, d.exponent + 1))
    _ -> d
  }
}

fn compare_by_magnitude(a: Decimal, b: Decimal) -> order.Order {
  case int.compare(sign_of(a.coefficient), sign_of(b.coefficient)) {
    order.Eq -> compare_same_sign(a, b)
    other -> other
  }
}

fn compare_same_sign(a: Decimal, b: Decimal) -> order.Order {
  let na = normalize(a)
  let nb = normalize(b)
  let abs_a = int.absolute_value(na.coefficient)
  let abs_b = int.absolute_value(nb.coefficient)
  let len_a = digit_count(abs_a)
  let len_b = digit_count(abs_b)
  let mag_a = len_a + na.exponent
  let mag_b = len_b + nb.exponent
  let raw = case int.compare(mag_a, mag_b) {
    order.Eq ->
      compare_same_magnitude(a: abs_a, len_a: len_a, b: abs_b, len_b: len_b)
    other -> other
  }
  use <- bool.guard(when: na.coefficient < 0, return: reverse_order(raw))
  raw
}

/// Compare two non-negative integers that share a common magnitude
/// (`digit_count + exponent` ties at the call site). The two
/// coefficients may carry different digit counts; the shorter is
/// right-padded with zeros to match the longer, after which a
/// lexicographic compare of equal-length non-negative digit strings is
/// numerically correct. This path avoids `a * 10^k` to remain safe
/// even when the caller has constructed an out-of-bounds coefficient
/// via `new/2`.
fn compare_same_magnitude(
  a a: Int,
  len_a len_a: Int,
  b b: Int,
  len_b len_b: Int,
) -> order.Order {
  let max_len = int.max(len_a, len_b)
  let str_a = int.to_string(a) <> string.repeat("0", max_len - len_a)
  let str_b = int.to_string(b) <> string.repeat("0", max_len - len_b)
  string.compare(str_a, str_b)
}

fn reverse_order(o: order.Order) -> order.Order {
  case o {
    order.Lt -> order.Gt
    order.Gt -> order.Lt
    order.Eq -> order.Eq
  }
}

fn digit_count(n: Int) -> Int {
  use <- bool.guard(when: n < 10, return: 1)
  1 + digit_count(n / 10)
}

// --- Internals -----------------------------------------------------------

fn sign_of(n: Int) -> Int {
  case int.compare(n, 0) {
    order.Lt -> -1
    order.Gt -> 1
    order.Eq -> 1
  }
}

fn check_precision(n: Int) -> Result(Int, ArithmeticError) {
  use <- bool.guard(
    when: int.absolute_value(n) > max_safe_coefficient,
    return: Error(PrecisionExceeded),
  )
  Ok(n)
}

fn align(a: Decimal, b: Decimal) -> Result(#(Int, Int, Int), ArithmeticError) {
  let target = int.min(a.exponent, b.exponent)
  use scaled_a <- result.try(scale_up(a.coefficient, a.exponent - target))
  use scaled_b <- result.map(scale_up(b.coefficient, b.exponent - target))
  #(scaled_a, scaled_b, target)
}

fn scale_up(c: Int, by: Int) -> Result(Int, ArithmeticError) {
  case by {
    0 -> Ok(c)
    _ -> check_precision(c * pow_10(by))
  }
}

fn pow_10(n: Int) -> Int {
  pow_10_loop(n, 1)
}

fn pow_10_loop(n: Int, acc: Int) -> Int {
  use <- bool.guard(when: n <= 0, return: acc)
  pow_10_loop(n - 1, acc * 10)
}
