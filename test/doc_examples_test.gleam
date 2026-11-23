//// The values claimed in the doc comments of the public functions.

import finanza/card
import finanza/decimal
import finanza/interest
import finanza/money
import gleam/list
import gleam/result
import support

pub fn doc_examples_test() {
  assert decimal.new(coefficient: 1234, exponent: -2)
    |> result.map(decimal.to_string)
    == Ok("12.34")
  assert decimal.new(coefficient: 1, exponent: 16) == Error(Nil)
  assert decimal.parse(" 12.30 ") |> result.map(decimal.to_string)
    == Ok("12.30")
  assert decimal.parse("1.2.3") == Error(decimal.MultipleDecimalPoints)
  assert decimal.format(
      support.parse("1234567.5"),
      thousands: ".",
      decimal_separator: ",",
    )
    == "1.234.567,5"
  assert decimal.divide(
      support.int(10),
      support.int(3),
      digits: 2,
      rounding: decimal.HalfEven,
    )
    |> result.map(decimal.to_string)
    == Ok("3.33")
  assert decimal.round(
      support.parse("2.345"),
      digits: 2,
      rounding: decimal.HalfEven,
    )
    |> result.map(decimal.to_string)
    == Ok("2.34")
  assert decimal.round(
      support.parse("2.345"),
      digits: 2,
      rounding: decimal.HalfUp,
    )
    |> result.map(decimal.to_string)
    == Ok("2.35")
  assert decimal.divide(
      support.int(1),
      support.int(3),
      digits: 15,
      rounding: decimal.HalfEven,
    )
    |> result.is_ok
  assert decimal.divide(
      support.int(1),
      support.int(3),
      digits: 16,
      rounding: decimal.HalfEven,
    )
    == Error(decimal.PrecisionExceeded)
  assert decimal.to_string(support.new(coefficient: 12, exponent: 2)) == "1200"
  assert money.find_currency("JPY") == Ok(money.jpy)
  let assert Ok(a) = money.from_minor(150, in: money.usd)
  let assert Ok(b) = money.from_minor(1, in: money.eur)
  assert money.add(a, b)
    == Error(money.CurrencyMismatch(left: "USD", right: "EUR"))
  let assert Ok(price) = money.from_minor(999, in: money.usd)
  assert money.multiply(
      price,
      by: support.parse("0.08"),
      rounding: decimal.HalfEven,
    )
    |> result.map(money.to_string)
    == Ok("USD 0.80")
  let assert Ok(bill) = money.from_minor(1000, in: money.usd)
  assert money.allocate(bill, [1, 1, 1])
    |> result.map(list.map(_, money.to_string))
    == Ok(["USD 3.34", "USD 3.33", "USD 3.33"])
  assert money.allocate(bill, [0, 0]) == Error(money.NonPositiveRatio)
  let assert Ok(p) = money.from_minor(-123_456, in: money.eur)
  let options =
    money.FormatOptions(
      ..money.default_format,
      thousands_separator: ".",
      decimal_separator: ",",
      symbol_position: money.Suffix,
      negative_style: money.Parentheses,
    )
  assert money.format(p, with: options) == "(1.234,56€)"
  assert money.format(p, with: money.default_format) == "-€1,234.56"
  assert interest.simple(
      principal: support.parse("1000"),
      rate: support.parse("0.05"),
      periods: 3,
      digits: 2,
    )
    |> result.map(decimal.to_string)
    == Ok("150.00")
  assert interest.future_value(
      present: support.parse("1000"),
      rate_per_period: support.parse("0.05"),
      periods: 10,
      digits: 2,
    )
    |> result.map(decimal.to_string)
    == Ok("1628.89")
  assert interest.payment(
      principal: support.parse("200000"),
      rate_per_period: support.parse("0.005"),
      periods: 360,
      digits: 2,
    )
    |> result.map(decimal.to_string)
    == Ok("1199.10")
  let assert Ok([first, ..]) =
    interest.schedule(
      principal: support.parse("1000"),
      rate_per_period: support.parse("0.01"),
      periods: 12,
      digits: 2,
    )
  assert #(
      decimal.to_string(first.interest),
      decimal.to_string(first.principal_paid),
    )
    == #("10.00", "78.85")
  assert interest.schedule(
      principal: support.parse("1000"),
      rate_per_period: support.parse("0.01"),
      periods: 0,
      digits: 2,
    )
    == Ok([])
  assert card.normalize("4111-1111 1111.1111") == "4111111111111111"
  assert card.luhn_valid("79927398713")
  assert !card.luhn_valid("7992 7398 713")
  assert card.validate("4111 1111 1111 1112") == Error(card.InvalidLuhn)
  assert card.expiry_valid(
    card.Expiry(month: 5, year: 2026),
    today: card.Expiry(month: 5, year: 2026),
  )
  assert card.parse_expiry("13/28") == Error(Nil)
  assert card.parse_expiry("126") == Error(Nil)
  assert card.brand_to_string(card.AmericanExpress) == "AMEX"
}
