//// Exact arithmetic followed by one rounding, for `finanza/money` and
//// `finanza/interest`.
////
//// `decimal.multiply` returns the exact product, so it fails when the
//// product has a non-zero digit past 28 places or more than 2^53 − 1 in
//// its coefficient, even when the caller is about to round it to a few
//// places. `multiply` here rounds the exact product directly, so only the
//// rounded value has to be in range. `Number` holds exact values of any
//// size, so the interest functions can compute or bound a result
//// exactly and round it once.

import gleam/bool
import gleam/int
import gleam/list
import gleam/order
import gleam/result

import finanza/decimal.{type Decimal, type RoundingMode}
import finanza/internal/limb

/// Returns `a × b` rounded to `digits` places after the decimal point,
/// with the same result as `decimal.round` gives for the exact product.
///
/// Returns `Error(PrecisionExceeded)` when `digits` is outside -15 to 28
/// or the rounded product is out of range.
///
pub fn multiply(
  a: Decimal,
  b: Decimal,
  digits digits: Int,
  rounding mode: RoundingMode,
) -> Result(Decimal, decimal.ArithmeticError) {
  use <- bool.guard(
    when: digits < -15 || digits > 28,
    return: Error(decimal.PrecisionExceeded),
  )
  let left = int.absolute_value(decimal.coefficient(a))
  let right = int.absolute_value(decimal.coefficient(b))
  let sign = case decimal.is_negative(a) == decimal.is_negative(b) {
    True -> 1
    False -> -1
  }
  let exponent = decimal.exponent(a) + decimal.exponent(b)
  // A product within 2^53 - 1 whose exponent is in range is a Decimal
  // already, so `decimal.round` rounds it.
  let small = case left == 0 || left <= limb.max_safe_coefficient / right {
    True ->
      decimal.new(
        coefficient: decimal.coefficient(a) * decimal.coefficient(b),
        exponent:,
      )
    False -> Error(Nil)
  }
  case small, left == 0 || right == 0 {
    Ok(exact), _ -> decimal.round(exact, digits:, rounding: mode)
    Error(Nil), True ->
      decimal.new(coefficient: 0, exponent: -digits)
      |> result.replace_error(decimal.PrecisionExceeded)
    Error(Nil), False ->
      round_digits(
        limb.product_digits(left, right),
        -digits - exponent,
        sign,
        mode,
      )
      |> result.try(fn(coefficient) {
        decimal.new(coefficient:, exponent: -digits)
        |> result.replace_error(decimal.PrecisionExceeded)
      })
  }
}

/// An exact number of any size, `sign × limbs × 10^exponent`, for the
/// interest functions. `limbs` has no leading zero limbs, so zero is
/// `[]`, and the sign of zero is 1.
///
pub type Number {
  Number(sign: Int, limbs: List(Int), exponent: Int)
}

/// The exact value of a decimal.
///
pub fn from_decimal(value: Decimal) -> Number {
  number(
    sign_of(value),
    limb.limbs(int.absolute_value(decimal.coefficient(value))),
    decimal.exponent(value),
  )
}

/// The exact value of an integer within 2^53 − 1.
///
pub fn from_int(value: Int) -> Number {
  number(
    case value < 0 {
      True -> -1
      False -> 1
    },
    limb.limbs(int.absolute_value(value)),
    0,
  )
}

fn number(sign: Int, limbs: List(Int), exponent: Int) -> Number {
  case limb.trim(limbs) {
    [] -> Number(1, [], 0)
    limbs -> Number(sign, limbs, exponent)
  }
}

/// Returns `True` when the number is zero.
///
pub fn is_zero(value: Number) -> Bool {
  value.limbs == []
}

/// The number with its sign flipped.
///
pub fn negate(value: Number) -> Number {
  number(-value.sign, value.limbs, value.exponent)
}

/// The number without its sign.
///
pub fn absolute(value: Number) -> Number {
  Number(..value, sign: 1)
}

/// The exact product.
///
pub fn times(a: Number, b: Number) -> Number {
  number(
    a.sign * b.sign,
    limb.multiply(a.limbs, b.limbs),
    a.exponent + b.exponent,
  )
}

