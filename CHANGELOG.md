# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-05-11

### Fixed

- Release workflow now publishes to Hex with the required
  non-semantic-versioning acknowledgement piped into `gleam publish`.

## [0.1.0] - 2026-05-11

Initial release. The four modules below cover decimal arithmetic,
currency / money handling, time-value-of-money calculations, and
payment-card primitives, all behind opaque types with explicit
rounding modes. The package targets both Erlang and JavaScript.

### Added

- `finanza/decimal` — opaque `Decimal` (`coefficient × 10^exponent`)
  with `from_int`, `from_string`, `new`, `to_string`, accessors,
  predicates (`is_zero` / `is_positive` / `is_negative`), `negate`,
  `absolute`, `add`, `subtract`, `multiply`, `divide`, `round`,
  `truncate`, `rescale`, `compare`, `equal`, and a `format` helper
  with configurable thousands / decimal separators.
- `finanza/decimal/rounding` — rounding `Mode` enum with the seven
  IBM Decimal modes (`HalfEven`, `HalfUp`, `HalfDown`, `Up`, `Down`,
  `Ceiling`, `Floor`).
- `finanza/currency` — opaque `Currency` and `Money` with smart
  constructors (`new_currency`, `new_money`, `from_minor`), arithmetic
  (`add`, `subtract`, `multiply`, `divide`, `negate`), proportional
  `allocate`, comparison, equality, ISO-style `to_string`, and a full
  `FormatOptions` builder (symbol position, separators, negative
  style, currency-code suffix, minor-unit normalisation).
- `finanza/currency/catalog` — constructors for 15 major currencies
  (USD/EUR/JPY/GBP/CHF/CAD/AUD/CNY/HKD/SGD/KRW/INR/BRL/MXN/ZAR);
  snapshot as of 2026-05.
- `finanza/interest` — `simple_interest`, `compound_interest`,
  `future_value`, `present_value`, `payment`, `effective_annual_rate`.
- `finanza/interest/amortization` — opaque `Period` and `schedule`
  generator that closes the final balance to zero exactly.
- `finanza/card` — `normalize`, `luhn_valid`, `detect_brand`,
  `validate`, segment-aware `mask` with the `MaskOptions` builder,
  `last_four`, `bin`, `parse_expiry`, and `expiry_valid` that takes
  two `#(month, year)` tuples (so month/year order cannot be silently
  swapped). Brand detection covers Visa, Mastercard (incl. 2-series),
  American Express, Discover, JCB, Diners Club (14–19 digits per
  ISO/IEC 7812-1), and UnionPay.

### Notes

- Currency catalogue and brand IIN ranges are static snapshots; the
  library does not track ISO 4217 or BIN-database updates
  dynamically. For currencies outside the catalogue, construct your
  own with `currency.new_currency`.
- On the JavaScript target, `Decimal` coefficients are bounded by
  `Number.MAX_SAFE_INTEGER` (2^53 − 1). Arithmetic that would
  overflow this bound returns `decimal.PrecisionExceeded`; parsing a
  value beyond it returns `decimal.ParsedValueTooLarge`. Behaviour is
  identical on the Erlang target (where Int is arbitrary precision)
  so cross-target code does not have to special-case either runtime.
- Property-based, metamorphic, fuzzing, and differential test suites
  ship under `test/property/` and `test/dig_round*` and run on every
  CI build.
