//// Work that grew with the inputs after 0.14.0.
////
//// - When the bounds did not settle a result, the interest functions
////   computed `(1 + rate)^periods` in full, so a 28-place rate over 1200
////   periods built numbers of about 34,000 digits and could take
////   seconds. An exact tie can only happen when that power has fewer
////   than about 250 digits, so the exact value is now computed only up
////   to `tvm.exact_limbs` limbs, and beyond that the result is
////   `PrecisionExceeded`.
//// - A `payment` at a positive rate is `principal × rate` plus
////   `principal × rate / ((1 + rate)^periods - 1)`, so when `principal ×
////   rate` is itself a tie and the power is huge, the payment is a tie
////   plus a tiny amount, which no bounds at 70 digits settle and whose
////   exact power is far past the limit. It is now settled without the
////   power.
//// - `payment` at a rate near 2^53 or near -1 over 1200 periods, and
////   `effective_annual_rate` at a huge nominal rate, added 1 to a bound
////   of about 10^19000 exactly, so the bounds had thousands of limbs and
////   a call took up to 0.3 s on JavaScript. Every bound now keeps its
////   precision.
//// - The `card` functions read a card number or an expiry of any length,
////   splitting all of it into graphemes before checking its length, so
////   ten megabytes of input took ten megabytes of work and many times that
////   in memory. They now reject input over 1,000 bytes before reading it,
////   as `decimal.parse` does.

import gleam/int
import gleam/list
import gleam/string

import finanza/card
import finanza/decimal
import finanza/interest
import finanza/internal/rounded.{type Number}
import finanza/internal/tvm
import support

const max = 9_007_199_254_740_991

const exceeded = Error(decimal.PrecisionExceeded)

// The most limbs a bound may have: two more than its precision, or 10
// for a payment just above principal × rate, which is kept exactly with
// one digit at the 31st place, at most 64 digits.
fn limit(precision: Int) -> Int {
  int.max(precision + 2, 10)
}

