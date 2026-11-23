//// Time value of money: simple interest, future and present value, loan
//// payments, effective annual rates and amortization schedules.
////
//// Rates are per period as decimals, so 0.5% a month is `0.005`. Every
//// function rounds its result half-even to `digits` places.
////
//// Growth over many periods is computed one period at a time. Results
//// agree with numpy-financial and spreadsheet functions to the cent for
//// monthly rates over 30 years. `future_value` and `present_value` work
//// at `digits + 2` places; `payment`, `effective_annual_rate` and
//// `schedule` work at 7, so a `digits` above 7 pads with zeros there.

import gleam/bool
import gleam/int
import gleam/list
import gleam/order
import gleam/result

import finanza/decimal.{type Decimal}

/// Why an interest calculation was rejected.
///
pub type InterestError {
  /// The principal was negative.
  NegativePrincipal
  /// The rate was below -1, a loss of more than 100%.
  RateBelowMinusOne
  /// The number of periods was negative or above 1200 (100 years of
  /// months). `payment` also rejects 0.
  PeriodsOutOfRange
  /// The number of compounding periods per year was zero, negative or
  /// above 1200.
  CompoundsOutOfRange
  /// `digits` was negative.
  NegativeDigits
  /// The decimal arithmetic underneath failed.
  ArithmeticFailed(decimal.ArithmeticError)
}

/// One row of an amortization schedule.
///
pub type Period {
  Period(
    /// The period number, starting at 1.
    index: Int,
    /// The total paid in this period.
    payment: Decimal,
    /// The part of the payment that is interest.
    interest: Decimal,
    /// The part of the payment that reduces the balance.
    principal_paid: Decimal,
    /// The balance left after this period.
    balance: Decimal,
  )
}

const max_periods: Int = 1200

const max_work_digits: Int = 7

const max_safe_coefficient: Int = 9_007_199_254_740_991

