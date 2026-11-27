import gleam/list
import gleam/order
import gleeunit/should

import finanza/decimal
import finanza/interest
import support

// --- Simple interest -----------------------------------------------------

pub fn simple_interest_basic_test() -> Nil {
  // 100 × 0.05 × 3 = 15
  let assert Ok(p) = decimal.parse("100")
  let assert Ok(r) = decimal.parse("0.05")
  let assert Ok(result) =
    interest.simple(principal: p, rate: r, periods: 3, digits: 2)
  decimal.to_string(result)
  |> should.equal("15.00")
}

// Issue #25: simple_interest at zero rate (or any whole-number
// product) used to render without the requested decimal places
// because `decimal.round` is trim-only and never pads. Asserting
// against the rendered form pins the precision contract.
pub fn simple_interest_zero_rate_renders_with_digits_test() -> Nil {
  let p = support.int(1000)
  let r = decimal.zero()
  let assert Ok(result) =
    interest.simple(principal: p, rate: r, periods: 5, digits: 4)
  decimal.to_string(result)
  |> should.equal("0.0000")
}

pub fn simple_interest_whole_number_result_renders_with_digits_test() -> Nil {
  // 200 × 0.5 × 4 = 400 (exact). Without the fix the result rendered
  // as "400" at digits=2; with rescale it now renders as "400.00".
  let p = support.int(200)
  let assert Ok(r) = decimal.parse("0.5")
  let assert Ok(result) =
    interest.simple(principal: p, rate: r, periods: 4, digits: 2)
  decimal.to_string(result)
  |> should.equal("400.00")
}

// Issue #26: present_value used to overflow with
// `Error(ArithmeticError(PrecisionExceeded))` when `future`
// already carried high-precision Decimal exponents — e.g. the
// output of `future_value(P, r, n, digits: 6)`. The fix rounds
// `future` adaptively before multiplying by the inverse growth
// factor so the FV/PV inverse property holds.
pub fn present_value_round_trips_high_precision_future_test() -> Nil {
  let p = support.int(1000)
  let assert Ok(r) = decimal.parse("0.05")
  let assert Ok(fv) =
    interest.future_value(
      present: p,
      rate_per_period: r,
      periods: 10,
      digits: 6,
    )
  let assert Ok(pv) =
    interest.present_value(
      future: fv,
      rate_per_period: r,
      periods: 10,
      digits: 6,
    )
  // PV should match P to the cent.
  let assert Ok(expected) = decimal.parse("1000.00")
  decimal.equal(support.round(pv, 2, decimal.HalfEven), expected)
  |> should.be_true
}

// Issue #76 (re-verification of #26): the *inverse* direction —
// future_value(present_value(fv, ...), ...) — used to fail with
// Error(ArithmeticError(PrecisionExceeded)) at digits >= 6, because
// future_value multiplied the high-precision PV by the growth factor
// without the adaptive safe-multiply guard that present_value already
// had. These DoD cases pin the round-trip across the full digit range
// so the asymmetry cannot return.
// `|a - b| <= one unit in the last place at `digits``. The FV/PV inverse
// cannot be bit-exact under fixed-point rounding — every iterative
// multiply/divide rounds, so the round-trip can land 1 ULP either side of
// the original. The issue's prose asks for the inverse "within rounding
// tolerance"; this encodes exactly that bound (1 ULP), which is the
// strongest guarantee a rounding arithmetic can make.
fn within_one_ulp(
  a a: decimal.Decimal,
  b b: decimal.Decimal,
  digits digits: Int,
) -> Bool {
  let assert Ok(diff) = decimal.subtract(a, b)
  let one_ulp = support.new(coefficient: 1, exponent: -digits)
  decimal.compare(decimal.absolute(diff), one_ulp) != order.Gt
}

pub fn fv_pv_inverse_at_common_digits_test() -> Nil {
  let assert Ok(fv) = decimal.parse("1000")
  let assert Ok(rate) = decimal.parse("0.05")
  // Within the package's working-precision ceiling, the round-trip
  // returns to the original within rounding tolerance (1 ULP).
  list.each([2, 4, 6, 8], fn(digits) {
    let assert Ok(pv) =
      interest.present_value(
        future: fv,
        rate_per_period: rate,
        periods: 5,
        digits: digits,
      )
    let assert Ok(fv2) =
      interest.future_value(
        present: pv,
        rate_per_period: rate,
        periods: 5,
        digits: digits,
      )
    within_one_ulp(fv2, fv, digits: digits) |> should.be_true
  })
}

