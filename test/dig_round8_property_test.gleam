//// dig-bug round 8: extended property-based testing.
////
//// Second property pass complementing round 2. Round 2 covers
//// commutativity, identities, double-negate, subtract inverse,
//// compare antisymmetry, round idempotence, string round-trip, money
//// from_minor/to_minor, allocate total preservation, Luhn check
//// digit, normalize idempotence, and mask keep counts — all with
//// random LCG inputs.
////
//// Round 6 added more *fixed-pool* metamorphic checks (associativity,
//// distributivity, transitivity). This round randomises those same
//// properties with the same LCG style as round 2, plus introduces
//// randomised property checks for interest / amortisation / money
//// arithmetic that no earlier round exercised at random inputs.

import gleam/int
import gleam/list
import gleam/order
import gleeunit/should

import finanza/decimal
import finanza/interest
import finanza/money
import support

const trials: Int = 200

// --- LCG PRNG (matches round 2) -----------------------------------------

type Prng {
  Prng(state: Int)
}

fn next_int(prng: Prng) -> #(Int, Prng) {
  let new_state = { prng.state * 1_103_515_245 + 12_345 } % 2_147_483_648
  #(new_state, Prng(state: new_state))
}

fn int_in_range(prng: Prng, low: Int, high: Int) -> #(Int, Prng) {
  let #(n, prng2) = next_int(prng)
  let span = high - low + 1
  #(low + int.absolute_value(n) % span, prng2)
}

// Coefficients in [-100_000, 100_000] × exponents in [-4, 2] so triple
// products stay well inside 2^53.
fn gen_decimal(prng: Prng) -> #(decimal.Decimal, Prng) {
  let #(coef, p1) = int_in_range(prng, -100_000, 100_000)
  let #(exp, p2) = int_in_range(p1, -4, 2)
  #(support.new(coefficient: coef, exponent: exp), p2)
}

fn gen_non_negative_decimal(prng: Prng) -> #(decimal.Decimal, Prng) {
  let #(coef, p1) = int_in_range(prng, 0, 100_000)
  let #(exp, p2) = int_in_range(p1, -4, 0)
  #(support.new(coefficient: coef, exponent: exp), p2)
}

fn iterate(prng: Prng, n: Int, step: fn(Prng) -> Prng) -> Prng {
  case n <= 0 {
    True -> prng
    False -> iterate(step(prng), n - 1, step)
  }
}

// --- Decimal associativity / distributivity (randomised) ----------------

pub fn decimal_add_associative_test() -> Nil {
  let prng = Prng(state: 311)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = gen_decimal(p)
    let #(b, p2) = gen_decimal(p1)
    let #(c, p3) = gen_decimal(p2)
    let left = case decimal.add(a, b) {
      Ok(ab) -> decimal.add(ab, c)
      Error(e) -> Error(e)
    }
    let right = case decimal.add(b, c) {
      Ok(bc) -> decimal.add(a, bc)
      Error(e) -> Error(e)
    }
    case left, right {
      Ok(x), Ok(y) ->
        decimal.equal(x, y)
        |> should.be_true
      Error(_), Error(_) -> Nil
      _, _ -> should.be_true(False)
    }
    p3
  })
  Nil
}

pub fn decimal_multiply_associative_test() -> Nil {
  let prng = Prng(state: 313)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = gen_decimal(p)
    let #(b, p2) = gen_decimal(p1)
    let #(c, p3) = gen_decimal(p2)
    let left = case decimal.multiply(a, b) {
      Ok(ab) -> decimal.multiply(ab, c)
      Error(e) -> Error(e)
    }
    let right = case decimal.multiply(b, c) {
      Ok(bc) -> decimal.multiply(a, bc)
      Error(e) -> Error(e)
    }
    case left, right {
      Ok(x), Ok(y) ->
        decimal.equal(x, y)
        |> should.be_true
      Error(_), Error(_) -> Nil
      _, _ -> should.be_true(False)
    }
    p3
  })
  Nil
}

pub fn decimal_distributive_test() -> Nil {
  let prng = Prng(state: 317)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = gen_decimal(p)
    let #(b, p2) = gen_decimal(p1)
    let #(c, p3) = gen_decimal(p2)
    let left = case decimal.add(b, c) {
      Ok(bc) -> decimal.multiply(a, bc)
      Error(e) -> Error(e)
    }
    let right = case decimal.multiply(a, b), decimal.multiply(a, c) {
      Ok(ab), Ok(ac) -> decimal.add(ab, ac)
      Error(e), _ -> Error(e)
      _, Error(e) -> Error(e)
    }
    case left, right {
      Ok(x), Ok(y) ->
        decimal.equal(x, y)
        |> should.be_true
      Error(_), Error(_) -> Nil
      _, _ -> should.be_true(False)
    }
    p3
  })
  Nil
}

