//// Time value of money: simple interest, future and present value, loan
//// payments, effective annual rates and amortization schedules.
////
//// Rates are per period as decimals, so 0.5% a month is `0.005`. Every
//// function rounds its result half-even to `digits` places.
////
//// Growth over many periods is computed one period at a time, from the
//// exact value of `x × (1 + rate)`, so a rate written to 16 places, such
//// as `0.0041666666666667` for 5% a year over 12 months, is used as it is
//// even though `1 + rate` does not fit a `Decimal`.
////
//// `payment` and `effective_annual_rate` keep every intermediate value
//// at the most places, up to 28, that fit a `Decimal`, about 16
//// significant digits, and round once to `digits` at the end;
//// `effective_annual_rate` divides the nominal rate that way too.
//// `schedule` pays that payment and rounds each period's interest, the
//// exact balance times the rate, to `digits`. The unrounded payment is
//// within about `periods × 1e-15` of the exact one, relative to the
//// larger of the payment and `principal × rate`, and Python's `decimal`
//// measured at most 1.3e-14. Only a payment whose exact value is closer
//// than that to a half-unit at `digits` places can round to the other
//// neighbour. For monthly rates of 1% to 20% a year over 360 and 1200
//// months, the payment and every row of the schedule are the same as
//// Python's `decimal` gives.
////
//// `future_value` and `present_value` work at `digits + 2` places, at
//// least 7. `present_value` divides by `1 + rate`, which has to fit a
//// `Decimal`. When it does not, as for `0.0041666666666667`, the rate in
//// it is rounded half-even to the most places at which it does, which is
//// 15 for a rate between -1 and 1, so the rate moves by at most 5e-16.
////
//// A `Decimal` has at most 28 places, so a `digits` above 28 returns
//// `DigitsOutOfRange` before any work is done, and `future_value` and
//// `present_value` work at no more than 28 places.
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

// The fewest places future_value and present_value work at.
const min_growth_digits: Int = 7

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
  use periods <- result.try(int_to_decimal(periods))
  // Scale the principal by the period count exactly and round the
  // product with the rate once. When that scaling does not fit, round
  // principal × rate at as many places as fit, then scale it.
  case decimal.multiply(principal, periods) {
    Ok(scaled) ->
      rounded.multiply(scaled, rate, digits:, rounding: decimal.HalfEven)
    Error(decimal.PrecisionExceeded) | Error(decimal.DivisionByZero) -> {
      use product <- result.try(rounded.multiply_add(
        principal,
        rate,
        plus: [],
        at_most: max_digits,
      ))
      rounded.multiply(product, periods, digits:, rounding: decimal.HalfEven)
    }
  }
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
  use grown <- result.try(compound(
    rate: rate,
    periods: periods,
    accumulator: present,
    plus_rate: False,
    digits: growth_digits(digits),
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
    digits: growth_digits(digits),
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
  // principal × rate / (1 - (1 + rate)^-periods) is
  // principal × rate × (1 + 1 / growth), where growth is
  // (1 + rate)^periods - 1. Computing growth itself, rather than
  // (1 + rate)^periods, keeps its significant digits when the rate is
  // small, and the payment is then one division and one sum, each kept
  // at the most places that fit, and one rounding to `digits`.
  use growth <- result.try(compound(
    rate: rate,
    periods: periods,
    accumulator: decimal.zero(),
    plus_rate: True,
    digits: max_digits,
  ))
  let amount = {
    use interest <- result.try(rounded.multiply_add(
      principal,
      rate,
      plus: [],
      at_most: max_digits,
    ))
    use share <- result.try(
      at_most(max_digits, fn(places) {
        decimal.divide(
          interest,
          growth,
          digits: places,
          rounding: decimal.HalfEven,
        )
      }),
    )
    use amount <- result.try(rounded.multiply_add(
      share,
      decimal.one(),
      plus: [interest],
      at_most: digits,
    ))
    // Fewer places than `digits` fit only when the payment is out of
    // range at `digits`.
    case decimal.exponent(amount) == -digits {
      True -> Ok(amount)
      False -> Error(decimal.PrecisionExceeded)
    }
  }
  result.map_error(amount, ArithmeticFailed)
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
    at_most(max_digits, fn(places) {
      decimal.divide(
        nominal_rate,
        compounds,
        digits: places,
        rounding: decimal.HalfEven,
      )
    })
    |> result.map_error(ArithmeticFailed),
  )
  // (1 + rate)^compounds - 1, computed as such so no digits are lost to
  // the leading 1.
  use growth <- result.try(compound(
    rate: rate,
    periods: compounds_per_year,
    accumulator: decimal.zero(),
    plus_rate: True,
    digits: max_digits,
  ))
  round_to(growth, digits)
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
  }
}

