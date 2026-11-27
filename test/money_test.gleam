import gleam/list
import gleam/order
import gleam/result
import gleeunit/should

import finanza/decimal
import finanza/money
import support

// --- Currency ------------------------------------------------------------

pub fn custom_currency_test() -> Nil {
  let xyz = money.Currency(code: "XYZ", exponent: 3, symbol: "X", name: "Test")
  let assert Ok(m) = money.from_minor(1234, in: xyz)
  money.to_string(m) |> should.equal("XYZ 1.234")
}

// --- Catalogue ----------------------------------------------------------

pub fn catalogue_usd_test() -> Nil {
  let c = money.usd
  c.code
  |> should.equal("USD")
  c.exponent
  |> should.equal(2)
}

pub fn catalogue_jpy_test() -> Nil {
  let c = money.jpy
  c.code
  |> should.equal("JPY")
  c.exponent
  |> should.equal(0)
}

pub fn catalogue_codes_are_unique_and_found_test() -> Nil {
  [
    "USD",
    "EUR",
    "JPY",
    "GBP",
    "CHF",
    "CAD",
    "AUD",
    "CNY",
    "HKD",
    "SGD",
    "KRW",
    "INR",
    "BRL",
    "MXN",
    "ZAR",
  ]
  |> list.map(fn(code) {
    money.find_currency(code) |> result.map(fn(c) { c.code })
  })
  |> should.equal([
    Ok("USD"),
    Ok("EUR"),
    Ok("JPY"),
    Ok("GBP"),
    Ok("CHF"),
    Ok("CAD"),
    Ok("AUD"),
    Ok("CNY"),
    Ok("HKD"),
    Ok("SGD"),
    Ok("KRW"),
    Ok("INR"),
    Ok("BRL"),
    Ok("MXN"),
    Ok("ZAR"),
  ])
}

pub fn catalogue_find_known_test() -> Nil {
  let assert Ok(c) = money.find_currency("EUR")
  c.code
  |> should.equal("EUR")
}

pub fn catalogue_find_unknown_test() -> Nil {
  money.find_currency("XYZ")
  |> should.equal(Error(Nil))
}

// --- Money construction -------------------------------------------------

pub fn from_minor_test() -> Nil {
  let m = support.from_minor(units: 1234, currency: money.usd)
  m.amount
  |> decimal.to_string
  |> should.equal("12.34")
}

pub fn from_minor_jpy_test() -> Nil {
  let m = support.from_minor(units: 5000, currency: money.jpy)
  m.amount
  |> decimal.to_string
  |> should.equal("5000")
}

pub fn to_minor_test() -> Nil {
  let m = support.from_minor(units: 1234, currency: money.usd)
  money.to_minor(m, rounding: decimal.HalfEven)
  |> should.equal(Ok(1234))
}

pub fn from_major_usd_test() -> Nil {
  // $35 — two-exponent currency, but `from_major` does not scale by
  // the exponent so the human-readable amount lands as-is.
  let m = support.from_major(35, money.usd)
  m.amount
  |> decimal.to_string
  |> should.equal("35")
}

pub fn from_major_jpy_test() -> Nil {
  // ¥3,500 — zero-exponent money. Same shape as `from_minor` for
  // this case; documenting that callers no longer have to pick
  // between the two for major-unit ingestion.
  let m = support.from_major(3500, money.jpy)
  m.amount
  |> decimal.to_string
  |> should.equal("3500")
}

pub fn from_major_round_trips_via_to_minor_test() -> Nil {
  // $35 → 3500 cents. Confirms `from_major` lines up with the
  // existing minor-unit machinery for the two-exponent case.
  let m = support.from_major(35, money.usd)
  money.to_minor(m, rounding: decimal.HalfEven)
  |> should.equal(Ok(3500))
}

pub fn from_minor_rejects_out_of_range_units_test() -> Nil {
  money.from_minor(9_007_199_254_740_991 + 1, in: money.jpy)
  |> should.equal(Error(money.ArithmeticFailed(decimal.PrecisionExceeded)))
}

