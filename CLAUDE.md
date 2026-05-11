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
src/
  finanza.gleam                    # version() and top-level entry
  finanza/
    decimal.gleam                  # opaque Decimal, arithmetic
    decimal/
      rounding.gleam               # Mode enum
    currency.gleam                 # opaque Currency / Money, FormatOptions
    currency/
      catalog.gleam                # 15 hardcoded major currencies
    interest.gleam                 # TVM functions
    interest/
      amortization.gleam           # opaque Period, schedule generator
    card.gleam                     # PAN: Luhn, brand, mask, expiry
test/
  finanza_test.gleam               # main gleeunit entry
  decimal_test.gleam
  decimal/rounding_test.gleam
  currency_test.gleam
  currency/catalog_test.gleam
  interest_test.gleam
  interest/amortization_test.gleam
  card_test.gleam
  property/                        # metamon property tests
doc/
  reference/                       # third-party OSS clones (gitignored)
```

## Design principles

- **Opaque public types** — `Decimal`, `Currency`, `Money`,
  `FormatOptions`, `MaskOptions`, and `Period` are all `pub opaque`.
  Construct through smart constructors and inspect through accessors.
  Use `pub type` only for closed enums (`Brand`, `rounding.Mode`,
  error variants).
- **No panics** — every fallible path returns a typed `Result`. The
  glinter config forbids `panic`, `todo`, and `unwrap`. Division by
  zero and JS-target precision overflow surface as typed errors.
- **Explicit rounding** — no operation rounds implicitly. Every
  function that may round takes a `digits: Int` and a
  `mode: rounding.Mode`.
- **No external services** — no exchange-rate fetcher, no live ISO
  4217 sync, no BIN database. Snapshots only, documented as such.
- **Cross-target** — Erlang and JavaScript. On JS the decimal
  coefficient is capped at `Number.MAX_SAFE_INTEGER`; overflow returns
  `decimal.PrecisionExceeded`.

## Error handling

- Each module defines a dedicated error ADT — `decimal.ParseError`,
  `decimal.ArithmeticError`, `currency.CurrencyError`,
  `interest.InterestError`, `card.ValidationError`.
- `stringly_typed_error` is forbidden by glinter; always model error
  variants with their own constructors.
- Wrap lower-layer errors explicitly (e.g.
  `interest.InterestError::ArithmeticError(decimal.ArithmeticError)`).

## Testing strategy

- Unit tests live next to each module in `test/`.
- Property tests under `test/property/` use `metamon` and assert
  algebraic laws: decimal additive commutativity / associativity,
  Luhn reversibility on appended check digit, PMT × periods ≈ FV.
- Boundary tests for every rounding mode at `2.5`, `3.5`, `10.005`,
  and negative variants.
- Round-trip: `to_string` ∘ `from_string` must be the identity on
  normalized decimals.
- Reference values: cross-check `payment`, `future_value`,
  `present_value` against numpy-financial / Excel published values.
- Card tests use only Wikipedia / public test PANs
  (`79927398713`, `4111 1111 1111 1111`, etc.).

## Dependencies

- `gleam_stdlib` — standard library
- `gleam_regexp` — PAN / decimal string parsing
- `gleeunit` (dev) — test runner
- `glinter` (dev) — strict lint (dataprep-style)
- `metamon` (dev) — property test combinators

## Reference clones

The directory `doc/reference/` holds shallow clones of third-party
OSS that informed the API and test design. It is gitignored. See
`doc/reference/README.md` for license boundaries and what to look at
in each project. Never copy code verbatim from these clones; use them
only for API shape, test inputs, and algorithm clarification.
