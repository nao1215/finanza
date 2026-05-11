//// Smoke tests for the snippets in `README.md`. These exist so that a
//// rename or signature change in the public API surfaces as a build
//// failure rather than as silently-stale documentation.

import gleam/result
import gleam/string
import gleeunit/should

import finanza/card
import finanza/currency
import finanza/currency/catalog
import finanza/decimal
import finanza/decimal/rounding
import finanza/interest

pub fn readme_invoice_total_test() -> Nil {
  let assert Ok(text) = invoice_total()
  text
  |> should.equal("107.99")
}

fn invoice_total() -> Result(String, decimal.ArithmeticError) {
  let assert Ok(subtotal) = decimal.from_string("99.99")
  let assert Ok(rate) = decimal.from_string("0.08")
  use tax_raw <- result.try(decimal.multiply(subtotal, rate))
  let tax = decimal.round(tax_raw, 2, rounding.HalfEven)
  use total <- result.map(decimal.add(subtotal, tax))
  decimal.to_string(total)
}

pub fn readme_split_bill_test() -> Nil {
  let assert Ok(parts) = split_bill()
  let totals =
    parts
    |> list_map(fn(p) {
      let assert Ok(units) = currency.to_minor(m: p, mode: rounding.HalfEven)
      units
    })
  totals
  |> should.equal([3334, 3333, 3333])
}

fn split_bill() -> Result(List(currency.Money), currency.CurrencyError) {
  let bill = currency.from_minor(units: 10_000, currency: catalog.jpy())
  currency.allocate(bill, [1, 1, 1])
}

pub fn readme_invoice_label_test() -> Nil {
  invoice_label()
  |> should.equal("1.234,56€")
}

fn invoice_label() -> String {
  let amount = currency.from_minor(units: 123_456, currency: catalog.eur())
  let options =
    currency.default_format()
    |> currency.with_thousands_separator(separator: ".")
    |> currency.with_decimal_separator(separator: ",")
    |> currency.with_symbol_position(position: currency.Suffix)
  currency.format(amount, options)
}

pub fn readme_monthly_payment_test() -> Nil {
  let assert Ok(text) = monthly_payment()
  // Sanity: rendered mortgage payment is a small numeric string.
  let length = string.length(text)
  { length > 0 && length < 10 }
  |> should.be_true
}

fn monthly_payment() -> Result(String, interest.InterestError) {
  let assert Ok(principal) = decimal.from_string("200000")
  let assert Ok(rate) = decimal.from_string("0.005")
  case
    interest.payment(
      principal: principal,
      rate_per_period: rate,
      periods: 360,
      digits: 2,
    )
  {
    Ok(pmt) -> Ok(decimal.to_string(pmt))
    Error(e) -> Error(e)
  }
}

pub fn readme_classify_test() -> Nil {
  classify("4111 1111 1111 1111")
  |> should.equal(Ok(card.Visa))
}

fn classify(pan: String) -> Result(card.Brand, card.ValidationError) {
  card.validate(pan)
}

pub fn readme_mask_test() -> Nil {
  mask("4111111111111111")
  |> should.equal(Ok("4111 **** **** 1111"))
}

fn mask(pan: String) -> Result(String, card.ValidationError) {
  card.mask(pan, card.mask_defaults())
}

// --- Helpers ------------------------------------------------------------

fn list_map(items: List(a), f: fn(a) -> b) -> List(b) {
  case items {
    [] -> []
    [head, ..rest] -> [f(head), ..list_map(rest, f)]
  }
}
