//// The examples in README.md, kept here so that they compile and their
//// results stay true.

import finanza/card
import finanza/decimal
import finanza/interest
import finanza/money
import gleam/list
import gleam/result

fn price_with_tax() -> Result(String, money.MoneyError) {
  let assert Ok(price) = money.from_minor(9999, in: money.usd)
  let assert Ok(rate) = decimal.parse("0.08")
  use tax <- result.try(money.multiply(
    price,
    by: rate,
    rounding: decimal.HalfEven,
  ))
  use total <- result.map(money.add(price, tax))
  money.format(total, with: money.default_format)
}

pub fn price_with_tax_test() -> Nil {
  assert price_with_tax() == Ok("$107.99")
}

fn split_bill() -> Result(List(String), money.MoneyError) {
  let assert Ok(bill) = money.from_minor(100_000, in: money.eur)
  let german =
    money.FormatOptions(
      ..money.default_format,
      thousands_separator: ".",
      decimal_separator: ",",
      symbol_position: money.Suffix,
    )
  use parts <- result.map(money.allocate(bill, [1, 1, 1]))
  list.map(parts, money.format(_, with: german))
}

pub fn split_bill_test() -> Nil {
  assert split_bill() == Ok(["333,34€", "333,33€", "333,33€"])
}

fn mortgage() -> #(String, String) {
  let assert Ok(principal) = decimal.parse("200000")
  let assert Ok(rate) = decimal.parse("0.005")
  let assert Ok([first, ..]) =
    interest.schedule(
      principal:,
      rate_per_period: rate,
      periods: 360,
      digits: 2,
    )
  #(decimal.to_string(first.payment), decimal.to_string(first.interest))
}

pub fn mortgage_test() -> Nil {
  assert mortgage() == #("1199.10", "1000.00")
}

pub fn card_details_test() -> Nil {
  assert card.validate("4111 1111 1111 1111") == Ok(card.Visa)
  assert card.mask("378282246310005", with: card.default_mask)
    == Ok("3782 **** *** 0005")
  assert card.parse_expiry("12/28") == Ok(card.Expiry(month: 12, year: 2028))
}
