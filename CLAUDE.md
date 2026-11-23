# CLAUDE.md — finanza

Small fintech utility library for Gleam: decimal arithmetic, currency,
interest math, and payment-card primitives.

## Build and test commands

```sh
just ci          # deps + format check + lint + check + build/test both targets
just build       # gleam build --warnings-as-errors
just test        # gleam test
just format      # gleam format src/ test/
just format-check
just lint        # gleam run -m glinter
just typecheck   # gleam check
just check       # clean + format check + lint + check + build + test
just docs        # gleam docs build
just all         # clean → deps → full validation → docs
just clean
```

## Repository layout

```
src/finanza/
  decimal.gleam   # opaque Decimal, RoundingMode, arithmetic, parse/format
  money.gleam     # Currency and Money records, the 15 currency constants,
                  # arithmetic, allocate, FormatOptions and format
  interest.gleam  # TVM functions and the amortization schedule (Period)
  card.gleam      # PAN: Luhn, brand, MaskOptions and mask, Expiry
  internal/
    rounded.gleam # multiply-then-round on the exact product, for money
                  # and interest (internal: not public API, not in docs)
    limb.gleam    # exact products of two coefficients in 7-digit limbs,
                  # shared by decimal and rounded (no Decimal dependency)
test/
  finanza_test.gleam   # gleeunit entry
  support.gleam        # let-assert helpers for in-range test inputs
  decimal_test.gleam, money_test.gleam, interest_test.gleam, card_test.gleam
  readme_test.gleam    # the README examples
  dig_round*_test.gleam
  property/            # metamon property tests
doc/
  reference/           # third-party OSS clones (gitignored)
```

There is no `finanza` root module. Each public module is one domain.

## Design principles

- Only `Decimal` is opaque, because its coefficient must stay within
  2^53 - 1 (also for the integer a positive exponent stands for) and
  its exponent within -28..15.
  Every other type (`Currency`, `Money`, `FormatOptions`,
  `MaskOptions`, `Period`, `Expiry`) is a plain record that callers
  build and read directly, with defaults as constants
  (`money.default_format`, `card.default_mask`). Do not add setters
  or getters for record fields.
- No panics. Every fallible path returns a `Result`, and constructors
  such as `decimal.new` and `money.from_minor` return one too. A
  function with a single reason to fail returns `Result(a, Nil)`,
  unless it shares the module's error type so that it chains with
  `result.try` (`decimal.add`, `money.from_minor`).
- Explicit rounding. Every arithmetic function that may drop digits
  takes a `rounding: decimal.RoundingMode`. The exceptions round
  half-even and say so in their docs: the interest functions,
  `money.allocate` and `money.format`.
- No external services: no exchange rates, no live ISO 4217 sync, no
  BIN database. Snapshots only, documented as such.
- Cross-target: Erlang and JavaScript give the same results because
  the 2^53 - 1 bound is enforced on both.
- One function per job. Do not add `_with`, `try_`, `_checked` or
  `_or_panic` variants of an existing function.

## Error handling

- `decimal.ParseError`, `decimal.ArithmeticError`, `money.MoneyError`,
  `interest.InterestError` and `card.ValidationError`.
- `stringly_typed_error` is forbidden by glinter; model each failure as
  a variant named after what happened.
- Wrap lower-layer errors in a variant
  (`money.ArithmeticFailed(decimal.ArithmeticError)`).

## Testing strategy

- Unit tests live next to each module in `test/`.
- Property tests under `test/property/` use `metamon` and assert
  algebraic laws: decimal additive commutativity / associativity,
  Luhn reversibility on appended check digit, PMT × periods ≈ FV.
- Boundary tests for every rounding mode at `2.5`, `3.5`, `10.005`,
  and negative variants.
- Round-trip: `to_string` ∘ `parse` must be the identity on
  normalized decimals.
- Reference values: cross-check `payment`, `future_value`,
  `present_value` against numpy-financial / Excel published values.
- Card tests use only Wikipedia / public test PANs
  (`79927398713`, `4111 1111 1111 1111`, etc.).

## Dependencies

- `gleam_stdlib` — standard library
- `gleeunit` (dev) — test runner
- `glinter` (dev) — strict lint (dataprep-style)
- `metamon` (dev) — property test combinators

## Reference clones

The directory `doc/reference/` holds shallow clones of third-party
OSS that informed the API and test design. It is gitignored. See
`doc/reference/README.md` for license boundaries and what to look at
in each project. Never copy code verbatim from these clones; use them
only for API shape, test inputs, and algorithm clarification.
