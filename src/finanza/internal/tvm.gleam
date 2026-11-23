//// The values `finanza/interest` rounds: each one is known by bounds at
//// a chosen precision and by an exact computation, and `round` rounds
//// it once, half-even. The inputs are checked by `finanza/interest`
//// first (internal: not public API, not in docs).

import gleam/bool
import gleam/int
import gleam/list
import gleam/result

import finanza/decimal.{type Decimal}
import finanza/internal/rounded.{type Number}

/// A value to round. `bounds(precision)` returns two numbers computed
/// with `precision` significant limbs of seven digits that, rounded at
/// any `digits` from 0 to 28, give no more and no less than the value
/// does (a lower and an upper bound, or a number that rounds like one),
/// or `Error(Nil)` when that precision cannot bound the value.
/// `exact(digits)` rounds the exact value half-even to `digits` places,
/// or returns `PrecisionExceeded` when the exact value would pass
/// `exact_limbs`.
///
pub type Value {
  Value(
    bounds: fn(Int) -> Result(#(Number, Number), Nil),
    exact: fn(Int) -> Result(Decimal, decimal.ArithmeticError),
  )
}

/// The precisions, in limbs, the bounds are computed with before the
/// exact value.
///
pub const precisions: List(Int) = [5, 10]

/// The most limbs, and the largest exponent over seven, of a number the
/// exact value is computed with. Beyond them the exact value is
/// `PrecisionExceeded`.
///
/// The exact value is only needed when the bounds at 70 digits round
/// differently: for an exact tie, and otherwise for a value within about
/// 10^-60 of a half-unit. A payment at a positive rate whose principal ×
/// rate is a tie is such a value over many periods, and its bounds
/// settle it without the exact value (see `just_above`); no other inputs
/// are known to come that close to a half-unit. A tie can only happen when
/// the exact `(1 + rate)^periods` is short: write `1 + rate` as
/// `m / 10^k` with `m` not a multiple of 10. For `future_value`, a tie at
/// `digits` places needs the number of digits of `present × m^periods`
/// below the rounding place to be at most the power of 2 or of 5 in the
/// coefficient of `present`, at most 53, so `m^periods` has at most 70
/// digits. For `present_value`, a tie makes `m^periods` divide
/// 2 × 10^E × the future value's coefficient for an E of at most 23, so
/// at most 40 digits (60 for a rate whose `1 + rate` ends in zeros). For
/// `payment`, with `1 + rate = C / D` in lowest terms, `C^periods -
/// D^periods` must divide a number below 2 × 10^44, which leaves
/// `m^periods` at most about 180 digits. For `effective_annual_rate`, a
/// tie needs `(1 + nominal / compounds)^compounds` to have at most 29
/// places, so at most 29 compounds, and the numerator then has at most
/// about 90 digits. 100 limbs, 700 digits, leave room for all of them.
///
pub const exact_limbs: Int = 100

/// Rounds the value half-even to `digits` places: at each precision,
/// when both bounds round to the same result it is the result, because
/// rounding never decreases. Otherwise the exact value is rounded.
///
pub fn round(
  value: Value,
  digits digits: Int,
) -> Result(Decimal, decimal.ArithmeticError) {
  let settled =
    list.find_map(precisions, fn(precision) {
      use #(low, high) <- result.try(value.bounds(precision))
      let low = rounded.round(low, digits:, rounding: decimal.HalfEven)
      let high = rounded.round(high, digits:, rounding: decimal.HalfEven)
      case low == high {
        True -> Ok(low)
        False -> Error(Nil)
      }
    })
  case settled {
    Ok(result) -> result
    Error(Nil) -> value.exact(digits)
  }
}

/// `present × (1 + rate)^periods`.
///
pub fn future_value(present: Decimal, rate: Decimal, periods: Int) -> Value {
  let base = one_plus(rate)
  let start = rounded.absolute(rounded.from_decimal(present))
  let sign = rounded.from_int(rounded.from_decimal(present).sign)
  Value(
    bounds: fn(precision) {
      let #(low, high) = power(base, periods, start, precision)
      Ok(#(rounded.times(sign, low), rounded.times(sign, high)))
    },
    exact: fn(digits) {
      use grown <- result.try(exact_power(base, periods, start))
      rounded.round(
        rounded.times(sign, grown),
        digits:,
        rounding: decimal.HalfEven,
      )
    },
  )
}

/// `future ÷ (1 + rate)^periods`, for a rate above -1 or no periods.
///
pub fn present_value(future: Decimal, rate: Decimal, periods: Int) -> Value {
  let base = one_plus(rate)
  let future = rounded.from_decimal(future)
  Value(
    bounds: fn(precision) {
      let #(low, high) = power(base, periods, one(), precision)
      Ok(#(
        rounded.quotient(future, high, limbs: precision, up: False),
        rounded.quotient(future, low, limbs: precision, up: True),
      ))
    },
    exact: fn(digits) {
      use growth <- result.try(exact_power(base, periods, one()))
      rounded.divide_round(future, growth, digits:, rounding: decimal.HalfEven)
    },
  )
}

/// `principal × rate / (1 - (1 + rate)^-periods)`, for a principal of 0
/// or more, a rate that is neither 0 nor -1 and at least one period. The
/// bounds rest on the principal not being negative.
///
pub fn payment(principal: Decimal, rate: Decimal, periods: Int) -> Value {
  // principal × rate / (1 - (1 + rate)^-periods) is
  // principal × rate + principal × rate / growth, where growth is
  // (1 + rate)^periods - 1. For a negative rate both growth and
  // principal × rate are negative, so this is
  // |principal × rate| / |growth| - |principal × rate|.
  let base = one_plus(rate)
  let interest =
    rounded.times(rounded.from_decimal(principal), rounded.from_decimal(rate))
  let size = rounded.absolute(interest)
  Value(
    bounds: fn(precision) {
      use #(small, large) <- result.try(growth(rate, periods, precision))
      let low = rounded.quotient(size, large, limbs: precision, up: False)
      let high = rounded.quotient(size, small, limbs: precision, up: True)
      Ok(#(
        just_above(interest, low, precision),
        rounded.plus_bound(high, interest, limbs: precision, up: True),
      ))
    },
    exact: fn(digits) {
      // principal × rate × (1 + rate)^periods / growth.
      use grown <- result.try(exact_power(base, periods, one()))
      rounded.divide_round(
        rounded.times(interest, grown),
        minus_one(grown),
        digits:,
        rounding: decimal.HalfEven,
      )
    },
  )
}

