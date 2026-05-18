//// Time-value-of-money helpers built on
//// [`finanza/decimal`](./decimal.html).
////
//// Every function takes its inputs as decimals, computes in decimal,
//// and rounds the final result with `HalfEven` ("banker's") to the
//// caller-supplied number of decimal places.
////
//// ## Precision
////
//// Iterative computations (`future_value`, `present_value`,
//// `payment`, `effective_annual_rate`, `compound_interest`) target
//// **7 decimal digits** of internal working precision. Before
//// every multiplication inside the iterative growth-factor loop
//// the accumulator is rounded adaptively to the largest digit
//// count for which the resulting product still fits under
//// 2^53 − 1 (the JavaScript safe-integer ceiling enforced by
//// [`finanza/decimal`](./decimal.html)). For typical inputs the
//// target precision is always reached; only when the growth
//// factor swells (long horizons at very high rates, growth above
//// ~10⁵) does the per-step precision shed digits to keep the
//// multiplication safe.
////
//// Concrete consequence: results match textbook 50-digit references
//// (Python `decimal`, `numpy_financial`, Excel) to the cent at
//// `digits = 2` and to ~10⁻⁶ at `digits = 6` for monthly rates and
//// horizons up to about 30 years. For lending-grade work where the
//// answer must be reproducible against external industry tooling,
//// stick to those typical-input ranges or compute the closed form
//// in a higher-precision package.

import gleam/bool
import gleam/int
import gleam/result

import finanza/decimal
import finanza/decimal/rounding

/// Errors raised by interest functions.
pub type InterestError {
  /// `principal` was negative.
  NegativePrincipal
  /// `rate` was negative.
  NegativeRate
  /// `periods` was zero or negative, or exceeded the supported range
  /// `1..=1200` (100 years of monthly compounding).
  PeriodsOutOfRange
  /// `compounds_per_year` was zero or negative.
  CompoundsOutOfRange
  /// `digits` was negative.
  NegativeDigits
  /// Underlying decimal arithmetic produced an error.
  ArithmeticError(error: decimal.ArithmeticError)
}

const max_periods: Int = 1200

/// Target internal working precision for iterative growth-factor
/// computations. The adaptive `pow_loop` rounds the accumulator
/// down to fewer digits per step if it would otherwise push the
/// multiplication above `max_safe_coefficient`. 7 digits is the
/// highest target that keeps typical-input multiplications safe
/// while still giving textbook-cent accuracy at `digits = 2`.
const max_work_digits: Int = 7

/// Upper bound on a `Decimal` coefficient that `finanza/decimal`
/// will accept (2^53 − 1, the IEEE-754 double safe-integer ceiling).
/// Mirrors the value enforced inside `finanza/decimal`; kept here
/// so `pow_loop` can predict overflow before calling `multiply`.
const max_safe_coefficient: Int = 9_007_199_254_740_991

// --- Simple interest -----------------------------------------------------

/// Simple interest: `I = P × r × t`.
pub fn simple_interest(
  principal principal: decimal.Decimal,
  rate rate: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use _ <- result.try(check_principal(principal))
  use _ <- result.try(check_rate(rate))
  use _ <- result.try(check_periods(periods))
  use _ <- result.try(check_digits(digits))
  use pr <- result.try(
    decimal.multiply(principal, rate) |> result.map_error(ArithmeticError),
  )
  use product <- result.try(
    decimal.multiply(pr, decimal.from_int(n: periods))
    |> result.map_error(ArithmeticError),
  )
  rescale_to_digits(product, digits)
}

// --- Compound interest ---------------------------------------------------

/// Future value under compound interest:
///
/// ```text
/// FV = principal × (1 + annual_rate / compounds_per_year)^(compounds_per_year × years)
/// ```
pub fn compound_interest(
  principal principal: decimal.Decimal,
  annual_rate annual_rate: decimal.Decimal,
  years years: Int,
  compounds_per_year compounds_per_year: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use _ <- result.try(check_principal(principal))
  use _ <- result.try(check_rate(annual_rate))
  use _ <- result.try(check_periods(years))
  use _ <- result.try(check_compounds(compounds_per_year))
  use _ <- result.try(check_digits(digits))
  let total_periods = years * compounds_per_year
  use _ <- result.try(check_periods(total_periods))
  let work_digits = max_work_digits
  use rate_per_period <- result.try(
    decimal.divide(
      a: annual_rate,
      b: decimal.from_int(n: compounds_per_year),
      digits: work_digits,
      mode: rounding.HalfEven,
    )
    |> result.map_error(ArithmeticError),
  )
  use growth <- result.try(growth_factor(
    rate: rate_per_period,
    periods: total_periods,
    digits: work_digits,
  ))
  use product <- result.try(
    decimal.multiply(principal, growth) |> result.map_error(ArithmeticError),
  )
  rescale_to_digits(product, digits)
}

// --- FV / PV / PMT / EAR -------------------------------------------------

