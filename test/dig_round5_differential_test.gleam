//// dig-bug round 5: differential testing.
////
//// Each test compares finanza output against a value sourced from
//// an authoritative external implementation or specification:
////
//// - Python `decimal` module (PEP 327 / IBM Decimal spec)
//// - numpy-financial `pmt`/`fv`/`pv` (BSD-3-Clause)
//// - Microsoft Excel financial function documentation
//// - Wikipedia Luhn algorithm example
//// - Stripe / Braintree published test PANs
////
//// References are cited in comments next to each case so the source
//// of truth is auditable.

import gleam/list
import gleeunit/should

import finanza/card
import finanza/decimal
import finanza/decimal/rounding
import finanza/interest

// --- Decimal vs Python decimal ------------------------------------------

pub fn add_vs_python_decimal_test() -> Nil {
  // Python: Decimal('0.1') + Decimal('0.2') == Decimal('0.3') (exact).
  // This is the canonical case that fails under IEEE 754 floats.
  let assert Ok(a) = decimal.from_string("0.1")
  let assert Ok(b) = decimal.from_string("0.2")
  let assert Ok(sum) = decimal.add(a, b)
  decimal.to_string(sum)
  |> should.equal("0.3")
}

pub fn multiply_vs_python_decimal_test() -> Nil {
  // Python: Decimal('1.1') * Decimal('1.1') == Decimal('1.21').
  let assert Ok(a) = decimal.from_string("1.1")
  let assert Ok(b) = decimal.from_string("1.1")
  let assert Ok(prod) = decimal.multiply(a, b)
  decimal.to_string(prod)
  |> should.equal("1.21")
}

pub fn divide_vs_python_decimal_test() -> Nil {
  // Python: Decimal('1') / Decimal('3') quantised to 6 dp = Decimal('0.333333').
  let assert Ok(a) = decimal.from_string("1")
  let assert Ok(b) = decimal.from_string("3")
  let assert Ok(q) = decimal.divide(a, b, 6, rounding.HalfEven)
  decimal.to_string(q)
  |> should.equal("0.333333")
}

pub fn round_half_even_vs_python_test() -> Nil {
  // IBM Decimal spec banker's rounding test vectors:
  // 0.5  -> 0   (even)
  // 1.5  -> 2   (even)
  // 2.5  -> 2   (even)
  // 3.5  -> 4   (even)
  // -2.5 -> -2  (even)
  let cases = [
    #("0.5", "0"),
    #("1.5", "2"),
    #("2.5", "2"),
    #("3.5", "4"),
    #("-2.5", "-2"),
  ]
  list.each(cases, fn(case_) {
    let #(input, expected) = case_
    let assert Ok(d) = decimal.from_string(input)
    decimal.round(d, 0, rounding.HalfEven)
    |> decimal.to_string
    |> should.equal(expected)
  })
}

pub fn round_half_up_vs_python_test() -> Nil {
  // ROUND_HALF_UP test vectors from Python decimal docs:
  // 1.5  -> 2
  // 2.5  -> 3
  // -2.5 -> -3   (away from zero)
  let cases = [
    #("1.5", "2"),
    #("2.5", "3"),
    #("-2.5", "-3"),
  ]
  list.each(cases, fn(case_) {
    let #(input, expected) = case_
    let assert Ok(d) = decimal.from_string(input)
    decimal.round(d, 0, rounding.HalfUp)
    |> decimal.to_string
    |> should.equal(expected)
  })
}

pub fn rounding_money_examples_test() -> Nil {
  // Common penny-rounding cases that have caused bugs in fintech systems
  // (round-half-even is the canonical "GAAP" behaviour for money).
  // Computed against Python's decimal.Context(rounding=ROUND_HALF_EVEN).
  let cases = [
    #("1.005", "1.00"),
    #("1.015", "1.02"),
    #("1.025", "1.02"),
    #("1.035", "1.04"),
    #("1.045", "1.04"),
    #("1.055", "1.06"),
  ]
  list.each(cases, fn(case_) {
    let #(input, expected) = case_
    let assert Ok(d) = decimal.from_string(input)
    decimal.round(d, 2, rounding.HalfEven)
    |> decimal.to_string
    |> should.equal(expected)
  })
}

