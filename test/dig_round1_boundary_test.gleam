//// dig-bug round 1: boundary-value analysis across all four modules.

import gleam/order
import gleam/string
import gleeunit/should

import finanza/card
import finanza/currency
import finanza/currency/catalog
import finanza/decimal
import finanza/decimal/rounding
import finanza/interest

// --- Decimal boundaries -------------------------------------------------

pub fn parse_just_sign_rejected_test() -> Nil {
  // "+" with no digits must be rejected, not silently accepted as 0.
  decimal.from_string("+")
  |> should.equal(Error(decimal.NoDigits))
}

pub fn parse_just_dot_rejected_test() -> Nil {
  decimal.from_string(".")
  |> should.equal(Error(decimal.NoDigits))
}

pub fn parse_dot_only_with_sign_rejected_test() -> Nil {
  decimal.from_string("-.")
  |> should.equal(Error(decimal.NoDigits))
}

pub fn parse_leading_dot_test() -> Nil {
  let assert Ok(d) = decimal.from_string(".5")
  decimal.to_string(d)
  |> should.equal("0.5")
}

pub fn parse_trailing_dot_test() -> Nil {
  let assert Ok(d) = decimal.from_string("5.")
  decimal.to_string(d)
  |> should.equal("5")
}

pub fn parse_max_safe_test() -> Nil {
  let assert Ok(d) = decimal.from_string("9007199254740991")
  decimal.coefficient(d)
  |> should.equal(9_007_199_254_740_991)
}

pub fn negative_zero_equals_zero_test() -> Nil {
  let assert Ok(neg_zero) = decimal.from_string("-0")
  decimal.equal(neg_zero, decimal.zero())
  |> should.be_true
}

pub fn divide_zero_by_nonzero_test() -> Nil {
  let assert Ok(q) =
    decimal.divide(decimal.zero(), decimal.one(), 2, rounding.HalfEven)
  decimal.is_zero(q)
  |> should.be_true
  decimal.to_string(q)
  |> should.equal("0.00")
}

pub fn divide_zero_by_zero_test() -> Nil {
  decimal.divide(decimal.zero(), decimal.zero(), 2, rounding.HalfEven)
  |> should.equal(Error(decimal.DivisionByZero))
}

pub fn round_to_zero_digits_test() -> Nil {
  let value = decimal.new(coefficient: 1234, exponent: -2)
  // 12.34 -> 12 at 0 dp.
  decimal.round(value, 0, rounding.HalfEven)
  |> decimal.to_string
  |> should.equal("12")
}

pub fn round_to_negative_digits_test() -> Nil {
  let value = decimal.new(coefficient: 15, exponent: 0)
  // 15 rounded to tens place (digits = -1, target_exp = 1).
  // HalfEven: 1.5 ties; 2 is even → 2 (i.e. 20).
  decimal.round(value, -1, rounding.HalfEven)
  |> decimal.to_string
  |> should.equal("20")
}

pub fn round_zero_at_any_precision_test() -> Nil {
  decimal.round(decimal.zero(), 4, rounding.HalfEven)
  |> decimal.is_zero
  |> should.be_true
}

pub fn compare_zero_to_negative_zero_test() -> Nil {
  let assert Ok(neg_zero) = decimal.from_string("-0")
  decimal.compare(neg_zero, decimal.zero())
  |> should.equal(order.Eq)
}

pub fn add_positive_to_negative_yielding_zero_test() -> Nil {
  let a = decimal.from_int(5)
  let b = decimal.negate(decimal.from_int(5))
  let assert Ok(sum) = decimal.add(a, b)
  decimal.is_zero(sum)
  |> should.be_true
}

// --- Currency boundaries ------------------------------------------------

pub fn currency_zero_exponent_test() -> Nil {
  let assert Ok(c) =
    currency.new_currency(code: "JPY", exponent: 0, symbol: "¥", name: "Yen")
  currency.exponent(c)
  |> should.equal(0)
}

