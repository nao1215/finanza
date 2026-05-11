//// dig-bug round 6: extended metamorphic relations.
////
//// A second pass over `finanza` after dig-bug round 3. Round 3 covered
//// canonical round-trips (negate involution, abs sign neutrality,
//// round idempotence, allocate equal-ratio spread, PV/FV round-trip,
//// normalize/validate equivalence, etc.). This round attacks the
//// *algebraic* surface — commutativity, associativity, distributivity,
//// identities — across the full Decimal operator set, plus the
//// arbitrary-ratio sum-preservation property of `currency.allocate`
//// (round 3 only checked equal ratios), plus the strong amortisation
//// invariants the docstring promises ("closes the final balance to
//// zero exactly"), plus parse_expiry / brand-detection / mask edges.
////
//// Every relation here is one that holds independent of specific
//// input values, so each test iterates over a fixed pool of inputs
//// and short-circuits to `should` on the first counterexample.

import gleam/int
import gleam/list
import gleam/order
import gleam/string
import gleeunit/should

import finanza/card
import finanza/currency
import finanza/currency/catalog
import finanza/decimal
import finanza/decimal/rounding
import finanza/interest
import finanza/interest/amortization

// --- Local helpers -------------------------------------------------------

fn d(s: String) -> decimal.Decimal {
  let assert Ok(v) = decimal.from_string(s)
  v
}

// A reasonably diverse pool covering signs, integer / fractional, and
// exponents that force `align` to do real work. All values stay well
// inside the precision window so arithmetic never returns
// `PrecisionExceeded` on the inputs themselves.
fn decimal_pool() -> List(decimal.Decimal) {
  [
    decimal.zero(),
    decimal.one(),
    d("-1"),
    d("0.5"),
    d("-0.5"),
    d("2"),
    d("10"),
    d("0.01"),
    d("-0.01"),
    d("3.14"),
    d("-3.14"),
    d("100"),
    d("0.001"),
    d("12345.6789"),
    d("-9876.5432"),
    d("0.0000001"),
  ]
}

// A smaller pool for cubic-time tests (associativity, distributivity).
fn decimal_small_pool() -> List(decimal.Decimal) {
  [
    decimal.zero(),
    decimal.one(),
    d("-1"),
    d("0.5"),
    d("2"),
    d("0.01"),
    d("100"),
    d("-3.14"),
  ]
}

// Equal in the result-or-error sense: both Ok with equal values, or
// both Error. Mixed outcomes are a counterexample.
fn results_agree(
  a: Result(decimal.Decimal, decimal.ArithmeticError),
  b: Result(decimal.Decimal, decimal.ArithmeticError),
) -> Bool {
  case a, b {
    Ok(x), Ok(y) -> decimal.equal(x, y)
    Error(_), Error(_) -> True
    _, _ -> False
  }
}

// --- Decimal: add commutativity / associativity / identity ---------------

pub fn add_commutativity_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    list.each(decimal_pool(), fn(b) {
      let ab = decimal.add(a, b)
      let ba = decimal.add(b, a)
      results_agree(ab, ba)
      |> should.be_true
    })
  })
}

pub fn add_associativity_test() -> Nil {
  list.each(decimal_small_pool(), fn(a) {
    list.each(decimal_small_pool(), fn(b) {
      list.each(decimal_small_pool(), fn(c) {
        let left = case decimal.add(a, b) {
          Ok(ab) -> decimal.add(ab, c)
          Error(e) -> Error(e)
        }
        let right = case decimal.add(b, c) {
          Ok(bc) -> decimal.add(a, bc)
          Error(e) -> Error(e)
        }
        results_agree(left, right)
        |> should.be_true
      })
    })
  })
}

pub fn add_identity_zero_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    let assert Ok(left) = decimal.add(a, decimal.zero())
    decimal.equal(left, a)
    |> should.be_true
    let assert Ok(right) = decimal.add(decimal.zero(), a)
    decimal.equal(right, a)
    |> should.be_true
  })
}

pub fn subtract_self_is_zero_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    let assert Ok(diff) = decimal.subtract(a, a)
    decimal.equal(diff, decimal.zero())
    |> should.be_true
  })
}