pub fn to_minor_with_finer_precision_test() -> Nil {
  // $1.005 → 100 (banker's rounding because 100.5 ties, 100 is even).
  let assert Ok(amount) = decimal.parse("1.005")
  let m = money.Money(amount: amount, currency: money.usd)
  money.to_minor(m, rounding: decimal.HalfEven)
  |> should.equal(Ok(100))
}

// --- Money arithmetic ---------------------------------------------------

pub fn add_same_currency_test() -> Nil {
  let a = support.from_minor(units: 100, currency: money.usd)
  let b = support.from_minor(units: 250, currency: money.usd)
  let assert Ok(sum) = money.add(a, b)
  let assert Ok(units) = money.to_minor(sum, rounding: decimal.HalfEven)
  units
  |> should.equal(350)
}

pub fn add_currency_mismatch_test() -> Nil {
  let a = support.from_minor(units: 100, currency: money.usd)
  let b = support.from_minor(units: 100, currency: money.eur)
  money.add(a, b)
  |> should.equal(Error(money.CurrencyMismatch(left: "USD", right: "EUR")))
}

pub fn subtract_test() -> Nil {
  let a = support.from_minor(units: 1000, currency: money.usd)
  let b = support.from_minor(units: 250, currency: money.usd)
  let assert Ok(diff) = money.subtract(a, b)
  let assert Ok(units) = money.to_minor(diff, rounding: decimal.HalfEven)
  units
  |> should.equal(750)
}

// --- Sum -----------------------------------------------------------------

pub fn sum_empty_list_is_zero_in_the_currency_test() -> Nil {
  let assert Ok(total) = money.sum([], in: money.usd)
  money.to_string(total) |> should.equal("USD 0.00")
}

pub fn sum_single_currency_test() -> Nil {
  let usd = money.usd
  let items = [
    support.from_minor(units: 100, currency: usd),
    support.from_minor(units: 250, currency: usd),
  ]
  let assert Ok(total) = money.sum(items, in: usd)
  let assert Ok(units) = money.to_minor(total, rounding: decimal.HalfEven)
  units |> should.equal(350)
}

pub fn sum_currency_mismatch_returns_error_test() -> Nil {
  let usd = support.from_minor(units: 100, currency: money.usd)
  let eur = support.from_minor(units: 50, currency: money.eur)
  money.sum([usd, eur], in: money.usd)
  |> should.equal(Error(money.CurrencyMismatch(left: "USD", right: "EUR")))
}

pub fn sum_checks_items_against_the_currency_test() -> Nil {
  let eur = support.from_minor(units: 50, currency: money.eur)
  money.sum([eur], in: money.usd)
  |> should.equal(Error(money.CurrencyMismatch(left: "USD", right: "EUR")))
}

pub fn multiply_test() -> Nil {
  let m = support.from_minor(units: 1000, currency: money.usd)
  let factor = support.int(3)
  let assert Ok(product) =
    money.multiply(m, by: factor, rounding: decimal.HalfEven)
  let assert Ok(units) = money.to_minor(product, rounding: decimal.HalfEven)
  units
  |> should.equal(3000)
}

pub fn multiply_jpy_respects_zero_exponent_test() -> Nil {
  let m = support.from_minor(units: 100, currency: money.jpy)
  let assert Ok(factor) = decimal.parse("0.5")
  let assert Ok(product) =
    money.multiply(m, by: factor, rounding: decimal.HalfEven)
  money.to_string(product)
  |> should.equal("JPY 50")
}

pub fn multiply_jpy_small_factor_rounds_to_zero_test() -> Nil {
  let m = support.from_minor(units: 100, currency: money.jpy)
  let assert Ok(factor) = decimal.parse("0.001")
  let assert Ok(product) =
    money.multiply(m, by: factor, rounding: decimal.HalfEven)
  // 100 * 0.001 = 0.1 → HalfEven rounds to 0 for JPY (exponent 0).
  money.to_string(product)
  |> should.equal("JPY 0")
}

