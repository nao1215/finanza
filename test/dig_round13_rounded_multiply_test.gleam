//// `money.multiply` and the interest functions round the exact product
//// to the places they return, so a product that `decimal.multiply`
//// cannot hold exactly still succeeds when its rounded value is in
//// range. The expected values come from Python's `decimal` module with
//// 200 digits of precision and `quantize` in the matching mode.
//// The properties are in `test/property/rounded_multiply_test.gleam`.

import gleam/list
import gleam/result

import finanza/decimal
import finanza/interest
import finanza/money
import support

// 2^53 - 1.
const max = 9_007_199_254_740_991

const modes = [
  decimal.HalfEven,
  decimal.HalfUp,
  decimal.HalfDown,
  decimal.Up,
  decimal.Down,
  decimal.Ceiling,
  decimal.Floor,
]

fn usd(amount: String) -> money.Money {
  money.Money(amount: support.parse(amount), currency: money.usd)
}

fn times(
  amount: money.Money,
  factor: String,
  mode: decimal.RoundingMode,
) -> Result(String, money.MoneyError) {
  money.multiply(amount, by: support.parse(factor), rounding: mode)
  |> result.map(fn(product) { decimal.to_string(product.amount) })
}

fn every_mode(
  amount: money.Money,
  factor: String,
) -> List(Result(String, money.MoneyError)) {
  list.map(modes, times(amount, factor, _))
}

fn text(value: Result(decimal.Decimal, a)) -> Result(String, a) {
  result.map(value, decimal.to_string)
}

// --- the reported products ---------------------------------------------------

pub fn usd_times_a_sixteen_digit_factor_test() {
  // 1234.57 × 1.234567890123456 = 1524.16048010971507392
  assert every_mode(usd("1234.57"), "1.234567890123456")
    == [
      Ok("1524.16"),
      Ok("1524.16"),
      Ok("1524.16"),
      Ok("1524.17"),
      Ok("1524.16"),
      Ok("1524.17"),
      Ok("1524.16"),
    ]
}

pub fn negative_usd_times_a_sixteen_digit_factor_test() {
  assert every_mode(usd("-1234.57"), "1.234567890123456")
    == [
      Ok("-1524.16"),
      Ok("-1524.16"),
      Ok("-1524.16"),
      Ok("-1524.17"),
      Ok("-1524.16"),
      Ok("-1524.16"),
      Ok("-1524.17"),
    ]
}

pub fn usd_times_a_factor_past_28_places_test() {
  // 1000.01 × 1e-27 = 1.00001e-24, which has a digit at 29 places.
  assert every_mode(usd("1000.01"), "1e-27")
    == [
      Ok("0.00"),
      Ok("0.00"),
      Ok("0.00"),
      Ok("0.01"),
      Ok("0.00"),
      Ok("0.01"),
      Ok("0.00"),
    ]
  assert every_mode(usd("-1000.01"), "1e-27")
    == [
      Ok("0.00"),
      Ok("0.00"),
      Ok("0.00"),
      Ok("-0.01"),
      Ok("0.00"),
      Ok("0.00"),
      Ok("-0.01"),
    ]
}

pub fn product_past_28_places_at_28_places_test() {
  let currency = money.Currency(..money.usd, exponent: 28)
  let amount = money.Money(amount: support.parse("1000.01"), currency:)
  assert times(amount, "1e-27", decimal.HalfEven)
    == Ok("0.0000000000000000000000010000")
  assert times(amount, "1e-27", decimal.Up)
    == Ok("0.0000000000000000000000010001")
}

// --- exactly half ------------------------------------------------------------

pub fn half_cent_past_the_coefficient_bound_test() {
  // 9007199254740.99 × 1.5 = 13510798882111.485, a coefficient past
  // 2^53 - 1 that is exactly half a cent.
  assert every_mode(usd("9007199254740.99"), "1.5")
    == [
      Ok("13510798882111.48"),
      Ok("13510798882111.49"),
      Ok("13510798882111.48"),
      Ok("13510798882111.49"),
      Ok("13510798882111.48"),
      Ok("13510798882111.49"),
      Ok("13510798882111.48"),
    ]
  assert every_mode(usd("-9007199254740.99"), "1.5")
    == [
      Ok("-13510798882111.48"),
      Ok("-13510798882111.49"),
      Ok("-13510798882111.48"),
      Ok("-13510798882111.49"),
      Ok("-13510798882111.48"),
      Ok("-13510798882111.48"),
      Ok("-13510798882111.49"),
    ]
}

pub fn half_cent_with_an_odd_cent_test() {
  // 9007199254740.97 × 1.5 = 13510798882111.455: HalfEven goes to the
  // even 46 here, up instead of down.
  assert times(usd("9007199254740.97"), "1.5", decimal.HalfEven)
    == Ok("13510798882111.46")
  assert times(usd("9007199254740.97"), "1.5", decimal.HalfDown)
    == Ok("13510798882111.45")
}