pub fn subtract_antisymmetric_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    list.each(decimal_pool(), fn(b) {
      let ab = decimal.subtract(a, b)
      let ba = decimal.subtract(b, a)
      let negated_ba = case ba {
        Ok(v) -> Ok(decimal.negate(v))
        Error(e) -> Error(e)
      }
      results_agree(ab, negated_ba)
      |> should.be_true
    })
  })
}

// --- Decimal: multiply commutativity / associativity / identity / zero --

pub fn multiply_commutativity_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    list.each(decimal_pool(), fn(b) {
      let ab = decimal.multiply(a, b)
      let ba = decimal.multiply(b, a)
      results_agree(ab, ba)
      |> should.be_true
    })
  })
}

pub fn multiply_identity_one_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    let assert Ok(prod) = decimal.multiply(a, decimal.one())
    decimal.equal(prod, a)
    |> should.be_true
  })
}

pub fn multiply_zero_is_zero_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    let assert Ok(prod) = decimal.multiply(a, decimal.zero())
    decimal.equal(prod, decimal.zero())
    |> should.be_true
  })
}

pub fn multiply_negate_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    list.each(decimal_pool(), fn(b) {
      let left = decimal.multiply(a, decimal.negate(b))
      let right = case decimal.multiply(a, b) {
        Ok(ab) -> Ok(decimal.negate(ab))
        Error(e) -> Error(e)
      }
      results_agree(left, right)
      |> should.be_true
    })
  })
}

pub fn multiply_associativity_test() -> Nil {
  list.each(decimal_small_pool(), fn(a) {
    list.each(decimal_small_pool(), fn(b) {
      list.each(decimal_small_pool(), fn(c) {
        let left = case decimal.multiply(a, b) {
          Ok(ab) -> decimal.multiply(ab, c)
          Error(e) -> Error(e)
        }
        let right = case decimal.multiply(b, c) {
          Ok(bc) -> decimal.multiply(a, bc)
          Error(e) -> Error(e)
        }
        results_agree(left, right)
        |> should.be_true
      })
    })
  })
}

pub fn multiply_distributivity_test() -> Nil {
  list.each(decimal_small_pool(), fn(a) {
    list.each(decimal_small_pool(), fn(b) {
      list.each(decimal_small_pool(), fn(c) {
        let left = case decimal.add(b, c) {
          Ok(bc) -> decimal.multiply(a, bc)
          Error(e) -> Error(e)
        }
        let right = case decimal.multiply(a, b), decimal.multiply(a, c) {
          Ok(ab), Ok(ac) -> decimal.add(ab, ac)
          Error(e), _ -> Error(e)
          _, Error(e) -> Error(e)
        }
        results_agree(left, right)
        |> should.be_true
      })
    })
  })
}

// --- Decimal: compare consistency ---------------------------------------

pub fn compare_antisymmetry_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    list.each(decimal_pool(), fn(b) {
      let ab = decimal.compare(a, b)
      let ba = decimal.compare(b, a)
      let expected = case ab {
        order.Lt -> order.Gt
        order.Gt -> order.Lt
        order.Eq -> order.Eq
      }
      ba
      |> should.equal(expected)
    })
  })
}

pub fn compare_eq_implies_equal_test() -> Nil {
  list.each(decimal_pool(), fn(a) {
    list.each(decimal_pool(), fn(b) {
      let cmp = decimal.compare(a, b)
      let eq = decimal.equal(a, b)
      let consistent = case cmp, eq {
        order.Eq, True -> True
        order.Lt, False -> True
        order.Gt, False -> True
        _, _ -> False
      }
      consistent
      |> should.be_true
    })
  })
}

pub fn compare_transitivity_test() -> Nil {
  let triples = [
    #(d("0"), d("1"), d("2")),
    #(d("-5"), d("0"), d("3.14")),
    #(d("0.1"), d("0.2"), d("0.3")),
    #(d("-100"), d("-50"), d("-10")),
  ]
  list.each(triples, fn(triple) {
    let #(a, b, c) = triple
    let ab = decimal.compare(a, b)
    let bc = decimal.compare(b, c)
    let ac = decimal.compare(a, c)
    let consistent = case ab, bc, ac {
      order.Lt, order.Lt, order.Lt -> True
      order.Gt, order.Gt, order.Gt -> True
      order.Eq, order.Eq, order.Eq -> True
      _, _, _ -> False
    }
    consistent
    |> should.be_true
  })
}

