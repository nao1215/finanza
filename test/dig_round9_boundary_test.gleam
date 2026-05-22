//// dig-bug round 9: extended boundary testing.
////
//// Second boundary pass complementing round 1. Round 1 covers parser
//// rejection of partial inputs, negative zero, currency exponent 0 /
//// 8 / 9, allocate single-ratio / zero-amount / negative-amount,
//// payment_periods 0 / 1 / max / 1201, several PAN-length edges.
////
//// This round attacks angles round 1 did not:
////
//// - The 2^53 − 1 = 9_007_199_254_740_991 precision cliff: add / sub
////   / multiply / negate / parser exactly-at and just-over.
//// - Decimal at large positive / negative exponents.
//// - JPY (exponent 0) rounding direction at the 0.5-cent boundary.
//// - Allocate with empty ratios / zero ratio / negative ratio.
//// - rescale across wide exponent jumps.
//// - currency.divide by zero.
//// - card.validate at minimum (14-digit Diners) and over-maximum
////   (20-digit) PAN lengths.

import gleeunit/should

import finanza/card
import finanza/currency
import finanza/currency/catalog
import finanza/decimal
import finanza/decimal/rounding

// Exposed in the module doc as `2^53 − 1`.
const max_safe: Int = 9_007_199_254_740_991

fn d(s: String) -> decimal.Decimal {
  let assert Ok(v) = decimal.from_string(s)
  v
}

// --- max_safe_coefficient cliff (decimal) -------------------------------

pub fn add_max_safe_plus_zero_test() -> Nil {
  let max = decimal.new(coefficient: max_safe, exponent: 0)
  let assert Ok(sum) = decimal.add(max, decimal.zero())
  decimal.equal(sum, max)
  |> should.be_true
}

pub fn add_max_safe_plus_one_overflows_test() -> Nil {
  let max = decimal.new(coefficient: max_safe, exponent: 0)
  case decimal.add(max, decimal.one()) {
    Error(decimal.PrecisionExceeded) -> Nil
    other -> should.equal(format_arith(other), "PrecisionExceeded")
  }
}

pub fn add_max_safe_minus_one_plus_one_fits_test() -> Nil {
  let almost_max = decimal.new(coefficient: max_safe - 1, exponent: 0)
  let assert Ok(sum) = decimal.add(almost_max, decimal.one())
  decimal.equal(sum, decimal.new(coefficient: max_safe, exponent: 0))
  |> should.be_true
}

pub fn subtract_neg_max_safe_minus_one_overflows_test() -> Nil {
  let neg_max = decimal.new(coefficient: 0 - max_safe, exponent: 0)
  case decimal.subtract(neg_max, decimal.one()) {
    Error(decimal.PrecisionExceeded) -> Nil
    other -> should.equal(format_arith(other), "PrecisionExceeded")
  }
}

pub fn multiply_max_by_one_fits_test() -> Nil {
  let max = decimal.new(coefficient: max_safe, exponent: 0)
  let assert Ok(prod) = decimal.multiply(max, decimal.one())
  decimal.equal(prod, max)
  |> should.be_true
}

pub fn multiply_max_by_two_overflows_test() -> Nil {
  let max = decimal.new(coefficient: max_safe, exponent: 0)
  case decimal.multiply(max, decimal.from_int(2)) {
    Error(decimal.PrecisionExceeded) -> Nil
    other -> should.equal(format_arith(other), "PrecisionExceeded")
  }
}

pub fn negate_max_safe_stays_in_bound_test() -> Nil {
  let max = decimal.new(coefficient: max_safe, exponent: 0)
  let neg = decimal.negate(max)
  decimal.coefficient(neg)
  |> should.equal(0 - max_safe)
}

pub fn parser_at_max_safe_test() -> Nil {
  // Wikipedia gives 9007199254740991 as the safe integer ceiling.
  let assert Ok(d_max) = decimal.from_string("9007199254740991")
  decimal.coefficient(d_max)
  |> should.equal(max_safe)
}

pub fn parser_at_max_safe_plus_one_rejected_test() -> Nil {
  case decimal.from_string("9007199254740992") {
    Error(decimal.ParsedValueTooLarge) -> Nil
    other -> should.equal(format_parse(other), "ParsedValueTooLarge")
  }
}

pub fn parser_at_neg_max_safe_minus_one_rejected_test() -> Nil {
  case decimal.from_string("-9007199254740992") {
    Error(decimal.ParsedValueTooLarge) -> Nil
    other -> should.equal(format_parse(other), "ParsedValueTooLarge")
  }
}