pub fn half_past_28_places_test() {
  // 5e-28 × 0.1 = 5e-29, exactly half of the last place.
  let currency = money.Currency(..money.usd, exponent: 28)
  let amount = money.Money(amount: support.parse("5e-28"), currency:)
  assert times(amount, "0.1", decimal.HalfEven)
    == Ok("0.0000000000000000000000000000")
  assert times(amount, "0.1", decimal.HalfUp)
    == Ok("0.0000000000000000000000000001")
  assert times(amount, "0.1", decimal.HalfDown)
    == Ok("0.0000000000000000000000000000")
  assert times(amount, "0.3", decimal.HalfEven)
    == Ok("0.0000000000000000000000000002")
}

// --- the coefficient bound ---------------------------------------------------

pub fn rounded_product_at_the_coefficient_bound_test() {
  // 9007199254740982 × 1.000000000000001 = 9007199254740991.007199254740982
  let yen = money.Money(amount: support.int(max - 9), currency: money.jpy)
  let factor = "1.000000000000001"
  assert times(yen, factor, decimal.Down) == Ok("9007199254740991")
  assert times(yen, factor, decimal.HalfEven) == Ok("9007199254740991")
  assert times(yen, factor, decimal.Floor) == Ok("9007199254740991")
  // Rounding up gives 2^53, one past the bound.
  assert times(yen, factor, decimal.Up)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  assert times(yen, factor, decimal.Ceiling)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
}

pub fn negative_rounded_product_at_the_coefficient_bound_test() {
  let yen =
    money.Money(amount: support.int(0 - { max - 9 }), currency: money.jpy)
  let factor = "1.000000000000001"
  assert times(yen, factor, decimal.Ceiling) == Ok("-9007199254740991")
  assert times(yen, factor, decimal.Down) == Ok("-9007199254740991")
  assert times(yen, factor, decimal.Floor)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  assert times(yen, factor, decimal.Up)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
}

pub fn rounded_product_past_the_coefficient_bound_test() {
  // 2^53 - 1 yen × 1.5 is out of range in every mode.
  let yen = money.Money(amount: support.int(max), currency: money.jpy)
  assert every_mode(yen, "1.5")
    == list.repeat(Error(money.ArithmeticFailed(decimal.PrecisionExceeded)), 7)
}

pub fn padding_past_the_coefficient_bound_test() {
  // 9007199254740991 × 10 needs one more digit than the coefficient
  // holds, at 0 places as at 2.
  let yen = money.Money(amount: support.int(max), currency: money.jpy)
  assert times(yen, "10", decimal.HalfEven)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  assert times(usd("90071992547409.91"), "1", decimal.HalfEven)
    == Ok("90071992547409.91")
  assert times(usd("90071992547409.91"), "10", decimal.HalfEven)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
}

// --- interest ----------------------------------------------------------------

pub fn simple_interest_with_a_sixteen_digit_rate_test() {
  // 1234.57 × 0.0123456789012345 × 3 = 45.72...
  let principal = support.parse("1234.57")
  let rate = support.parse("0.0123456789012345")
  assert interest.simple(principal:, rate:, periods: 3, digits: 2) |> text
    == Ok("45.72")
}

pub fn simple_interest_when_no_exact_scaling_fits_test() {
  // Neither principal × 1200 nor rate × 1200 fits exactly, so the
  // product of principal and rate is rounded to 12 places first. The
  // exact answer is 1334399877581.658065588675254187520.
  let principal = support.new(coefficient: max, exponent: -6)
  let rate = support.parse("0.1234567890123456")
  assert interest.simple(principal:, rate:, periods: 1200, digits: 2) |> text
    == Ok("1334399877581.66")
}

pub fn payment_with_a_fifteen_digit_rate_test() {
  // 5% a year over 12 months, written to 15 places: 0.05 / 12. The
  // numerator 123456.78 × 0.004166666666667 = 514.40325000004115226 does
  // not fit a Decimal exactly.
  let principal = support.parse("123456.78")
  let rate = support.parse("0.004166666666667")
  assert interest.payment(
      principal:,
      rate_per_period: rate,
      periods: 12,
      digits: 2,
    )
    |> text
    == Ok("10568.82")
}

pub fn schedule_with_a_fifteen_digit_rate_test() {
  // The first month's interest is 123456.78 × 0.004166666666667 =
  // 514.40325000004115226.
  let principal = support.parse("123456.78")
  let rate = support.parse("0.004166666666667")
  let assert Ok(rows) =
    interest.schedule(principal:, rate_per_period: rate, periods: 12, digits: 2)
  let assert [first, ..] = rows
  assert decimal.to_string(first.interest) == "514.40"
  assert decimal.to_string(first.principal_paid) == "10054.42"
  assert list.length(rows) == 12
  let assert Ok(last) = list.last(rows)
  assert decimal.is_zero(last.balance)
}