pub fn multiply_usd_keeps_two_decimals_test() -> Nil {
  let m = support.from_minor(units: 10_000, currency: money.usd)
  let assert Ok(factor) = decimal.parse("0.5")
  let assert Ok(product) =
    money.multiply(m, by: factor, rounding: decimal.HalfEven)
  money.to_string(product)
  |> should.equal("USD 50.00")
}

pub fn divide_test() -> Nil {
  let m = support.from_minor(units: 1000, currency: money.usd)
  let divisor = support.int(3)
  let assert Ok(quotient) =
    money.divide(m, by: divisor, rounding: decimal.HalfEven)
  // $10.00 / 3 = $3.3333..., rounded to 2 dp = $3.33
  let assert Ok(units) = money.to_minor(quotient, rounding: decimal.HalfEven)
  units
  |> should.equal(333)
}

pub fn negate_test() -> Nil {
  let m = support.from_minor(units: 500, currency: money.usd)
  let neg = money.negate(m)
  let assert Ok(units) = money.to_minor(neg, rounding: decimal.HalfEven)
  units
  |> should.equal(-500)
}

// --- Allocation --------------------------------------------------------

pub fn allocate_even_test() -> Nil {
  // $10.00 split 3 ways → $3.34, $3.33, $3.33 (remainder to first slot)
  let m = support.from_minor(units: 1000, currency: money.usd)
  let assert Ok(parts) = money.allocate(m, [1, 1, 1])
  parts
  |> list_map(fn(p) {
    let assert Ok(units) = money.to_minor(p, rounding: decimal.HalfEven)
    units
  })
  |> should.equal([334, 333, 333])
}

pub fn allocate_weighted_test() -> Nil {
  // $10.00 split 1:2:1 → $2.50, $5.00, $2.50
  let m = support.from_minor(units: 1000, currency: money.usd)
  let assert Ok(parts) = money.allocate(m, [1, 2, 1])
  parts
  |> list_map(fn(p) {
    let assert Ok(units) = money.to_minor(p, rounding: decimal.HalfEven)
    units
  })
  |> should.equal([250, 500, 250])
}

pub fn allocate_preserves_total_test() -> Nil {
  // Property: sum of allocated parts equals the original
  let m = support.from_minor(units: 9999, currency: money.usd)
  let assert Ok(parts) = money.allocate(m, [3, 5, 2])
  let total =
    parts
    |> list_fold(0, fn(acc, p) {
      let assert Ok(units) = money.to_minor(p, rounding: decimal.HalfEven)
      acc + units
    })
  total
  |> should.equal(9999)
}

pub fn allocate_rejects_empty_ratios_test() -> Nil {
  let m = support.from_minor(units: 100, currency: money.usd)
  money.allocate(m, [])
  |> should.equal(Error(money.EmptyRatios))
}

pub fn allocate_accepts_zero_in_mixed_list_test() -> Nil {
  // `[1, 0, 1]` is the "skip the middle recipient" pattern. As of
  // #49 the function distributes across the non-zero slots and
  // assigns zero to the skipped slot.
  let m = support.from_minor(units: 10_000, currency: money.usd)
  let assert Ok(parts) = money.allocate(m, [1, 0, 1])
  let amounts =
    list.map(parts, fn(p) {
      let assert Ok(units) = money.to_minor(p, rounding: decimal.HalfEven)
      units
    })
  amounts |> should.equal([5000, 0, 5000])
}

pub fn allocate_accepts_zero_at_edges_test() -> Nil {
  let m = support.from_minor(units: 10_000, currency: money.usd)
  let assert Ok(parts) = money.allocate(m, [0, 1, 0])
  let amounts =
    list.map(parts, fn(p) {
      let assert Ok(units) = money.to_minor(p, rounding: decimal.HalfEven)
      units
    })
  amounts |> should.equal([0, 10_000, 0])
}

