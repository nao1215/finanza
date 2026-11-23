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
//// for that, as for a tie, is it computed in full.
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
import finanza/internal/rounded.{type Number}

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

// The significant limbs of seven digits the bounds are computed with,
// before the exact value.
const precisions: List(Int) = [5, 10]

// A precision of 0 keeps every digit.
const exact: Int = 0

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
  let base = one_plus(rate)
  let start = rounded.absolute(rounded.from_decimal(present))
  let sign = rounded.from_int(rounded.from_decimal(present).sign)
  resolve(digits, fn(precision) {
    let #(low, high) = power(base, periods, start, precision)
    Ok(#(rounded.times(sign, low), rounded.times(sign, high)))
  })
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
  let base = one_plus(rate)
  use <- bool.guard(
    when: rounded.is_zero(base) && periods > 0,
    return: Error(ArithmeticFailed(decimal.DivisionByZero)),
  )
  let future = rounded.from_decimal(future)
  resolve_or_exact(
    digits,
    fn(precision) {
      let #(low, high) = power(base, periods, one(), precision)
      Ok(#(
        rounded.quotient(future, high, limbs: precision, up: False),
        rounded.quotient(future, low, limbs: precision, up: True),
      ))
    },
    fn() {
      let #(growth, _) = power(base, periods, one(), exact)
      rounded.divide_round(future, growth, digits:, rounding: decimal.HalfEven)
    },
  )
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
  // principal × rate / (1 - (1 + rate)^-periods) is
  // principal × rate + principal × rate / growth, where growth is
  // (1 + rate)^periods - 1. For a negative rate both growth and
  // principal × rate are negative, so this is
  // |principal × rate| / |growth| - |principal × rate|.
  let base = one_plus(rate)
  let interest =
    rounded.times(rounded.from_decimal(principal), rounded.from_decimal(rate))
  let size = rounded.absolute(interest)
  let negative = decimal.is_negative(rate)
  resolve_or_exact(
    digits,
    fn(precision) {
      let #(low, high) = power(base, periods, one(), precision)
      // The bounds of |growth|, the smaller first.
      let #(small, large) = case negative {
        False -> #(minus_one(low), minus_one(high))
        True -> #(one_minus(high), one_minus(low))
      }
      use <- bool.guard(
        when: small.sign < 0 || rounded.is_zero(small),
        return: Error(Nil),
      )
      let low = rounded.quotient(size, large, limbs: precision, up: False)
      let high = rounded.quotient(size, small, limbs: precision, up: True)
      Ok(#(rounded.plus(low, interest), rounded.plus(high, interest)))
    },
    fn() {
      // principal × rate × (1 + rate)^periods / growth.
      let #(grown, _) = power(base, periods, one(), exact)
      rounded.divide_round(
        rounded.times(interest, grown),
        minus_one(grown),
        digits:,
        rounding: decimal.HalfEven,
      )
    },
  )
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
  let nominal = rounded.from_decimal(nominal_rate)
  let compounds = rounded.from_int(compounds_per_year)
  resolve_or_exact(
    digits,
    fn(precision) {
      // The bounds of nominal_rate / compounds_per_year, the smaller
      // first: dropping digits away from zero lowers a negative rate.
      let toward =
        rounded.quotient(nominal, compounds, limbs: precision, up: False)
      let away =
        rounded.quotient(nominal, compounds, limbs: precision, up: True)
      let #(small, large) = case decimal.is_negative(nominal_rate) {
        False -> #(toward, away)
        True -> #(away, toward)
      }
      let small = rounded.plus(one(), small)
      let large = rounded.plus(one(), large)
      use <- bool.guard(when: small.sign < 0, return: Error(Nil))
      let #(low, high) =
        power_between(small, large, compounds_per_year, one(), precision)
      Ok(#(minus_one(low), minus_one(high)))
    },
    fn() {
      // ((compounds + nominal_rate)^compounds - compounds^compounds)
      //   / compounds^compounds
      let numerator = rounded.plus(compounds, nominal)
      let #(top, _) = power(numerator, compounds_per_year, one(), exact)
      let #(bottom, _) = power(compounds, compounds_per_year, one(), exact)
      rounded.divide_round(
        rounded.plus(top, rounded.negate(bottom)),
        bottom,
        digits:,
        rounding: decimal.HalfEven,
      )
    },
  )
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

