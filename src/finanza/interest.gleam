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
//// `payment`, `effective_annual_rate`, `compound_interest`) cap
//// their internal working precision at **6 decimal digits**. The
//// cap exists so that two N-digit coefficients multiplied together
//// stay under 2^53 - 1 (the JavaScript safe-integer ceiling
//// enforced by [`finanza/decimal`](./decimal.html)): at 6 digits,
//// `(10^6) × (10^6) = 10^12`, comfortably below 2^53 ≈ 9 × 10^15.
////
//// Concrete consequence: for inputs with **exact rates at ≤ 6 dp**
//// over **short horizons** (≤ ~36 periods), results match textbook
//// full-precision values to the cent. For inputs with **inexact
//// rates** (e.g. `0.04 / 12 = 0.003333…` truncated to 6 dp) or
//// **long horizons** (180+ periods, daily compounding over years),
//// the per-iteration rounding accumulates and the final value can
//// differ from a textbook 50-digit reference (Python `decimal`,
//// `numpy_financial`, Excel) by **0.01–0.10** in `digits = 2`
//// outputs, or a few parts-per-million in `digits = 6` outputs.
////
//// Examples of drift versus textbook references:
////
//// | Scenario | Textbook | finanza | Drift |
//// |---|---|---|---|
//// | PMT 200_000 @ 4%/12 monthly, n=180, dg=2 | 1479.38 | 1479.34 | 0.04 |
//// | PMT 50_000 @ 3.5%/12 monthly, n=84, dg=2 | 671.99 | 672.01 | 0.02 |
//// | EAR 5% nominal / daily (365), dg=6 | 0.051267 | 0.051272 | 5 ppm |
//// | FV 1000 @ 5% for 10 periods, dg=6 | 1628.894627 | 1628.894000 | 0.0006 |
////
//// For "kitchen-table" and educational use, the drift is invisible.
//// **For regulated lending, mortgage amortisation tables, or any
//// flow whose payments must match what an external regulator
//// recomputes**, do not rely on these functions; reach for a
//// higher-precision library or compute the closed form externally.
//// Re-raising the cap to recover textbook accuracy requires reworking
//// the precision-overflow guard so that intermediate products stay
//// under 2^53 - 1 — tracked in
//// [#9](https://github.com/nao1215/finanza/issues/9).

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

/// Intermediate working precision is capped so that two N-digit
/// coefficients multiplied together stay under 2^53 (the JavaScript
/// safe-integer ceiling enforced by `finanza/decimal`). 6 digits
/// keeps `(10^6) × (10^6) = 10^12` well below 2^53 ≈ 9 × 10^15 while
/// retaining good precision for typical financial inputs.
const max_work_digits: Int = 6

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
  use product <- result.map(
    decimal.multiply(pr, decimal.from_int(n: periods))
    |> result.map_error(ArithmeticError),
  )
  decimal.round(d: product, digits: digits, mode: rounding.HalfEven)
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
  let work_digits = int.min(digits + 4, max_work_digits)
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
  use product <- result.map(
    decimal.multiply(principal, growth) |> result.map_error(ArithmeticError),
  )
  decimal.round(d: product, digits: digits, mode: rounding.HalfEven)
}

// --- FV / PV / PMT / EAR -------------------------------------------------

/// Future value of `present` after `periods` periods at `rate_per_period`.
///
/// See the module-level **Precision** section for the
/// 6-working-digit cap and the resulting drift vs textbook
/// references on long horizons or with inexact rates.
pub fn future_value(
  present present: decimal.Decimal,
  rate_per_period rate_per_period: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use _ <- result.try(check_rate(rate_per_period))
  use _ <- result.try(check_periods(periods))
  use _ <- result.try(check_digits(digits))
  let work_digits = int.min(digits + 4, max_work_digits)
  use growth <- result.try(growth_factor(
    rate: rate_per_period,
    periods: periods,
    digits: work_digits,
  ))
  use product <- result.map(
    decimal.multiply(present, growth) |> result.map_error(ArithmeticError),
  )
  decimal.round(d: product, digits: digits, mode: rounding.HalfEven)
}

/// Present value of `future` discounted at `rate_per_period` for
/// `periods` periods.
///
/// See the module-level **Precision** section for the
/// 6-working-digit cap and the resulting drift vs textbook
/// references on long horizons or with inexact rates.
pub fn present_value(
  future future: decimal.Decimal,
  rate_per_period rate_per_period: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use _ <- result.try(check_rate(rate_per_period))
  use _ <- result.try(check_periods(periods))
  use _ <- result.try(check_digits(digits))
  let work_digits = int.min(digits + 4, max_work_digits)
  use growth <- result.try(growth_factor(
    rate: rate_per_period,
    periods: periods,
    digits: work_digits,
  ))
  use quotient <- result.map(
    decimal.divide(
      a: future,
      b: growth,
      digits: digits,
      mode: rounding.HalfEven,
    )
    |> result.map_error(ArithmeticError),
  )
  quotient
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
/// 6-working-digit cap. For long amortising loans (e.g. a 15-year
/// monthly mortgage = 180 periods) the cent value of the returned
/// payment can drift from a textbook PMT computed in 50-digit
/// precision by up to ~0.04 — too much for regulated lending.
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
  let work_digits = int.min(digits + 4, max_work_digits)
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
/// 6-working-digit cap and the resulting drift vs textbook
/// references at high compounding frequencies (e.g. daily / 365).
pub fn effective_annual_rate(
  nominal_rate nominal_rate: decimal.Decimal,
  compounds_per_year compounds_per_year: Int,
  digits digits: Int,
) -> Result(decimal.Decimal, InterestError) {
  use _ <- result.try(check_rate(nominal_rate))
  use _ <- result.try(check_compounds(compounds_per_year))
  use _ <- result.try(check_digits(digits))
  let work_digits = int.min(digits + 4, max_work_digits)
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
  use ear_raw <- result.map(
    decimal.subtract(growth, decimal.one())
    |> result.map_error(ArithmeticError),
  )
  decimal.round(d: ear_raw, digits: digits, mode: rounding.HalfEven)
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
  use product <- result.try(
    decimal.multiply(acc, base) |> result.map_error(ArithmeticError),
  )
  let trimmed =
    decimal.round(d: product, digits: digits, mode: rounding.HalfEven)
  pow_loop(base: base, exponent: exponent - 1, acc: trimmed, digits: digits)
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