// --- Interest vs numpy-financial / Excel ---------------------------------

pub fn pmt_vs_excel_30y_fixed_6pct_test() -> Nil {
  // Excel: PMT(0.06/12, 360, -200000) = $1199.10  (rounded to 2 dp).
  // Cross-referenced against numpy_financial.pmt(0.005, 360, -200000).
  let assert Ok(p) = decimal.from_string("200000")
  let assert Ok(r) = decimal.from_string("0.005")
  let assert Ok(pmt) = interest.payment(p, r, 360, 2)
  decimal.to_string(pmt)
  |> should.equal("1199.10")
}

pub fn fv_vs_textbook_test() -> Nil {
  // Textbook: $1000 invested at 5% annually for 10 years yields $1628.89.
  // numpy_financial.fv(0.05, 10, 0, -1000) → 1628.894626...
  let assert Ok(pv) = decimal.from_string("1000")
  let assert Ok(r) = decimal.from_string("0.05")
  let assert Ok(fv) = interest.future_value(pv, r, 10, 2)
  decimal.to_string(fv)
  |> should.equal("1628.89")
}

pub fn ear_vs_investopedia_test() -> Nil {
  // Investopedia EAR example:
  // Nominal 12% APR compounded monthly: EAR = (1+0.01)^12 - 1 = 0.126825.
  let assert Ok(r) = decimal.from_string("0.12")
  let assert Ok(ear) = interest.effective_annual_rate(r, 12, 6)
  decimal.to_string(ear)
  |> should.equal("0.126825")
}

pub fn simple_interest_textbook_test() -> Nil {
  // 1000 × 0.05 × 3 = 150.00.
  let assert Ok(p) = decimal.from_string("1000")
  let assert Ok(r) = decimal.from_string("0.05")
  let assert Ok(i) = interest.simple_interest(p, r, 3, 2)
  decimal.to_string(i)
  |> should.equal("150.00")
}

// --- Card Luhn / brand vs published references --------------------------

pub fn luhn_wikipedia_example_test() -> Nil {
  // Wikipedia canonical example: 79927398713 is Luhn-valid.
  card.luhn_valid("79927398713")
  |> should.be_true
}

pub fn luhn_wikipedia_mutation_table_test() -> Nil {
  // Wikipedia notes any single-digit change of the trailing check digit
  // makes the PAN invalid. Test the full mutation table.
  let invalid_endings = ["0", "1", "2", "4", "5", "6", "7", "8", "9"]
  list.each(invalid_endings, fn(suffix) {
    let pan = "7992739871" <> suffix
    card.luhn_valid(pan)
    |> should.be_false
  })
}

pub fn stripe_test_pans_test() -> Nil {
  // Stripe sandbox PANs (https://stripe.com/docs/testing). These are
  // published facts; using them in tests is industry-standard.
  let cases = [
    #("4242 4242 4242 4242", card.Visa),
    #("4000 0566 5566 5556", card.Visa),
    #("5555 5555 5555 4444", card.Mastercard),
    #("2223 0031 2200 3222", card.Mastercard),
    #("3782 822463 10005", card.AmericanExpress),
    #("3714 496353 98431", card.AmericanExpress),
    #("6011 1111 1111 1117", card.Discover),
    #("3056 9300 0902 0004", card.DinersClub),
    #("3566 0020 2036 0505", card.Jcb),
    #("6200 0000 0000 0005", card.UnionPay),
  ]
  list.each(cases, fn(case_) {
    let #(pan, expected_brand) = case_
    card.validate(pan)
    |> should.equal(Ok(expected_brand))
  })
}

pub fn braintree_test_pans_test() -> Nil {
  // Braintree-published test PANs. Subset that overlaps Stripe.
  let cases = [
    #("378282246310005", card.AmericanExpress),
    #("371449635398431", card.AmericanExpress),
    #("4111111111111111", card.Visa),
    #("4222222222222", card.Visa),
    #("3530111333300000", card.Jcb),
    #("3566002020360505", card.Jcb),
  ]
  list.each(cases, fn(case_) {
    let #(pan, expected_brand) = case_
    card.validate(pan)
    |> should.equal(Ok(expected_brand))
  })
}
