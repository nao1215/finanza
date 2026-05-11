# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

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