fn one() -> Number {
  rounded.from_int(1)
}

// 1 + rate, exactly. It is not negative, because the rate is -1 or more.
fn one_plus(rate: Decimal) -> Number {
  rounded.plus(one(), rounded.from_decimal(rate))
}

fn minus_one(value: Number) -> Number {
  rounded.plus(value, rounded.from_int(-1))
}

fn one_minus(value: Number) -> Number {
  rounded.plus(one(), rounded.negate(value))
}

// Bounds of start × base^periods, for non-negative values. Each period
// keeps `precision` limbs of the exact product and drops the rest toward
// zero, which lowers the value by less than 10^(-7 × (precision - 1)) of
// itself, ε. So the result is a lower bound, and the exact value is at
// most the result × (1 - ε)^-periods, below the result × (1 +
// 2 × periods × ε) because periods × ε is at most 1/2. With a precision of 0
// both bounds are the exact value. The loop calls itself last, so it
// runs in constant stack for any number of periods.
fn power(
  base: Number,
  periods: Int,
  start: Number,
  precision: Int,
) -> #(Number, Number) {
  let low = power_loop(base, periods, start, precision, False)
  case precision {
    0 -> #(low, low)
    _ -> {
      let slack =
        rounded.Number(
          ..rounded.from_int(2 * periods),
          exponent: -7 * { precision - 1 },
        )
      #(
        low,
        rounded.plus(
          low,
          rounded.truncate(rounded.times(low, slack), limbs: 2, up: True),
        ),
      )
    }
  }
}

// Bounds of start × low^periods and start × high^periods, for
// non-negative values with low <= high: the lower one keeps `precision`
// limbs dropping the rest toward zero and the upper one away from zero.
fn power_between(
  low: Number,
  high: Number,
  periods: Int,
  start: Number,
  precision: Int,
) -> #(Number, Number) {
  #(
    power_loop(low, periods, start, precision, False),
    power_loop(high, periods, start, precision, True),
  )
}

fn power_loop(
  base: Number,
  periods: Int,
  value: Number,
  precision: Int,
  up: Bool,
) -> Number {
  case periods {
    _ if periods <= 0 -> value
    _ ->
      power_loop(
        base,
        periods - 1,
        rounded.truncate(rounded.times(value, base), limbs: precision, up:),
        precision,
        up,
      )
  }
}

// Rounds a value known only by its bounds: at each precision, when both
// bounds round to the same result it is the result, because rounding
// never decreases. The last precision keeps every digit, so both bounds
// are the exact value.
fn resolve(
  digits: Int,
  bounds: fn(Int) -> Result(#(Number, Number), Nil),
) -> Result(Decimal, InterestError) {
  resolve_or_exact(digits, bounds, fn() {
    case bounds(exact) {
      Ok(#(value, _)) ->
        rounded.round(value, digits:, rounding: decimal.HalfEven)
      Error(Nil) -> Error(decimal.PrecisionExceeded)
    }
  })
}

// Like `resolve`, with `exact` computing the rounded exact value when
// no precision settles it, for a value that is a quotient and so has no
// exact bounds.
fn resolve_or_exact(
  digits: Int,
  bounds: fn(Int) -> Result(#(Number, Number), Nil),
  exact: fn() -> Result(Decimal, decimal.ArithmeticError),
) -> Result(Decimal, InterestError) {
  let settled =
    list.find_map(precisions, fn(precision) {
      use #(low, high) <- result.try(bounds(precision))
      let low = rounded.round(low, digits:, rounding: decimal.HalfEven)
      let high = rounded.round(high, digits:, rounding: decimal.HalfEven)
      case low == high {
        True -> Ok(low)
        False -> Error(Nil)
      }
    })
  case settled {
    Ok(value) -> value
    Error(Nil) -> exact()
  }
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
