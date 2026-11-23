//// Every interest function against an exact oracle.
////
//// The oracle computes each result as an exact fraction with Erlang's
//// bignums and rounds it half-even once, so it runs on Erlang only. The
//// inputs mix monthly rates, rates with 16 places, negative rates and
//// principals near the coefficient bound, so that results often land
//// close to the rounding boundary or past the range.

import finanza/decimal
import finanza/interest

@target(erlang)
import metamon
@target(erlang)
import metamon/generator.{type Generator}
@target(erlang)
import metamon/generator/range

/// The first case the oracle found against 0.13.4, on both targets: the
/// exact payment is 43787710.37029200000…00019 (140 zeros), and 0.13.4,
/// which kept about 16 significant digits, rounded it otherwise.
pub fn payment_found_by_the_oracle_test() {
  let assert Ok(principal) = decimal.parse("6321400.68")
  let assert Ok(rate) = decimal.parse("6.9269")
  let assert Ok(payment) =
    interest.payment(principal:, rate_per_period: rate, periods: 155, digits: 7)
  assert decimal.to_string(payment) == "43787710.3702920"
}

// 2^53 - 1.
@target(erlang)
const max = 9_007_199_254_740_991

// A fraction with a positive denominator.
@target(erlang)
type Fraction {
  Fraction(numerator: Int, denominator: Int)
}

@target(erlang)
fn pow10(n: Int) -> Int {
  power(10, n)
}

@target(erlang)
fn power(base: Int, n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False ->
      case n % 2 {
        0 -> {
          let half = power(base, n / 2)
          half * half
        }
        _ -> base * power(base, n - 1)
      }
  }
}

@target(erlang)
fn of(value: decimal.Decimal) -> Fraction {
  let c = decimal.coefficient(value)
  let e = decimal.exponent(value)
  case e >= 0 {
    True -> Fraction(c * pow10(e), 1)
    False -> Fraction(c, pow10(0 - e))
  }
}

@target(erlang)
fn integer(value: Int) -> Fraction {
  Fraction(value, 1)
}

@target(erlang)
fn add(a: Fraction, b: Fraction) -> Fraction {
  Fraction(
    a.numerator * b.denominator + b.numerator * a.denominator,
    a.denominator * b.denominator,
  )
}

@target(erlang)
fn multiply(a: Fraction, b: Fraction) -> Fraction {
  Fraction(a.numerator * b.numerator, a.denominator * b.denominator)
}

@target(erlang)
fn divide(a: Fraction, b: Fraction) -> Result(Fraction, Nil) {
  case b.numerator {
    0 -> Error(Nil)
    n if n < 0 ->
      Ok(Fraction(0 - a.numerator * b.denominator, 0 - a.denominator * n))
    n -> Ok(Fraction(a.numerator * b.denominator, a.denominator * n))
  }
}

@target(erlang)
fn raise(a: Fraction, n: Int) -> Fraction {
  Fraction(power(a.numerator, n), power(a.denominator, n))
}

@target(erlang)
fn floor_divide(a: Int, b: Int) -> Int {
  let q = a / b
  case a % b < 0 {
    True -> q - 1
    False -> q
  }
}