// --- Decimal: truncate sign asymmetry and idempotence -------------------

pub fn truncate_idempotent_test() -> Nil {
  let cases = [
    d("123.456"),
    d("-123.456"),
    d("0.999"),
    d("-0.999"),
    d("1000"),
  ]
  list.each(cases, fn(v) {
    list.each([0, 1, 2, 3], fn(digits) {
      let once = decimal.truncate(v, digits)
      let twice = decimal.truncate(once, digits)
      decimal.equal(once, twice)
      |> should.be_true
    })
  })
}

pub fn truncate_positive_le_input_test() -> Nil {
  let cases = [d("123.456"), d("0.999"), d("0.1"), d("999.999")]
  list.each(cases, fn(v) {
    list.each([0, 1, 2], fn(digits) {
      let t = decimal.truncate(v, digits)
      case decimal.compare(t, v) {
        order.Lt -> Nil
        order.Eq -> Nil
        order.Gt -> should.be_true(False)
      }
    })
  })
}

pub fn truncate_negative_ge_input_test() -> Nil {
  // truncate rounds toward zero. For negatives, that means the
  // truncated value is greater than or equal to the input.
  let cases = [d("-123.456"), d("-0.999"), d("-0.1"), d("-999.999")]
  list.each(cases, fn(v) {
    list.each([0, 1, 2], fn(digits) {
      let t = decimal.truncate(v, digits)
      case decimal.compare(t, v) {
        order.Gt -> Nil
        order.Eq -> Nil
        order.Lt -> should.be_true(False)
      }
    })
  })
}

pub fn round_digits_zero_pattern_test() -> Nil {
  let cases = [
    #(d("3.49"), "3"),
    #(d("3.50"), "4"),
    #(d("3.51"), "4"),
    #(d("-3.49"), "-3"),
    #(d("-3.50"), "-4"),
  ]
  list.each(cases, fn(c) {
    let #(input, expected) = c
    let rounded = decimal.round(input, 0, rounding.HalfUp)
    decimal.to_string(rounded)
    |> should.equal(expected)
  })
}

// --- Currency: allocate sum-preservation for arbitrary ratios -----------

fn allocate_to_units(
  units: Int,
  ratios: List(Int),
  curr: currency.Currency,
) -> Int {
  let m = currency.from_minor(units, curr)
  let assert Ok(parts) = currency.allocate(m, ratios)
  parts
  |> list.map(fn(p) {
    let assert Ok(u) = currency.to_minor(p, rounding.HalfEven)
    u
  })
  |> list.fold(0, int.add)
}

pub fn allocate_sum_preserved_arbitrary_ratios_test() -> Nil {
  let totals = [0, 1, 7, 100, 999, 1234, 10_000, 999_999]
  let ratio_sets = [
    [1, 1, 1],
    [2, 1, 1],
    [3, 2, 1],
    [7, 11, 13],
    [1, 99],
    [99, 1],
    [1, 2, 3, 4, 5],
    [100, 1],
    [1, 100],
    [5, 5, 5, 5],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  ]
  list.each(totals, fn(units) {
    list.each(ratio_sets, fn(ratios) {
      allocate_to_units(units, ratios, catalog.usd())
      |> should.equal(units)
    })
  })
}

pub fn allocate_sum_preserved_negative_test() -> Nil {
  let totals = [-1, -7, -100, -999, -1234, -10_000]
  let ratio_sets = [[1, 1, 1], [3, 2, 1], [7, 11, 13], [1, 99]]
  list.each(totals, fn(units) {
    list.each(ratio_sets, fn(ratios) {
      allocate_to_units(units, ratios, catalog.usd())
      |> should.equal(units)
    })
  })
}

pub fn allocate_sum_preserved_jpy_test() -> Nil {
  // JPY has exponent 0, so to_minor never rounds.
  let totals = [0, 1, 100, 1000, 99_999, -50, -1234]
  let ratio_sets = [[1, 1, 1], [5, 3, 2], [7, 11, 13, 17]]
  list.each(totals, fn(units) {
    list.each(ratio_sets, fn(ratios) {
      allocate_to_units(units, ratios, catalog.jpy())
      |> should.equal(units)
    })
  })
}

