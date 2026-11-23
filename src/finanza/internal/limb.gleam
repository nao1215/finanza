//// Exact arithmetic on non-negative integers of any size, for
//// `finanza/decimal` and `finanza/internal/rounded`.
////
//// A coefficient is within 2^53 − 1, so the product of two, or a sum
//// after one is scaled to the other's exponent, can pass what JavaScript
//// holds exactly. These functions compute every digit of it on both
//// targets, in limbs of seven digits whose every intermediate value stays
//// below 2^53. Limbs and digits are listed least significant first. They
//// work on plain integers and do not depend on `Decimal`, so both modules
//// can import them.

import gleam/int
import gleam/list
import gleam/order

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
  to_digits(product_limbs(a, b))
}

/// The exact product of two magnitudes within 2^53 − 1, as its five
/// limbs, the least significant first.
///
pub fn product_limbs(a: Int, b: Int) -> List(Int) {
  let #(a0, a1, a2) = split_limbs(a)
  let #(b0, b1, b2) = split_limbs(b)
  let c0 = a0 * b0
  let c1 = a0 * b1 + a1 * b0 + c0 / limb_base
  let c2 = a0 * b2 + a1 * b1 + a2 * b0 + c1 / limb_base
  let c3 = a1 * b2 + a2 * b1 + c2 / limb_base
  // At most 90 × 90 plus a carry of at most 181, so below the base.
  let c4 = a2 * b2 + c3 / limb_base
  [
    c0 % limb_base,
    c1 % limb_base,
    c2 % limb_base,
    c3 % limb_base,
    c4,
  ]
}

/// The limbs of the non-negative `magnitude`, within 2^53 − 1.
///
pub fn limbs(magnitude: Int) -> List(Int) {
  let #(a0, a1, a2) = split_limbs(magnitude)
  [a0, a1, a2]
}

/// The decimal digits of `limbs`, seven for each limb.
///
pub fn to_digits(limbs: List(Int)) -> List(Int) {
  list.flat_map(limbs, limb_to_digits(_, limb_digits, []))
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

/// `limbs` times 10^`zeros`, for `zeros` of 0 or more. Each limb is
/// multiplied by at most 10^6, below 10^13 with its carry, so this is
/// exact on both targets.
///
pub fn shift(limbs: List(Int), zeros zeros: Int) -> List(Int) {
  let factor = int.product(list.repeat(10, zeros % limb_digits))
  list.append(list.repeat(0, zeros / limb_digits), scale(limbs, factor, 0, []))
}

/// The exact sum of two signed numbers, each given as a sign (1 or -1)
/// and its limbs. Returns the sign and the limbs of the sum, one more limb
/// than the longer operand has. A zero sum has the sign of `a`. Every step
/// adds or subtracts two limbs and a carry, so the sum is exact on both
/// targets however long the operands are.
///
pub fn add(a: #(Int, List(Int)), b: #(Int, List(Int))) -> #(Int, List(Int)) {
  let #(a_sign, a_limbs) = a
  let #(b_sign, b_limbs) = b
  let length = int.max(list.length(a_limbs), list.length(b_limbs)) + 1
  let a_limbs = pad(a_limbs, length)
  let b_limbs = pad(b_limbs, length)
  case a_sign == b_sign {
    True -> #(a_sign, carry_add(a_limbs, b_limbs, 0, []))
    False ->
      case compare(list.reverse(a_limbs), list.reverse(b_limbs)) {
        order.Lt -> #(b_sign, borrow_subtract(b_limbs, a_limbs, 0, []))
        order.Eq | order.Gt -> #(
          a_sign,
          borrow_subtract(a_limbs, b_limbs, 0, []),
        )
      }
  }
}

/// `limbs` without the zero limbs at the most significant end.
///
pub fn trim(limbs: List(Int)) -> List(Int) {
  limbs
  |> list.reverse
  |> list.drop_while(fn(limb) { limb == 0 })
  |> list.reverse
}

/// How many digits are left once the leading zeros go: 0 for zero.
///
pub fn significant(digits: List(Int)) -> Int {
  digits
  |> list.reverse
  |> list.drop_while(fn(digit) { digit == 0 })
  |> list.length
}

// `scaled` collects the limbs most significant first.
fn scale(
  limbs: List(Int),
  factor: Int,
  carry: Int,
  scaled: List(Int),
) -> List(Int) {
  case limbs {
    [limb, ..limbs] -> {
      let value = limb * factor + carry
      scale(limbs, factor, value / limb_base, [value % limb_base, ..scaled])
    }
    [] -> list.reverse([carry, ..scaled])
  }
}

fn pad(limbs: List(Int), length: Int) -> List(Int) {
  list.append(limbs, list.repeat(0, length - list.length(limbs)))
}

// Both lists have the same length, and `sum` collects the limbs most
// significant first.
fn carry_add(
  a: List(Int),
  b: List(Int),
  carry: Int,
  sum: List(Int),
) -> List(Int) {
  case a, b {
    [x, ..a], [y, ..b] -> {
      let total = x + y + carry
      carry_add(a, b, total / limb_base, [total % limb_base, ..sum])
    }
    _, _ -> list.reverse(sum)
  }
}

// `a - b` for `a >= b`, both of the same length.
fn borrow_subtract(
  a: List(Int),
  b: List(Int),
  borrow: Int,
  difference: List(Int),
) -> List(Int) {
  case a, b {
    [x, ..a], [y, ..b] -> {
      let limb = x - y - borrow
      case limb < 0 {
        True -> borrow_subtract(a, b, 1, [limb + limb_base, ..difference])
        False -> borrow_subtract(a, b, 0, [limb, ..difference])
      }
    }
    _, _ -> list.reverse(difference)
  }
}