// The fraction rounded half-even to `digits` places, as a coefficient
// and exponent, or PrecisionExceeded when that is out of range.
@target(erlang)
fn round(
  value: Fraction,
  digits: Int,
) -> Result(#(Int, Int), interest.InterestError) {
  let numerator = value.numerator * pow10(digits)
  let floor = floor_divide(numerator, value.denominator)
  let twice = 2 * { numerator - floor * value.denominator }
  let coefficient = case twice > value.denominator {
    True -> floor + 1
    False ->
      case twice == value.denominator && floor % 2 != 0 {
        True -> floor + 1
        False -> floor
      }
  }
  case coefficient > max || coefficient < 0 - max {
    True -> Error(interest.ArithmeticFailed(decimal.PrecisionExceeded))
    False -> Ok(#(coefficient, 0 - digits))
  }
}

@target(erlang)
fn parts(
  value: Result(decimal.Decimal, interest.InterestError),
) -> Result(#(Int, Int), interest.InterestError) {
  case value {
    Ok(d) -> Ok(#(decimal.coefficient(d), decimal.exponent(d)))
    Error(error) -> Error(error)
  }
}

@target(erlang)
fn make(coefficient: Int, exponent: Int) -> decimal.Decimal {
  case decimal.new(coefficient:, exponent:) {
    Ok(value) -> value
    Error(Nil) -> decimal.zero()
  }
}

@target(erlang)
fn amount_generator() -> Generator(decimal.Decimal) {
  generator.one_of([
    generator.map2(
      generator.int(range.constant(0, 1_000_000_000)),
      generator.int(range.constant(-2, 0)),
      make,
    ),
    generator.map2(
      generator.int(range.constant(0, max)),
      generator.int(range.constant(-6, 0)),
      make,
    ),
    generator.map(generator.int(range.constant(0, 100_000)), make(_, -2)),
  ])
}

@target(erlang)
fn rate_generator() -> Generator(decimal.Decimal) {
  generator.one_of([
    // Monthly rates of 0.01% to 20% a year, at 10 to 16 places.
    generator.map2(
      generator.int(range.constant(1, 2000)),
      generator.int(range.constant(10, 16)),
      fn(basis_points, places) {
        make(basis_points * pow10(places) / 120_000, 0 - places)
      },
    ),
    generator.map2(
      generator.int(range.constant(-9999, 99_999)),
      generator.int(range.constant(4, 6)),
      fn(c, places) { make(c, 0 - places) },
    ),
    generator.map(generator.int(range.constant(1, max / 10)), make(_, -16)),
    generator.map(generator.int(range.constant(1, 1000)), make(_, -28)),
  ])
}

@target(erlang)
fn config() {
  metamon.with_runs_or_panic(metamon.default_config(), 300)
}

@target(erlang)
fn inputs() {
  generator.tuple4(
    amount_generator(),
    rate_generator(),
    generator.int(range.constant(1, 400)),
    generator.int(range.constant(0, 10)),
  )
}

@target(erlang)
pub fn simple_matches_the_exact_oracle_test() {
  metamon.forall_with(config(), inputs(), fn(input) {
    let #(principal, rate, periods, digits) = input
    let expected =
      round(
        multiply(multiply(of(principal), of(rate)), integer(periods)),
        digits,
      )
    parts(interest.simple(principal:, rate:, periods:, digits:)) == expected
  })
}

@target(erlang)
pub fn future_value_matches_the_exact_oracle_test() {
  metamon.forall_with(config(), inputs(), fn(input) {
    let #(present, rate, periods, digits) = input
    let growth = raise(add(integer(1), of(rate)), periods)
    let expected = round(multiply(of(present), growth), digits)
    parts(interest.future_value(
      present:,
      rate_per_period: rate,
      periods:,
      digits:,
    ))
    == expected
  })
}

@target(erlang)
pub fn present_value_matches_the_exact_oracle_test() {
  metamon.forall_with(config(), inputs(), fn(input) {
    let #(future, rate, periods, digits) = input
    let growth = raise(add(integer(1), of(rate)), periods)
    let expected = case divide(of(future), growth) {
      Ok(value) -> round(value, digits)
      Error(Nil) -> Error(interest.ArithmeticFailed(decimal.DivisionByZero))
    }
    parts(interest.present_value(
      future:,
      rate_per_period: rate,
      periods:,
      digits:,
    ))
    == expected
  })
}

@target(erlang)
pub fn payment_matches_the_exact_oracle_test() {
  metamon.forall_with(config(), inputs(), fn(input) {
    let #(principal, rate, periods, digits) = input
    let r = of(rate)
    let growth = raise(add(integer(1), r), periods)
    let expected = case
      decimal.is_zero(rate),
      divide(
        multiply(multiply(of(principal), r), growth),
        add(growth, integer(-1)),
      )
    {
      True, _ ->
        case divide(of(principal), integer(periods)) {
          Ok(value) -> round(value, digits)
          Error(Nil) -> Error(interest.ArithmeticFailed(decimal.DivisionByZero))
        }
      False, Ok(value) -> round(value, digits)
      False, Error(Nil) ->
        Error(interest.ArithmeticFailed(decimal.DivisionByZero))
    }
    parts(interest.payment(principal:, rate_per_period: rate, periods:, digits:))
    == expected
  })
}

@target(erlang)
pub fn effective_annual_rate_matches_the_exact_oracle_test() {
  metamon.forall_with(
    config(),
    generator.tuple3(
      rate_generator(),
      generator.int(range.constant(1, 1200)),
      generator.int(range.constant(0, 14)),
    ),
    fn(input) {
      let #(nominal, compounds, digits) = input
      let assert Ok(per_period) = divide(of(nominal), integer(compounds))
      let growth = raise(add(integer(1), per_period), compounds)
      let expected = round(add(growth, integer(-1)), digits)
      parts(interest.effective_annual_rate(
        nominal_rate: nominal,
        compounds_per_year: compounds,
        digits:,
      ))
      == expected
    },
  )
}