/// Returns the simple interest `principal × rate × periods`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(principal) = decimal.parse("1000")
/// let assert Ok(rate) = decimal.parse("0.05")
/// interest.simple(principal:, rate:, periods: 3, digits: 2)
/// |> result.map(decimal.to_string)
/// // -> Ok("150.00")
/// ```
///
pub fn simple(
  principal principal: Decimal,
  rate rate: Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(Decimal, InterestError) {
  use _ <- result.try(check_principal(principal))
  use _ <- result.try(check_rate(rate))
  use _ <- result.try(check_periods(periods, minimum: 0))
  use _ <- result.try(check_digits(digits))
  use periods <- result.try(int_to_decimal(periods))
  decimal.multiply(principal, rate)
  |> result.try(decimal.multiply(_, periods))
  |> result.map_error(ArithmeticFailed)
  |> result.try(round_to(_, digits))
}

/// Returns `present × (1 + rate_per_period)^periods`.
///
/// For a nominal annual rate compounded `n` times a year, pass the
/// annual rate divided by `n` and the number of years times `n`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(present) = decimal.parse("1000")
/// let assert Ok(rate) = decimal.parse("0.05")
/// interest.future_value(present:, rate_per_period: rate, periods: 10, digits: 2)
/// |> result.map(decimal.to_string)
/// // -> Ok("1628.89")
/// ```
///
pub fn future_value(
  present present: Decimal,
  rate_per_period rate: Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(Decimal, InterestError) {
  use _ <- result.try(check_rate(rate))
  use _ <- result.try(check_periods(periods, minimum: 0))
  use _ <- result.try(check_digits(digits))
  use base <- result.try(one_plus(rate))
  use grown <- result.try(pow_loop(
    base: base,
    exponent: periods,
    accumulator: present,
    digits: int.max(max_work_digits, digits + 2),
  ))
  round_to(grown, digits)
}

/// Returns `future ÷ (1 + rate_per_period)^periods`, the inverse of
/// `future_value`.
///
pub fn present_value(
  future future: Decimal,
  rate_per_period rate: Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(Decimal, InterestError) {
  use _ <- result.try(check_rate(rate))
  use _ <- result.try(check_periods(periods, minimum: 0))
  use _ <- result.try(check_digits(digits))
  use base <- result.try(one_plus(rate))
  use discounted <- result.try(discount_loop(
    base: base,
    exponent: periods,
    accumulator: future,
    digits: int.max(max_work_digits, digits + 2),
  ))
  round_to(discounted, digits)
}

/// Returns the payment per period that repays `principal` over
/// `periods` periods: `principal × rate / (1 - (1 + rate)^-periods)`,
/// or `principal / periods` when the rate is zero.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(principal) = decimal.parse("200000")
/// let assert Ok(rate) = decimal.parse("0.005")
/// interest.payment(principal:, rate_per_period: rate, periods: 360, digits: 2)
/// |> result.map(decimal.to_string)
/// // -> Ok("1199.10")
/// ```
///
pub fn payment(
  principal principal: Decimal,
  rate_per_period rate: Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(Decimal, InterestError) {
  use _ <- result.try(check_principal(principal))
  use _ <- result.try(check_rate(rate))
  use _ <- result.try(check_periods(periods, minimum: 1))
  use _ <- result.try(check_digits(digits))
  use <- bool.guard(when: decimal.is_zero(rate), return: {
    use periods <- result.try(int_to_decimal(periods))
    decimal.divide(
      principal,
      periods,
      digits: digits,
      rounding: decimal.HalfEven,
    )
    |> result.map_error(ArithmeticFailed)
  })
  use growth <- result.try(growth_factor(rate, periods))
  let quotient = {
    use inverse <- result.try(decimal.divide(
      decimal.one(),
      growth,
      digits: max_work_digits,
      rounding: decimal.HalfEven,
    ))
    use denominator <- result.try(decimal.subtract(decimal.one(), inverse))
    use numerator <- result.try(decimal.multiply(principal, rate))
    // Dividing at more than the working precision would overflow for
    // ordinary loans and add no accuracy, so pad afterwards instead.
    decimal.divide(
      numerator,
      denominator,
      digits: int.min(digits, max_work_digits),
      rounding: decimal.HalfEven,
    )
  }
  quotient
  |> result.map_error(ArithmeticFailed)
  |> result.try(round_to(_, digits))
}

/// Returns the effective annual rate of a nominal rate compounded
/// `compounds_per_year` times a year:
/// `(1 + nominal_rate / compounds_per_year)^compounds_per_year - 1`.
///
pub fn effective_annual_rate(
  nominal_rate nominal_rate: Decimal,
  compounds_per_year compounds_per_year: Int,
  digits digits: Int,
) -> Result(Decimal, InterestError) {
  use _ <- result.try(check_rate(nominal_rate))
  use <- bool.guard(
    when: compounds_per_year <= 0 || compounds_per_year > max_periods,
    return: Error(CompoundsOutOfRange),
  )
  use _ <- result.try(check_digits(digits))
  use compounds <- result.try(int_to_decimal(compounds_per_year))
  use rate <- result.try(
    decimal.divide(
      nominal_rate,
      compounds,
      digits: max_work_digits,
      rounding: decimal.HalfEven,
    )
    |> result.map_error(ArithmeticFailed),
  )
  use growth <- result.try(growth_factor(rate, compounds_per_year))
  decimal.subtract(growth, decimal.one())
  |> result.map_error(ArithmeticFailed)
  |> result.try(round_to(_, digits))
}

/// Returns the amortization schedule of a loan repaid with `payment`
/// each period, or an empty list for 0 periods. Each period's interest is the balance times the rate,
/// rounded half-even to `digits` places. The last period pays off what
/// is left, so the final balance is exactly zero.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(principal) = decimal.parse("1000")
/// let assert Ok(rate) = decimal.parse("0.01")
/// let assert Ok([first, ..]) =
///   interest.schedule(principal:, rate_per_period: rate, periods: 12, digits: 2)
/// #(decimal.to_string(first.interest), decimal.to_string(first.principal_paid))
/// // -> #("10.00", "78.85")
/// ```
///
pub fn schedule(
  principal principal: Decimal,
  rate_per_period rate: Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(List(Period), InterestError) {
  use _ <- result.try(check_principal(principal))
  use _ <- result.try(check_rate(rate))
  use _ <- result.try(check_digits(digits))
  use <- bool.guard(when: periods == 0, return: Ok([]))
  use amount <- result.try(payment(
    principal: principal,
    rate_per_period: rate,
    periods: periods,
    digits: digits,
  ))
  schedule_loop(
    payment: amount,
    rate: rate,
    periods: periods,
    digits: digits,
    index: 1,
    balance: principal,
    rows: [],
  )
  |> result.map_error(ArithmeticFailed)
}

fn schedule_loop(
  payment payment: Decimal,
  rate rate: Decimal,
  periods periods: Int,
  digits digits: Int,
  index index: Int,
  balance balance: Decimal,
  rows rows: List(Period),
) -> Result(List(Period), decimal.ArithmeticError) {
  use <- bool.guard(when: index > periods, return: Ok(list.reverse(rows)))
  use interest <- result.try(
    decimal.multiply(balance, rate)
    |> result.try(decimal.round(_, digits: digits, rounding: decimal.HalfEven)),
  )
  use row <- result.try(case index == periods {
    // The last row clears whatever rounding has left on the balance.
    True -> {
      use payment <- result.try(decimal.add(interest, balance))
      use principal_paid <- result.try(decimal.subtract(payment, interest))
      use balance <- result.map(decimal.round(
        decimal.zero(),
        digits: digits,
        rounding: decimal.HalfEven,
      ))
      Period(index:, payment:, interest:, principal_paid:, balance:)
    }
    False -> {
      use principal_paid <- result.try(decimal.subtract(payment, interest))
      use balance <- result.map(decimal.subtract(balance, principal_paid))
      Period(index:, payment:, interest:, principal_paid:, balance:)
    }
  })
  schedule_loop(
    payment: payment,
    rate: rate,
    periods: periods,
    digits: digits,
    index: index + 1,
    balance: row.balance,
    rows: [row, ..rows],
  )
}

// Internals ------------------------------------------------------------------

fn growth_factor(
  rate: Decimal,
  periods: Int,
) -> Result(Decimal, InterestError) {
  use base <- result.try(one_plus(rate))
  pow_loop(
    base: base,
    exponent: periods,
    accumulator: decimal.one(),
    digits: max_work_digits,
  )
}

fn one_plus(rate: Decimal) -> Result(Decimal, InterestError) {
  decimal.add(decimal.one(), rate) |> result.map_error(ArithmeticFailed)
}

// accumulator × base^exponent, one multiplication at a time, rounding
// between steps so the coefficient stays in range.
fn pow_loop(
  base base: Decimal,
  exponent exponent: Int,
  accumulator accumulator: Decimal,
  digits digits: Int,
) -> Result(Decimal, InterestError) {
  use <- bool.guard(when: exponent <= 0, return: Ok(accumulator))
  // Give up places in the accumulator when the product would otherwise
  // overflow. Fast growth loses precision instead of failing.
  let safe = round_for_multiply(accumulator, base, digits)
  use product <- result.try(
    decimal.multiply(safe, base) |> result.map_error(ArithmeticFailed),
  )
  pow_loop(
    base: base,
    exponent: exponent - 1,
    accumulator: round_or_keep(product, digits),
    digits: digits,
  )
}

// accumulator ÷ base^exponent, the inverse of pow_loop.
fn discount_loop(
  base base: Decimal,
  exponent exponent: Int,
  accumulator accumulator: Decimal,
  digits digits: Int,
) -> Result(Decimal, InterestError) {
  use <- bool.guard(when: exponent <= 0, return: Ok(accumulator))
  use quotient <- result.try(divide_at_most(accumulator, base, digits))
  discount_loop(
    base: base,
    exponent: exponent - 1,
    accumulator: quotient,
    digits: digits,
  )
}

// Divides at the most places up to `digits` that do not overflow.
fn divide_at_most(
  a: Decimal,
  b: Decimal,
  digits: Int,
) -> Result(Decimal, InterestError) {
  case decimal.divide(a, b, digits: digits, rounding: decimal.HalfEven) {
    Ok(quotient) -> Ok(quotient)
    Error(error) ->
      case digits > 0 {
        True -> divide_at_most(a, b, digits - 1)
        False -> Error(ArithmeticFailed(error))
      }
  }
}

// Rounds `a` to the most places up to `digits` at which a × b stays in
// range. Returns `a` unchanged when no number of places is enough; the
// multiplication then reports the overflow.
fn round_for_multiply(a: Decimal, b: Decimal, digits: Int) -> Decimal {
  let b_magnitude = int.absolute_value(decimal.coefficient(b))
  use <- bool.guard(when: digits < 0 || b_magnitude == 0, return: a)
  let candidate = round_or_keep(a, digits)
  case
    int.absolute_value(decimal.coefficient(candidate)) * b_magnitude
    <= max_safe_coefficient
  {
    True -> candidate
    False -> round_for_multiply(a, b, digits - 1)
  }
}

// Rounding to fewer places cannot overflow; padding to more places can,
// and then the value is kept as it is.
fn round_or_keep(value: Decimal, digits: Int) -> Decimal {
  case decimal.round(value, digits: digits, rounding: decimal.HalfEven) {
    Ok(rounded) -> rounded
    Error(decimal.PrecisionExceeded) | Error(decimal.DivisionByZero) -> value
  }
}

fn round_to(value: Decimal, digits: Int) -> Result(Decimal, InterestError) {
  decimal.round(value, digits: digits, rounding: decimal.HalfEven)
  |> result.map_error(ArithmeticFailed)
}

fn int_to_decimal(value: Int) -> Result(Decimal, InterestError) {
  decimal.from_int(value)
  |> result.replace_error(ArithmeticFailed(decimal.PrecisionExceeded))
}

fn check_principal(principal: Decimal) -> Result(Nil, InterestError) {
  use <- bool.guard(
    when: decimal.is_negative(principal),
    return: Error(NegativePrincipal),
  )
  Ok(Nil)
}

fn check_rate(rate: Decimal) -> Result(Nil, InterestError) {
  case decimal.compare(rate, decimal.negate(decimal.one())) {
    order.Lt -> Error(RateBelowMinusOne)
    order.Eq | order.Gt -> Ok(Nil)
  }
}

fn check_periods(
  periods: Int,
  minimum minimum: Int,
) -> Result(Nil, InterestError) {
  use <- bool.guard(
    when: periods < minimum || periods > max_periods,
    return: Error(PeriodsOutOfRange),
  )
  Ok(Nil)
}

fn check_digits(digits: Int) -> Result(Nil, InterestError) {
  use <- bool.guard(when: digits < 0, return: Error(NegativeDigits))
  Ok(Nil)
}