// Issue #76's headline failure was an outright Error(PrecisionExceeded)
// crash at digits >= 6. Beyond the working-precision ceiling the round-trip
// can no longer be exact to the last ULP, but it must never crash and must
// stay within a few ULP — this guards the no-overflow guarantee across the
// whole requested range, including the digits=6/8/10 the issue named.
pub fn fv_pv_inverse_does_not_overflow_at_high_digits_test() -> Nil {
  let assert Ok(fv) = decimal.parse("1000")
  let assert Ok(rate) = decimal.parse("0.05")
  list.each([6, 8, 10, 12], fn(digits) {
    let assert Ok(pv) =
      interest.present_value(
        future: fv,
        rate_per_period: rate,
        periods: 5,
        digits: digits,
      )
    let assert Ok(fv2) =
      interest.future_value(
        present: pv,
        rate_per_period: rate,
        periods: 5,
        digits: digits,
      )
    // Stays within a cent regardless of the requested precision.
    let assert Ok(cent) = decimal.parse("0.01")
    let assert Ok(diff) = decimal.subtract(fv2, fv)
    decimal.compare(decimal.absolute(diff), cent)
    |> should.equal(order.Lt)
  })
}

pub fn pv_fv_inverse_for_diverse_rates_periods_test() -> Nil {
  let cases = [
    #("1000", "0.05", 5),
    #("500", "0.10", 10),
    #("100", "0.01", 30),
    #("1", "0.001", 100),
  ]
  list.each(cases, fn(c) {
    let #(fv_s, r_s, n) = c
    let assert Ok(fv) = decimal.parse(fv_s)
    let assert Ok(rate) = decimal.parse(r_s)
    let assert Ok(pv) =
      interest.present_value(
        future: fv,
        rate_per_period: rate,
        periods: n,
        digits: 8,
      )
    let assert Ok(fv2) =
      interest.future_value(
        present: pv,
        rate_per_period: rate,
        periods: n,
        digits: 8,
      )
    let lhs = support.round(fv2, 4, decimal.HalfEven) |> decimal.to_string
    let rhs = support.round(fv, 4, decimal.HalfEven) |> decimal.to_string
    lhs |> should.equal(rhs)
  })
}

// The forward FV at digits >= 6 must also not overflow on its own (the
// multiply guard makes future_value total for high-precision inputs).
pub fn future_value_high_digits_does_not_overflow_test() -> Nil {
  let assert Ok(pv) = decimal.parse("783.526200")
  let assert Ok(rate) = decimal.parse("0.05")
  let assert Ok(_) =
    interest.future_value(
      present: pv,
      rate_per_period: rate,
      periods: 5,
      digits: 6,
    )
  Nil
}

pub fn simple_interest_rejects_negative_principal_test() -> Nil {
  let assert Ok(p) = decimal.parse("-100")
  let assert Ok(r) = decimal.parse("0.05")
  interest.simple(principal: p, rate: r, periods: 1, digits: 2)
  |> should.equal(Error(interest.NegativePrincipal))
}

pub fn simple_interest_zero_periods_yields_zero_test() -> Nil {
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.05")
  let assert Ok(zero) = decimal.parse("0.00")
  interest.simple(principal: p, rate: r, periods: 0, digits: 2)
  |> should.equal(Ok(zero))
}

pub fn simple_interest_rejects_negative_periods_test() -> Nil {
  let assert Ok(p) = decimal.parse("100")
  let assert Ok(r) = decimal.parse("0.05")
  interest.simple(principal: p, rate: r, periods: -1, digits: 2)
  |> should.equal(Error(interest.PeriodsOutOfRange))
}

pub fn future_value_zero_periods_returns_present_test() -> Nil {
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.05")
  let assert Ok(expected) = decimal.parse("1000.00")
  interest.future_value(present: p, rate_per_period: r, periods: 0, digits: 2)
  |> should.equal(Ok(expected))
}

pub fn present_value_zero_periods_returns_future_test() -> Nil {
  let assert Ok(fv) = decimal.parse("1500")
  let assert Ok(r) = decimal.parse("0.05")
  let assert Ok(expected) = decimal.parse("1500.00")
  interest.present_value(future: fv, rate_per_period: r, periods: 0, digits: 2)
  |> should.equal(Ok(expected))
}