pub fn currency_exponent_eight_test() -> Nil {
  // Highest accepted exponent per the validator. Synthetic crypto-style.
  let assert Ok(c) =
    currency.new_currency(
      code: "SAT",
      exponent: 8,
      symbol: "₿",
      name: "Satoshi",
    )
  currency.exponent(c)
  |> should.equal(8)
}

pub fn currency_exponent_nine_rejected_test() -> Nil {
  currency.new_currency(code: "XXX", exponent: 9, symbol: "?", name: "Bad")
  |> should.equal(Error(currency.InvalidExponent))
}

pub fn from_minor_zero_test() -> Nil {
  let m = currency.from_minor(0, catalog.usd())
  currency.format(m, currency.default_format())
  |> should.equal("$0.00")
}

pub fn from_minor_negative_test() -> Nil {
  let m = currency.from_minor(-1234, catalog.usd())
  currency.format(m, currency.default_format())
  |> should.equal("-$12.34")
}

pub fn allocate_single_ratio_test() -> Nil {
  let bill = currency.from_minor(1234, catalog.usd())
  let assert Ok(parts) = currency.allocate(bill, [1])
  let assert [only] = parts
  let assert Ok(units) = currency.to_minor(only, rounding.HalfEven)
  units
  |> should.equal(1234)
}

pub fn allocate_one_to_each_zero_amount_test() -> Nil {
  // Zero money split N ways → N zero parts.
  let bill = currency.from_minor(0, catalog.usd())
  let assert Ok(parts) = currency.allocate(bill, [1, 1, 1])
  parts
  |> list_all(fn(p) {
    let assert Ok(u) = currency.to_minor(p, rounding.HalfEven)
    u == 0
  })
  |> should.be_true
}

pub fn allocate_negative_amount_test() -> Nil {
  // Negative bill (refund) should split with sign preserved.
  let bill = currency.from_minor(-1000, catalog.usd())
  let assert Ok(parts) = currency.allocate(bill, [1, 1, 1])
  let units =
    parts
    |> list_map(fn(p) {
      let assert Ok(u) = currency.to_minor(p, rounding.HalfEven)
      u
    })
  // Each part should be negative.
  units
  |> list_all(fn(u) { u < 0 })
  |> should.be_true
  // The remainder of -1 should be distributed somewhere.
  let total = list_sum(units)
  total
  |> should.equal(-1000)
}

// --- Interest boundaries ------------------------------------------------

pub fn simple_interest_zero_principal_test() -> Nil {
  let assert Ok(i) =
    interest.simple_interest(
      principal: decimal.zero(),
      rate: decimal.from_int(1),
      periods: 12,
      digits: 2,
    )
  decimal.is_zero(i)
  |> should.be_true
}

pub fn payment_zero_principal_test() -> Nil {
  let assert Ok(pmt) =
    interest.payment(
      principal: decimal.zero(),
      rate_per_period: decimal.zero(),
      periods: 12,
      digits: 2,
    )
  decimal.is_zero(pmt)
  |> should.be_true
}

pub fn payment_periods_one_test() -> Nil {
  // Loan with 1 period: PMT = principal × (1 + r). For r = 0, PMT == principal.
  let assert Ok(p) = decimal.from_string("100")
  let assert Ok(pmt) =
    interest.payment(
      principal: p,
      rate_per_period: decimal.zero(),
      periods: 1,
      digits: 2,
    )
  decimal.to_string(pmt)
  |> should.equal("100.00")
}

pub fn payment_periods_zero_rejected_test() -> Nil {
  let assert Ok(p) = decimal.from_string("100")
  interest.payment(
    principal: p,
    rate_per_period: decimal.zero(),
    periods: 0,
    digits: 2,
  )
  |> should.equal(Error(interest.PeriodsOutOfRange))
}

