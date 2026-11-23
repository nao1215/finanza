//// Limits left after 0.13.4.
////
//// - `money.format` padded a hand-built `Currency` with a huge exponent
////   with that many zeros, and `from_minor`, `to_minor`, `multiply` and
////   `divide` accepted a negative exponent although the documented range
////   is 0 to 28.
//// - `decimal.parse` rejected `"0.10000000000000000000000000000"` (29
////   places) and `"9007199254740991.0"`, whose values are in range once
////   their trailing zeros go.
//// - `decimal.add` returned the other operand when one was zero, so the
////   sum did not take the smaller exponent: a schedule row whose
////   principal paid was exactly zero showed a balance of `200000` among
////   rows of `200000.00`.
//// - `interest.simple` rounded principal × rate to about 16 digits
////   before scaling it by the periods when that scaling did not fit.
//// - `interest.future_value` and `present_value` worked at `digits + 2`
////   places, and `payment` and `effective_annual_rate` at about 16
////   significant digits, so a result could round the other way. They now
////   round the exact value once; the expected values are Python's
////   `decimal` at 200 digits and exact fractions.

import gleam/result

import finanza/decimal
import finanza/interest
import finanza/money
import support

fn text(value: Result(decimal.Decimal, a)) -> Result(String, a) {
  result.map(value, decimal.to_string)
}

const max = 9_007_199_254_740_991

// --- money: the currency exponent -------------------------------------------

fn currency(exponent: Int) -> money.Currency {
  money.Currency(code: "XTS", exponent:, symbol: "¤", name: "Test")
}

pub fn format_does_not_pad_for_a_huge_exponent_test() {
  let amount = money.Money(support.parse("1.5"), currency(1_000_000))
  assert money.format(amount, with: money.default_format) == "¤1.5"
}

pub fn format_renders_a_negative_exponent_as_stored_test() {
  let amount = money.Money(support.parse("1234.5"), currency(-1))
  assert money.format(amount, with: money.default_format) == "¤1,234.5"
}

pub fn format_still_rounds_within_the_range_test() {
  let amount = money.Money(support.parse("1.005"), currency(28))
  assert money.format(amount, with: money.default_format)
    == "¤1.0050000000000000000000000000"
}

pub fn a_negative_currency_exponent_is_rejected_test() {
  let exceeded = Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  assert money.from_minor(5, in: currency(-1)) == exceeded
  let amount = money.Money(support.parse("15"), currency(-1))
  assert money.to_minor(amount, rounding: decimal.HalfEven)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  assert money.multiply(
      amount,
      by: support.parse("2"),
      rounding: decimal.HalfEven,
    )
    == exceeded
  assert money.divide(
      amount,
      by: support.parse("2"),
      rounding: decimal.HalfEven,
    )
    == exceeded
  assert money.allocate(amount, [1, 1])
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  assert money.sum([], in: currency(-1)) == exceeded
}

pub fn an_exponent_past_28_is_rejected_test() {
  let exceeded = Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  let amount = money.Money(support.parse("15"), currency(29))
  assert money.from_minor(5, in: currency(29)) == exceeded
  assert money.multiply(
      amount,
      by: support.parse("2"),
      rounding: decimal.HalfEven,
    )
    == exceeded
  assert money.divide(
      amount,
      by: support.parse("2"),
      rounding: decimal.HalfEven,
    )
    == exceeded
}

// --- parse: trailing zeros past the range -----------------------------------

pub fn parse_drops_trailing_zeros_to_fit_test() {
  assert text(decimal.parse("0.10000000000000000000000000000"))
    == Ok("0.1000000000000000")
  assert text(decimal.parse("1.0e-28")) == Ok("0.0000000000000000000000000001")
  assert text(decimal.parse("9007199254740991.0")) == Ok("9007199254740991")
  assert text(decimal.parse("12.3400000000000000000000000000000"))
    == Ok("12.34000000000000")
}

pub fn parse_keeps_the_exponent_as_written_when_it_fits_test() {
  assert text(decimal.parse("12.30")) == Ok("12.30")
  assert text(decimal.parse("1.000000000000000")) == Ok("1.000000000000000")
  assert text(decimal.parse("0.0000000000000000000000000010"))
    == Ok("0.0000000000000000000000000010")
}

pub fn parse_moves_a_zero_into_the_range_test() {
  assert text(decimal.parse("0e-40")) == Ok("0.0000000000000000000000000000")
  assert text(decimal.parse("0.0000000000000000000000000000000"))
    == Ok("0.0000000000000000000000000000")
  assert text(decimal.parse("0e16")) == Ok("0")
  assert text(decimal.parse("-0e999999999")) == Ok("0")
}

pub fn parse_still_rejects_values_out_of_range_test() {
  assert decimal.parse("1e-29") == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("0.00000000000000000000000000001")
    == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("1e16") == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("10e15") == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("9007199254740992.0")
    == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("1e-999999999") == Error(decimal.ParsedValueTooLarge)
}