// A number that rounds like interest + rest at 0 to 28 places, for a rest
// at least 0 and at most the part of the payment past interest. For a
// positive rate the rest is above 0, and when it is below both 10^-30 and
// the last digit of interest, every such rest rounds the same: the sum is
// just above interest, and above it by less than one unit of a place no
// rounding keeps. So 10^(-31) or less stands in for it, and a payment that
// is a tie plus 10^-450 rounds up without its power being computed. A
// zero or larger rest, or a negative rate, gives a lower bound of the sum.
fn just_above(interest: Number, rest: Number, precision: Int) -> Number {
  let place = int.min(interest.exponent, -30)
  case
    interest.sign > 0 && rounded.below(rest, place) && !rounded.is_zero(rest)
  {
    True -> rounded.plus(interest, rounded.Number(1, [1], place - 1))
    False -> rounded.plus_bound(rest, interest, limbs: precision, up: False)
  }
}

/// Bounds of `|(1 + rate)^periods - 1|` with `precision` limbs, the
/// smaller first, or `Error(Nil)` when the smaller is not above zero, for
/// a rate of -1 or more that is not 0 and at least one period.
///
pub fn growth(
  rate: Decimal,
  periods: Int,
  precision: Int,
) -> Result(#(Number, Number), Nil) {
  let #(low, high) = power(one_plus(rate), periods, one(), precision)
  let #(small, large) = case decimal.is_negative(rate) {
    False -> #(
      rounded.plus_bound(low, minus(), limbs: precision, up: False),
      rounded.plus_bound(high, minus(), limbs: precision, up: True),
    )
    True -> #(
      rounded.plus_bound(
        one(),
        rounded.negate(high),
        limbs: precision,
        up: False,
      ),
      rounded.plus_bound(one(), rounded.negate(low), limbs: precision, up: True),
    )
  }
  use <- bool.guard(
    when: small.sign < 0 || rounded.is_zero(small),
    return: Error(Nil),
  )
  Ok(#(small, large))
}

