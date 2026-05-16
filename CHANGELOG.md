# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `finanza/currency`: `currency.from_major(amount, currency)` builds a `Money` from an integer whole-currency amount, mirroring `from_minor/2` for the human-readable price case. `from_major(35, usd())` represents `$35` and `from_major(3500, jpy())` represents `¥3,500` — the call shape is the same regardless of the currency's `exponent`, so callers no longer have to pre-multiply by `10 ^ exponent` (the silent off-by-100× footgun `from_minor` has on two-exponent currencies when the input is actually a major-unit integer). `from_minor` keeps its role for callers who already hold a minor-units integer (e.g. a value loaded from a `cents` database column). (#16)

## [0.4.0] - 2026-05-14

### Changed

- `finanza/interest`: internal working precision target raised from
  6 to 7 decimal digits in the iterative `pow_loop`, with an
  adaptive overflow guard that sheds per-step precision one digit
  at a time when an upcoming `multiply` would push the coefficient
  above `2^53 − 1` (the JavaScript safe-integer ceiling enforced
  by `finanza/decimal`). The work-digit calculation is no longer
  derived from the caller's `digits` argument, so PMT / FV / PV
  / EAR at `digits = 2` now also benefit from the extra precision
  — for the 36-month / 0.5 %-monthly amortising loan from the
  README, `payment` now matches the Python `decimal` prec=50
  textbook PMT (3042.19) instead of the previous 3042.20. EAR at
  5 % nominal monthly and EAR at 10 % nominal monthly also become
  exact to 6 dp (0.051162 and 0.104713 respectively). Long-horizon
  scenarios (15-year monthly mortgages, 84-month auto loans)
  improve by 1 cent each. (#9)

- `finanza/interest.present_value`: computed as `future × (1 /
  growth)` instead of `future / growth`. The internal `decimal.divide`
  in the previous direct-divide path scaled the numerator by
  `digits + work_digits` digits, which overflowed the 2^53 − 1
  coefficient ceiling once `work_digits` reached 7. The inverse
  formulation only scales the constant `1`, so the multiplication
  by `future` happens with both factors already bounded. (#9)

## [0.3.0] - 2026-05-12

### Documentation

- `finanza/interest`: document the 6-decimal-digit internal working
  precision cap shared by `future_value`, `present_value`,
  `payment`, `effective_annual_rate`, and `compound_interest`. The
  cap is in place so each iterative `multiply` keeps coefficients
  under 2^53 - 1 (the JavaScript safe-integer ceiling enforced by
  `finanza/decimal`). The new module-level **Precision** section
  shows concrete drift versus textbook (Python `decimal` prec=50,
  Excel, `numpy_financial`) values: short-horizon / exact-rate
  inputs match to the cent, but long horizons with inexact rates
  (e.g. PMT on a 15-year monthly mortgage) drift by 0.01–0.04 in
  `digits = 2` outputs. Per-function docstrings on
  `future_value`, `present_value`, `payment`, and
  `effective_annual_rate` now point readers at the section. The
  reference is **not** safe for regulated lending or any flow that
  must match an external 50-digit reference until the cap is
  raised in a follow-up. (#9)

### Fixed

- `decimal.add` no longer returns `Error(PrecisionExceeded)` for the
  additive-identity case `add(d, zero())` (and the symmetric
  `add(zero(), d)`) when `d` has an exponent large enough that
  realigning it to zero's exponent would overflow
  `max_safe_coefficient = 2^53 − 1`. For example,
  `decimal.add(decimal.new(coefficient: 1, exponent: 20),
  decimal.zero())` now returns `Ok(d)` instead of failing. The
  alignment step is now skipped entirely when either coefficient is
  zero (the mathematical result is just the other operand), and the
  both-zero case picks the smaller exponent to keep `add(a, b) ==
  add(b, a)` at the level of structural equality. `subtract`
  benefits transitively via its existing `add(a, negate(b))`
  definition. (#7)

## [0.2.0] - 2026-05-12

### Added

- `test/dig_round6_metamorphic_test.gleam` — second metamorphic pass:
  randomised algebraic laws (associativity, distributivity, transitivity,
  commutativity at fixed pools) for `decimal` and `currency`, plus
  allocate sum-preservation for arbitrary ratios, amortisation
  invariants, and card-edge metamorphic relations.
- `test/dig_round7_fuzzing_test.gleam` — second fuzzing pass against
  the arithmetic and combinator surfaces round 4 did not touch
  (decimal add/sub/mul/div, round/truncate/rescale incl. extreme
  digits, interest formulas, amortization.schedule, currency.new_currency,
  currency.allocate, from_minor/to_minor at extreme units, card.bin /
  card.last_four, and chained arithmetic).
- `test/dig_round8_property_test.gleam` — randomised property tests
  for properties round 6 covered only at fixed pools (associativity,
  distributivity, transitivity), plus randomised interest /
  amortisation invariants no earlier round exercised at random
  inputs.
- `test/dig_round9_boundary_test.gleam` — additional boundary tests:
  the `2^53 − 1` precision cliff for add/sub/multiply/negate/parser,
  large negative exponents, JPY rounding direction across modes,
  high-precision (8-decimal) currency, allocate ratio errors,
  currency.divide-by-zero, currency mismatch on add/compare, card
  validate at minimum (14-digit Diners) and over-maximum lengths.
- `test/dig_round10_differential_test.gleam` — additional differential
  tests vs a Python `decimal` simulation that mirrors finanza's
  `pow_loop` algorithm: decimal subtract, divide at multiple
  precisions, the five rounding modes round 5 did not exercise, three
  PMT scenarios, FV / PV / EAR at additional rates, amortisation
  period-1, brand detection for 2-series Mastercard, JCB, 14-digit
  Diners, UnionPay.

### Notes

- No source changes in this release. The package's public API and
  runtime behaviour are unchanged from `v0.1.1`.
- Test count grew from ~295 to **449**. Linux / macOS / Windows ×
  Erlang / JavaScript CI matrix is green.
- Two upstream issues were filed during this dig-bug session and
  remain open for future fixes: nao1215/finanza#7 (additive identity
  `add(d, zero())` overflows for `d` with large positive exponent)
  and nao1215/finanza#9 (`max_work_digits = 6` cap causes
  `interest.payment` / `future_value` / `present_value` /
  `effective_annual_rate` to diverge from textbook full-precision
  values by 0.01–0.04 cents on long-horizon scenarios). No fix is
  shipped in this release; both are tracked for v0.3.

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