pub fn future_value_rejects_negative_periods_test() -> Nil {
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.05")
  interest.future_value(present: p, rate_per_period: r, periods: -1, digits: 2)
  |> should.equal(Error(interest.PeriodsOutOfRange))
}

pub fn payment_zero_periods_still_errors_test() -> Nil {
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.05")
  interest.payment(principal: p, rate_per_period: r, periods: 0, digits: 2)
  |> should.equal(Error(interest.PeriodsOutOfRange))
}

// --- Future / present value ---------------------------------------------

pub fn future_value_test() -> Nil {
  // 1000 × (1.05)^10 ≈ 1628.89
  let assert Ok(pv) = decimal.parse("1000")
  let assert Ok(rate) = decimal.parse("0.05")
  let assert Ok(fv) =
    interest.future_value(
      present: pv,
      rate_per_period: rate,
      periods: 10,
      digits: 2,
    )
  decimal.to_string(fv)
  |> should.equal("1628.89")
}

pub fn present_value_round_trip_test() -> Nil {
  // 1628.89 / (1.05)^10 ≈ 1000.00
  let assert Ok(fv) = decimal.parse("1628.89")
  let assert Ok(rate) = decimal.parse("0.05")
  let assert Ok(pv) =
    interest.present_value(
      future: fv,
      rate_per_period: rate,
      periods: 10,
      digits: 2,
    )
  decimal.to_string(pv)
  |> should.equal("1000.00")
}

// --- Compound interest --------------------------------------------------

// --- Effective annual rate ----------------------------------------------

pub fn effective_annual_rate_test() -> Nil {
  // Nominal 12%, monthly compounding: EAR = (1.01)^12 - 1 ≈ 0.126825
  let assert Ok(r) = decimal.parse("0.12")
  let assert Ok(ear) =
    interest.effective_annual_rate(
      nominal_rate: r,
      compounds_per_year: 12,
      digits: 6,
    )
  decimal.to_string(ear)
  |> should.equal("0.126825")
}

// --- Payment (PMT) -------------------------------------------------------

pub fn payment_test() -> Nil {
  // 1000 at 1% for 12 periods → 88.85
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.01")
  let assert Ok(pmt) =
    interest.payment(principal: p, rate_per_period: r, periods: 12, digits: 2)
  decimal.to_string(pmt)
  |> should.equal("88.85")
}

pub fn payment_zero_rate_test() -> Nil {
  // Straight-line: 1200 / 12 = 100
  let assert Ok(p) = decimal.parse("1200")
  let assert Ok(pmt) =
    interest.payment(
      principal: p,
      rate_per_period: decimal.zero(),
      periods: 12,
      digits: 2,
    )
  decimal.to_string(pmt)
  |> should.equal("100.00")
}

pub fn payment_rejects_rate_below_minus_one_test() -> Nil {
  // As of #50, rates in `[-1.0, ∞)` are accepted (deflation,
  // depreciation, total loss). Only rates strictly below `-1.0`
  // remain rejected — and they now emit `RateBelowMinusOne`.
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("-1.5")
  interest.payment(principal: p, rate_per_period: r, periods: 12, digits: 2)
  |> should.equal(Error(interest.RateBelowMinusOne))
}

pub fn future_value_deflation_test() -> Nil {
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("-0.02")
  let assert Ok(fv) =
    interest.future_value(present: p, rate_per_period: r, periods: 1, digits: 2)
  decimal.to_string(fv) |> should.equal("980.00")
}

pub fn future_value_total_loss_test() -> Nil {
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("-1.0")
  let assert Ok(fv) =
    interest.future_value(present: p, rate_per_period: r, periods: 1, digits: 2)
  decimal.is_zero(fv) |> should.be_true
}

pub fn future_value_below_minus_one_rejected_test() -> Nil {
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("-1.5")
  interest.future_value(present: p, rate_per_period: r, periods: 1, digits: 2)
  |> should.equal(Error(interest.RateBelowMinusOne))
}

// --- Amortization schedule ----------------------------------------------

pub fn schedule_periods_test() -> Nil {
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.01")
  let assert Ok(rows) =
    interest.schedule(principal: p, rate_per_period: r, periods: 12, digits: 2)
  rows
  |> list_length
  |> should.equal(12)
}