pub fn allocate_gives_no_remainder_to_zero_ratios_test() -> Nil {
  let m = support.from_minor(units: 3, currency: money.usd)
  let assert Ok(parts) = money.allocate(m, [0, 1, 1])
  list.map(parts, fn(p) { money.to_minor(p, rounding: decimal.HalfEven) })
  |> should.equal([Ok(0), Ok(2), Ok(1)])
}

pub fn allocate_gives_no_negative_remainder_to_zero_ratios_test() -> Nil {
  let m = support.from_minor(units: -3, currency: money.usd)
  let assert Ok(parts) = money.allocate(m, [1, 0, 1, 0])
  list.map(parts, fn(p) { money.to_minor(p, rounding: decimal.HalfEven) })
  |> should.equal([Ok(-2), Ok(0), Ok(-1), Ok(0)])
}

pub fn allocate_rejects_all_zeros_test() -> Nil {
  let m = support.from_minor(units: 100, currency: money.usd)
  money.allocate(m, [0, 0, 0])
  |> should.equal(Error(money.NonPositiveRatio))
}

pub fn allocate_rejects_negative_ratio_test() -> Nil {
  let m = support.from_minor(units: 100, currency: money.usd)
  money.allocate(m, [1, -1, 1])
  |> should.equal(Error(money.NonPositiveRatio))
}

// --- Compare / equal ----------------------------------------------------

pub fn compare_test() -> Nil {
  let a = support.from_minor(units: 100, currency: money.usd)
  let b = support.from_minor(units: 200, currency: money.usd)
  money.compare(a, b)
  |> should.equal(Ok(order.Lt))
  money.compare(b, a)
  |> should.equal(Ok(order.Gt))
  money.compare(a, a)
  |> should.equal(Ok(order.Eq))
}

pub fn compare_mismatch_test() -> Nil {
  let a = support.from_minor(units: 100, currency: money.usd)
  let b = support.from_minor(units: 100, currency: money.eur)
  money.compare(a, b)
  |> result.is_error
  |> should.be_true
}

pub fn equal_same_test() -> Nil {
  let a = support.from_minor(units: 100, currency: money.usd)
  let b = support.from_minor(units: 100, currency: money.usd)
  support.money_equal(a, b)
  |> should.be_true
}

pub fn equal_different_currency_returns_false_test() -> Nil {
  let a = support.from_minor(units: 100, currency: money.usd)
  let b = support.from_minor(units: 100, currency: money.eur)
  support.money_equal(a, b)
  |> should.be_false
}

// --- Formatting --------------------------------------------------------

pub fn to_string_default_test() -> Nil {
  let m = support.from_minor(units: 1234, currency: money.usd)
  money.to_string(m)
  |> should.equal("USD 12.34")
}

pub fn format_default_prefix_test() -> Nil {
  let m = support.from_minor(units: 123_456, currency: money.usd)
  money.format(m, with: money.default_format)
  |> should.equal("$1,234.56")
}

pub fn format_suffix_test() -> Nil {
  let m = support.from_minor(units: 123_456, currency: money.eur)
  let opts =
    money.FormatOptions(..money.default_format, symbol_position: money.Suffix)
  money.format(m, with: opts)
  |> should.equal("1,234.56€")
}

pub fn format_no_symbol_test() -> Nil {
  let m = support.from_minor(units: 123_456, currency: money.usd)
  let opts =
    money.FormatOptions(..money.default_format, symbol_position: money.NoSymbol)
  money.format(m, with: opts)
  |> should.equal("1,234.56")
}

pub fn format_negative_minus_test() -> Nil {
  let m = support.from_minor(units: -123_456, currency: money.usd)
  money.format(m, with: money.default_format)
  |> should.equal("-$1,234.56")
}

pub fn format_negative_parentheses_test() -> Nil {
  let m = support.from_minor(units: -123_456, currency: money.usd)
  let opts =
    money.FormatOptions(
      ..money.default_format,
      negative_style: money.Parentheses,
    )
  money.format(m, with: opts)
  |> should.equal("($1,234.56)")
}