// --- Decimal at large negative exponents --------------------------------

pub fn new_large_negative_exponent_arithmetic_test() -> Nil {
  let tiny = decimal.new(coefficient: 1, exponent: -20)
  let assert Ok(sum) = decimal.add(tiny, decimal.zero())
  decimal.equal(sum, tiny)
  |> should.be_true
}

pub fn rescale_finer_then_coarser_round_trip_test() -> Nil {
  // rescale(d, -6) then rescale back to original exponent — value preserved.
  let v = d("12.34")
  let assert Ok(finer) = decimal.rescale(v, -6, rounding.HalfEven)
  let assert Ok(back) =
    decimal.rescale(finer, decimal.exponent(v), rounding.HalfEven)
  decimal.equal(back, v)
  |> should.be_true
}

pub fn rescale_to_zero_exponent_drops_fraction_test() -> Nil {
  // rescaling 1.49 to exponent 0 with HalfEven produces 1.
  let v = d("1.49")
  let assert Ok(rounded) = decimal.rescale(v, 0, rounding.HalfEven)
  decimal.to_string(rounded)
  |> should.equal("1")
}

// --- JPY rounding direction (currency with exponent 0) ------------------

pub fn jpy_to_minor_half_even_at_half_test() -> Nil {
  // 0.5 JPY → HalfEven → 0 (even).
  let m = currency.new_money(d("0.5"), catalog.jpy())
  let assert Ok(units) = currency.to_minor(m, rounding.HalfEven)
  units
  |> should.equal(0)
}

pub fn jpy_to_minor_half_even_1_5_test() -> Nil {
  // 1.5 JPY → HalfEven → 2 (next even).
  let m = currency.new_money(d("1.5"), catalog.jpy())
  let assert Ok(units) = currency.to_minor(m, rounding.HalfEven)
  units
  |> should.equal(2)
}

pub fn jpy_to_minor_half_up_at_half_test() -> Nil {
  let m = currency.new_money(d("0.5"), catalog.jpy())
  let assert Ok(units) = currency.to_minor(m, rounding.HalfUp)
  units
  |> should.equal(1)
}

pub fn jpy_to_minor_negative_half_floor_test() -> Nil {
  let m = currency.new_money(d("-0.5"), catalog.jpy())
  let assert Ok(units) = currency.to_minor(m, rounding.Floor)
  units
  |> should.equal(-1)
}

pub fn jpy_to_minor_negative_half_ceiling_test() -> Nil {
  let m = currency.new_money(d("-0.5"), catalog.jpy())
  let assert Ok(units) = currency.to_minor(m, rounding.Ceiling)
  units
  |> should.equal(0)
}

// --- High-precision currency (exponent 8) -------------------------------

pub fn high_precision_currency_from_to_minor_test() -> Nil {
  // Build an 8-decimal-place currency (e.g. crypto smallest unit).
  let assert Ok(btc) =
    currency.new_currency(
      code: "BTC",
      exponent: 8,
      symbol: "₿",
      name: "Bitcoin",
    )
  let m = currency.from_minor(123_456_789, btc)
  let assert Ok(back) = currency.to_minor(m, rounding.HalfEven)
  back
  |> should.equal(123_456_789)
}

// --- Allocate edges round 1 missed --------------------------------------

pub fn allocate_empty_ratios_errors_test() -> Nil {
  let m = currency.from_minor(1000, catalog.usd())
  case currency.allocate(m, []) {
    Error(currency.EmptyRatios) -> Nil
    other -> should.equal(format_currency(other), "EmptyRatios")
  }
}

pub fn allocate_with_all_zero_ratios_errors_test() -> Nil {
  // `[1, 0, 1]` was previously rejected as a `NonPositiveRatio`
  // failure; #49 relaxed that to "skip recipient" semantics. The
  // boundary now sits at the all-zero list, which still has no
  // positive total to distribute and remains rejected.
  let m = currency.from_minor(1000, catalog.usd())
  case currency.allocate(m, [0, 0, 0]) {
    Error(currency.NonPositiveRatio) -> Nil
    other -> should.equal(format_currency(other), "NonPositiveRatio")
  }
}

pub fn allocate_with_negative_ratio_errors_test() -> Nil {
  let m = currency.from_minor(1000, catalog.usd())
  case currency.allocate(m, [1, -1, 1]) {
    Error(currency.NonPositiveRatio) -> Nil
    other -> should.equal(format_currency(other), "NonPositiveRatio")
  }
}