/// The exact sum.
///
pub fn plus(a: Number, b: Number) -> Number {
  use <- bool.guard(when: is_zero(a), return: b)
  use <- bool.guard(when: is_zero(b), return: a)
  let exponent = int.min(a.exponent, b.exponent)
  let #(sign, limbs) =
    limb.add(#(a.sign, limb.shift(a.limbs, zeros: a.exponent - exponent)), #(
      b.sign,
      limb.shift(b.limbs, zeros: b.exponent - exponent),
    ))
  number(sign, limbs, exponent)
}

/// Keeps the `limbs` most significant limbs of the number, dropping the
/// rest toward zero, or away from zero when `up` is set and a dropped
/// limb is not zero. `limbs` of 0 keeps every limb.
///
pub fn truncate(value: Number, limbs count: Int, up up: Bool) -> Number {
  let length = list.length(value.limbs)
  case count <= 0 || length <= count {
    True -> value
    False -> {
      let #(dropped, kept) = list.split(value.limbs, length - count)
      let kept = case up && list.any(dropped, fn(limb) { limb != 0 }) {
        True -> limb.trim(limb.add(#(1, kept), #(1, [1])).1)
        False -> kept
      }
      number(value.sign, kept, value.exponent + 7 * { length - count })
    }
  }
}

/// `a / b` for a non-zero `b`, with about `limbs` limbs of significant
/// digits, dropped toward zero or, when `up` is set, away from zero.
///
pub fn quotient(a: Number, b: Number, limbs count: Int, up up: Bool) -> Number {
  use <- bool.guard(when: is_zero(a), return: a)
  let exponent = magnitude(a) - magnitude(b) - 7 * count - 1
  let #(whole, remainder, _) = divide_at(a, b, exponent)
  let whole = case up && remainder != [] {
    True -> limb.trim(limb.add(#(1, whole), #(1, [1])).1)
    False -> whole
  }
  number(a.sign * b.sign, whole, exponent)
}

/// `a / b` for a non-zero `b`, rounded to `digits` places, from the exact
/// quotient and remainder. Returns `Error(PrecisionExceeded)` when the
/// rounded value is out of range.
///
pub fn divide_round(
  a: Number,
  b: Number,
  digits digits: Int,
  rounding mode: RoundingMode,
) -> Result(Decimal, decimal.ArithmeticError) {
  use <- bool.guard(
    when: digits < -15 || digits > 28,
    return: Error(decimal.PrecisionExceeded),
  )
  use <- bool.guard(when: is_zero(a), return: zero_at(digits))
  // The quotient has at least magnitude(a) - magnitude(b) + digits
  // digits, so from 17 it is past 2^53 - 1.
  use <- bool.guard(
    when: magnitude(a) - magnitude(b) + digits >= 17,
    return: Error(decimal.PrecisionExceeded),
  )
  let sign = a.sign * b.sign
  let #(whole, remainder, divisor) = divide_at(a, b, -digits)
  use whole <- result.try(
    limb.digits_value(limb.to_digits(whole))
    |> result.replace_error(decimal.PrecisionExceeded),
  )
  let fraction = case remainder {
    [] -> 0
    _ ->
      case
        limb.compare_values(
          limb.add(#(1, remainder), #(1, remainder)).1,
          divisor,
        )
      {
        order.Lt -> 1
        order.Eq -> 5
        order.Gt -> 9
      }
  }
  use bump <- result.try(rounding_step(whole % 2, fraction, sign, mode))
  decimal.new(coefficient: sign * { whole + bump }, exponent: -digits)
  |> result.replace_error(decimal.PrecisionExceeded)
}

/// The number rounded to `digits` places, with the same result as
/// `decimal.round` on the exact value. Returns `Error(PrecisionExceeded)`
/// when `digits` is outside -15 to 28 or the rounded value is out of
/// range.
///
pub fn round(
  value: Number,
  digits digits: Int,
  rounding mode: RoundingMode,
) -> Result(Decimal, decimal.ArithmeticError) {
  use <- bool.guard(
    when: digits < -15 || digits > 28,
    return: Error(decimal.PrecisionExceeded),
  )
  use <- bool.guard(when: is_zero(value), return: zero_at(digits))
  // A value with 17 or more digits at `digits` places is out of range, so
  // its padding is not built.
  use <- bool.guard(
    when: magnitude(value) + digits > 16,
    return: Error(decimal.PrecisionExceeded),
  )
  let dropped = -digits - value.exponent
  round_digits(limb.to_digits(value.limbs), dropped, value.sign, mode)
  |> result.try(fn(coefficient) {
    decimal.new(coefficient:, exponent: -digits)
    |> result.replace_error(decimal.PrecisionExceeded)
  })
}

// The position of the leading digit of a non-zero value: it is below
// 10^magnitude(value) and at least 10^(magnitude(value) - 1).
fn magnitude(value: Number) -> Int {
  limb.significant(limb.to_digits(value.limbs)) + value.exponent
}

// Zero at `digits` places, for digits within -15 to 28.
fn zero_at(digits: Int) -> Result(Decimal, decimal.ArithmeticError) {
  decimal.new(coefficient: 0, exponent: -digits)
  |> result.replace_error(decimal.PrecisionExceeded)
}

// The quotient and remainder of a / b, both magnitudes, with the quotient
// counted in units of 10^exponent: floor(|a| / (|b| × 10^exponent)).
// Also returns the divisor the remainder is below, `b` scaled to the
// dividend's units.
fn divide_at(
  a: Number,
  b: Number,
  exponent: Int,
) -> #(List(Int), List(Int), List(Int)) {
  let shift = a.exponent - b.exponent - exponent
  let #(dividend, divisor) = case shift >= 0 {
    True -> #(limb.shift(a.limbs, zeros: shift), b.limbs)
    False -> #(a.limbs, limb.shift(b.limbs, zeros: -shift))
  }
  let #(whole, remainder) = limb.divide(dividend, divisor)
  #(whole, remainder, divisor)
}

fn sign_of(value: Decimal) -> Int {
  use <- bool.guard(when: decimal.is_negative(value), return: -1)
  1
}

// Drops the `dropped` least significant of `digits` (listed least
// significant first), the ones past the places asked for, and rounds
// what is left, or pads it with zeros when `dropped` is negative.
// Returns the signed coefficient.
fn round_digits(
  digits: List(Int),
  dropped: Int,
  sign: Int,
  mode: RoundingMode,
) -> Result(Int, decimal.ArithmeticError) {
  let #(removed, kept) = case dropped < 0 {
    True -> #([], list.append(list.repeat(0, -dropped), digits))
    False -> list.split(digits, dropped)
  }
  use quotient <- result.try(
    limb.digits_value(kept) |> result.replace_error(decimal.PrecisionExceeded),
  )
  // Past the end of the list the removed digits are zeros, so the
  // leading one is 0 when the list ran out before `dropped`.
  let leading = case list.length(removed) == dropped, list.last(removed) {
    True, Ok(digit) -> digit
    _, _ -> 0
  }
  let rest_is_zero =
    removed |> list.take(dropped - 1) |> list.all(fn(digit) { digit == 0 })
  // One digit that rounds the same way as the removed digits do: 0 for
  // none, 1 below a half, 5 for exactly a half, 9 above it.
  let fraction = case leading, rest_is_zero {
    0, True -> 0
    5, True -> 5
    leading, _ if leading < 5 -> 1
    _, _ -> 9
  }
  use bump <- result.map(rounding_step(quotient % 2, fraction, sign, mode))
  sign * { quotient + bump }
}

// Whether to round the magnitude up by one, decided by `decimal.round`
// on a stand-in with the same sign, the same parity and a fraction that
// rounds the same way, so every mode means exactly what it means there.
fn rounding_step(
  parity: Int,
  fraction: Int,
  sign: Int,
  mode: RoundingMode,
) -> Result(Int, decimal.ArithmeticError) {
  use stand_in <- result.try(
    decimal.new(coefficient: sign * { parity * 10 + fraction }, exponent: -1)
    |> result.replace_error(decimal.PrecisionExceeded),
  )
  use rounded <- result.map(decimal.round(stand_in, digits: 0, rounding: mode))
  int.absolute_value(decimal.coefficient(rounded)) - parity
}
