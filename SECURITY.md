# Security Policy

## Supported versions

Pre-1.0: only the latest published release receives security fixes.
Older `0.x` releases will not be patched.

## Reporting a vulnerability

Report vulnerabilities privately via GitHub Security Advisories:

<https://github.com/nao1215/finanza/security/advisories/new>

Do not open a public issue or pull request for security reports.

Include in the report:

- Affected version or commit hash
- Reproduction steps or proof-of-concept
- Impact assessment

We aim to acknowledge reports within 7 days and coordinate disclosure
once a fix is available.

## Security-critical areas

The following modules have direct financial impact and receive priority
on security triage:

- **`finanza/decimal`** — incorrect rounding or silent precision loss
  affecting monetary calculations.
- **`finanza/currency`** — currency mismatch handling, allocation
  rounding, integer-overflow on `to_minor` / `from_minor` conversions.
- **`finanza/interest`** — formula correctness for `payment`,
  `future_value`, `present_value`, and amortization schedules.
- **`finanza/card`** — Luhn algorithm correctness, brand
  misclassification, and unsafe masking that exposes more digits than
  configured.

## Known boundaries

- **JavaScript target precision**: On the JavaScript target, `Decimal`
  coefficients are bounded by `Number.MAX_SAFE_INTEGER` (2^53 - 1).
  Operations that would exceed this bound return `PrecisionExceeded`
  rather than silently losing precision. The Erlang target uses
  arbitrary-precision integers.
- **No live data**: the ISO 4217 currency catalog and the card-brand
  IIN ranges are static snapshots. They are not authoritative for
  newly issued or recently retired codes. Applications that need
  real-time data must source it externally.
- **No BIN database**: `finanza/card` does not ship a BIN-to-issuer
  mapping. Brand detection is by IIN range only.
