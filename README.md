# finanza

[![Package Version](https://img.shields.io/hexpm/v/finanza)](https://hex.pm/packages/finanza)
[![Downloads](https://img.shields.io/hexpm/dt/finanza)](https://hex.pm/packages/finanza)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/finanza/)
[![CI](https://github.com/nao1215/finanza/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/finanza/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/nao1215/finanza)](LICENSE)

Decimal arithmetic, currency, interest, and payment card primitives for
Gleam — a small fintech utility kit with no panics and no implicit
rounding.

## Features

- **Decimal** — opaque fixed-point type with explicit rounding modes
  (`HalfEven`, `HalfUp`, `HalfDown`, `Up`, `Down`, `Ceiling`, `Floor`)
- **Money / Currency** — opaque `Money` and `Currency`, ratio allocation
  without losing cents, customizable `FormatOptions` builder, snapshot
  catalog of 15 major currencies plus user-defined `currency.new_currency`
- **Interest** — simple/compound interest, `future_value`, `present_value`,
  `payment`, `effective_annual_rate`, and amortization schedules
- **Payment cards** — Luhn check, IIN-based brand detection
  (Visa/MC/Amex/Discover/JCB/DinersClub/UnionPay), masking, BIN/last-four,
  expiry parse and validation
- Runs on both **Erlang** and **JavaScript** targets
- No panics, no silent rounding, no external dependencies beyond
  `gleam_stdlib` and `gleam_regexp`

## Install

```sh
gleam add finanza
```

## Decimal arithmetic

```gleam
import gleam/result
import finanza/decimal
import finanza/decimal/rounding

pub fn invoice_total() -> Result(String, decimal.ArithmeticError) {
  let assert Ok(subtotal) = decimal.from_string("99.99")
  let assert Ok(rate) = decimal.from_string("0.08")
  use tax_raw <- result.try(decimal.multiply(subtotal, rate))
  let tax = decimal.round(tax_raw, 2, rounding.HalfEven)
  use total <- result.map(decimal.add(subtotal, tax))
  decimal.to_string(total)
}

// invoice_total() -> Ok("107.99")
```

## Money and allocation

`allocate` distributes a `Money` value according to integer ratios and
keeps the rounding remainder on the first slot — useful for splitting an
invoice across line items without losing cents.

```gleam
import finanza/currency
import finanza/currency/catalog

pub fn split_bill() -> Result(List(currency.Money), currency.CurrencyError) {
  let bill = currency.from_minor(units: 10_000, currency: catalog.jpy())
  currency.allocate(bill, [1, 1, 1])
}

// split_bill() -> Ok([¥3334, ¥3333, ¥3333])
```

## Money formatting

```gleam
import finanza/currency
import finanza/currency/catalog

pub fn invoice_label() -> String {
  let amount = currency.from_minor(units: 123_456, currency: catalog.eur())
  let options =
    currency.default_format()
    |> currency.with_thousands_separator(separator: ".")
    |> currency.with_decimal_separator(separator: ",")
    |> currency.with_symbol_position(position: currency.Suffix)
  currency.format(amount, options)
}

// invoice_label() -> "1.234,56€"
```

## Time value of money

```gleam
import finanza/decimal
import finanza/interest

pub fn monthly_payment() -> Result(String, interest.InterestError) {
  let assert Ok(principal) = decimal.from_string("200000")
  let assert Ok(rate) = decimal.from_string("0.005")
  // 30-year fixed loan, 360 monthly payments at 0.5%/month.
  case interest.payment(
    principal: principal,
    rate_per_period: rate,
    periods: 360,
    digits: 2,
  ) {
    Ok(pmt) -> Ok(decimal.to_string(pmt))
    Error(e) -> Error(e)
  }
}
```

## Payment card primitives

```gleam
import finanza/card

pub fn classify(pan: String) -> Result(card.Brand, card.ValidationError) {
  card.validate(pan)
}

pub fn mask(pan: String) -> Result(String, card.ValidationError) {
  card.mask(pan, card.mask_defaults())
}

// classify("4111 1111 1111 1111") -> Ok(Visa)
// mask("4111111111111111")        -> Ok("4111 **** **** 1111")
```

## Snapshot disclaimer

The 15-currency catalog and the brand IIN ranges are static snapshots
taken in **May 2026**. The library does not track ISO 4217 updates or
BIN-database changes. For currencies outside the catalog, build your
own with `currency.new_currency`.

## JavaScript target precision

On the JavaScript target, `Decimal` coefficients are bounded by
`Number.MAX_SAFE_INTEGER` (2^53 - 1). Operations that would exceed this
bound return `decimal.PrecisionExceeded` rather than silently losing
precision. The Erlang target uses arbitrary-precision integers and is
unaffected.

## Development

```sh
mise install
just deps
just ci
```

`just` recipes source `scripts/lib/mise_bootstrap.sh`, so `mise activate`
is not required in the current shell.

## License

[MIT](LICENSE)