pub fn payment_periods_max_test() -> Nil {
  // 1200 is the documented maximum.
  let assert Ok(p) = decimal.from_string("100")
  let assert Ok(_) =
    interest.payment(
      principal: p,
      rate_per_period: decimal.zero(),
      periods: 1200,
      digits: 2,
    )
  Nil
}

pub fn payment_periods_1201_rejected_test() -> Nil {
  let assert Ok(p) = decimal.from_string("100")
  interest.payment(
    principal: p,
    rate_per_period: decimal.zero(),
    periods: 1201,
    digits: 2,
  )
  |> should.equal(Error(interest.PeriodsOutOfRange))
}

pub fn payment_negative_digits_rejected_test() -> Nil {
  let assert Ok(p) = decimal.from_string("100")
  interest.payment(
    principal: p,
    rate_per_period: decimal.zero(),
    periods: 12,
    digits: -1,
  )
  |> should.equal(Error(interest.NegativeDigits))
}

// --- Card boundaries ----------------------------------------------------

pub fn luhn_single_zero_test() -> Nil {
  // "0" has sum 0; 0 % 10 == 0 → Luhn-valid. Degenerate but consistent.
  card.luhn_valid("0")
  |> should.be_true
}

pub fn validate_all_zeros_16_test() -> Nil {
  // 16 zeros: Luhn passes (sum=0) but no brand matches → UnknownBrand.
  card.validate("0000000000000000")
  |> should.equal(Error(card.UnknownBrand))
}

pub fn validate_short_pan_test() -> Nil {
  card.validate("12345678901")
  |> should.equal(Error(card.InvalidLength(length: 11)))
}

pub fn validate_long_pan_test() -> Nil {
  let too_long = "12345678901234567890"
  card.validate(too_long)
  |> should.equal(Error(card.InvalidLength(length: 20)))
}

pub fn validate_pan_with_only_separators_test() -> Nil {
  card.validate(" - -- ")
  |> should.equal(Error(card.EmptyInput))
}

pub fn mask_when_keep_exceeds_length_test() -> Nil {
  // keep_first=4, keep_last=4 with a 5-digit input: keep_first clamps,
  // keep_last clamps to remaining length, mask block is empty.
  // Should not crash; should keep everything visible.
  let assert Ok(masked) = card.mask("12345", card.mask_defaults())
  string.contains(masked, "*")
  |> should.be_false
}

pub fn last_four_short_pan_test() -> Nil {
  card.last_four("123")
  |> should.equal(Error(card.InvalidLength(length: 3)))
}

pub fn bin_short_pan_test() -> Nil {
  card.bin("12345")
  |> should.equal(Error(card.InvalidLength(length: 5)))
}

pub fn parse_expiry_just_slash_test() -> Nil {
  card.parse_expiry("/")
  |> should.equal(Error(card.InvalidExpiry))
}

pub fn parse_expiry_empty_test() -> Nil {
  card.parse_expiry("")
  |> should.equal(Error(card.InvalidExpiry))
}

pub fn parse_expiry_month_zero_test() -> Nil {
  card.parse_expiry("0/28")
  |> should.equal(Error(card.InvalidExpiry))
}

pub fn expiry_year_zero_test() -> Nil {
  card.expiry_valid(month: 1, year: 0, today_year: 2026, today_month: 5)
  |> should.be_false
}

// --- Helpers ------------------------------------------------------------

fn list_all(items: List(a), f: fn(a) -> Bool) -> Bool {
  case items {
    [] -> True
    [head, ..rest] ->
      case f(head) {
        True -> list_all(rest, f)
        False -> False
      }
  }
}

fn list_map(items: List(a), f: fn(a) -> b) -> List(b) {
  case items {
    [] -> []
    [head, ..rest] -> [f(head), ..list_map(rest, f)]
  }
}

fn list_sum(items: List(Int)) -> Int {
  case items {
    [] -> 0
    [head, ..rest] -> head + list_sum(rest)
  }
}
