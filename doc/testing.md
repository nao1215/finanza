# Testing

`just ci` runs everything below except the nightly job and mutation testing. Tests run on the Erlang and JavaScript targets, on the Gleam floor (1.14.0, OTP 27, Node 22) and on the latest Gleam 1.x, on Linux, macOS and Windows.

## Examples and unit tests

Every module has a test file under `test/`: decimal parsing, arithmetic and every rounding mode at `2.5`, `3.5`, `10.005` and their negatives, money formatting and allocation, interest and amortization schedules, and card validation with public test PANs only. `test/dig_round1_boundary_test.gleam` and `test/dig_round9_boundary_test.gleam` probe the limits (JavaScript's safe-integer cap, empty and huge inputs). `test/readme_test.gleam` runs the README examples, and `test/support.gleam` holds the `let assert` helpers for inputs known to be in range.

## Generated properties

`test/property/` and `test/dig_round2_property_test.gleam` / `test/dig_round8_property_test.gleam` use metamon to check algebraic laws: commutativity, associativity and distributivity of decimal arithmetic, string round trips, `allocate` preserving the total, Luhn on an appended check digit, and an amortization schedule whose balance closes to zero.

## Metamorphic relations

`test/dig_round3_metamorphic_test.gleam` and `test/dig_round6_metamorphic_test.gleam` check relations between runs: scaling, inverse operations and round trips through minor units.

## Differential testing

`test/dig_round5_differential_test.gleam` and `test/dig_round10_differential_test.gleam` compare arithmetic, rounding, PMT, FV, PV, EAR and amortization with values computed by Python `decimal` and published Excel examples. `test/property/decimal_oracle_test.gleam` compares `decimal.round` and `decimal.divide` with an oracle that does one integer division and applies each of the seven rounding modes to the remainder, for random coefficients, exponents and precisions, with ties (`...5`, `...50`) mixed in. It also checks that `round` always returns exactly `digits` fractional places.

## Fuzzing

There is no coverage-guided fuzzer for Gleam. `test/dig_round4_fuzzing_test.gleam` and `test/dig_round7_fuzzing_test.gleam` pump random and malformed strings through every parser and require a typed error instead of a crash, and the nightly job below repeats every property with more inputs.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `metamon.with_seed` and kept as a regression test.

## Mutation testing

There is no mutation testing tool for Gleam, so `gleam_mutate.py` (from the mutation-testing lab in nao1215/debimate) is run by hand on a copy of the project. It rewrites one operator or boolean result at a time and runs `gleam test` on the Erlang target; a mutant that makes the suite hang past 120 seconds counts as killed. For this run the script also mutated integer comparisons and `+` / `-`. The score is killed / (killed + lived).

| Date | Files | Killed | Lived | Score |
|---|---|---:|---:|---:|
| 2026-11-19, first run | every module under `src/` with mutants (260) | 205 | 55 | 78.8% |
| 2026-11-19, after the brand boundary test | same | 218 | 42 | 83.8% |

The first run showed that brand detection was tested with one PAN per brand, so no range end (JCB 3528 and 3589, Discover 644 to 649, Diners 300 to 305) and no length window (Visa 13 and 19, Amex 15 only, Diners from 14, UnionPay 16 to 19) was checked; `detect_brand_at_the_edges_of_each_range_test` kills those 13 mutants. The survivors, grouped:

- `decimal` (19): digit counting, sign and dot handling in the parser and the comparison of equal-sign values on paths that the tests reach only with values far from the boundary, and the overflow checks that only matter on JavaScript at `Number.MAX_SAFE_INTEGER`.
- `card` (13): the 12 to 19 digit length check of `validate`, the `mask` clamps, the expiry month and year window, and one Luhn step.
- `interest` (8) and `amortization` (1): the argument checks at their exact bounds (zero periods, zero digits) and the extra digits used for intermediate rounding.
- `currency` (1): the remainder distribution of `allocate` when a share is exactly zero.

Brand detection checks UnionPay (`62`, 16 to 19 digits) before Discover, so Discover's co-branded range 622126 to 622925 is reported as UnionPay. The Discover rule for that range could never match and was removed in 0.12.0.
