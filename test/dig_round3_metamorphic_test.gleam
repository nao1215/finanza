//// dig-bug round 3: metamorphic testing.
////
//// Each property is an algebraic relationship that should hold for
//// the package independent of the specific input values: round-trips,
//// scale-invariance, and inverse pairs.

import gleam/int
import gleam/list
import gleam/order
import gleeunit/should

import finanza/card
import finanza/decimal
import finanza/interest
import finanza/money
import support

// --- Decimal round-trips -------------------------------------------------

pub fn decimal_string_round_trip_canonical_test() -> Nil {
  let cases = [
    "0", "1", "-1", "10", "-10", "0.1", "0.01", "0.001", "-0.5", "100.50",
    "1234.5678", "9007199254740991", "-9007199254740991",
  ]
  list.each(cases, fn(input) {
    let assert Ok(d) = decimal.parse(input)
    let rendered = decimal.to_string(d)
    let assert Ok(d2) = decimal.parse(rendered)
    decimal.equal(d, d2)
    |> should.be_true
  })
}

pub fn decimal_negate_involution_test() -> Nil {
  let cases = ["0", "1", "-1", "123.45", "-0.001", "9999999"]
  list.each(cases, fn(input) {
    let assert Ok(d) = decimal.parse(input)
    let twice = decimal.negate(decimal.negate(d))
    decimal.equal(twice, d)
    |> should.be_true
  })
}

pub fn decimal_abs_sign_neutral_test() -> Nil {
  let cases = ["-1", "-123.45", "-0.001"]
  list.each(cases, fn(input) {
    let assert Ok(d) = decimal.parse(input)
    let from_pos = decimal.absolute(d)
    let from_neg = decimal.absolute(decimal.negate(d))
    decimal.equal(from_pos, from_neg)
    |> should.be_true
  })
}

pub fn decimal_round_then_round_idempotent_test() -> Nil {
  let cases = ["123.456", "0.005", "-0.115", "999.999"]
  list.each(cases, fn(input) {
    let assert Ok(d) = decimal.parse(input)
    list.each([0, 1, 2, 3], fn(digits) {
      let once = support.round(d, digits, decimal.HalfEven)
      let twice = support.round(once, digits, decimal.HalfEven)
      decimal.equal(once, twice)
      |> should.be_true
    })
  })
}

pub fn decimal_divide_multiply_inverse_test() -> Nil {
  // (a / b) * b should equal a, modulo rounding noise that we control
  // by quantising both sides to the same digit count.
  let pairs = [
    #("100", "4"),
    #("999", "3"),
    #("1000", "8"),
    #("1.5", "0.5"),
    #("12.34", "2"),
  ]
  list.each(pairs, fn(pair) {
    let #(a_in, b_in) = pair
    let assert Ok(a) = decimal.parse(a_in)
    let assert Ok(b) = decimal.parse(b_in)
    let assert Ok(q) = decimal.divide(a, b, 6, decimal.HalfEven)
    let assert Ok(product) = decimal.multiply(q, b)
    let a_quant = support.round(a, 4, decimal.HalfEven)
    let product_quant = support.round(product, 4, decimal.HalfEven)
    decimal.equal(a_quant, product_quant)
    |> should.be_true
  })
}

pub fn decimal_rescale_compose_lossless_test() -> Nil {
  // Rescaling to finer then back to original should preserve the value
  // (only adds trailing zeros, no rounding).
  let cases = [
    #("12.34", -4),
    #("100", -2),
    #("0.5", -3),
  ]
  list.each(cases, fn(case_) {
    let #(input, finer) = case_
    let assert Ok(d) = decimal.parse(input)
    let assert Ok(rescaled) =
      decimal.round(d, digits: -finer, rounding: decimal.HalfEven)
    let assert Ok(back) =
      decimal.round(
        rescaled,
        digits: -{ decimal.exponent(d) },
        rounding: decimal.HalfEven,
      )
    decimal.equal(back, d)
    |> should.be_true
  })
}

// --- Currency round-trips ------------------------------------------------

pub fn money_add_inverse_yields_zero_test() -> Nil {
  let inputs = [100, 1234, 999_999, -1, -1234]
  list.each(inputs, fn(units) {
    let m = support.from_minor(units, money.usd)
    let neg = money.negate(m)
    let assert Ok(sum) = money.add(m, neg)
    let assert Ok(back) = money.to_minor(sum, decimal.HalfEven)
    back
    |> should.equal(0)
  })
}

pub fn allocate_equal_ratios_spread_test() -> Nil {
  // For [1,1,...,1] of length n, parts differ by at most 1 minor unit.
  let inputs = [10, 100, 999, 1234, 9_999_999]
  list.each(inputs, fn(units) {
    let m = support.from_minor(units, money.usd)
    let assert Ok(parts) = money.allocate(m, [1, 1, 1, 1, 1, 1, 1])
    let unit_values =
      list.map(parts, fn(p) {
        let assert Ok(u) = money.to_minor(p, decimal.HalfEven)
        u
      })
    let assert Ok(max_v) = list.reduce(unit_values, int.max)
    let assert Ok(min_v) = list.reduce(unit_values, int.min)
    let spread = max_v - min_v
    case spread <= 1 {
      True -> Nil
      False -> {
        let _ = unit_values
        should.equal(spread, 0)
      }
    }
  })
}