pub fn allocate_length_matches_ratios_test() -> Nil {
  let ratio_sets = [
    [1],
    [1, 1],
    [1, 1, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [3, 2, 1],
  ]
  list.each(ratio_sets, fn(ratios) {
    let m = currency.from_minor(1000, catalog.usd())
    let assert Ok(parts) = currency.allocate(m, ratios)
    list.length(parts)
    |> should.equal(list.length(ratios))
  })
}

pub fn allocate_single_ratio_returns_input_test() -> Nil {
  let units_set = [1, 100, 1234, 99_999, -100]
  let k_set = [1, 2, 7, 100]
  list.each(units_set, fn(units) {
    list.each(k_set, fn(k) {
      let m = currency.from_minor(units, catalog.usd())
      let assert Ok(parts) = currency.allocate(m, [k])
      let assert [only] = parts
      let assert Ok(back) = currency.to_minor(only, rounding.HalfEven)
      back
      |> should.equal(units)
    })
  })
}

pub fn allocate_zero_money_yields_zero_parts_test() -> Nil {
  let m = currency.from_minor(0, catalog.usd())
  let ratio_sets = [[1, 1, 1], [7, 3, 5], [1]]
  list.each(ratio_sets, fn(ratios) {
    let assert Ok(parts) = currency.allocate(m, ratios)
    list.each(parts, fn(p) {
      let assert Ok(u) = currency.to_minor(p, rounding.HalfEven)
      u
      |> should.equal(0)
    })
  })
}

pub fn allocate_large_ratios_test() -> Nil {
  let m = currency.from_minor(1_000_000, catalog.usd())
  let ratios = [100_000, 200_000, 300_000, 400_000]
  let assert Ok(parts) = currency.allocate(m, ratios)
  let sum =
    parts
    |> list.map(fn(p) {
      let assert Ok(u) = currency.to_minor(p, rounding.HalfEven)
      u
    })
    |> list.fold(0, int.add)
  sum
  |> should.equal(1_000_000)
}

// --- Money round-trip and arithmetic ------------------------------------

pub fn from_minor_to_minor_round_trip_usd_test() -> Nil {
  let units_set = [
    0, 1, 99, 100, 1234, 99_999, 1_000_000, -1, -100, -1234, -99_999,
  ]
  list.each(units_set, fn(u) {
    let m = currency.from_minor(u, catalog.usd())
    let assert Ok(back) = currency.to_minor(m, rounding.HalfEven)
    back
    |> should.equal(u)
  })
}

pub fn from_minor_to_minor_round_trip_jpy_test() -> Nil {
  let units_set = [0, 1, 100, 9999, -1, -100, -9999]
  list.each(units_set, fn(u) {
    let m = currency.from_minor(u, catalog.jpy())
    let assert Ok(back) = currency.to_minor(m, rounding.HalfEven)
    back
    |> should.equal(u)
  })
}

pub fn money_add_commutativity_test() -> Nil {
  let pairs = [#(100, 200), #(-100, 200), #(0, 0), #(1, 999), #(-1, -999)]
  list.each(pairs, fn(p) {
    let #(a_u, b_u) = p
    let a = currency.from_minor(a_u, catalog.usd())
    let b = currency.from_minor(b_u, catalog.usd())
    let assert Ok(ab) = currency.add(a, b)
    let assert Ok(ba) = currency.add(b, a)
    currency.equal(ab, ba)
    |> should.be_true
  })
}

pub fn money_subtract_self_zero_test() -> Nil {
  let units_set = [0, 1, 100, 999_999, -1, -100]
  list.each(units_set, fn(u) {
    let m = currency.from_minor(u, catalog.usd())
    let assert Ok(diff) = currency.subtract(m, m)
    let assert Ok(back) = currency.to_minor(diff, rounding.HalfEven)
    back
    |> should.equal(0)
  })
}

pub fn money_negate_involution_test() -> Nil {
  let units_set = [0, 1, 100, 999_999, -1, -100]
  list.each(units_set, fn(u) {
    let m = currency.from_minor(u, catalog.usd())
    let twice = currency.negate(currency.negate(m))
    currency.equal(twice, m)
    |> should.be_true
  })
}

pub fn money_multiply_by_one_test() -> Nil {
  let units_set = [0, 1, 100, 999_999, -1, -100]
  list.each(units_set, fn(u) {
    let m = currency.from_minor(u, catalog.usd())
    let assert Ok(prod) = currency.multiply(m, decimal.one())
    currency.equal(prod, m)
    |> should.be_true
  })
}

pub fn money_compare_matches_decimal_test() -> Nil {
  let pairs = [#(100, 200), #(0, 0), #(-100, 100), #(99, 99)]
  list.each(pairs, fn(p) {
    let #(a_u, b_u) = p
    let ma = currency.from_minor(a_u, catalog.usd())
    let mb = currency.from_minor(b_u, catalog.usd())
    let assert Ok(money_cmp) = currency.compare(ma, mb)
    money_cmp
    |> should.equal(int.compare(a_u, b_u))
  })
}

// --- to_minor rounding mode behaviour -----------------------------------

pub fn to_minor_half_even_rounds_to_even_test() -> Nil {
  // 0.005 cents → HalfEven → 0 (last whole cent 0 is even, banker's
  // rule rounds half-to-even).
  let m = currency.new_money(d("0.005"), catalog.usd())
  let assert Ok(units) = currency.to_minor(m, rounding.HalfEven)
  units
  |> should.equal(0)
}

pub fn to_minor_half_up_rounds_away_from_zero_test() -> Nil {
  // 0.005 cents → HalfUp → 1 cent.
  let m = currency.new_money(d("0.005"), catalog.usd())
  let assert Ok(units) = currency.to_minor(m, rounding.HalfUp)
  units
  |> should.equal(1)
}

pub fn to_minor_half_even_15_25_pattern_test() -> Nil {
  // 0.015 → 0.02 (next even), 0.025 → 0.02 (also even).
  let m015 = currency.new_money(d("0.015"), catalog.usd())
  let m025 = currency.new_money(d("0.025"), catalog.usd())
  let assert Ok(u015) = currency.to_minor(m015, rounding.HalfEven)
  u015
  |> should.equal(2)
  let assert Ok(u025) = currency.to_minor(m025, rounding.HalfEven)
  u025
  |> should.equal(2)
}

// --- Interest: identities and zero-rate special cases -------------------

pub fn payment_matches_amortization_first_period_test() -> Nil {
  let cases = [
    #("1000", "0.01", 12, 2),
    #("500", "0.02", 6, 2),
    #("100000", "0.005", 36, 2),
  ]
  list.each(cases, fn(case_) {
    let #(p_in, r_in, n, dg) = case_
    let principal = d(p_in)
    let rate = d(r_in)
    let assert Ok(pmt) = interest.payment(principal, rate, n, dg)
    let assert Ok(rows) = amortization.schedule(principal, rate, n, dg)
    let assert [head, ..] = rows
    decimal.equal(amortization.payment(head), pmt)
    |> should.be_true
  })
}

pub fn ear_freq_one_identity_test() -> Nil {
  let rates = ["0.01", "0.05", "0.10", "0.123"]
  list.each(rates, fn(r_in) {
    let r = d(r_in)
    let assert Ok(ear) = interest.effective_annual_rate(r, 1, 6)
    decimal.equal(decimal.round(ear, 6, rounding.HalfEven), r)
    |> should.be_true
  })
}

pub fn fv_rate_zero_equals_pv_test() -> Nil {
  let principals = ["100", "1000", "12345.67"]
  list.each(principals, fn(p_in) {
    let p = d(p_in)
    let assert Ok(fv) = interest.future_value(p, decimal.zero(), 12, 2)
    decimal.equal(fv, decimal.round(p, 2, rounding.HalfEven))
    |> should.be_true
  })
}

pub fn pv_rate_zero_equals_fv_test() -> Nil {
  let futures = ["100", "1000", "5000"]
  list.each(futures, fn(f_in) {
    let f = d(f_in)
    let assert Ok(pv) = interest.present_value(f, decimal.zero(), 12, 2)
    decimal.equal(pv, decimal.round(f, 2, rounding.HalfEven))
    |> should.be_true
  })
}

pub fn simple_interest_linear_in_periods_test() -> Nil {
  let cases = [#("1000", "0.05"), #("500", "0.01"), #("12345.67", "0.02")]
  list.each(cases, fn(case_) {
    let #(p_in, r_in) = case_
    let p = d(p_in)
    let r = d(r_in)
    let assert Ok(i_n) = interest.simple_interest(p, r, 5, 6)
    let assert Ok(i_2n) = interest.simple_interest(p, r, 10, 6)
    let assert Ok(double) = decimal.multiply(i_n, decimal.from_int(2))
    decimal.equal(
      decimal.round(double, 6, rounding.HalfEven),
      decimal.round(i_2n, 6, rounding.HalfEven),
    )
    |> should.be_true
  })
}

pub fn compound_interest_rate_zero_test() -> Nil {
  let cases = [#("1000", 5), #("12345.67", 3)]
  list.each(cases, fn(case_) {
    let #(p_in, yrs) = case_
    let p = d(p_in)
    let assert Ok(ci) = interest.compound_interest(p, decimal.zero(), yrs, 1, 4)
    decimal.equal(
      decimal.round(ci, 4, rounding.HalfEven),
      decimal.round(p, 4, rounding.HalfEven),
    )
    |> should.be_true
  })
}

// --- Amortisation: docstring invariants ---------------------------------

fn run_schedule(
  principal_str: String,
  rate_str: String,
  periods: Int,
  digits: Int,
) -> List(amortization.Period) {
  let assert Ok(rows) =
    amortization.schedule(d(principal_str), d(rate_str), periods, digits)
  rows
}

pub fn schedule_final_balance_is_zero_test() -> Nil {
  let cases = [
    #("1000", "0.01", 12, 2),
    #("100000", "0.005", 36, 2),
    #("500", "0.02", 6, 2),
    #("1", "0.01", 3, 4),
  ]
  list.each(cases, fn(case_) {
    let #(p, r, n, dg) = case_
    let rows = run_schedule(p, r, n, dg)
    let assert Ok(last) = list.last(rows)
    decimal.is_zero(amortization.balance(last))
    |> should.be_true
  })
}

pub fn schedule_principal_paid_sums_to_principal_test() -> Nil {
  let cases = [
    #("1000", "0.01", 12, 2),
    #("100000", "0.005", 36, 2),
    #("500", "0.02", 6, 2),
    #("1200", "0.01", 24, 4),
  ]
  list.each(cases, fn(case_) {
    let #(p, r, n, dg) = case_
    let principal = d(p)
    let rows = run_schedule(p, r, n, dg)
    let sum =
      list.fold(rows, decimal.zero(), fn(acc, row) {
        let assert Ok(next) = decimal.add(acc, amortization.principal_paid(row))
        next
      })
    decimal.equal(sum, principal)
    |> should.be_true
  })
}

pub fn schedule_balance_monotonic_test() -> Nil {
  let cases = [
    #("1000", "0.01", 12, 2),
    #("500", "0.02", 6, 2),
    #("100000", "0.005", 12, 2),
  ]
  list.each(cases, fn(case_) {
    let #(p, r, n, dg) = case_
    let rows = run_schedule(p, r, n, dg)
    let balances = list.map(rows, amortization.balance)
    check_monotonic_nonincreasing(balances)
  })
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

pub fn schedule_period_indices_consecutive_test() -> Nil {
  let rows = run_schedule("1000", "0.01", 5, 2)
  list.map(rows, amortization.index)
  |> should.equal([1, 2, 3, 4, 5])
}

pub fn schedule_payments_constant_except_last_test() -> Nil {
  let rows = run_schedule("1000", "0.01", 5, 2)
  let assert [head, ..rest] = rows
  let head_pmt = amortization.payment(head)
  let rest_init = drop_last(rest)
  list.each(rest_init, fn(row) {
    decimal.equal(amortization.payment(row), head_pmt)
    |> should.be_true
  })
}

pub fn schedule_single_period_closes_test() -> Nil {
  let assert Ok(rows) = amortization.schedule(d("1000"), d("0.01"), 1, 2)
  list.length(rows)
  |> should.equal(1)
  let assert [only] = rows
  decimal.equal(
    amortization.principal_paid(only),
    decimal.round(d("1000"), 2, rounding.HalfEven),
  )
  |> should.be_true
  decimal.is_zero(amortization.balance(only))
  |> should.be_true
}

fn drop_last(xs: List(a)) -> List(a) {
  let n = list.length(xs)
  case n {
    0 -> []
    _ -> list.take(xs, n - 1)
  }
}

// --- Card: parse_expiry / detect_brand / normalize edges ----------------

pub fn parse_expiry_invalid_month_test() -> Nil {
  let invalids = ["00/28", "13/28", "14/28", "99/28", "00/2028", "13/2028"]
  list.each(invalids, fn(input) {
    case card.parse_expiry(input) {
      Error(_) -> Nil
      Ok(_) -> should.be_true(False)
    }
  })
}

pub fn parse_expiry_short_and_long_year_agree_test() -> Nil {
  let cases = [
    #("01/28", "01/2028"),
    #("12/30", "12/2030"),
    #("06/26", "06/2026"),
  ]
  list.each(cases, fn(p) {
    let #(short, long) = p
    card.parse_expiry(short)
    |> should.equal(card.parse_expiry(long))
  })
}

pub fn parse_expiry_year_zero_consistency_test() -> Nil {
  // Two-digit "00" and four-digit "2000" must map to the same year
  // (whatever the parser chooses, it must be consistent).
  card.parse_expiry("12/00")
  |> should.equal(card.parse_expiry("12/2000"))
}

pub fn expiry_valid_monotonic_in_today_test() -> Nil {
  let expiry = #(12, 2028)
  card.expiry_valid(expiry: expiry, today: #(1, 2026))
  |> should.be_true
  card.expiry_valid(expiry: expiry, today: #(1, 2028))
  |> should.be_true
  card.expiry_valid(expiry: expiry, today: #(12, 2028))
  |> should.be_true
  card.expiry_valid(expiry: expiry, today: #(1, 2029))
  |> should.be_false
}

pub fn detect_brand_mastercard_2_series_test() -> Nil {
  // 2-series Mastercard test PAN (range 2221-2720 per ISO).
  card.brand_to_string(card.detect_brand("2221000000000009"))
  |> should.equal("MASTERCARD")
}

pub fn detect_brand_unionpay_62_prefix_test() -> Nil {
  card.brand_to_string(card.detect_brand("6200000000000005"))
  |> should.equal("UNIONPAY")
}

pub fn detect_brand_empty_input_does_not_crash_test() -> Nil {
  // Any returned brand is fine; the test asserts the call returns.
  let inputs = ["", "   ", "----", "    -  "]
  list.each(inputs, fn(input) {
    let _ = card.detect_brand(input)
    Nil
  })
}

pub fn normalize_idempotent_test() -> Nil {
  let inputs = [
    "4111 1111 1111 1111",
    "5555-5555-5555-4444",
    "  3782 8224 6310 005  ",
    "abc 4111111111111111 def",
    "",
    "1234",
  ]
  list.each(inputs, fn(input) {
    let once = card.normalize(input)
    let twice = card.normalize(once)
    twice
    |> should.equal(once)
  })
}

pub fn luhn_short_inputs_do_not_crash_test() -> Nil {
  let inputs = ["", "0", "1", "12", "123", "1234"]
  list.each(inputs, fn(input) {
    let _ = card.luhn_valid(input)
    Nil
  })
}

pub fn last_four_short_input_errors_test() -> Nil {
  let shorts = ["", "1", "123"]
  list.each(shorts, fn(input) {
    case card.last_four(input) {
      Error(_) -> Nil
      Ok(_) -> should.be_true(False)
    }
  })
}

pub fn bin_short_input_errors_test() -> Nil {
  let shorts = ["", "1", "12345"]
  list.each(shorts, fn(input) {
    case card.bin(input) {
      Error(_) -> Nil
      Ok(_) -> should.be_true(False)
    }
  })
}

pub fn bin_is_prefix_and_last_four_is_suffix_of_normalised_test() -> Nil {
  let pans = [
    "4111 1111 1111 1111",
    "5555-5555-5555-4444",
    "378282246310005",
    "30569309025904",
    "6200000000000005",
  ]
  list.each(pans, fn(pan) {
    let normalised = card.normalize(pan)
    let assert Ok(bin) = card.bin(pan)
    let assert Ok(last4) = card.last_four(pan)
    string.starts_with(normalised, bin)
    |> should.be_true
    string.ends_with(normalised, last4)
    |> should.be_true
  })
}
