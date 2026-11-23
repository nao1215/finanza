//// Exact products of two coefficients, for `finanza/decimal` and
//// `finanza/internal/rounded`.
////
//// A coefficient is within 2^53 − 1, so the product of two can pass what
//// JavaScript holds exactly. These functions compute it in limbs of seven
//// digits, so both targets get every digit of it. They work on plain
//// integers and do not depend on `Decimal`, so both modules can import
//// them.

import gleam/list

/// 2^53 − 1, the bound on a coefficient in `finanza/decimal`.
///
pub const max_safe_coefficient: Int = 9_007_199_254_740_991

// Base of the limbs a product is computed in. Every coefficient is
// below 10^16, so it splits into three limbs, the top one at most 90.
// A product of two limbs is below 10^14, and a sum of three of them
// plus a carry stays below 2^53, so both targets compute every step
// exactly.
const limb_base: Int = 10_000_000

const limb_digits: Int = 7

/// The exact product of two magnitudes within 2^53 − 1, as its 35
/// decimal digits, the least significant first.
///
pub fn product_digits(a: Int, b: Int) -> List(Int) {
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
  |> list.flat_map(limb_to_digits(_, limb_digits, []))
}

/// The value of digits listed least significant first, or `Error(Nil)`
/// when it passes 2^53 − 1. Each step checks before it multiplies, so no
/// intermediate value passes 2^53 − 1 either.
///
pub fn digits_value(digits: List(Int)) -> Result(Int, Nil) {
  digits
  |> list.reverse
  |> list.try_fold(0, fn(value, digit) {
    case value > { max_safe_coefficient - digit } / 10 {
      True -> Error(Nil)
      False -> Ok(value * 10 + digit)
    }
  })
}

fn split_limbs(value: Int) -> #(Int, Int, Int) {
  #(
    value % limb_base,
    value / limb_base % limb_base,
    value / { limb_base * limb_base },
  )
}

// The `count` least significant digits of `limb`, the least significant
// first. `digits` collects them most significant first and is reversed
// at the end.
fn limb_to_digits(limb: Int, count: Int, digits: List(Int)) -> List(Int) {
  case count {
    0 -> list.reverse(digits)
    _ -> limb_to_digits(limb / 10, count - 1, [limb % 10, ..digits])
  }
}
