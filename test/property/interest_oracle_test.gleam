//// Every interest function against an exact oracle.
////
//// The oracle computes each result as an exact fraction with Erlang's
//// bignums and rounds it half-even once, so it runs on Erlang only. The
//// inputs mix monthly rates, rates with 16 places, negative rates and
//// principals near the coefficient bound, so that results often land
//// close to the rounding boundary or past the range. A second set of
//// inputs makes exact ties, which only the exact value settles, and
//// checks that `tvm` computes them within its limit.

import finanza/decimal
import finanza/interest

@target(erlang)
import finanza/internal/tvm
@target(erlang)
import gleam/int
@target(erlang)
import gleam/list
@target(erlang)
import gleam/order

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

// --- ties ---------------------------------------------------------------------

@target(erlang)
fn gcd(a: Int, b: Int) -> Int {
  case b == 0 {
    True -> int.absolute_value(a)
    False -> gcd(b, a % b)
  }
}

@target(erlang)
fn strip(n: Int, prime: Int, count: Int) -> #(Int, Int) {
  case n % prime == 0 {
    True -> strip(n / prime, prime, count + 1)
    False -> #(n, count)
  }
}

// The places of a fraction whose decimal expansion ends, or Error(Nil).
@target(erlang)
fn places(value: Fraction) -> Result(Int, Nil) {
  let denominator = value.denominator / gcd(value.numerator, value.denominator)
  let #(rest, twos) = strip(denominator, 2, 0)
  let #(rest, fives) = strip(rest, 5, 0)
  case rest == 1 {
    True -> Ok(int.max(twos, fives))
    False -> Error(Nil)
  }
}

// The digits to round at: one place short of a value with at most 29
// places, so that its last digit decides, a tie when that digit is 5.
// Otherwise `fallback`. The flag says whether the value was short.
@target(erlang)
fn tie_digits(value: Fraction, fallback: Int) -> #(Int, Bool) {
  case places(value) {
    Ok(count) if count >= 1 && count <= 29 -> #(count - 1, True)
    _ -> #(fallback, False)
  }
}

@target(erlang)
fn is_tie(value: Fraction) -> Bool {
  case places(value) {
    Ok(count) if count >= 1 && count <= 29 -> {
      let scaled = value.numerator * pow10(count) / value.denominator
      int.absolute_value(scaled) % 10 == 5
    }
    _ -> False
  }
}

// Rates whose 1 + rate is a ratio of powers of 2 and 5, or ends in 5,
// so that powers of it end and ties are common.
@target(erlang)
fn tie_rate() -> Generator(decimal.Decimal) {
  generator.element_of(
    list.map(
      [
        #(0, 0),
        #(5, -1),
        #(1, 0),
        #(15, -1),
        #(-5, -1),
        #(25, -2),
        #(5, -2),
        #(4, 0),
        #(-75, -2),
        #(24, -3),
        #(-2, -1),
        #(6, -1),
        #(9, 0),
        #(-96, -2),
        #(125, -3),
      ],
      fn(pair) { make(pair.0, pair.1) },
    ),
  )
}

@target(erlang)
fn tie_amount() -> Generator(decimal.Decimal) {
  generator.map3(
    generator.int(range.constant(0, 99_999)),
    generator.element_of([1, 5, 25, 125, 375, 1024]),
    generator.int(range.constant(-8, 0)),
    fn(c, factor, exponent) { make({ 2 * c + 1 } * factor, exponent) },
  )
}

@target(erlang)
fn tie_inputs() {
  generator.tuple4(
    tie_amount(),
    tie_rate(),
    generator.one_of([
      generator.int(range.constant(1, 25)),
      generator.int(range.constant(1, 1200)),
    ]),
    generator.int(range.constant(0, 28)),
  )
}

