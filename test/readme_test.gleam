//// Every example in `README.md` is exercised here so that a rename
//// or signature change in the public API surfaces as a build failure
//// rather than silently-stale documentation. The snippets in this
//// file must match the README byte-for-byte.

import gleam/list
import gleam/result
import gleeunit/should

import finanza/card
import finanza/currency
import finanza/currency/catalog
import finanza/decimal
import finanza/decimal/rounding
import finanza/interest
import finanza/interest/amortization

// --- Decimal ------------------------------------------------------------

fn invoice_total() -> Result(String, decimal.ArithmeticError) {
  let assert Ok(subtotal) = decimal.from_string("99.99")
  let assert Ok(rate) = decimal.from_string("0.08")
  use raw <- result.try(decimal.multiply(subtotal, rate))
  let tax = decimal.round(raw, 2, rounding.HalfEven)
  use total <- result.map(decimal.add(subtotal, tax))
  decimal.to_string(total)
}

pub fn readme_invoice_total_test() -> Nil {
  invoice_total()
  |> should.equal(Ok("107.99"))
}

pub fn readme_decimal_format_test() -> Nil {
  decimal.format(
    d: decimal.new(coefficient: 1_234_567, exponent: -2),
    thousands: ",",
    decimal_separator: ".",
  )
  |> should.equal("12,345.67")
}

// --- Money --------------------------------------------------------------

fn invoice_line() -> String {
  currency.new_money(decimal.from_int(200_000), catalog.usd())
  |> currency.format(currency.default_format())
}

pub fn readme_invoice_line_test() -> Nil {
  invoice_line()
  |> should.equal("$200,000.00")
}

fn split_yen_bill() -> Result(List(Int), currency.CurrencyError) {
  let bill = currency.from_minor(10_000, catalog.jpy())
  use parts <- result.try(currency.allocate(bill, [1, 1, 1]))
  parts
  |> list.map(fn(p) { currency.to_minor(p, rounding.HalfEven) })
  |> result.all
}

pub fn readme_split_yen_bill_test() -> Nil {
  split_yen_bill()
  |> should.equal(Ok([3334, 3333, 3333]))
}

fn invoice_label_de() -> String {
  let amount = currency.from_minor(123_456, catalog.eur())
  let options =
    currency.default_format()
    |> currency.with_thousands_separator(".")
    |> currency.with_decimal_separator(",")
    |> currency.with_symbol_position(currency.Suffix)
  currency.format(amount, options)
}

pub fn readme_invoice_label_de_test() -> Nil {
  invoice_label_de()
  |> should.equal("1.234,56€")
}

// --- Interest -----------------------------------------------------------

fn monthly_mortgage() -> Result(String, interest.InterestError) {
  let assert Ok(principal) = decimal.from_string("200000")
  let assert Ok(rate) = decimal.from_string("0.005")
  // 30-year fixed, 360 monthly payments at 0.5%/month.
  use pmt <- result.map(interest.payment(principal, rate, 360, 2))
  decimal.to_string(pmt)
}

pub fn readme_monthly_mortgage_test() -> Nil {
  monthly_mortgage()
  |> should.equal(Ok("1199.10"))
}

fn first_payment_breakdown() -> Result(#(String, String), Nil) {
  let assert Ok(principal) = decimal.from_string("1000")
  let assert Ok(rate) = decimal.from_string("0.01")
  use rows <- result.try(
    amortization.schedule(principal, rate, 12, 2)
    |> result.replace_error(Nil),
  )
  use first <- result.map(list.first(rows))
  #(
    decimal.to_string(amortization.interest(first)),
    decimal.to_string(amortization.principal_paid(first)),
  )
}

pub fn readme_first_payment_breakdown_test() -> Nil {
  first_payment_breakdown()
  |> should.equal(Ok(#("10.00", "78.85")))
}

// --- Card ---------------------------------------------------------------

fn check_card(pan: String) -> Result(card.Brand, card.ValidationError) {
  card.validate(pan)
}

pub fn readme_check_card_visa_test() -> Nil {
  check_card("4111 1111 1111 1111")
  |> should.equal(Ok(card.Visa))
}

pub fn readme_check_card_amex_test() -> Nil {
  check_card("378282246310005")
  |> should.equal(Ok(card.AmericanExpress))
}

pub fn readme_check_card_luhn_fail_test() -> Nil {
  check_card("4111111111111112")
  |> should.equal(Error(card.InvalidLuhn))
}

fn safe_display(pan: String) -> Result(String, card.ValidationError) {
  card.mask(pan, card.default_mask())
}

pub fn readme_safe_display_visa_test() -> Nil {
  safe_display("4111111111111111")
  |> should.equal(Ok("4111 **** **** 1111"))
}

pub fn readme_safe_display_amex_test() -> Nil {
  safe_display("378282246310005")
  |> should.equal(Ok("3782 **** *** 0005"))
}

fn parse_card_expiry(input: String) {
  card.parse_expiry(input)
}

pub fn readme_parse_expiry_short_test() -> Nil {
  parse_card_expiry("12/28")
  |> should.equal(Ok(#(12, 2028)))
}

pub fn readme_parse_expiry_long_test() -> Nil {
  parse_card_expiry("12/2028")
  |> should.equal(Ok(#(12, 2028)))
}

pub fn readme_parse_expiry_invalid_test() -> Nil {
  parse_card_expiry("13/28")
  |> should.equal(Error(card.InvalidExpiry))
}

fn still_valid(month: Int, year: Int) -> Bool {
  card.expiry_valid(expiry: #(month, year), today: #(5, 2026))
}

pub fn readme_still_valid_future_test() -> Nil {
  still_valid(12, 2028)
  |> should.be_true
}

pub fn readme_still_valid_current_test() -> Nil {
  still_valid(5, 2026)
  |> should.be_true
}

pub fn readme_still_valid_past_test() -> Nil {
  still_valid(4, 2026)
  |> should.be_false
}