// --- add: the sum takes the smaller exponent, zero too ----------------------

pub fn adding_zero_takes_the_smaller_exponent_test() {
  assert text(decimal.add(support.parse("0.00"), support.parse("5")))
    == Ok("5.00")
  assert text(decimal.add(support.parse("5"), support.parse("0.00")))
    == Ok("5.00")
  assert text(decimal.add(decimal.zero(), support.parse("1.23"))) == Ok("1.23")
  assert text(decimal.subtract(support.parse("200000"), support.parse("0.00")))
    == Ok("200000.00")
  assert text(decimal.add(support.parse("0.000"), support.parse("0.0")))
    == Ok("0.000")
}

pub fn adding_zero_keeps_a_value_that_cannot_be_scaled_test() {
  assert text(decimal.add(
      support.new(coefficient: 0, exponent: -28),
      support.int(max),
    ))
    == Ok("9007199254740991")
}

pub fn money_add_of_zero_takes_the_currency_places_test() {
  let zero = support.from_minor(units: 0, currency: money.usd)
  let five = money.Money(support.parse("5"), money.usd)
  assert result.map(money.add(zero, five), money.to_string) == Ok("USD 5.00")
}

pub fn schedule_row_with_zero_principal_paid_keeps_the_places_test() {
  let assert Ok([first, second, ..]) =
    interest.schedule(
      principal: support.parse("200000"),
      rate_per_period: support.parse("0.05"),
      periods: 1200,
      digits: 2,
    )
  assert decimal.to_string(first.principal_paid) == "0.00"
  assert decimal.to_string(first.balance) == "200000.00"
  assert decimal.to_string(second.balance) == "200000.00"
}

// --- interest: results that do not fit at `digits` places -----------------

pub fn a_result_past_the_coefficient_bound_at_digits_is_an_error_test() {
  let exceeded = Error(interest.ArithmeticFailed(decimal.PrecisionExceeded))
  let principal = support.parse("200000")
  let rate = support.parse("0.005")
  assert interest.payment(
      principal:,
      rate_per_period: rate,
      periods: 360,
      digits: 20,
    )
    == exceeded
  assert interest.future_value(
      present: principal,
      rate_per_period: rate,
      periods: 360,
      digits: 20,
    )
    == exceeded
  assert interest.present_value(
      future: principal,
      rate_per_period: rate,
      periods: 360,
      digits: 20,
    )
    == exceeded
  assert interest.simple(principal:, rate:, periods: 360, digits: 20)
    == exceeded
  assert interest.schedule(
      principal:,
      rate_per_period: rate,
      periods: 360,
      digits: 20,
    )
    == Error(interest.ArithmeticFailed(decimal.PrecisionExceeded))
  // At 10 places it fits.
  assert text(interest.payment(
      principal:,
      rate_per_period: rate,
      periods: 360,
      digits: 10,
    ))
    == Ok("1199.1010503055")
}

// --- interest: exact rounding -----------------------------------------------

pub fn simple_is_exact_when_principal_times_periods_does_not_fit_test() {
  // 8007199254740.997 × 1200 does not fit a Decimal. Python's decimal:
  // 8007199254740.997 × 0.0041666666666667 × 1200 = 40035996273705.30558...
  // Rounding principal × rate to 16 digits first gave 40035996273705.30.
  assert text(interest.simple(
      principal: support.parse("8007199254740.997"),
      rate: support.parse("0.0041666666666667"),
      periods: 1200,
      digits: 2,
    ))
    == Ok("40035996273705.31")
}

pub fn future_value_rounds_the_exact_value_test() {
  // Python's decimal at 200 digits: 6142183.76893998...
  assert text(interest.future_value(
      present: support.parse("1310186.18"),
      rate_per_period: support.parse("0.0129583333"),
      periods: 120,
      digits: 6,
    ))
    == Ok("6142183.768940")
  assert text(interest.future_value(
      present: support.parse("509951565680"),
      rate_per_period: support.parse("0.0134083333"),
      periods: 360,
      digits: 2,
    ))
    == Ok("61650777558593.58")
}

pub fn present_value_rounds_the_exact_value_test() {
  assert text(interest.present_value(
      future: support.parse("5435498990.4"),
      rate_per_period: support.parse("0.01120833333333"),
      periods: 360,
      digits: 6,
    ))
    == Ok("98312566.596259")
}

pub fn present_value_uses_a_16_place_rate_as_given_test() {
  // Python: 1000 / 1.0041666666666667^360 = 223.826595641349 at 12 places.
  // With the rate rounded to 15 places in 1 + rate it is 223.826595641325.
  assert text(interest.present_value(
      future: support.parse("1000"),
      rate_per_period: support.parse("0.0041666666666667"),
      periods: 360,
      digits: 12,
    ))
    == Ok("223.826595641349")
}
