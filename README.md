# finanza

[![CI](https://github.com/nao1215/finanza/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/finanza/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/finanza/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/finanza/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/finanza/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/finanza/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/finanza/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/finanza/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/finanza)](https://hex.pm/packages/finanza)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/finanza/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/finanza)](https://hex.pm/packages/finanza)
[![License](https://img.shields.io/github/license/nao1215/finanza)](https://github.com/nao1215/finanza/blob/main/LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/finanza/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/finanza)

Decimal numbers, money, interest and payment card helpers for Gleam, on
the Erlang and JavaScript targets.

```sh
gleam add finanza
```

## Usage

Adding sales tax to a price, rounded to the cent:

```gleam
import finanza/decimal
import finanza/money
import gleam/result

pub fn price_with_tax() -> Result(String, money.MoneyError) {
  let assert Ok(price) = money.from_minor(9999, in: money.usd)
  let assert Ok(rate) = decimal.parse("0.08")
  use tax <- result.try(money.multiply(price, by: rate, rounding: decimal.HalfEven))
  use total <- result.map(money.add(price, tax))
  money.format(total, with: money.default_format)
  // -> Ok("$107.99")
}
```

Splitting a bill three ways without losing the remainder, and formatting
for a German invoice:

```gleam
import finanza/money
import gleam/list
import gleam/result

pub fn split_bill() -> Result(List(String), money.MoneyError) {
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
  // -> Ok(["333,34€", "333,33€", "333,33€"])
}
```

A monthly mortgage payment and the first row of its schedule:

```gleam
import finanza/decimal
import finanza/interest

pub fn mortgage() -> #(String, String) {
  let assert Ok(principal) = decimal.parse("200000")
  let assert Ok(rate) = decimal.parse("0.005")
  let assert Ok([first, ..]) =
    interest.schedule(principal:, rate_per_period: rate, periods: 360, digits: 2)
  #(decimal.to_string(first.payment), decimal.to_string(first.interest))
  // -> #("1199.10", "1000.00")
}
```

Checking and masking a card number:

```gleam
import finanza/card

pub fn card_details() {
  #(
    card.validate("4111 1111 1111 1111"),
    // -> Ok(card.Visa)
    card.mask("378282246310005", with: card.default_mask),
    // -> Ok("3782 **** *** 0005")
    card.parse_expiry("12/28"),
    // -> Ok(card.Expiry(month: 12, year: 2028))
  )
}
```

The API reference is on [HexDocs](https://hexdocs.pm/finanza/).

## Notes

- A decimal's coefficient, and the integer a positive exponent stands for, stay within ±9,007,199,254,740,991 (2^53 − 1) on both targets, so results match on Erlang and JavaScript. Larger results are `PrecisionExceeded` errors.
- The 15 built-in currencies and the card brand rules are snapshots taken in May 2026. There is no exchange rate lookup or BIN database.

How the package is tested is described in [doc/testing.md](https://github.com/nao1215/finanza/blob/main/doc/testing.md).

## Verifying releases

Each GitHub Release attaches the Hex package tarball (`finanza-<version>.tar`),
`checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and
build provenance (`finanza-<version>.intoto.jsonl`). Download the assets, then:

```sh
gh attestation verify finanza-<version>.tar --repo nao1215/finanza

cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/finanza/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

[MIT](https://github.com/nao1215/finanza/blob/main/LICENSE)