@target(erlang)
fn exact_parts(
  value: Result(decimal.Decimal, decimal.ArithmeticError),
) -> Result(#(Int, Int), interest.InterestError) {
  case value {
    Ok(d) -> Ok(#(decimal.coefficient(d), decimal.exponent(d)))
    Error(error) -> Error(interest.ArithmeticFailed(error))
  }
}

// The function equals the oracle, and so does the exact value when the
// exact value is short, as every tie is: the limit on the exact value
// never turns a tie into `PrecisionExceeded`.
@target(erlang)
fn agrees(
  exact: Fraction,
  fallback: Int,
  compute: fn(Int) -> Result(decimal.Decimal, interest.InterestError),
  value: tvm.Value,
) -> Bool {
  let #(digits, short) = tie_digits(exact, fallback)
  let expected = round(exact, digits)
  parts(compute(digits)) == expected
  && { !short || exact_parts(value.exact(digits)) == expected }
}

@target(erlang)
pub fn future_value_ties_match_the_exact_oracle_test() {
  metamon.forall_with(config(), tie_inputs(), fn(input) {
    let #(present, rate, periods, fallback) = input
    let exact = multiply(of(present), raise(add(integer(1), of(rate)), periods))
    agrees(
      exact,
      fallback,
      fn(digits) {
        interest.future_value(
          present:,
          rate_per_period: rate,
          periods:,
          digits:,
        )
      },
      tvm.future_value(present, rate, periods),
    )
  })
}

@target(erlang)
pub fn present_value_ties_match_the_exact_oracle_test() {
  metamon.forall_with(config(), tie_inputs(), fn(input) {
    let #(future, rate, periods, fallback) = input
    let assert Ok(exact) =
      divide(of(future), raise(add(integer(1), of(rate)), periods))
    agrees(
      exact,
      fallback,
      fn(digits) {
        interest.present_value(
          future:,
          rate_per_period: rate,
          periods:,
          digits:,
        )
      },
      tvm.present_value(future, rate, periods),
    )
  })
}

@target(erlang)
pub fn payment_ties_match_the_exact_oracle_test() {
  metamon.forall_with(
    config(),
    generator.filter(tie_inputs(), fn(input) { !decimal.is_zero(input.1) }),
    fn(input) {
      let #(principal, rate, periods, fallback) = input
      let growth = raise(add(integer(1), of(rate)), periods)
      let assert Ok(exact) =
        divide(
          multiply(multiply(of(principal), of(rate)), growth),
          add(growth, integer(-1)),
        )
      agrees(
        exact,
        fallback,
        fn(digits) {
          interest.payment(principal:, rate_per_period: rate, periods:, digits:)
        },
        tvm.payment(principal, rate, periods),
      )
    },
  )
}

@target(erlang)
pub fn effective_annual_rate_ties_match_the_exact_oracle_test() {
  metamon.forall_with(
    config(),
    generator.tuple3(
      generator.map2(
        generator.int(range.constant(-100, 4000)),
        generator.int(range.constant(-2, 0)),
        fn(c, exponent) { make(int.max(c, -100), exponent) },
      )
        |> generator.filter(fn(nominal) {
          decimal.compare(nominal, decimal.negate(decimal.one())) != order.Lt
        }),
      generator.one_of([
        generator.int(range.constant(1, 29)),
        generator.int(range.constant(1, 1200)),
      ]),
      generator.int(range.constant(0, 28)),
    ),
    fn(input) {
      let #(nominal, compounds, fallback) = input
      let assert Ok(per_period) = divide(of(nominal), integer(compounds))
      let exact =
        add(raise(add(integer(1), per_period), compounds), integer(-1))
      agrees(
        exact,
        fallback,
        fn(digits) {
          interest.effective_annual_rate(
            nominal_rate: nominal,
            compounds_per_year: compounds,
            digits:,
          )
        },
        tvm.effective_annual_rate(nominal, compounds),
      )
    },
  )
}

@target(erlang)
/// The tie inputs do make ties: at least a tenth of them for
/// `future_value` and `present_value`.
pub fn the_tie_inputs_make_ties_test() {
  let samples = generator.sample(tie_inputs(), 500)
  let future =
    list.count(samples, fn(input) {
      let #(present, rate, periods, _) = input
      is_tie(multiply(of(present), raise(add(integer(1), of(rate)), periods)))
    })
  let present =
    list.count(samples, fn(input) {
      let #(future, rate, periods, _) = input
      case divide(of(future), raise(add(integer(1), of(rate)), periods)) {
        Ok(value) -> is_tie(value)
        Error(Nil) -> False
      }
    })
  assert future >= 50
  assert present >= 50
}