/// Future value of `present` after `periods` periods at `rate_per_period`.
///
/// See the module-level **Precision** section for the
/// 7-working-digit target and the adaptive overflow guard.
pub fn future_value(
  present present: decimal.Decimal,
  rate_per_period rate_per_period: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use _ <- result.try(check_rate(rate_per_period))
  use _ <- result.try(check_periods(periods))
  use _ <- result.try(check_digits(digits))
  let work_digits = max_work_digits
  use growth <- result.try(growth_factor(
    rate: rate_per_period,
    periods: periods,
    digits: work_digits,
  ))
  use product <- result.try(
    decimal.multiply(present, growth) |> result.map_error(ArithmeticError),
  )
  rescale_to_digits(product, digits)
}

/// Present value of `future` discounted at `rate_per_period` for
/// `periods` periods.
///
/// See the module-level **Precision** section for the
/// 7-working-digit target and the adaptive overflow guard.
pub fn present_value(
  future future: decimal.Decimal,
  rate_per_period rate_per_period: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use _ <- result.try(check_rate(rate_per_period))
  use _ <- result.try(check_periods(periods))
  use _ <- result.try(check_digits(digits))
  let work_digits = max_work_digits
  use growth <- result.try(growth_factor(
    rate: rate_per_period,
    periods: periods,
    digits: work_digits,
  ))
  // Compute `future / growth` as `future × (1 / growth)` so that the
  // intermediate scaling inside `decimal.divide` cannot push the
  // numerator above `max_safe_coefficient` when `future` is large
  // (e.g. a 7-digit principal at `digits = 6`). The inverse divide
  // only scales the constant `1`, which stays safely below the
  // ceiling.
  use inv_growth <- result.try(
    decimal.divide(
      a: decimal.one(),
      b: growth,
      digits: work_digits + 1,
      mode: rounding.HalfEven,
    )
    |> result.map_error(ArithmeticError),
  )
  // Issue #26: when `future` carries the precision returned by a
  // previous `future_value` call at the user's requested `digits`
  // (e.g. 6 places → coefficient ~1.6e9), multiplying it against
  // the high-precision `inv_growth` coefficient overflows
  // `max_safe_coefficient`. Round `future` adaptively to the
  // largest digit count for which the product still fits, so the
  // FV/PV inverse property holds for callers that thread the
  // result of `future_value` through `present_value` at the same
  // `digits`.
  let future_safe =
    round_for_safe_multiply(a: future, b: inv_growth, max_digits: work_digits)
  use product <- result.try(
    decimal.multiply(future_safe, inv_growth)
    |> result.map_error(ArithmeticError),
  )
  rescale_to_digits(product, digits)
}

/// Periodic payment for a fully-amortising loan:
///
/// ```text
/// PMT = principal × rate / (1 - (1 + rate)^(-periods))
/// ```
///
/// When `rate_per_period` is zero, returns straight-line
/// `principal / periods`.
///
/// See the module-level **Precision** section for the
/// 7-working-digit target and the adaptive overflow guard.
pub fn payment(
  principal principal: decimal.Decimal,
  rate_per_period rate_per_period: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use _ <- result.try(check_principal(principal))
  use _ <- result.try(check_rate(rate_per_period))
  use _ <- result.try(check_periods(periods))
  use _ <- result.try(check_digits(digits))
  use <- bool.guard(
    when: decimal.is_zero(rate_per_period),
    return: straight_line_payment(
      principal: principal,
      periods: periods,
      digits: digits,
    ),
  )
  amortising_payment(
    principal: principal,
    rate: rate_per_period,
    periods: periods,
    digits: digits,
  )
}

fn straight_line_payment(
  principal principal: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  decimal.divide(
    a: principal,
    b: decimal.from_int(n: periods),
    digits: digits,
    mode: rounding.HalfEven,
  )
  |> result.map_error(ArithmeticError)
}

fn amortising_payment(
  principal principal: decimal.Decimal,
  rate rate: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  let work_digits = max_work_digits
  use growth <- result.try(growth_factor(
    rate: rate,
    periods: periods,
    digits: work_digits,
  ))
  use inv_growth <- result.try(
    decimal.divide(
      a: decimal.one(),
      b: growth,
      digits: work_digits,
      mode: rounding.HalfEven,
    )
    |> result.map_error(ArithmeticError),
  )
  use denominator <- result.try(
    decimal.subtract(decimal.one(), inv_growth)
    |> result.map_error(ArithmeticError),
  )
  use numerator <- result.try(
    decimal.multiply(principal, rate) |> result.map_error(ArithmeticError),
  )
  decimal.divide(
    a: numerator,
    b: denominator,
    digits: digits,
    mode: rounding.HalfEven,
  )
  |> result.map_error(ArithmeticError)
}

