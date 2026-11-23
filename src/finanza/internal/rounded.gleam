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

// 2^53 - 1, the bound on a coefficient in finanza/decimal.
const max_safe_coefficient: Int = 9_007_199_254_740_991

// Base of the limbs a product is computed in. Every coefficient is
// below 10^16, so it splits into three limbs, the top one at most 90.
// A product of two limbs is below 10^14, and a sum of three of them
// plus a carry stays below 2^53, so both targets compute every step
// exactly.
const limb_base: Int = 10_000_000

const limb_digits: Int = 7

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
  let small = case left == 0 || left <= max_safe_coefficient / right {
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
      round_digits(product_digits(left, right), -digits - exponent, sign, mode)
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
    digits_value(kept) |> result.replace_error(decimal.PrecisionExceeded),
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

// `digits_value`, `product_digits` and the limb constants are the same
// as in finanza/decimal, which cannot import them from here because this
// module imports it. Change both together.

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