// Internals ------------------------------------------------------------------

// 1 + rate, for present_value, which divides by it. A coefficient holds
// about 16 digits, so a rate written to 16 places, such as
// 0.0041666666666667, makes 1 + rate need 17. The rate is tried at its
// own places first, so a sum `decimal.add` computes is exact. Otherwise
// the rate is rounded half-even to the most places at which 1 + rate
// fits, and then 1 is added exactly.
//
// When the rate keeps one place or more, this equals 1 + rate rounded
// half-even at that place: adding the integer 1 moves both neighbours by
// 1, so the distances to them stay the same, and 1 is 10^k units of the
// k-th place, an even number, so the parity of each neighbour's last
// digit stays the same too. This holds for a negative rate as well. A
// rate between -1 and 1 is rounded to no fewer than 15 places, so it
// moves by at most 5e-16.
fn one_plus(rate: Decimal) -> Result(Decimal, InterestError) {
  at_most(int.max(0, -decimal.exponent(rate)), fn(places) {
    use rate <- result.try(decimal.round(
      rate,
      digits: places,
      rounding: decimal.HalfEven,
    ))
    decimal.add(decimal.one(), rate)
  })
  |> result.map_error(ArithmeticFailed)
}

// Applies `periods` periods of growth at `rate` to `accumulator`: each
// period takes it to `accumulator × (1 + rate)`, plus `rate` when
// `plus_rate` is set, so that from zero it tracks (1 + rate)^periods - 1.
// Each period's value is exact before it is rounded half-even at the
// most places up to `digits` that fit, so `1 + rate` never has to be a
// Decimal and fast growth loses places instead of failing. The loop
// calls itself last, so it runs in constant stack for any number of
// periods.
fn compound(
  rate rate: Decimal,
  periods periods: Int,
  accumulator accumulator: Decimal,
  plus_rate plus_rate: Bool,
  digits digits: Int,
) -> Result(Decimal, InterestError) {
  let addends = case plus_rate {
    True -> [accumulator, rate]
    False -> [accumulator]
  }
  case periods {
    _ if periods <= 0 -> Ok(accumulator)
    _ ->
      case
        rounded.multiply_add(accumulator, rate, plus: addends, at_most: digits)
      {
        Ok(next) ->
          compound(
            rate: rate,
            periods: periods - 1,
            accumulator: next,
            plus_rate: plus_rate,
            digits: digits,
          )
        Error(error) -> Error(ArithmeticFailed(error))
      }
  }
}

// accumulator ÷ base^exponent, the inverse of compound.
fn discount_loop(
  base base: Decimal,
  exponent exponent: Int,
  accumulator accumulator: Decimal,
  digits digits: Int,
) -> Result(Decimal, InterestError) {
  case exponent {
    _ if exponent <= 0 -> Ok(accumulator)
    _ -> {
      let quotient =
        at_most(digits, fn(places) {
          decimal.divide(
            accumulator,
            base,
            digits: places,
            rounding: decimal.HalfEven,
          )
        })
      case quotient {
        Ok(quotient) ->
          discount_loop(
            base: base,
            exponent: exponent - 1,
            accumulator: quotient,
            digits: digits,
          )
        Error(error) -> Error(ArithmeticFailed(error))
      }
    }
  }
}

// Runs `attempt` at the most places up to `digits`, and no fewer than
// 0, at which it does not overflow.
fn at_most(
  digits: Int,
  attempt: fn(Int) -> Result(Decimal, decimal.ArithmeticError),
) -> Result(Decimal, decimal.ArithmeticError) {
  case attempt(digits) {
    Ok(value) -> Ok(value)
    Error(error) ->
      case digits > 0 {
        True -> at_most(digits - 1, attempt)
        False -> Error(error)
      }
  }
}

// The places future_value and present_value work at: two more than
// asked for, at least 7 and at most 28.
fn growth_digits(digits: Int) -> Int {
  int.min(max_digits, int.max(min_growth_digits, digits + 2))
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
  use <- bool.guard(
    when: digits < 0 || digits > max_digits,
    return: Error(DigitsOutOfRange),
  )
  Ok(Nil)
}
