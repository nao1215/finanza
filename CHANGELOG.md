# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Breaking changes (API consistency pass)

These rename a small number of public functions / arguments to remove
naming inconsistencies before 0.1.0. Adapt call sites accordingly.

- `finanza/card.expiry_valid` now takes two `#(month, year)` tuples
  (`expiry` and `today`) instead of four labelled `Int`s. The original
  shape was prone to silent argument swaps; the tuple form makes the
  pairing explicit at the call site.
- `finanza/card.mask_defaults` is renamed to `default_mask` so it
  matches `finanza/currency.default_format` (`default_X` everywhere
  rather than `default_X` / `X_defaults`).
- `finanza/currency.new` (Money constructor) is renamed to `new_money`
  so it pairs with `new_currency` and the `currency.` prefix no longer
  appears to return the wrong type.
- `finanza/currency.with_currency_code` now uses the label `enabled:`
  instead of `show:`, matching `with_minor_units(enabled:)`.

### Added

- `finanza/decimal.format` — render a `Decimal` with configurable
  thousands and decimal separators (`"1,234.56"`, `"1.234,56"`,
  `"1234.56"`).
- `finanza/currency.with_minor_units` — `FormatOptions` toggle (default
  `True`) that rescales a `Money` amount to the currency's minor-unit
  exponent before rendering, so `currency.new_money(decimal.from_int(200_000),
  catalog.usd())` renders as `"$200,000.00"` rather than `"$200000"`.

### Changed

- `finanza/currency` exposes `currency_of(m)` instead of the awkward
  `currency.currency(m)`. The new name reads cleanly at the call site.
- `finanza/card.mask` now groups the kept-first, masked-middle, and
  kept-last regions independently. On 15-digit AMEX or 14-digit Diners
  Club PANs the kept-last four digits stay in one block (e.g.
  `"3782 **** *** 0005"`) instead of being split across groups
  (`"3782 **** ***0 005"`).

### Removed

- Internal `interest.periods_bound/0` placeholder. It was a dead
  function that existed only to anchor the `gleam/int` import; that
  import is now justified by genuine uses inside the module.

### Added (initial release)

- Initial scaffold for the `finanza` package.
- `finanza/decimal`: opaque `Decimal` type and arbitrary-precision fixed-point
  arithmetic (`add`, `subtract`, `multiply`, `divide`, `negate`, `abs`,
  `round`, `truncate`, `rescale`, `compare`). Parsing via `from_string` and
  rendering via `to_string`.
- `finanza/decimal/rounding`: rounding `Mode` enum
  (`HalfEven`, `HalfUp`, `HalfDown`, `Up`, `Down`, `Ceiling`, `Floor`).
- `finanza/currency`: opaque `Currency` and `Money` types; arithmetic, ratio
  allocation, and configurable formatting through `FormatOptions` builder.
- `finanza/currency/catalog`: constructors for 15 major currencies
  (USD/EUR/JPY/GBP/CHF/CAD/AUD/CNY/HKD/SGD/KRW/INR/BRL/MXN/ZAR), a
  snapshot as of 2026-05.
- `finanza/interest`: time-value-of-money primitives
  (`simple_interest`, `compound_interest`, `future_value`, `present_value`,
  `payment`, `effective_annual_rate`).
- `finanza/interest/amortization`: opaque `Period` type and `schedule`
  generator for amortizing loans.
- `finanza/card`: payment card primitives — Luhn check, brand detection
  (Visa/MC/Amex/Discover/JCB/DinersClub/UnionPay), masking with the opaque
  `MaskOptions` builder, BIN/last-four extraction, expiry parsing and
  validation.

### Notes

- Currency catalog and card brand IIN ranges are static snapshots; the
  library does not track ISO 4217 or BIN-database updates dynamically.
- On the JavaScript target, `Decimal` coefficients are bounded by
  `Number.MAX_SAFE_INTEGER` (2^53 - 1). Operations that would overflow this
  bound return `PrecisionExceeded`. The Erlang target uses arbitrary
  precision integers and is not affected.
