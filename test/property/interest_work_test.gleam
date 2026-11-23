//// The work an interest function does stays bounded, on both targets.
////
//// gleeunit enforces no time limit, so these check the size of the
//// numbers the functions build instead: every bound keeps the precision
//// it is computed at (within a few limbs), and the exact value is either
//// the rounded result
//// or `PrecisionExceeded` once it would pass `tvm.exact_limbs` limbs.
//// The inputs are the extremes: rates near 2^53, near -1, with 16 or 28
//// places, principals up to 2^53, and up to 1200 periods.

import gleam/int
import gleam/list
import gleam/order
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range

import finanza/decimal.{type Decimal}
import finanza/internal/rounded.{type Number}
import finanza/internal/tvm

const max = 9_007_199_254_740_991

fn make(coefficient: Int, exponent: Int) -> Decimal {
  case decimal.new(coefficient:, exponent:) {
    Ok(value) -> value
    Error(Nil) -> decimal.zero()
  }
}

fn amount() -> Generator(Decimal) {
  generator.one_of([
    generator.map(generator.int(range.constant(0, max)), make(_, 0)),
    generator.map(generator.int(range.constant(1, max)), make(_, -28)),
    generator.map(generator.int(range.constant(1, 1_000_000)), make(_, -2)),
  ])
}

fn rate() -> Generator(Decimal) {
  generator.one_of([
    // Up to 2^53.
    generator.map(generator.int(range.constant(1, max)), make(_, 0)),
    // Just above -1.
    generator.map(generator.int(range.constant(1, 1000)), fn(c) {
      make(c - 1_000_000_000_000_000, -15)
    }),
    // 16 and 28 places.
    generator.map(generator.int(range.constant(-max, max)), make(_, -16)),
    generator.map(generator.int(range.constant(1, max)), make(_, -28)),
    generator.map(generator.int(range.constant(-max, max)), make(_, -28)),
    // A few digits, -1 or more.
    generator.map2(
      generator.int(range.constant(-99, 9999)),
      generator.int(range.constant(2, 4)),
      fn(c, places) { make(c, 0 - places) },
    ),
  ])
  |> generator.filter(fn(rate) {
    decimal.compare(rate, decimal.negate(decimal.one())) != order.Lt
  })
}

fn periods() -> Generator(Int) {
  generator.one_of([
    generator.int(range.constant(1, 1200)),
    generator.int(range.constant(1100, 1200)),
    generator.int(range.constant(1, 30)),
  ])
}

// The functions the inputs make, for a rate of -1 or more. `payment`
// needs a rate that is neither 0 nor -1, and `present_value` one that is
// not -1.
fn values(input: #(Decimal, Decimal, Int)) -> List(tvm.Value) {
  let #(amount, rate, periods) = input
  let minus_one = decimal.negate(decimal.one())
  let usable = !decimal.equal(rate, minus_one)
  let nonzero = usable && !decimal.is_zero(rate)
  list.flatten([
    [tvm.future_value(amount, rate, periods)],
    case usable {
      True -> [tvm.present_value(amount, rate, periods)]
      False -> []
    },
    case nonzero {
      True -> [tvm.payment(amount, rate, periods)]
      False -> []
    },
    [tvm.effective_annual_rate(rate, periods)],
  ])
}

// The most limbs a bound may have: two more than its precision, or 10
// for a payment just above principal × rate, which is kept exactly with
// one digit at the 31st place, at most 64 digits.
fn limit(precision: Int) -> Int {
  int.max(precision + 2, 10)
}

fn width(bounds: Result(#(Number, Number), Nil)) -> Int {
  case bounds {
    Ok(#(low, high)) -> int.max(list.length(low.limbs), list.length(high.limbs))
    Error(Nil) -> -1
  }
}

fn inputs() {
  generator.tuple3(amount(), rate(), periods())
}

/// Every bound has at most `limit(precision)` limbs, and so do the bounds
/// of `(1 + rate)^periods - 1` that `payment` divides by.
pub fn bounds_keep_their_precision_test() {
  metamon.forall_with(
    metamon.with_runs_or_panic(metamon.default_config(), 200),
    inputs(),
    fn(input) {
      let #(_, rate, periods) = input
      let growth = case decimal.is_zero(rate) {
        True -> fn(_) { Error(Nil) }
        False -> tvm.growth(rate, periods, _)
      }
      list.all(tvm.precisions, fn(precision) {
        width(growth(precision)) <= precision + 2
        && list.all(values(input), fn(value) {
          width(value.bounds(precision)) <= limit(precision)
        })
      })
    },
  )
}

/// The exact value, when it is computed, rounds to the same result as the
/// bounds give, and otherwise it is `PrecisionExceeded`.
pub fn the_exact_value_agrees_or_is_capped_test() {
  metamon.forall_with(
    metamon.with_runs_or_panic(metamon.default_config(), 100),
    generator.tuple2(inputs(), generator.int(range.constant(0, 28))),
    fn(input) {
      let #(input, digits) = input
      list.all(values(input), fn(value) {
        let exact = value.exact(digits)
        exact == Error(decimal.PrecisionExceeded)
        || exact == tvm.round(value, digits:)
      })
    },
  )
}