// --- currency.divide by zero --------------------------------------------

pub fn money_divide_by_zero_errors_test() -> Nil {
  let m = currency.from_minor(1000, catalog.usd())
  case currency.divide(m, decimal.zero(), rounding.HalfEven) {
    Error(currency.ArithmeticError(decimal.DivisionByZero)) -> Nil
    other ->
      should.equal(format_currency(other), "ArithmeticError DivisionByZero")
  }
}

// --- Currency mismatch in compound ops ----------------------------------

pub fn money_add_currency_mismatch_test() -> Nil {
  let usd_money = currency.from_minor(100, catalog.usd())
  let jpy_money = currency.from_minor(100, catalog.jpy())
  case currency.add(usd_money, jpy_money) {
    Error(currency.CurrencyMismatch(_, _)) -> Nil
    other -> should.equal(format_currency(other), "CurrencyMismatch")
  }
}

pub fn money_compare_currency_mismatch_test() -> Nil {
  let usd_money = currency.from_minor(100, catalog.usd())
  let eur_money = currency.from_minor(100, catalog.eur())
  case currency.compare(usd_money, eur_money) {
    Error(currency.CurrencyMismatch(_, _)) -> Nil
    Error(_) -> should.be_true(False)
    Ok(_) -> should.be_true(False)
  }
}

// --- Card validate at minimum / over-maximum lengths --------------------

pub fn validate_14_digit_diners_test() -> Nil {
  // 30569309025904 is a 14-digit Diners Club test PAN (Luhn-valid).
  let assert Ok(brand) = card.validate("30569309025904")
  card.brand_to_string(brand)
  |> should.equal("DINERS")
}

pub fn validate_13_digit_pan_rejected_test() -> Nil {
  // 13 digits is below the minimum for every supported brand.
  case card.validate("1234567891234") {
    Error(_) -> Nil
    Ok(brand) ->
      should.equal("expected error, got " <> card.brand_to_string(brand), "")
  }
}

pub fn validate_20_digit_pan_rejected_test() -> Nil {
  case card.validate("12345678901234567890") {
    Error(_) -> Nil
    Ok(brand) ->
      should.equal("expected error, got " <> card.brand_to_string(brand), "")
  }
}

pub fn validate_19_digit_pan_test() -> Nil {
  // 19-digit PANs are allowed for some brands (Visa / Mastercard
  // can issue 16-19 per ISO/IEC 7812-1). Either Ok-with-brand or
  // a typed error is acceptable; what we ban is a panic.
  let _ = card.validate("4111111111111111110")
  Nil
}

// --- Helpers (format errors for diagnostic should.equal calls) ---------

fn format_arith(r: Result(decimal.Decimal, decimal.ArithmeticError)) -> String {
  case r {
    Ok(_) -> "Ok"
    Error(decimal.DivisionByZero) -> "DivisionByZero"
    Error(decimal.PrecisionExceeded) -> "PrecisionExceeded"
  }
}

fn format_parse(r: Result(decimal.Decimal, decimal.ParseError)) -> String {
  case r {
    Ok(_) -> "Ok"
    Error(decimal.EmptyInput) -> "EmptyInput"
    Error(decimal.InvalidCharacter(_, _)) -> "InvalidCharacter"
    Error(decimal.MultipleDecimalPoints) -> "MultipleDecimalPoints"
    Error(decimal.MultipleSigns) -> "MultipleSigns"
    Error(decimal.NoDigits) -> "NoDigits"
    Error(decimal.ParsedValueTooLarge) -> "ParsedValueTooLarge"
  }
}

fn format_currency(r: Result(a, currency.CurrencyError)) -> String {
  case r {
    Ok(_) -> "Ok"
    Error(currency.CurrencyMismatch(_, _)) -> "CurrencyMismatch"
    Error(currency.InvalidExponent) -> "InvalidExponent"
    Error(currency.InvalidCurrencyCode) -> "InvalidCurrencyCode"
    Error(currency.EmptyRatios) -> "EmptyRatios"
    Error(currency.NonPositiveRatio) -> "NonPositiveRatio"
    Error(currency.EmptyList) -> "EmptyList"
    Error(currency.ArithmeticError(decimal.DivisionByZero)) ->
      "ArithmeticError DivisionByZero"
    Error(currency.ArithmeticError(decimal.PrecisionExceeded)) ->
      "ArithmeticError PrecisionExceeded"
  }
}
