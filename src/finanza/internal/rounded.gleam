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

/// Returns `a × b` plus every one of `addends`, rounded half-even to the
/// most places up to `at_most`, and no fewer than 0, at which the result
/// is in range. The value is exact before it is rounded once, so
/// `multiply_add(x, rate, plus: [x], ..)` is `x × (1 + rate)` rounded,
/// even when `1 + rate` has too many digits to be a `Decimal`.
///
/// Returns `Error(PrecisionExceeded)` when `at_most` is outside 0 to 28
/// or the value is out of range even at 0 places.
///
pub fn multiply_add(
  a: Decimal,
  b: Decimal,
  plus addends: List(Decimal),
  at_most places: Int,
) -> Result(Decimal, decimal.ArithmeticError) {
  use <- bool.guard(
    when: places < 0 || places > 28,
    return: Error(decimal.PrecisionExceeded),
  )
  let product =
    Term(
      sign: sign_of(a) * sign_of(b),
      limbs: limb.product_limbs(
        int.absolute_value(decimal.coefficient(a)),
        int.absolute_value(decimal.coefficient(b)),
      ),
      exponent: decimal.exponent(a) + decimal.exponent(b),
    )
  let terms = [
    product,
    ..list.map(addends, fn(addend) {
      Term(
        sign: sign_of(addend),
        limbs: limb.limbs(int.absolute_value(decimal.coefficient(addend))),
        exponent: decimal.exponent(addend),
      )
    })
  ]
  let exponent =
    list.fold(terms, product.exponent, fn(lowest, term) {
      int.min(lowest, term.exponent)
    })
  // A product's exponent is within -56 to 30 and an addend's within -28
  // to 15, so a term is shifted by at most 71 places and the sum has
  // fewer than 120 digits.
  let #(sign, total) =
    list.fold(terms, #(1, []), fn(total, term) {
      limb.add(total, #(
        term.sign,
        limb.shift(term.limbs, zeros: term.exponent - exponent),
      ))
    })
  let digits = limb.to_digits(limb.trim(total))
  case limb.significant(digits) {
    0 ->
      decimal.new(coefficient: 0, exponent: -places)
      |> result.replace_error(decimal.PrecisionExceeded)
    // A coefficient within 2^53 - 1 has at most 16 digits, so no more
    // places than leave 16 of them can fit.
    significant ->
      most_places(
        digits,
        exponent,
        sign,
        int.min(places, 16 - significant - exponent),
      )
  }
}

type Term {
  Term(sign: Int, limbs: List(Int), exponent: Int)
}

// Rounds `digits × 10^exponent` half-even at `places`, or at the most
// places below it at which the coefficient fits. Rounding up can add a
// digit, so this takes at most two steps after the first.
fn most_places(
  digits: List(Int),
  exponent: Int,
  sign: Int,
  places: Int,
) -> Result(Decimal, decimal.ArithmeticError) {
  use <- bool.guard(when: places < 0, return: Error(decimal.PrecisionExceeded))
  let rounded =
    round_digits(digits, -places - exponent, sign, decimal.HalfEven)
    |> result.try(fn(coefficient) {
      decimal.new(coefficient:, exponent: -places)
      |> result.replace_error(decimal.PrecisionExceeded)
    })
  case rounded {
    Ok(value) -> Ok(value)
    Error(error) ->
      case places > 0 {
        True -> most_places(digits, exponent, sign, places - 1)
        False -> Error(error)
      }
  }
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
