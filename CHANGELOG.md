# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- `finanza/decimal`: `decimal.new(coefficient, exponent)` now panics with a structured message that names the function, echoes the offending coefficient and exponent, states the safe bound (`±9_007_199_254_740_991`), and points readers at `decimal.try_new` for the `Result`-returning variant. The previous `let assert Ok(d) = try_new(...)` body produced the generic `Pattern match failed, unmatched value: Error(CoefficientTooLarge)` runtime message, which left the caller without a hint about what the safe range was or which alternative constructor to use. (#38)

### Added

- `finanza/decimal`: `decimal.from_float(value: Float) -> Result(Decimal, ParseError)` — explicit, documented `Float → Decimal` conversion path for real-world callers whose input lives as `Float` (exchange-rate APIs, telemetry, percentage ratios). The conversion goes through `float.to_string |> from_string` so the resulting `Decimal` matches Gleam's textual rendering of the float on both targets, and `ParseError` is surfaced as `Result` rather than panicking. Callers who already hold a textual or coefficient/exponent representation should still prefer `from_string` / `try_new` since those skip the float round-trip. (#36)
- `finanza/card`: `card.parse_expiry` now accepts four common entry-form shapes in addition to the original `MM/YY` and `MM/YYYY`: hyphen-separated (`MM-YY`, `MM-YYYY`), dot-separated (`MM.YY`, `MM.YYYY`), and unseparated (`MMYY`, `MMYYYY`). Surrounding whitespace is still ignored, and single-digit months are still accepted in the separator forms (`"1/26"`, `"1-26"`, `"1.26"`). Three-digit unseparated input (`"126"`) stays rejected because it is ambiguous between "January 2026" and "December year 26" — the parser refuses to guess. (#42)
- `finanza/card`: `card.normalize` now folds the three Unicode digit blocks IMEs commonly produce — FULLWIDTH DIGIT ZERO..NINE (`U+FF10..U+FF19`), ARABIC-INDIC DIGIT ZERO..NINE (`U+0660..U+0669`), and EXTENDED ARABIC-INDIC DIGIT ZERO..NINE (`U+06F0..U+06F9`) — into their ASCII equivalents. PANs typed on Japanese-locale IMEs (`４２４２４２４２`), Arabic-script keyboards (`٤٢٤٢`), or Persian/Urdu keyboards (`۴۲۴۲`) now flow through `normalize → luhn_valid → validate` like ASCII input. Other Unicode digit forms and non-ASCII whitespace are still left to the caller. (#39)

### Fixed

- `finanza/card`: `card.parse_expiry(input: "12/-1")` now returns `Error(InvalidExpiry)` instead of `Ok(#(12, 1999))`. The two-digit length check accepted `-1` (length two, parses as `-1`) and the `20YY` expansion silently rewrote it to `1999`, masking caller typos and malicious input as a "successful" parse that downstream `expiry_valid` then flagged as expired. Negative years on the four-digit branch were already rejected via the length filter (e.g. `"-2026"` has length five) but are now also caught explicitly. `parse_month`'s existing `1..12` guard already rejected negative months. (#41)
- `finanza/interest`: `interest.simple_interest(principal, rate, periods: 0, digits)` now returns `Ok(0)` rescaled to `digits` instead of rejecting with `Error(PeriodsOutOfRange)`. The mathematical identity `I = P × r × 0 = 0` makes zero-period interest a legitimate input — and the previous reject-everything-non-positive guard forced callers to insert `case periods { 0 -> ... }` branches at every schedule-loop site that could legitimately ask for "interest as of period 0". Negative `periods` is still rejected with `PeriodsOutOfRange`. Sibling functions (`compound_interest`, `future_value`, `present_value`, `payment`, `effective_annual_rate`) keep their strict `periods > 0` guard until #44. (#40)
- `finanza/card`: `card.luhn_valid` now returns `False` for any input that contains a non-digit grapheme. The previous implementation silently dropped non-digit graphemes from the checksum sum, which left the partial sum at zero for any all-non-digit input (`"abc"`, `" "`, `"!@#$"`, `"🙂🙂🙂🙂"`) and reported `True`. The empty string still returns `False`. Mixed digit / non-digit inputs (`"4242 4242 4242 4242"`) now consistently return `False` regardless of whether the partial sum happened to land on a multiple of ten. Callers that want to normalise whitespace or formatting before the check should pre-process through `card.normalize`. (#37)

## [0.6.0] - 2026-05-18

### Added

- `finanza/decimal`: `decimal.try_new/2` and `decimal.try_from_int/1`, validated counterparts of `decimal.new/2` and `decimal.from_int/1` that return `Result(Decimal, ConstructError)` (variant `CoefficientTooLarge`) instead of panicking when the rendered value would exceed `±9_007_199_254_740_991`. Use these whenever the coefficient or exponent is supplied by a caller and might exceed the safe range — they surface the overflow as a value rather than crashing the process. (#23)

### Documentation

- `finanza/interest`: module-level "Precision" docstring now explicitly calls out the **honest-precision ceiling** — although the iterative helpers (`compound_interest`, `future_value`, `present_value`, `payment`, `effective_annual_rate`) return a `Decimal` whose exponent matches the caller's requested `-digits` (after #25's `decimal.rescale` fix), the trailing decimal places past 7 (the `max_work_digits` cap inside `growth_factor`) are zero padding from the rescale, not computed precision. The numeric value matches what the loop produces at 7 honest digits — asking for more produces a more verbose rendered form without making the result more accurate. The note points readers at higher-precision packages (e.g. Python `decimal` with `prec=50`) for caller flows that need more than 7 honest digits. (#28)

### Fixed

- `finanza/card`: `card.normalize` now strips every ASCII whitespace character (` `, `\t`, `\n`, `\r`, VT `\u{000B}`, FF `\u{000C}`) in addition to the existing hyphen-style separators (`-`, `_`, `.`). Previously the docstring promised "ASCII whitespace" but the implementation filtered only SPACE, so PANs copy-pasted from PDFs / emails that introduce tab- or CR/LF-separated digit groups passed through with the whitespace intact and then failed downstream Luhn / length validation. The docstring now also lists the exact stripped set, and explicitly notes that Unicode whitespace (NBSP, ideographic space) is out of scope so callers know to pre-normalise. (#24)
- `finanza/decimal`: `decimal.new/2` and `decimal.from_int/1` now reject coefficients whose rendered form would exceed the safe range (`|coefficient| × 10^exponent > 9_007_199_254_740_991` for non-negative exponents, or `|coefficient| > 9_007_199_254_740_991` for any exponent) — previously these constructors accepted any input silently, so `decimal.to_string(decimal.new(1, 20))` produced `"100000000000000000000"` which `decimal.from_string` then refused to parse with `ParsedValueTooLarge`, breaking the round-trip property `from_string(to_string(d)) == Ok(d)`. The check matches the long-standing `from_string` guard, so the construction side and the parse side now agree on what values are valid. Callers that previously relied on silent overflow can switch to `try_new/2` / `try_from_int/1` to surface the rejection as a `Result`. (#23)
- `finanza/interest`: the final rounding step in `simple_interest`, `compound_interest`, `future_value`, `present_value`, and `effective_annual_rate`, plus the per-row interest computation in `interest/amortization.schedule`, now use `decimal.rescale` instead of `decimal.round` so the returned value always has exponent `-digits` (i.e. the rendered form always carries exactly `digits` decimal places). Previously these helpers leaked the coarser exponent of a whole-number result, so `to_string(simple_interest(P, 0, 5, digits: 4))` returned `"0"` instead of `"0.0000"` and `to_string(future_value(1000, 100%, 1, digits: 2))` returned `"2000"` instead of `"2000.00"`. The `decimal.round` docstring is also clarified to explicitly call out the trim-only semantics (it never pads), pointing readers at `decimal.rescale` for precision-fixing. The change propagates `ArithmeticError(PrecisionExceeded)` when the requested `digits` cannot fit (previously the bug masked these by silently returning the coarser representation). (#25)
- `finanza/interest`: `present_value` no longer raises `Error(ArithmeticError(PrecisionExceeded))` when `future` already carries a high-precision exponent — e.g. the output of a previous `future_value(_, _, _, digits: 6)` call (coefficient ~1.6e9) used to overflow `max_safe_coefficient` when multiplied by the high-precision `inv_growth` factor inside `present_value`, so the textbook FV/PV inverse property `PV(FV(P, r, n), r, n) ≈ P` broke for any caller threading `digits ≥ 6` through both. The fix reuses the existing `round_for_safe_multiply` helper to adaptively round `future` down to the largest digit count for which the intermediate product still fits, so the round-trip succeeds at `digits = 6` and `digits = 8` with the answer recoverable to the cent. (#26)
- `finanza/interest`: `payment` (and through it `interest/amortization.schedule`) no longer raises `Error(ArithmeticError(PrecisionExceeded))` at `digits = 8` for inputs other interest helpers accept (e.g. principal=1000, rate=5%, periods=10). The internal `decimal.divide(numerator, denominator, digits, …)` in the amortising branch scaled the numerator by `digits + (numerator.exp − denominator.exp)` digits, which crossed `max_safe_coefficient` once `digits` reached 8. The divide is now capped at `max_work_digits` (the documented working-precision ceiling) and rescaled up to the caller's `digits` afterwards — past 7 the extra digits are zero-padding rather than computed precision, which matches the precision contract in the module-level "Precision" section. (#27)

## [0.5.0] - 2026-05-16

### Added

- `finanza/currency`: `currency.from_major(amount, currency)` builds a `Money` from an integer whole-currency amount, mirroring `from_minor/2` for the human-readable price case. `from_major(35, usd())` represents `$35` and `from_major(3500, jpy())` represents `¥3,500` — the call shape is the same regardless of the currency's `exponent`, so callers no longer have to pre-multiply by `10 ^ exponent` (the silent off-by-100× footgun `from_minor` has on two-exponent currencies when the input is actually a major-unit integer). `from_minor` keeps its role for callers who already hold a minor-units integer (e.g. a value loaded from a `cents` database column). (#16)
- `finanza/decimal`: typed `Decimal → Int` conversions, closing the gap that previously forced callers to round-trip through `int.parse(decimal.to_string(d))`. `decimal.to_int/1` succeeds only when `d` is exactly integer-valued (no fractional part *and* fits within `±max_safe_coefficient`); both a fractional remainder and a coefficient overflow surface as `PrecisionExceeded`. `decimal.to_int_truncated/1` drops the fractional part toward zero unconditionally (errors only on overflow). `decimal.to_int_rounded(d, mode)` applies any `rounding.Mode` and returns the integer — the natural fit for the "I rounded to N decimals, give me the integer" workflow that arises whenever rounded monetary values are persisted to an integer minor-units column. (#17)

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
