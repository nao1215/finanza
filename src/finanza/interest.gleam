//// Time value of money: simple interest, future and present value, loan
//// payments, effective annual rates and amortization schedules.
////
//// Rates are per period as decimals, so 0.5% a month is `0.005`. Every
//// function rounds its result half-even to `digits` places, once, from
//// the exact value: `simple`, `future_value`, `present_value`,
//// `payment` and `effective_annual_rate` give the same result as
//// rounding the exact fraction, so they agree with Python's `decimal`
//// at 200 digits. A rate is used as given, whatever its places, so a
//// rate written to 16 places such as `0.0041666666666667` (5% a year
//// over 12 months) works although `1 + rate` does not fit a `Decimal`.
////
//// The exact value of `(1 + rate)^periods` can have thousands of digits,
//// so it is first bounded from below and above with about 35, then 70,
//// significant digits. When both bounds round to the same result, that
//// is the result; only when the exact value is too close to a half-unit
//// for that, as for a tie, is it computed in full. An exact tie only
//// happens when that power has fewer than about 250 digits and an
//// exponent of at most about 230, so the full value is computed up to 700
//// digits and an exponent of 700, and no further: a value within
//// about 10^-60 of a half-unit, not on it, whose power would need more
//// is `ArithmeticFailed(PrecisionExceeded)`. No such input is known; a
//// payment just above a tie, such as principal × rate = 4833.95625 over
//// 1152 periods at 4 places, is settled without the power. So the work
//// of a call is bounded whatever its inputs: at most two products per
//// period at each of about 35 and 70 digits, and an exact value of at
//// most 700 digits.
////
//// The result of `simple`, `future_value`, `present_value`, `payment` and
//// `effective_annual_rate` always has exactly `digits` places. When it
//// does not fit a `Decimal` at `digits` places, because its coefficient
//// would pass 2^53 − 1, as for a payment of 1,199.10 at 20 places, the
//// function returns `ArithmeticFailed(PrecisionExceeded)` rather than
//// fewer places. A `digits` outside 0 to 28 returns `DigitsOutOfRange`
//// before any work is done.
////
//// `schedule` pays the rounded payment each period and rounds each
//// period's interest, the exact balance times the rate, to `digits`. The
//// balance and the last row keep the places of the principal when it has
//// more than `digits`, and a row whose sum would need fewer places than
//// its operands is `ArithmeticFailed(PrecisionExceeded)` too.
////
//// The number of periods, and of compounding periods per year, is at
//// most 1200 (100 years of months). The functions loop once per period in
//// constant stack, on JavaScript too.

import gleam/bool
import gleam/int
import gleam/list
import gleam/order
import gleam/result

import finanza/decimal.{type Decimal}
import finanza/internal/rounded
import finanza/internal/tvm

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
  /// `digits` was negative or above 28, the most places a `Decimal`
  /// has.
  DigitsOutOfRange
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

// The most places a Decimal has, from the range in finanza/decimal.
const max_digits: Int = 28

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
  rounded.from_decimal(principal)
  |> rounded.times(rounded.from_decimal(rate))
  |> rounded.times(rounded.from_int(periods))
  |> rounded.round(digits:, rounding: decimal.HalfEven)
  |> result.map_error(ArithmeticFailed)
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
  tvm.future_value(present, rate, periods)
  |> tvm.round(digits:)
  |> result.map_error(ArithmeticFailed)
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
  // At -1 every period divides by zero.
  use <- bool.guard(
    when: decimal.equal(rate, decimal.negate(decimal.one())) && periods > 0,
    return: Error(ArithmeticFailed(decimal.DivisionByZero)),
  )
  tvm.present_value(future, rate, periods)
  |> tvm.round(digits:)
  |> result.map_error(ArithmeticFailed)
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
  // At -1, (1 + rate)^-periods divides by zero.
  use <- bool.guard(
    when: decimal.equal(rate, decimal.negate(decimal.one())),
    return: Error(ArithmeticFailed(decimal.DivisionByZero)),
  )
  tvm.payment(principal, rate, periods)
  |> tvm.round(digits:)
  |> result.map_error(ArithmeticFailed)
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
  tvm.effective_annual_rate(nominal_rate, compounds_per_year)
  |> tvm.round(digits:)
  |> result.map_error(ArithmeticFailed)
}

/// Returns the amortization schedule of a loan repaid with `payment`
/// each period, or an empty list for 0 periods. Each period's interest is the balance times the rate,
/// rounded half-even to `digits` places. The last period pays off what
/// is left, so the final balance is exactly zero. Returns
/// `PeriodsOutOfRange` for negative periods or more than 1200.
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

// One row per step. Each step builds its row and the loop calls itself
// last, so it runs in constant stack on both targets for any number of
// periods. `rows` collects the rows in reverse.
fn schedule_loop(
  payment payment: Decimal,
  rate rate: Decimal,
  periods periods: Int,
  digits digits: Int,
  index index: Int,
  balance balance: Decimal,
  rows rows: List(Period),
) -> Result(List(Period), decimal.ArithmeticError) {
  case index {
    _ if index > periods -> Ok(list.reverse(rows))
    _ ->
      case schedule_row(payment, rate, periods, digits, index, balance) {
        Ok(row) ->
          schedule_loop(
            payment: payment,
            rate: rate,
            periods: periods,
            digits: digits,
            index: index + 1,
            balance: row.balance,
            rows: [row, ..rows],
          )
        Error(error) -> Error(error)
      }
  }
}

fn schedule_row(
  payment: Decimal,
  rate: Decimal,
  periods: Int,
  digits: Int,
  index: Int,
  balance: Decimal,
) -> Result(Period, decimal.ArithmeticError) {
  use interest <- result.try(rounded.multiply(
    balance,
    rate,
    digits: digits,
    rounding: decimal.HalfEven,
  ))
  case index == periods {
    // The last row clears whatever rounding has left on the balance.
    True -> {
      use payment <- result.try(add_keeping_places(interest, balance))
      use principal_paid <- result.try(add_keeping_places(
        payment,
        decimal.negate(interest),
      ))
      use balance <- result.map(decimal.round(
        decimal.zero(),
        digits: digits,
        rounding: decimal.HalfEven,
      ))
      Period(index:, payment:, interest:, principal_paid:, balance:)
    }
    False -> {
      use principal_paid <- result.try(add_keeping_places(
        payment,
        decimal.negate(interest),
      ))
      use balance <- result.map(add_keeping_places(
        balance,
        decimal.negate(principal_paid),
      ))
      Period(index:, payment:, interest:, principal_paid:, balance:)
    }
  }
}

// `decimal.add` drops a trailing zero from a sum past 2^53 - 1, so this
// fails instead, and every value in a row keeps the places of its
// operands.
fn add_keeping_places(
  a: Decimal,
  b: Decimal,
) -> Result(Decimal, decimal.ArithmeticError) {
  use sum <- result.try(decimal.add(a, b))
  use <- bool.guard(
    when: decimal.exponent(sum)
      > int.min(decimal.exponent(a), decimal.exponent(b)),
    return: Error(decimal.PrecisionExceeded),
  )
  Ok(sum)
}

// Internals ------------------------------------------------------------------

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
  use <- bool.guard(
    when: digits < 0 || digits > max_digits,
    return: Error(DigitsOutOfRange),
  )
  Ok(Nil)
}