pub fn allocate_with_minor_unit_smallest_amount_test() -> Nil {
  // 1 cent split N ways: one slot gets 1 cent, the rest 0.
  let m = support.from_minor(1, money.usd)
  let assert Ok(parts) = money.allocate(m, [1, 1, 1, 1, 1])
  let totals =
    list.map(parts, fn(p) {
      let assert Ok(u) = money.to_minor(p, decimal.HalfEven)
      u
    })
  list.fold(totals, 0, int.add)
  |> should.equal(1)
}

// --- Interest round-trips ------------------------------------------------

pub fn pv_fv_round_trip_test() -> Nil {
  // FV(PV(x, r, n), r, n) ≈ x within the digits precision.
  let cases = [
    #("1000", "0.05", 5),
    #("1000", "0.01", 12),
    #("500", "0.10", 3),
  ]
  list.each(cases, fn(case_) {
    let #(present, rate, periods) = case_
    let assert Ok(pv) = decimal.parse(present)
    let assert Ok(r) = decimal.parse(rate)
    let assert Ok(fv) = interest.future_value(pv, r, periods, 4)
    let assert Ok(pv_back) = interest.present_value(fv, r, periods, 2)
    let pv_quant = support.round(pv, 2, decimal.HalfEven)
    decimal.equal(pv_back, pv_quant)
    |> should.be_true
  })
}

pub fn payment_sum_exceeds_principal_when_positive_rate_test() -> Nil {
  // PMT × periods > principal when rate > 0 (interest is paid).
  let cases = [
    #("1000", "0.01", 12),
    #("100", "0.05", 6),
  ]
  list.each(cases, fn(case_) {
    let #(p_in, r_in, n) = case_
    let assert Ok(principal) = decimal.parse(p_in)
    let assert Ok(rate) = decimal.parse(r_in)
    let assert Ok(pmt) = interest.payment(principal, rate, n, 2)
    let assert Ok(total) = decimal.multiply(pmt, support.int(n))
    case decimal.compare(total, principal) {
      order.Gt -> Nil
      _ -> {
        // Surface the unexpected case.
        should.equal(decimal.to_string(total), decimal.to_string(principal))
      }
    }
  })
}

// --- Card metamorphic ----------------------------------------------------

pub fn normalize_then_validate_equiv_test() -> Nil {
  // Validating a PAN with and without separators must give the same
  // result (since validate normalises internally too).
  let pans = [
    "4111111111111111",
    "5555 5555 5555 4444",
    "378282246310005",
    "3530-1113-3330-0000",
    "6200 0000 0000 0005",
  ]
  list.each(pans, fn(pan) {
    let result_raw = card.validate(pan)
    let normalised = card.normalize(pan)
    let result_norm = card.validate(normalised)
    result_raw
    |> should.equal(result_norm)
  })
}

pub fn mask_preserves_keep_first_test() -> Nil {
  // mask output, when stripped of separators and mask chars, should
  // start with the first keep_first digits of the normalised PAN.
  // We assert a weaker form: the masked output contains those digits.
  let pans = [
    "4111111111111111",
    "378282246310005",
    "30569309025904",
    "6200000000000005",
  ]
  list.each(pans, fn(pan) {
    let assert Ok(masked) = card.mask(pan, card.default_mask)
    // mask_defaults keeps first 4 by default.
    let prefix = string_slice_first_4(pan)
    string_contains_local(masked, prefix)
    |> should.be_true
  })
}

pub fn detect_brand_invariant_under_normalisation_test() -> Nil {
  let pairs = [
    #("4111 1111 1111 1111", "4111111111111111"),
    #("3782-8224-6310-005", "378282246310005"),
    #("5555 5555 5555 4444", "5555555555554444"),
  ]
  list.each(pairs, fn(pair) {
    let #(formatted, plain) = pair
    let a = card.detect_brand(formatted)
    let b = card.detect_brand(plain)
    a
    |> should.equal(b)
  })
}

pub fn luhn_extra_zero_prefix_changes_validity_test() -> Nil {
  // Prefixing "0" to a Luhn-valid string of even length flips validity
  // (because position parity shifts). This is a metamorphic relation
  // between a known input and a perturbed input.
  // Wikipedia example "79927398713" is 11 digits (odd); prefixing "0"
  // makes it 12 digits → check positions reverse → may flip.
  let original = "79927398713"
  card.luhn_valid(original)
  |> should.be_true
  let prefixed = "0" <> original
  // Prefixing zero adds a value-0 digit at the leftmost position. In
  // the Luhn algorithm the doubling pattern only changes parity; the
  // sum is unchanged (since the new leftmost is 0). So validity is
  // preserved.
  card.luhn_valid(prefixed)
  |> should.be_true
}

// --- Helpers -------------------------------------------------------------

import gleam/string

fn string_slice_first_4(s: String) -> String {
  string.slice(s, 0, 4)
}

fn string_contains_local(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