/// Effective annual rate from a nominal rate compounded
/// `compounds_per_year` times per year:
///
/// ```text
/// EAR = (1 + nominal_rate / compounds_per_year)^compounds_per_year - 1
/// ```
///
/// See the module-level **Precision** section for the
/// 7-working-digit target and the adaptive overflow guard.
pub fn effective_annual_rate(
  nominal_rate nominal_rate: decimal.Decimal,
  compounds_per_year compounds_per_year: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use _ <- result.try(check_rate(nominal_rate))
  use _ <- result.try(check_compounds(compounds_per_year))
  use _ <- result.try(check_digits(digits))
  let work_digits = max_work_digits
  use rate_per_period <- result.try(
    decimal.divide(
      a: nominal_rate,
      b: decimal.from_int(n: compounds_per_year),
      digits: work_digits,
      mode: rounding.HalfEven,
    )
    |> result.map_error(ArithmeticError),
  )
  use growth <- result.try(growth_factor(
    rate: rate_per_period,
    periods: compounds_per_year,
    digits: work_digits,
  ))
  use ear_raw <- result.try(
    decimal.subtract(growth, decimal.one())
    |> result.map_error(ArithmeticError),
  )
  rescale_to_digits(ear_raw, digits)
}

// --- Internals -----------------------------------------------------------

/// `(1 + rate)^periods`, computed by repeated multiplication and
/// rounded to `digits` decimal places between steps so the
/// coefficient cannot grow unboundedly.
fn growth_factor(
  rate rate: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use base <- result.try(
    decimal.add(decimal.one(), rate) |> result.map_error(ArithmeticError),
  )
  pow_loop(base: base, exponent: periods, acc: decimal.one(), digits: digits)
}

fn pow_loop(
  base base: decimal.Decimal,
  exponent exponent: Int,
  acc acc: decimal.Decimal,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use <- bool.guard(when: exponent <= 0, return: Ok(acc))
  // Round the accumulator adaptively so that `acc × base` cannot
  // overflow `max_safe_coefficient`. For typical financial inputs
  // this is a no-op at the `digits` target; high-growth scenarios
  // shed precision per step rather than failing outright.
  let acc_safe = round_for_safe_multiply(a: acc, b: base, max_digits: digits)
  use product <- result.try(
    decimal.multiply(acc_safe, base) |> result.map_error(ArithmeticError),
  )
  let trimmed =
    decimal.round(d: product, digits: digits, mode: rounding.HalfEven)
  pow_loop(base: base, exponent: exponent - 1, acc: trimmed, digits: digits)
}

/// Round `a` to the largest `d ≤ max_digits` such that
/// `|a_rounded.coefficient| × |b.coefficient|` fits inside
/// `max_safe_coefficient`. Falls back to the input value if even
/// `d = 0` would still overflow (in that case the subsequent
/// `decimal.multiply` will surface a `PrecisionExceeded` error,
/// which is the right outcome — the caller's inputs are outside
/// the supported range).
fn round_for_safe_multiply(
  a a: decimal.Decimal,
  b b: decimal.Decimal,
  max_digits max_digits: Int,
) -> decimal.Decimal {
  let b_coef = int.absolute_value(decimal.coefficient(d: b))
  case b_coef {
    0 -> a
    _ -> do_round_for_safe(a: a, b_coef: b_coef, digits: max_digits)
  }
}

fn do_round_for_safe(
  a a: decimal.Decimal,
  b_coef b_coef: Int,
  digits digits: Int,
) -> decimal.Decimal {
  use <- bool.guard(when: digits < 0, return: a)
  let candidate = decimal.round(d: a, digits: digits, mode: rounding.HalfEven)
  let candidate_coef = int.absolute_value(decimal.coefficient(d: candidate))
  case candidate_coef * b_coef <= max_safe_coefficient {
    True -> candidate
    False -> do_round_for_safe(a: a, b_coef: b_coef, digits: digits - 1)
  }
}

fn check_principal(p: decimal.Decimal) -> Result(Nil, InterestError) {
  use <- bool.guard(
    when: decimal.is_negative(p),
    return: Error(NegativePrincipal),
  )
  Ok(Nil)
}

fn check_rate(r: decimal.Decimal) -> Result(Nil, InterestError) {
  use <- bool.guard(when: decimal.is_negative(r), return: Error(NegativeRate))
  Ok(Nil)
}

fn check_periods(p: Int) -> Result(Nil, InterestError) {
  use <- bool.guard(
    when: p <= 0 || p > max_periods,
    return: Error(PeriodsOutOfRange),
  )
  Ok(Nil)
}

fn check_compounds(n: Int) -> Result(Nil, InterestError) {
  use <- bool.guard(when: n <= 0, return: Error(CompoundsOutOfRange))
  Ok(Nil)
}

fn check_digits(d: Int) -> Result(Nil, InterestError) {
  use <- bool.guard(when: d < 0, return: Error(NegativeDigits))
  Ok(Nil)
}

/// Force `d` to exponent `-digits`, padding with zero or rounding
/// half-even as needed, so the rendered form always carries exactly
/// `digits` decimal places (issue #25 — `decimal.round` is trim-only
/// and cannot pad, so calling it as the final step lets results like
/// `2000` slip through when the caller asked for `digits: 2`).
fn rescale_to_digits(
  d: decimal.Decimal,
  digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  decimal.rescale(d: d, target_exponent: -digits, mode: rounding.HalfEven)
  |> result.map_error(ArithmeticError)
}
