# finanza

Decimal arithmetic, currency formatting, time-value-of-money, and
payment-card helpers for Gleam. Runs on the Erlang and JavaScript
targets.

[![Package Version](https://img.shields.io/hexpm/v/finanza)](https://hex.pm/packages/finanza)
[![Downloads](https://img.shields.io/hexpm/dt/finanza)](https://hex.pm/packages/finanza)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/finanza/)
[![CI](https://github.com/nao1215/finanza/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/finanza/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/nao1215/finanza)](LICENSE)

```sh
gleam add finanza
```

## Decimal

```gleam
import gleam/result
import finanza/decimal
import finanza/decimal/rounding

pub fn invoice_total() -> Result(String, decimal.ArithmeticError) {
  let assert Ok(subtotal) = decimal.from_string("99.99")
  let assert Ok(rate) = decimal.from_string("0.08")
  use raw <- result.try(decimal.multiply(subtotal, rate))
  let tax = decimal.round(raw, 2, rounding.HalfEven)
  use total <- result.map(decimal.add(subtotal, tax))
  decimal.to_string(total)
}
// invoice_total() == Ok("107.99")
```

```gleam
import finanza/decimal

decimal.format(
  d: decimal.new(coefficient: 1_234_567, exponent: -2),
  thousands: ",",
  decimal_separator: ".",
)
// "12,345.67"
```

## Money

```gleam
import finanza/currency
import finanza/currency/catalog
import finanza/decimal

pub fn invoice_line() -> String {
  currency.new_money(decimal.from_int(200_000), catalog.usd())
  |> currency.format(currency.default_format())
}
// invoice_line() == "$200,000.00"
```

```gleam
import gleam/list
import gleam/result
import finanza/currency
import finanza/currency/catalog
import finanza/decimal/rounding

pub fn split_yen_bill() -> Result(List(Int), currency.CurrencyError) {
  let bill = currency.from_minor(10_000, catalog.jpy())
  use parts <- result.try(currency.allocate(bill, [1, 1, 1]))
  parts
  |> list.map(fn(p) { currency.to_minor(p, rounding.HalfEven) })
  |> result.all
}
// split_yen_bill() == Ok([3334, 3333, 3333])
```

```gleam
import finanza/currency
import finanza/currency/catalog

pub fn invoice_label_de() -> String {
  let amount = currency.from_minor(123_456, catalog.eur())
  let options =
    currency.default_format()
    |> currency.with_thousands_separator(".")
    |> currency.with_decimal_separator(",")
    |> currency.with_symbol_position(currency.Suffix)
  currency.format(amount, options)
}
// invoice_label_de() == "1.234,56€"
```

```gleam
import gleam/result
import finanza/currency
import finanza/currency/catalog
import finanza/decimal/rounding

pub fn invoice_total() -> Result(Int, currency.CurrencyError) {
  let usd = catalog.usd()
  let line_items = [
    currency.from_minor(12_000, usd),
    currency.from_minor(4_500, usd),
    currency.from_minor(99, usd),
  ]
  use total <- result.try(currency.sum(line_items))
  currency.to_minor(total, rounding.HalfEven)
}
// invoice_total() == Ok(16_599)
```

## Interest

```gleam
import gleam/result
import finanza/decimal
import finanza/interest

pub fn monthly_mortgage() -> Result(String, interest.InterestError) {
  let assert Ok(principal) = decimal.from_string("200000")
  let assert Ok(rate) = decimal.from_string("0.005")
  // 30-year fixed, 360 monthly payments at 0.5%/month.
  use pmt <- result.map(interest.payment(principal, rate, 360, 2))
  decimal.to_string(pmt)
}
// monthly_mortgage() == Ok("1199.10")
```

```gleam
import gleam/list
import gleam/result
import finanza/decimal
import finanza/interest/amortization

pub fn first_payment_breakdown() -> Result(#(String, String), Nil) {
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
// first_payment_breakdown() == Ok(#("10.00", "78.85"))
```

## Card

```gleam
import finanza/card

pub fn check_card(pan: String) -> Result(card.Brand, card.ValidationError) {
  card.validate(pan)
}
// check_card("4111 1111 1111 1111") == Ok(card.Visa)
// check_card("378282246310005")    == Ok(card.AmericanExpress)
// check_card("4111111111111112")   == Error(card.InvalidLuhn)
```

```gleam
import finanza/card

pub fn safe_display(pan: String) -> Result(String, card.ValidationError) {
  card.mask(pan, card.default_mask())
}
// safe_display("4111111111111111") == Ok("4111 **** **** 1111")
// safe_display("378282246310005")  == Ok("3782 **** *** 0005")
```

```gleam
import finanza/card

pub fn parse_card_expiry(input: String) {
  card.parse_expiry(input)
}
// parse_card_expiry("12/28")   == Ok(#(12, 2028))
// parse_card_expiry("12/2028") == Ok(#(12, 2028))
// parse_card_expiry("13/28")   == Error(card.InvalidExpiry)
```

```gleam
import finanza/card

pub fn still_valid(month: Int, year: Int) -> Bool {
  card.expiry_valid(expiry: #(month, year), today: #(5, 2026))
}
// still_valid(12, 2028) == True
// still_valid(5, 2026)  == True
// still_valid(4, 2026)  == False
```

## Notes

- Currency catalogue and brand IIN ranges are static snapshots from
  May 2026.
- JavaScript target: Decimal coefficients are capped at 2^53 − 1.
  Operations beyond that return `decimal.PrecisionExceeded`.

## License

[MIT](LICENSE)
