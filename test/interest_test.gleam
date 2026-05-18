import gleeunit/should

import finanza/decimal
import finanza/interest
import finanza/interest/amortization

// --- Simple interest -----------------------------------------------------

pub fn simple_interest_basic_test() -> Nil {
  // 100 × 0.05 × 3 = 15
  let assert Ok(p) = decimal.from_string("100")
  let assert Ok(r) = decimal.from_string("0.05")
  let assert Ok(result) =
    interest.simple_interest(principal: p, rate: r, periods: 3, digits: 2)
  decimal.to_string(result)
  |> should.equal("15.00")
}

// Issue #25: simple_interest at zero rate (or any whole-number
// product) used to render without the requested decimal places
// because `decimal.round` is trim-only and never pads. Asserting
// against the rendered form pins the precision contract.
pub fn simple_interest_zero_rate_renders_with_digits_test() -> Nil {
  let p = decimal.from_int(1000)
  let r = decimal.zero()
  let assert Ok(result) =
    interest.simple_interest(principal: p, rate: r, periods: 5, digits: 4)
  decimal.to_string(result)
  |> should.equal("0.0000")
}

pub fn simple_interest_whole_number_result_renders_with_digits_test() -> Nil {
  // 200 × 0.5 × 4 = 400 (exact). Without the fix the result rendered
  // as "400" at digits=2; with rescale it now renders as "400.00".
  let p = decimal.from_int(200)
  let assert Ok(r) = decimal.from_string("0.5")
  let assert Ok(result) =
    interest.simple_interest(principal: p, rate: r, periods: 4, digits: 2)
  decimal.to_string(result)
  |> should.equal("400.00")
}

pub fn simple_interest_rejects_negative_principal_test() -> Nil {
  let assert Ok(p) = decimal.from_string("-100")
  let assert Ok(r) = decimal.from_string("0.05")
  interest.simple_interest(principal: p, rate: r, periods: 1, digits: 2)
  |> should.equal(Error(interest.NegativePrincipal))
}

pub fn simple_interest_rejects_zero_periods_test() -> Nil {
  let assert Ok(p) = decimal.from_string("100")
  let assert Ok(r) = decimal.from_string("0.05")
  interest.simple_interest(principal: p, rate: r, periods: 0, digits: 2)
  |> should.equal(Error(interest.PeriodsOutOfRange))
}

// --- Future / present value ---------------------------------------------

pub fn future_value_test() -> Nil {
  // 1000 × (1.05)^10 ≈ 1628.89
  let assert Ok(pv) = decimal.from_string("1000")
  let assert Ok(rate) = decimal.from_string("0.05")
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
  let assert Ok(fv) = decimal.from_string("1628.89")
  let assert Ok(rate) = decimal.from_string("0.05")
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

pub fn compound_interest_test() -> Nil {
  // 1000 × (1 + 0.05/1)^(1 × 5) = 1276.28
  let assert Ok(p) = decimal.from_string("1000")
  let assert Ok(r) = decimal.from_string("0.05")
  let assert Ok(fv) =
    interest.compound_interest(
      principal: p,
      annual_rate: r,
      years: 5,
      compounds_per_year: 1,
      digits: 2,
    )
  decimal.to_string(fv)
  |> should.equal("1276.28")
}

// --- Effective annual rate ----------------------------------------------

pub fn effective_annual_rate_test() -> Nil {
  // Nominal 12%, monthly compounding: EAR = (1.01)^12 - 1 ≈ 0.126825
  let assert Ok(r) = decimal.from_string("0.12")
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
  let assert Ok(p) = decimal.from_string("1000")
  let assert Ok(r) = decimal.from_string("0.01")
  let assert Ok(pmt) =
    interest.payment(principal: p, rate_per_period: r, periods: 12, digits: 2)
  decimal.to_string(pmt)
  |> should.equal("88.85")
}

pub fn payment_zero_rate_test() -> Nil {
  // Straight-line: 1200 / 12 = 100
  let assert Ok(p) = decimal.from_string("1200")
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

pub fn payment_rejects_negative_rate_test() -> Nil {
  let assert Ok(p) = decimal.from_string("1000")
  let assert Ok(r) = decimal.from_string("-0.01")
  interest.payment(principal: p, rate_per_period: r, periods: 12, digits: 2)
  |> should.equal(Error(interest.NegativeRate))
}

// --- Amortization schedule ----------------------------------------------

pub fn schedule_periods_test() -> Nil {
  let assert Ok(p) = decimal.from_string("1000")
  let assert Ok(r) = decimal.from_string("0.01")
  let assert Ok(rows) =
    amortization.schedule(
      principal: p,
      rate_per_period: r,
      periods: 12,
      digits: 2,
    )
  rows
  |> list_length
  |> should.equal(12)
}

pub fn schedule_closes_to_zero_test() -> Nil {
  // Final balance must be exactly 0.
  let assert Ok(p) = decimal.from_string("1000")
  let assert Ok(r) = decimal.from_string("0.01")
  let assert Ok(rows) =
    amortization.schedule(
      principal: p,
      rate_per_period: r,
      periods: 12,
      digits: 2,
    )
  let assert Ok(last) = list_last(rows)
  decimal.is_zero(amortization.balance(last))
  |> should.be_true
}

pub fn schedule_principal_sum_test() -> Nil {
  // Sum of principal_paid across rows must equal the original principal.
  let assert Ok(p) = decimal.from_string("1000")
  let assert Ok(r) = decimal.from_string("0.01")
  let assert Ok(rows) =
    amortization.schedule(
      principal: p,
      rate_per_period: r,
      periods: 12,
      digits: 2,
    )
  let assert Ok(total) =
    list_fold_result(rows, decimal.zero(), fn(acc, row) {
      decimal.add(acc, amortization.principal_paid(row))
    })
  decimal.equal(total, p)
  |> should.be_true
}

pub fn schedule_first_period_test() -> Nil {
  // First period interest = balance × rate = 1000 × 0.01 = 10.00
  let assert Ok(p) = decimal.from_string("1000")
  let assert Ok(r) = decimal.from_string("0.01")
  let assert Ok(rows) =
    amortization.schedule(
      principal: p,
      rate_per_period: r,
      periods: 12,
      digits: 2,
    )
  let assert Ok(first) = list_first(rows)
  amortization.index(first)
  |> should.equal(1)
  decimal.to_string(amortization.interest(first))
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