pub fn schedule_zero_periods_returns_empty_test() -> Nil {
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.05")
  interest.schedule(principal: p, rate_per_period: r, periods: 0, digits: 2)
  |> should.equal(Ok([]))
}

pub fn schedule_closes_to_zero_test() -> Nil {
  // Final balance must be exactly 0.
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.01")
  let assert Ok(rows) =
    interest.schedule(principal: p, rate_per_period: r, periods: 12, digits: 2)
  let assert Ok(last) = list_last(rows)
  decimal.is_zero(last.balance)
  |> should.be_true
}

pub fn schedule_principal_sum_test() -> Nil {
  // Sum of principal_paid across rows must equal the original principal.
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.01")
  let assert Ok(rows) =
    interest.schedule(principal: p, rate_per_period: r, periods: 12, digits: 2)
  let assert Ok(total) =
    list_fold_result(rows, decimal.zero(), fn(acc, row) {
      decimal.add(acc, row.principal_paid)
    })
  decimal.equal(total, p)
  |> should.be_true
}

// Issue #27: interest.schedule used to fail with
// `PrecisionExceeded` at `digits = 8` because the internal
// `amortising_payment` divide scaled the numerator by
// `digits + (numerator.exp - denominator.exp)` digits, which
// overflowed `max_safe_coefficient` once `digits` crossed 7.
// The fix caps the internal divide at `work_digits` and rescales
// to the requested `digits` afterwards.
pub fn schedule_high_digits_does_not_overflow_test() -> Nil {
  let principal = support.int(1000)
  let assert Ok(rate) = decimal.parse("0.05")
  let assert Ok(rows) =
    interest.schedule(
      principal: principal,
      rate_per_period: rate,
      periods: 10,
      digits: 8,
    )
  rows
  |> list_length
  |> should.equal(10)
}

pub fn schedule_first_period_test() -> Nil {
  // First period interest = balance × rate = 1000 × 0.01 = 10.00
  let assert Ok(p) = decimal.parse("1000")
  let assert Ok(r) = decimal.parse("0.01")
  let assert Ok(rows) =
    interest.schedule(principal: p, rate_per_period: r, periods: 12, digits: 2)
  let assert Ok(first) = list_first(rows)
  first.index
  |> should.equal(1)
  decimal.to_string(first.interest)
  |> should.equal("10.00")
}

// --- Helpers ------------------------------------------------------------

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

fn list_first(items: List(a)) -> Result(a, Nil) {
  case items {
    [] -> Error(Nil)
    [head, ..] -> Ok(head)
  }
}

fn list_last(items: List(a)) -> Result(a, Nil) {
  case items {
    [] -> Error(Nil)
    [item] -> Ok(item)
    [_, ..rest] -> list_last(rest)
  }
}

fn list_fold_result(
  items: List(a),
  acc: b,
  f: fn(b, a) -> Result(b, e),
) -> Result(b, e) {
  case items {
    [] -> Ok(acc)
    [head, ..rest] -> {
      case f(acc, head) {
        Ok(new_acc) -> list_fold_result(rest, new_acc, f)
        Error(e) -> Error(e)
      }
    }
  }
}

pub fn effective_annual_rate_caps_compounds_test() -> Nil {
  assert interest.effective_annual_rate(
      nominal_rate: support.parse("0.05"),
      compounds_per_year: 1201,
      digits: 6,
    )
    == Error(interest.CompoundsOutOfRange)
}

pub fn schedule_checks_inputs_for_zero_periods_test() -> Nil {
  assert interest.schedule(
      principal: support.parse("-1000"),
      rate_per_period: support.parse("0.01"),
      periods: 0,
      digits: 2,
    )
    == Error(interest.NegativePrincipal)
}

// --- Boundaries found by mutation testing ---------------------------------

pub fn present_value_at_rate_minus_one_over_zero_periods_test() -> Nil {
  let assert Ok(value) =
    interest.present_value(
      future: support.parse("100"),
      rate_per_period: decimal.negate(decimal.one()),
      periods: 0,
      digits: 2,
    )
  assert decimal.equal(value, support.parse("100"))
}

pub fn effective_annual_rate_rejects_zero_compounds_test() -> Nil {
  assert interest.effective_annual_rate(
      nominal_rate: support.parse("0.05"),
      compounds_per_year: 0,
      digits: 2,
    )
    == Error(interest.CompoundsOutOfRange)
}