// Compares two limb lists of the same length, most significant first.
fn compare(a: List(Int), b: List(Int)) -> order.Order {
  case a, b {
    [x, ..a], [y, ..b] if x == y -> compare(a, b)
    [x, ..], [y, ..] -> int.compare(x, y)
    _, _ -> order.Eq
  }
}

/// The exact product of two limb lists of any length. Each step adds one
/// limb product, below 10^14, and a carry to a limb, so every value
/// stays below 2^53.
///
pub fn multiply(a: List(Int), b: List(Int)) -> List(Int) {
  // One row per limb of the shorter operand, each as long as the longer.
  case list.length(a) <= list.length(b) {
    True -> multiply_rows(a, b, 0, [])
    False -> multiply_rows(b, a, 0, [])
  }
}

// Adds `limb × b`, shifted by `offset` limbs, to `total` for each limb
// of `a`.
fn multiply_rows(
  a: List(Int),
  b: List(Int),
  offset: Int,
  total: List(Int),
) -> List(Int) {
  case a {
    [] -> trim(total)
    [0, ..rest] -> multiply_rows(rest, b, offset + 1, total)
    [limb, ..rest] ->
      multiply_rows(
        rest,
        b,
        offset + 1,
        add_scaled(total, b, limb, offset, 0, []),
      )
  }
}

// `total + b × factor × base^skip` in one pass: the first `skip` limbs of
// `total` are kept, and each later step adds a limb of `total`, a limb
// product below 10^14 and a carry, so every value stays below 2^53.
// `sum` collects the limbs most significant first.
fn add_scaled(
  total: List(Int),
  b: List(Int),
  factor: Int,
  skip: Int,
  carry: Int,
  sum: List(Int),
) -> List(Int) {
  case skip > 0, total, b {
    True, [limb, ..total], _ ->
      add_scaled(total, b, factor, skip - 1, carry, [limb, ..sum])
    True, [], _ -> add_scaled([], b, factor, skip - 1, carry, [0, ..sum])
    False, [limb, ..total], [digit, ..b] -> {
      let value = limb + digit * factor + carry
      add_scaled(total, b, factor, 0, value / limb_base, [
        value % limb_base,
        ..sum
      ])
    }
    False, [], [digit, ..b] -> {
      let value = digit * factor + carry
      add_scaled([], b, factor, 0, value / limb_base, [value % limb_base, ..sum])
    }
    False, [limb, ..total], [] -> {
      let value = limb + carry
      add_scaled(total, [], factor, 0, value / limb_base, [
        value % limb_base,
        ..sum
      ])
    }
    False, [], [] ->
      case carry {
        0 -> list.reverse(sum)
        _ -> list.reverse([carry, ..sum])
      }
  }
}

/// `a - b` for `a >= b`, without leading zero limbs.
///
pub fn subtract(a: List(Int), b: List(Int)) -> List(Int) {
  let length = int.max(list.length(a), list.length(b))
  trim(borrow_subtract(pad(a, length), pad(b, length), 0, []))
}

/// Compares two limb lists by value, whatever their lengths.
///
pub fn compare_values(a: List(Int), b: List(Int)) -> order.Order {
  let left = trim(a)
  let right = trim(b)
  case int.compare(list.length(left), list.length(right)) {
    order.Eq -> compare(list.reverse(left), list.reverse(right))
    other -> other
  }
}

/// The limbs of digits listed least significant first.
///
pub fn from_digits(digits: List(Int)) -> List(Int) {
  digits
  |> list.sized_chunk(into: limb_digits)
  |> list.map(fn(chunk) {
    list.fold(list.reverse(chunk), 0, fn(value, digit) { value * 10 + digit })
  })
  |> trim
}

/// The quotient and remainder of `a / b`, for a non-zero `b`, by long
/// division one decimal digit at a time. The remainder starts from the
/// leading digits of `a` that are fewer than those of `b`, so each of the
/// remaining steps adds one digit to the quotient, and each subtracts
/// `b` at most nine times.
///
pub fn divide(a: List(Int), b: List(Int)) -> #(List(Int), List(Int)) {
  let divisor = trim(b)
  let leading =
    a
    |> to_digits
    |> list.reverse
    |> list.drop_while(fn(digit) { digit == 0 })
  let width = significant(to_digits(divisor)) - 1
  case list.length(leading) <= width {
    True -> #([], trim(a))
    False -> {
      let #(head, rest) = list.split(leading, width)
      divide_digits(rest, divisor, from_digits(list.reverse(head)), [])
    }
  }
}

// `quotient` collects the quotient digits, the latest, least significant
// one first.
fn divide_digits(
  digits: List(Int),
  divisor: List(Int),
  remainder: List(Int),
  quotient: List(Int),
) -> #(List(Int), List(Int)) {
  case digits {
    [] -> #(from_digits(quotient), remainder)
    [digit, ..rest] -> {
      let #(count, remainder) =
        subtract_while(trim(scale(remainder, 10, digit, [])), divisor, 0)
      divide_digits(rest, divisor, remainder, [count, ..quotient])
    }
  }
}

fn subtract_while(
  value: List(Int),
  divisor: List(Int),
  count: Int,
) -> #(Int, List(Int)) {
  case compare_values(value, divisor) {
    order.Lt -> #(count, value)
    order.Eq | order.Gt ->
      subtract_while(subtract(value, divisor), divisor, count + 1)
  }
}