pub fn decimal_multiply_zero_absorbs_test() -> Nil {
  let prng = Prng(state: 331)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = gen_decimal(p)
    case decimal.multiply(a, decimal.zero()) {
      Ok(prod) ->
        decimal.equal(prod, decimal.zero())
        |> should.be_true
      Error(_) -> should.be_true(False)
    }
    p1
  })
  Nil
}

pub fn decimal_multiply_negate_test() -> Nil {
  // multiply(a, -b) == -multiply(a, b)
  let prng = Prng(state: 337)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = gen_decimal(p)
    let #(b, p2) = gen_decimal(p1)
    let left = decimal.multiply(a, decimal.negate(b))
    let right = case decimal.multiply(a, b) {
      Ok(ab) -> Ok(decimal.negate(ab))
      Error(e) -> Error(e)
    }
    case left, right {
      Ok(x), Ok(y) ->
        decimal.equal(x, y)
        |> should.be_true
      Error(_), Error(_) -> Nil
      _, _ -> should.be_true(False)
    }
    p2
  })
  Nil
}

// --- compare consistency / transitivity (randomised) -------------------

pub fn decimal_compare_eq_consistent_with_equal_test() -> Nil {
  let prng = Prng(state: 347)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = gen_decimal(p)
    let #(b, p2) = gen_decimal(p1)
    let cmp = decimal.compare(a, b)
    let eq = decimal.equal(a, b)
    case cmp, eq {
      order.Eq, True -> Nil
      order.Lt, False -> Nil
      order.Gt, False -> Nil
      _, _ -> should.be_true(False)
    }
    p2
  })
  Nil
}

pub fn decimal_compare_transitive_test() -> Nil {
  // Pick three random decimals; the comparison results must be
  // consistent: if a < b and b < c then a < c.
  let prng = Prng(state: 349)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = gen_decimal(p)
    let #(b, p2) = gen_decimal(p1)
    let #(c, p3) = gen_decimal(p2)
    let ab = decimal.compare(a, b)
    let bc = decimal.compare(b, c)
    let ac = decimal.compare(a, c)
    let consistent = case ab, bc, ac {
      order.Lt, order.Lt, order.Lt -> True
      order.Gt, order.Gt, order.Gt -> True
      // Eq breaks the chain in both directions
      order.Eq, _, _ -> True
      _, order.Eq, _ -> True
      // Mixed Lt/Gt — ac is unconstrained by the chain
      order.Lt, order.Gt, _ -> True
      order.Gt, order.Lt, _ -> True
      _, _, _ -> False
    }
    consistent
    |> should.be_true
    p3
  })
  Nil
}

// --- Money: add commutativity, allocate length (randomised) -------------

pub fn money_add_commutative_test() -> Nil {
  let prng = Prng(state: 353)
  iterate(prng, trials, fn(p) {
    let #(a_u, p1) = int_in_range(p, -1_000_000, 1_000_000)
    let #(b_u, p2) = int_in_range(p1, -1_000_000, 1_000_000)
    let a = support.from_minor(a_u, money.usd)
    let b = support.from_minor(b_u, money.usd)
    let assert Ok(ab) = money.add(a, b)
    let assert Ok(ba) = money.add(b, a)
    support.money_equal(ab, ba)
    |> should.be_true
    p2
  })
  Nil
}

pub fn allocate_length_matches_ratios_test() -> Nil {
  let prng = Prng(state: 359)
  iterate(prng, trials, fn(p) {
    let #(units, p1) = int_in_range(p, -1_000_000, 1_000_000)
    let #(n, p2) = int_in_range(p1, 1, 10)
    let ratios = build_ratios(n)
    let money = support.from_minor(units, money.usd)
    let assert Ok(parts) = money.allocate(money, ratios)
    list.length(parts)
    |> should.equal(n)
    p2
  })
  Nil
}

fn build_ratios(n: Int) -> List(Int) {
  build_ratios_loop(n, [])
}

fn build_ratios_loop(n: Int, acc: List(Int)) -> List(Int) {
  case n <= 0 {
    True -> acc
    False -> build_ratios_loop(n - 1, [1, ..acc])
  }
}

// --- Interest / amortisation (randomised) ------------------------------