pub fn format_custom_separators_test() -> Nil {
  let m = support.from_minor(units: 123_456, currency: money.eur)
  let opts =
    money.FormatOptions(
      ..money.default_format,
      thousands_separator: ".",
      decimal_separator: ",",
      symbol_position: money.Suffix,
    )
  money.format(m, with: opts)
  |> should.equal("1.234,56€")
}

pub fn format_with_currency_code_test() -> Nil {
  let m = support.from_minor(units: 1234, currency: money.usd)
  let opts =
    money.FormatOptions(..money.default_format, show_currency_code: True)
  money.format(m, with: opts)
  |> should.equal("$12.34 USD")
}

pub fn format_jpy_no_decimals_test() -> Nil {
  let m = support.from_minor(units: 12_345, currency: money.jpy)
  money.format(m, with: money.default_format)
  |> should.equal("¥12,345")
}

pub fn format_normalises_integer_amount_to_minor_units_test() -> Nil {
  // Whole dollars should render with two cents and a thousands sep.
  let m = money.Money(amount: support.int(200_000), currency: money.usd)
  money.format(m, with: money.default_format)
  |> should.equal("$200,000.00")
}

pub fn format_minor_units_disabled_preserves_precision_test() -> Nil {
  // For FX-style four-decimal precision, opt out of minor-unit rescale.
  let assert Ok(amount) = decimal.parse("1.2345")
  let m = money.Money(amount: amount, currency: money.usd)
  let opts =
    money.FormatOptions(..money.default_format, round_to_minor_units: False)
  money.format(m, with: opts)
  |> should.equal("$1.2345")
}

pub fn format_minor_units_rounds_excess_precision_test() -> Nil {
  let assert Ok(amount) = decimal.parse("12.345")
  let m = money.Money(amount: amount, currency: money.usd)
  // Default minor_units = True, HalfEven rounding: 12.345 → 12.34 (tie, even).
  money.format(m, with: money.default_format)
  |> should.equal("$12.34")
}

pub fn format_pads_amounts_too_large_to_rescale_test() -> Nil {
  let m = support.from_minor(units: 9_007_199_254_740_991, currency: money.jpy)
  let usd = money.Money(..m, currency: money.usd)
  money.format(usd, with: money.default_format)
  |> should.equal("$9,007,199,254,740,991.00")
  money.format(money.negate(usd), with: money.default_format)
  |> should.equal("-$9,007,199,254,740,991.00")
}

pub fn format_pads_amounts_with_some_places_test() -> Nil {
  let amount = support.new(coefficient: 900_719_925_474_099, exponent: -1)
  let m = money.Money(amount:, currency: money.usd)
  money.format(m, with: money.default_format)
  |> should.equal("$90,071,992,547,409.90")
}

// --- Helpers ------------------------------------------------------------

fn list_map(items: List(a), f: fn(a) -> b) -> List(b) {
  case items {
    [] -> []
    [head, ..rest] -> [f(head), ..list_map(rest, f)]
  }
}

fn list_fold(items: List(a), acc: b, f: fn(b, a) -> b) -> b {
  case items {
    [] -> acc
    [head, ..rest] -> list_fold(rest, f(acc, head), f)
  }
}

// --- Boundaries found by mutation testing ---------------------------------

pub fn allocate_carries_a_share_that_wraps_the_ratio_total_test() -> Nil {
  // 6 × 2 / 4 = 3 exactly: the share of the last ratio wraps the total
  // of the ratios once.
  let assert Ok(parts) =
    money.allocate(support.from_minor(6, money.usd), [1, 1, 2])
  assert list.map(parts, fn(part) { money.to_minor(part, decimal.HalfEven) })
    == [Ok(2), Ok(1), Ok(3)]
}

pub fn add_keeps_the_places_when_the_second_operand_is_zero_test() -> Nil {
  let big = support.from_minor(9_007_199_254_740_991, money.usd)
  let zero =
    money.Money(
      amount: support.new(coefficient: 0, exponent: -3),
      currency: money.usd,
    )
  assert money.add(big, zero) == Ok(big)
}