/// `(1 + nominal_rate / compounds)^compounds - 1`, for a nominal rate of
/// -1 or more and a positive number of compounds.
///
pub fn effective_annual_rate(nominal_rate: Decimal, compounds: Int) -> Value {
  let nominal = rounded.from_decimal(nominal_rate)
  let count = rounded.from_int(compounds)
  Value(
    bounds: fn(precision) {
      // The bounds of nominal_rate / compounds, the smaller first:
      // dropping digits away from zero lowers a negative rate.
      let toward = rounded.quotient(nominal, count, limbs: precision, up: False)
      let away = rounded.quotient(nominal, count, limbs: precision, up: True)
      let #(small, large) = case decimal.is_negative(nominal_rate) {
        False -> #(toward, away)
        True -> #(away, toward)
      }
      let small = rounded.plus_bound(one(), small, limbs: precision, up: False)
      let large = rounded.plus_bound(one(), large, limbs: precision, up: True)
      use <- bool.guard(when: small.sign < 0, return: Error(Nil))
      let #(low, high) =
        power_between(small, large, compounds, one(), precision)
      Ok(#(
        rounded.plus_bound(low, minus(), limbs: precision, up: False),
        rounded.plus_bound(high, minus(), limbs: precision, up: True),
      ))
    },
    exact: fn(digits) {
      // ((compounds + nominal_rate)^compounds - compounds^compounds)
      //   / compounds^compounds
      let numerator = rounded.normalize(rounded.plus(count, nominal))
      use top <- result.try(exact_power(numerator, compounds, one()))
      use bottom <- result.try(exact_power(
        rounded.normalize(count),
        compounds,
        one(),
      ))
      rounded.divide_round(
        rounded.plus(top, rounded.negate(bottom)),
        bottom,
        digits:,
        rounding: decimal.HalfEven,
      )
    },
  )
}

fn one() -> Number {
  rounded.from_int(1)
}

fn minus() -> Number {
  rounded.from_int(-1)
}

// 1 + rate, exactly, without the zeros at the end of its digits. It is
// not negative, because the rate is -1 or more.
fn one_plus(rate: Decimal) -> Number {
  rounded.normalize(rounded.plus(one(), rounded.from_decimal(rate)))
}

fn minus_one(value: Number) -> Number {
  rounded.plus(value, minus())
}

// start × base^periods exactly, or `PrecisionExceeded` as soon as a
// partial product, the result included, passes `exact_limbs` limbs or an
// exponent of 7 × `exact_limbs` either way, so the work is bounded
// whatever the inputs.
// The loop calls itself last, so it runs in constant stack.
fn exact_power(
  base: Number,
  periods: Int,
  value: Number,
) -> Result(Number, decimal.ArithmeticError) {
  let too_large =
    list.length(value.limbs) > exact_limbs
    || int.absolute_value(value.exponent) > 7 * exact_limbs
  use <- bool.guard(when: too_large, return: Error(decimal.PrecisionExceeded))
  case periods <= 0 {
    True -> Ok(value)
    False -> exact_power(base, periods - 1, rounded.times(value, base))
  }
}

// Bounds of start × base^periods, for non-negative values. Each period
// keeps `precision` limbs of the exact product and drops the rest toward
// zero, which lowers the value by less than 10^(-7 × (precision - 1)) of
// itself, ε. So the result is a lower bound, and the exact value is at
// most the result × (1 - ε)^-periods, below the result × (1 +
// 2 × periods × ε) because periods × ε is at most 1/2. The loop calls
// itself last, so it runs in constant stack for any number of periods.
fn power(
  base: Number,
  periods: Int,
  start: Number,
  precision: Int,
) -> #(Number, Number) {
  let low = power_loop(base, periods, start, precision, False)
  let slack =
    rounded.Number(
      ..rounded.from_int(2 * periods),
      exponent: -7 * { precision - 1 },
    )
  #(
    low,
    rounded.plus(
      low,
      rounded.truncate(rounded.times(low, slack), limbs: 2, up: True),
    ),
  )
}

// Bounds of start × low^periods and start × high^periods, for
// non-negative values with low <= high: the lower one keeps `precision`
// limbs dropping the rest toward zero and the upper one away from zero.
fn power_between(
  low: Number,
  high: Number,
  periods: Int,
  start: Number,
  precision: Int,
) -> #(Number, Number) {
  #(
    power_loop(low, periods, start, precision, False),
    power_loop(high, periods, start, precision, True),
  )
}

fn power_loop(
  base: Number,
  periods: Int,
  value: Number,
  precision: Int,
  up: Bool,
) -> Number {
  case periods {
    _ if periods <= 0 -> value
    _ ->
      power_loop(
        base,
        periods - 1,
        rounded.truncate(rounded.times(value, base), limbs: precision, up:),
        precision,
        up,
      )
  }
}
