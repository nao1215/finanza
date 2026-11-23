//// Helpers for tests whose inputs are known to be in range.

import finanza/decimal.{type Decimal, type RoundingMode}
import finanza/money.{type Currency, type Money}

pub fn new(coefficient coefficient: Int, exponent exponent: Int) -> Decimal {
  let assert Ok(value) = decimal.new(coefficient:, exponent:)
  value
}

pub fn int(value: Int) -> Decimal {
  let assert Ok(value) = decimal.from_int(value)
  value
}

pub fn parse(input: String) -> Decimal {
  let assert Ok(value) = decimal.parse(input)
  value
}

pub fn round(
  value: Decimal,
  digits digits: Int,
  rounding mode: RoundingMode,
) -> Decimal {
  let assert Ok(rounded) = decimal.round(value, digits:, rounding: mode)
  rounded
}

pub fn from_minor(units units: Int, currency currency: Currency) -> Money {
  let assert Ok(value) = money.from_minor(units, in: currency)
  value
}

pub fn from_major(amount: Int, currency: Currency) -> Money {
  let assert Ok(value) = money.from_major(amount, in: currency)
  value
}

pub fn money_equal(a: Money, b: Money) -> Bool {
  a.currency.code == b.currency.code && decimal.equal(a.amount, b.amount)
}