pub fn simple_interest_linear_in_periods_test() -> Nil {
  // I(P, r, n) + I(P, r, n) == I(P, r, 2n), within rounding tolerance.
  // Issue #25 fix: simple_interest now rescales to exactly `digits`
  // decimal places (so the rendered form honours the precision
  // contract). For the high-magnitude triples this generator can
  // produce (`P * r * 2n` up to ~1e12), padding to 8 decimal places
  // would push the coefficient past `max_safe_coefficient`. The
  // property is only well-defined when both calls succeed — skip
  // the trial otherwise.
  let prng = Prng(state: 367)
  iterate(prng, trials, fn(p) {
    let #(principal, p1) = gen_non_negative_decimal(p)
    let #(rate, p2) = gen_non_negative_decimal(p1)
    let #(periods, p3) = int_in_range(p2, 1, 100)
    case
      interest.simple(principal, rate, periods, 8),
      interest.simple(principal, rate, periods * 2, 8)
    {
      Ok(i_n), Ok(i_2n) -> {
        let assert Ok(double) = decimal.multiply(i_n, support.int(2))
        decimal.equal(
          support.round(double, 6, decimal.HalfEven),
          support.round(i_2n, 6, decimal.HalfEven),
        )
        |> should.be_true
      }
      _, _ -> Nil
    }
    p3
  })
  Nil
}

pub fn ear_freq_one_identity_test() -> Nil {
  // EAR(rate, 1) == rate.
  let prng = Prng(state: 373)
  iterate(prng, trials, fn(p) {
    let #(rate, p1) = gen_non_negative_decimal(p)
    let assert Ok(ear) = interest.effective_annual_rate(rate, 1, 6)
    decimal.equal(support.round(ear, 6, decimal.HalfEven), rate)
    |> should.be_true
    p1
  })
  Nil
}

pub fn fv_rate_zero_equals_principal_test() -> Nil {
  let prng = Prng(state: 379)
  iterate(prng, trials, fn(p) {
    let #(present, p1) = gen_non_negative_decimal(p)
    let #(periods, p2) = int_in_range(p1, 1, 50)
    let assert Ok(fv) =
      interest.future_value(present, decimal.zero(), periods, 6)
    decimal.equal(fv, support.round(present, 6, decimal.HalfEven))
    |> should.be_true
    p2
  })
  Nil
}

pub fn amortization_balance_closes_to_zero_test() -> Nil {
  // The docstring guarantees "closes the final balance to zero exactly".
  let prng = Prng(state: 383)
  iterate(prng, 60, fn(p) {
    let #(principal_int, p1) = int_in_range(p, 1, 1_000_000)
    let principal = support.new(coefficient: principal_int, exponent: 0)
    let #(rate_num, p2) = int_in_range(p1, 1, 500)
    let rate = support.new(coefficient: rate_num, exponent: -4)
    let #(periods, p3) = int_in_range(p2, 1, 30)
    let assert Ok(rows) = interest.schedule(principal, rate, periods, 2)
    let assert Ok(last) = list.last(rows)
    decimal.is_zero(last.balance)
    |> should.be_true
    p3
  })
  Nil
}

pub fn amortization_principal_paid_sums_test() -> Nil {
  let prng = Prng(state: 389)
  iterate(prng, 60, fn(p) {
    let #(principal_int, p1) = int_in_range(p, 1, 100_000)
    let principal = support.new(coefficient: principal_int, exponent: 0)
    let #(rate_num, p2) = int_in_range(p1, 1, 500)
    let rate = support.new(coefficient: rate_num, exponent: -4)
    let #(periods, p3) = int_in_range(p2, 1, 24)
    let assert Ok(rows) = interest.schedule(principal, rate, periods, 2)
    let sum =
      list.fold(rows, decimal.zero(), fn(acc, row) {
        let assert Ok(next) = decimal.add(acc, row.principal_paid)
        next
      })
    decimal.equal(sum, principal)
    |> should.be_true
    p3
  })
  Nil
}

pub fn amortization_balance_monotonic_test() -> Nil {
  let prng = Prng(state: 397)
  iterate(prng, 60, fn(p) {
    let #(principal_int, p1) = int_in_range(p, 1000, 100_000)
    let principal = support.new(coefficient: principal_int, exponent: 0)
    let #(rate_num, p2) = int_in_range(p1, 1, 200)
    let rate = support.new(coefficient: rate_num, exponent: -4)
    let #(periods, p3) = int_in_range(p2, 2, 20)
    let assert Ok(rows) = interest.schedule(principal, rate, periods, 2)
    let balances = list.map(rows, fn(row) { row.balance })
    check_monotonic_nonincreasing(balances)
    p3
  })
  Nil
}

fn check_monotonic_nonincreasing(xs: List(decimal.Decimal)) -> Nil {
  case xs {
    [] -> Nil
    [_] -> Nil
    [a, b, ..rest] -> {
      case decimal.compare(b, a) {
        order.Gt -> should.be_true(False)
        _ -> check_monotonic_nonincreasing([b, ..rest])
      }
    }
  }
}
