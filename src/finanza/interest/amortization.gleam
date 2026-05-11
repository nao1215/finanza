//// Amortization schedule generation for an amortising loan.
////
//// The schedule lists, for each period, the periodic payment, the
//// portion of that payment that goes to interest, the portion that
//// reduces principal, and the resulting outstanding balance.

import gleam/bool
import gleam/list
import gleam/result

import finanza/decimal
import finanza/decimal/rounding
import finanza/interest

/// One line of an amortisation schedule. Inspect with the accessors:
/// [`index`](#index), [`payment`](#payment), [`interest`](#interest),
/// [`principal_paid`](#principal_paid), [`balance`](#balance).
pub opaque type Period {
  Period(
    index: Int,
    payment: decimal.Decimal,
    interest: decimal.Decimal,
    principal_paid: decimal.Decimal,
    balance: decimal.Decimal,
  )
}

/// 1-based period number.
pub fn index(p p: Period) -> Int {
  p.index
}

/// Total payment for this period.
pub fn payment(p p: Period) -> decimal.Decimal {
  p.payment
}

/// Interest component of the payment.
pub fn interest(p p: Period) -> decimal.Decimal {
  p.interest
}

/// Principal component of the payment.
pub fn principal_paid(p p: Period) -> decimal.Decimal {
  p.principal_paid
}

/// Remaining balance after this period.
pub fn balance(p p: Period) -> decimal.Decimal {
  p.balance
}

/// Build a full amortisation schedule for an amortising loan.
///
/// Each row in the returned list is a [`Period`](#Period). All
/// monetary values are rounded to `digits` decimal places with
/// `HalfEven`. The final row is adjusted so the outstanding balance
/// closes to zero exactly.
pub fn schedule(
  principal principal: decimal.Decimal,
  rate_per_period rate_per_period: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
) -> Result(List(Period), interest.InterestError) {
  use payment_amount <- result.try(interest.payment(
    principal: principal,
    rate_per_period: rate_per_period,
    periods: periods,
    digits: digits,
  ))
  let initial = ScheduleState(rows: [], balance: principal)
  use built <- result.map(build_schedule(
    payment: payment_amount,
    rate: rate_per_period,
    periods: periods,
    digits: digits,
    index: 1,
    state: initial,
  ))
  list.reverse(built.rows)
}

type ScheduleState {
  ScheduleState(rows: List(Period), balance: decimal.Decimal)
}

fn build_schedule(
  payment payment: decimal.Decimal,
  rate rate: decimal.Decimal,
  periods periods: Int,
  digits digits: Int,
  index index: Int,
  state state: ScheduleState,
) -> Result(ScheduleState, interest.InterestError) {
  use <- bool.guard(when: index > periods, return: Ok(state))
  use raw_interest <- result.try(
    decimal.multiply(state.balance, rate)
    |> result.map_error(interest.ArithmeticError),
  )
  let rounded_interest =
    decimal.round(d: raw_interest, digits: digits, mode: rounding.HalfEven)
  use principal_part <- result.try(
    decimal.subtract(payment, rounded_interest)
    |> result.map_error(interest.ArithmeticError),
  )
  use new_balance <- result.try(
    decimal.subtract(state.balance, principal_part)
    |> result.map_error(interest.ArithmeticError),
  )
  use #(final_payment, final_principal, final_balance) <- result.try(
    finalise_row(
      index: index,
      periods: periods,
      payment: payment,
      principal: principal_part,
      balance: new_balance,
      interest: rounded_interest,
      digits: digits,
    ),
  )
  let row =
    Period(
      index: index,
      payment: final_payment,
      interest: rounded_interest,
      principal_paid: final_principal,
      balance: final_balance,
    )
  build_schedule(
    payment: payment,
    rate: rate,
    periods: periods,
    digits: digits,
    index: index + 1,
    state: ScheduleState(rows: [row, ..state.rows], balance: final_balance),
  )
}

fn finalise_row(
  index index: Int,
  periods periods: Int,
  payment payment: decimal.Decimal,
  principal principal: decimal.Decimal,
  balance balance: decimal.Decimal,
  interest interest: decimal.Decimal,
  digits digits: Int,
) -> Result(
  #(decimal.Decimal, decimal.Decimal, decimal.Decimal),
  interest.InterestError,
) {
  use <- bool.guard(
    when: index != periods,
    return: Ok(#(payment, principal, balance)),
  )
  let target_zero = decimal.new(coefficient: 0, exponent: -digits)
  use adjusted_principal <- result.try(
    decimal.add(principal, balance)
    |> result.map_error(interest.ArithmeticError),
  )
  use adjusted_payment <- result.map(
    decimal.add(interest, adjusted_principal)
    |> result.map_error(interest.ArithmeticError),
  )
  #(adjusted_payment, adjusted_principal, target_zero)
}
