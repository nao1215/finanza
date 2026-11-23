//// Multiplication followed by rounding, for `finanza/money` and
//// `finanza/interest`.
////
//// `decimal.multiply` returns the exact product, so it fails when the
//// product has a non-zero digit past 28 places or more than 2^53 − 1 in
//// its coefficient, even when the caller is about to round it to a few
//// places. `multiply` here rounds the exact product directly, so only the
//// rounded value has to be in range.

import gleam/bool
import gleam/int
import gleam/list
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