// The most limbs either bound has, or -1 when there are none.
fn width(bounds: Result(#(Number, Number), Nil)) -> Int {
  case bounds {
    Ok(#(low, high)) -> int.max(list.length(low.limbs), list.length(high.limbs))
    Error(Nil) -> -1
  }
}

fn keeps_precision(value: tvm.Value) -> Bool {
  list.all(tvm.precisions, fn(precision) {
    width(value.bounds(precision)) <= limit(precision)
  })
}

// --- the exact path ---------------------------------------------------------

pub fn the_exact_effective_annual_rate_is_capped_test() {
  let nominal = support.parse("0.0000000000001234567890123456")
  assert tvm.effective_annual_rate(nominal, 1200).exact(28) == exceeded
}

pub fn the_exact_future_and_present_value_are_capped_test() {
  let rate = support.parse("0.0000000000001234567890123456")
  let one = decimal.one()
  assert tvm.future_value(one, rate, 1200).exact(2) == exceeded
  assert tvm.present_value(one, rate, 1200).exact(2) == exceeded
}

pub fn the_exact_payment_is_capped_test() {
  let rate = support.parse("0.0000000000001234567890123456")
  assert tvm.payment(decimal.one(), rate, 1200).exact(10) == exceeded
}

pub fn a_power_with_few_digits_is_still_exact_test() {
  // 1 at 0.5 over 60 periods is 1.5^60, 71 digits.
  let value = tvm.future_value(decimal.one(), support.parse("0.5"), 60)
  assert value.exact(2) == tvm.round(value, digits: 2)
}

pub fn the_cap_does_not_reach_the_usual_results_test() {
  let principal = support.parse("200000")
  let rate = support.parse("0.005")
  let assert Ok(payment) =
    interest.payment(principal:, rate_per_period: rate, periods: 360, digits: 2)
  assert decimal.to_string(payment) == "1199.10"
}

// --- ties, which need the exact value -----------------------------------------

pub fn a_future_value_tie_rounds_half_even_test() {
  // 5^22 / 10^21 × 2^20 is exactly 2.5.
  let present = support.new(coefficient: 2_384_185_791_015_625, exponent: -21)
  let assert Ok(value) =
    interest.future_value(
      present:,
      rate_per_period: decimal.one(),
      periods: 20,
      digits: 0,
    )
  assert decimal.to_string(value) == "2"
}

pub fn a_present_value_tie_rounds_half_even_test() {
  // 2.62144 / 1.024^2 is exactly 2.5.
  let assert Ok(value) =
    interest.present_value(
      future: support.parse("2.62144"),
      rate_per_period: support.parse("0.024"),
      periods: 2,
      digits: 0,
    )
  assert decimal.to_string(value) == "2"
  // 5^22 / 10^21 / 0.5^20 is exactly 2.5 too.
  let future = support.new(coefficient: 2_384_185_791_015_625, exponent: -21)
  let assert Ok(value) =
    interest.present_value(
      future:,
      rate_per_period: support.parse("-0.5"),
      periods: 20,
      digits: 0,
    )
  assert decimal.to_string(value) == "2"
}

pub fn a_payment_tie_rounds_half_even_test() {
  // 0.375 × 1 × 2^2 / (2^2 - 1) is exactly 0.5.
  let assert Ok(value) =
    interest.payment(
      principal: support.parse("0.375"),
      rate_per_period: decimal.one(),
      periods: 2,
      digits: 0,
    )
  assert decimal.to_string(value) == "0"
}

pub fn an_effective_annual_rate_tie_rounds_half_even_test() {
  // (1 + 1/2)^2 - 1 is exactly 1.25.
  let assert Ok(value) =
    interest.effective_annual_rate(
      nominal_rate: decimal.one(),
      compounds_per_year: 2,
      digits: 1,
    )
  assert decimal.to_string(value) == "1.2"
}

pub fn a_payment_just_above_a_tie_rounds_up_test() {
  // principal × rate is 4833.95625, and the rest is below 10^-450.
  let assert Ok(value) =
    interest.payment(
      principal: support.parse("3222.6375"),
      rate_per_period: support.parse("1.5"),
      periods: 1152,
      digits: 4,
    )
  assert decimal.to_string(value) == "4833.9563"
  // 4833.95445 over 1200 periods, the same.
  let assert Ok(value) =
    interest.payment(
      principal: support.parse("3222.6363"),
      rate_per_period: support.parse("1.5"),
      periods: 1200,
      digits: 4,
    )
  assert decimal.to_string(value) == "4833.9545"
}

// --- bounds -------------------------------------------------------------------

pub fn payment_bounds_at_a_huge_rate_keep_their_precision_test() {
  let rate = support.int(max)
  assert keeps_precision(tvm.payment(decimal.one(), rate, 1200))
  assert keeps_precision(tvm.payment(support.int(max), rate, 1200))
}

pub fn payment_bounds_near_minus_one_keep_their_precision_test() {
  let rate = support.parse("-0.999999999999999")
  list.each(tvm.precisions, fn(precision) {
    assert width(tvm.growth(rate, 1200, precision)) <= precision + 2
    assert width(tvm.growth(support.int(max), 1200, precision)) <= precision + 2
  })
  assert keeps_precision(tvm.payment(support.int(max), rate, 1200))
  assert keeps_precision(tvm.payment(decimal.one(), rate, 1200))
}

pub fn effective_annual_rate_bounds_at_a_huge_rate_keep_their_precision_test() {
  assert keeps_precision(tvm.effective_annual_rate(support.int(max), 1200))
  assert keeps_precision(tvm.effective_annual_rate(support.parse("9.5"), 1200))
}

pub fn value_bounds_at_extreme_rates_keep_their_precision_test() {
  let rates = [support.int(max), support.parse("-0.999999999999999")]
  list.each(rates, fn(rate) {
    assert keeps_precision(tvm.future_value(support.int(max), rate, 1200))
    assert keeps_precision(tvm.present_value(support.int(max), rate, 1200))
  })
}

pub fn results_at_extreme_rates_are_unchanged_test() {
  let assert Ok(value) =
    interest.payment(
      principal: support.int(max),
      rate_per_period: support.parse("-0.999999999999999"),
      periods: 1200,
      digits: 2,
    )
  assert decimal.to_string(value) == "0.00"
  assert interest.payment(
      principal: decimal.one(),
      rate_per_period: support.int(max),
      periods: 1200,
      digits: 2,
    )
    == Error(interest.ArithmeticFailed(decimal.PrecisionExceeded))
}

// --- card input -------------------------------------------------------------

pub fn card_input_over_1000_bytes_is_rejected_test() {
  let spaces = string.repeat(" ", 1001)
  assert card.validate(spaces) == Error(card.InvalidLength(length: 1001))
  assert card.validate(string.repeat("x", 1001))
    == Error(card.InvalidLength(length: 1001))
  let digits = string.repeat("4", 1001)
  assert card.mask(digits, with: card.default_mask)
    == Error(card.InvalidLength(length: 1001))
  assert card.last_four(digits) == Error(card.InvalidLength(length: 1001))
  assert card.bin(digits) == Error(card.InvalidLength(length: 1001))
  assert card.detect_brand(digits) == card.Unknown
  assert !card.luhn_valid(string.repeat("0", 1001))
  assert card.parse_expiry(string.repeat(" ", 997) <> "12/28") == Error(Nil)
}

pub fn card_input_counts_bytes_test() {
  // 334 ideographic spaces are 1,002 bytes.
  let wide = string.repeat("\u{3000}", 334) <> "4111111111111111"
  assert card.validate(wide) == Error(card.InvalidLength(length: 1018))
}

pub fn card_input_of_1000_bytes_is_read_test() {
  let pan = string.repeat(" ", 984) <> "4111111111111111"
  assert card.validate(pan) == Ok(card.Visa)
  assert card.last_four(pan) == Ok("1111")
  assert card.bin(pan) == Ok("411111")
  assert card.detect_brand(pan) == card.Visa
  assert card.mask(pan, with: card.default_mask) == Ok("4111 **** **** 1111")
  assert card.luhn_valid(string.repeat("0", 1000))
  assert card.parse_expiry(string.repeat(" ", 995) <> "12/28")
    == Ok(card.Expiry(month: 12, year: 2028))
}

pub fn a_very_long_card_input_is_rejected_at_once_test() {
  let long = string.repeat("1234567890", 1_000_000)
  assert card.validate(long) == Error(card.InvalidLength(length: 10_000_000))
  assert !card.luhn_valid(long)
  assert card.parse_expiry(long) == Error(Nil)
}
