import gleam/list
import gleam/order
import gleam/result
import gleeunit/should

import finanza/currency
import finanza/currency/catalog
import finanza/decimal
import finanza/decimal/rounding

// --- Currency construction ----------------------------------------------

pub fn new_currency_test() -> Nil {
  let assert Ok(c) =
    currency.new_currency(
      code: "XYZ",
      exponent: 2,
      symbol: "X",
      name: "Test Currency",
    )
  currency.code(c)
  |> should.equal("XYZ")
  currency.exponent(c)
  |> should.equal(2)
  currency.symbol(c)
  |> should.equal("X")
  currency.name(c)
  |> should.equal("Test Currency")
}

pub fn new_currency_rejects_empty_code_test() -> Nil {
  currency.new_currency(code: "", exponent: 2, symbol: "$", name: "Empty")
  |> should.equal(Error(currency.InvalidCurrencyCode))
}

pub fn new_currency_rejects_negative_exponent_test() -> Nil {
  currency.new_currency(code: "ABC", exponent: -1, symbol: "X", name: "Bad")
  |> should.equal(Error(currency.InvalidExponent))
}

pub fn new_currency_rejects_huge_exponent_test() -> Nil {
  currency.new_currency(code: "ABC", exponent: 9, symbol: "X", name: "Bad")
  |> should.equal(Error(currency.InvalidExponent))
}

// --- Catalogue ----------------------------------------------------------

pub fn catalogue_usd_test() -> Nil {
  let c = catalog.usd()
  currency.code(c)
  |> should.equal("USD")
  currency.exponent(c)
  |> should.equal(2)
}

pub fn catalogue_jpy_test() -> Nil {
  let c = catalog.jpy()
  currency.code(c)
  |> should.equal("JPY")
  currency.exponent(c)
  |> should.equal(0)
}

pub fn catalogue_size_test() -> Nil {
  catalog.all()
  |> list_length
  |> should.equal(15)
}

pub fn catalogue_find_known_test() -> Nil {
  let assert Ok(c) = catalog.find(code: "EUR")
  currency.code(c)
  |> should.equal("EUR")
}

pub fn catalogue_find_unknown_test() -> Nil {
  catalog.find(code: "XYZ")
  |> should.equal(Error(Nil))
}

// --- Money construction -------------------------------------------------

pub fn from_minor_test() -> Nil {
  let m = currency.from_minor(units: 1234, currency: catalog.usd())
  currency.amount(m)
  |> decimal.to_string
  |> should.equal("12.34")
}

pub fn from_minor_jpy_test() -> Nil {
  let m = currency.from_minor(units: 5000, currency: catalog.jpy())
  currency.amount(m)
  |> decimal.to_string
  |> should.equal("5000")
}

pub fn to_minor_test() -> Nil {
  let m = currency.from_minor(units: 1234, currency: catalog.usd())
  currency.to_minor(m: m, mode: rounding.HalfEven)
  |> should.equal(Ok(1234))
}

pub fn from_major_usd_test() -> Nil {
  // $35 — two-exponent currency, but `from_major` does not scale by
  // the exponent so the human-readable amount lands as-is.
  let m = currency.from_major(amount: 35, currency: catalog.usd())
  currency.amount(m)
  |> decimal.to_string
  |> should.equal("35")
}

pub fn from_major_jpy_test() -> Nil {
  // ¥3,500 — zero-exponent currency. Same shape as `from_minor` for
  // this case; documenting that callers no longer have to pick
  // between the two for major-unit ingestion.
  let m = currency.from_major(amount: 3500, currency: catalog.jpy())
  currency.amount(m)
  |> decimal.to_string
  |> should.equal("3500")
}

pub fn from_major_round_trips_via_to_minor_test() -> Nil {
  // $35 → 3500 cents. Confirms `from_major` lines up with the
  // existing minor-unit machinery for the two-exponent case.
  let m = currency.from_major(amount: 35, currency: catalog.usd())
  currency.to_minor(m: m, mode: rounding.HalfEven)
  |> should.equal(Ok(3500))
}

pub fn to_minor_with_finer_precision_test() -> Nil {
  // $1.005 → 100 (banker's rounding because 100.5 ties, 100 is even).
  let assert Ok(amount) = decimal.from_string("1.005")
  let m = currency.new_money(amount: amount, currency: catalog.usd())
  currency.to_minor(m: m, mode: rounding.HalfEven)
  |> should.equal(Ok(100))
}

// --- Money arithmetic ---------------------------------------------------

pub fn add_same_currency_test() -> Nil {
  let a = currency.from_minor(units: 100, currency: catalog.usd())
  let b = currency.from_minor(units: 250, currency: catalog.usd())
  let assert Ok(sum) = currency.add(a: a, b: b)
  let assert Ok(units) = currency.to_minor(m: sum, mode: rounding.HalfEven)
  units
  |> should.equal(350)
}

pub fn add_currency_mismatch_test() -> Nil {
  let a = currency.from_minor(units: 100, currency: catalog.usd())
  let b = currency.from_minor(units: 100, currency: catalog.eur())
  currency.add(a: a, b: b)
  |> should.equal(Error(currency.CurrencyMismatch(left: "USD", right: "EUR")))
}

pub fn subtract_test() -> Nil {
  let a = currency.from_minor(units: 1000, currency: catalog.usd())
  let b = currency.from_minor(units: 250, currency: catalog.usd())
  let assert Ok(diff) = currency.subtract(a: a, b: b)
  let assert Ok(units) = currency.to_minor(m: diff, mode: rounding.HalfEven)
  units
  |> should.equal(750)
}

// --- Sum -----------------------------------------------------------------

// Issue #68: sum a list of Money values without the per-call-site
// `list.fold + nested case + propagate CurrencyError` boilerplate.

pub fn sum_empty_list_returns_error_test() -> Nil {
  currency.sum(items: [])
  |> should.equal(Error(currency.EmptyList))
}

pub fn sum_single_currency_test() -> Nil {
  let usd = catalog.usd()
  let items = [
    currency.from_minor(units: 100, currency: usd),
    currency.from_minor(units: 250, currency: usd),
  ]
  let assert Ok(total) = currency.sum(items: items)
  let assert Ok(units) = currency.to_minor(m: total, mode: rounding.HalfEven)
  units |> should.equal(350)
}

pub fn sum_singleton_returns_only_element_test() -> Nil {
  let item = currency.from_minor(units: 4242, currency: catalog.usd())
  let assert Ok(total) = currency.sum(items: [item])
  currency.equal(total, item) |> should.be_true
}

pub fn sum_currency_mismatch_returns_error_test() -> Nil {
  let usd = currency.from_minor(units: 100, currency: catalog.usd())
  let eur = currency.from_minor(units: 50, currency: catalog.eur())
  currency.sum(items: [usd, eur])
  |> should.equal(Error(currency.CurrencyMismatch(left: "USD", right: "EUR")))
}

pub fn sum_with_zero_empty_returns_fallback_test() -> Nil {
  let zero = currency.from_minor(units: 0, currency: catalog.usd())
  let assert Ok(total) = currency.sum_with_zero(items: [], fallback: zero)
  currency.equal(total, zero) |> should.be_true
}

pub fn sum_with_zero_non_empty_test() -> Nil {
  let zero = currency.from_minor(units: 0, currency: catalog.usd())
  let items = [
    currency.from_minor(units: 100, currency: catalog.usd()),
    currency.from_minor(units: 200, currency: catalog.usd()),
    currency.from_minor(units: 50, currency: catalog.usd()),
  ]
  let assert Ok(total) = currency.sum_with_zero(items: items, fallback: zero)
  let assert Ok(units) = currency.to_minor(m: total, mode: rounding.HalfEven)
  units |> should.equal(350)
}

pub fn sum_with_zero_currency_mismatch_against_fallback_test() -> Nil {
  let zero = currency.from_minor(units: 0, currency: catalog.usd())
  let eur = currency.from_minor(units: 50, currency: catalog.eur())
  currency.sum_with_zero(items: [eur], fallback: zero)
  |> should.equal(Error(currency.CurrencyMismatch(left: "USD", right: "EUR")))
}

pub fn multiply_test() -> Nil {
  let m = currency.from_minor(units: 1000, currency: catalog.usd())
  let factor = decimal.from_int(n: 3)
  let assert Ok(product) = currency.multiply(m: m, factor: factor)
  let assert Ok(units) = currency.to_minor(m: product, mode: rounding.HalfEven)
  units
  |> should.equal(3000)
}

pub fn multiply_jpy_respects_zero_exponent_test() -> Nil {
  let m = currency.from_minor(units: 100, currency: catalog.jpy())
  let assert Ok(factor) = decimal.from_string("0.5")
  let assert Ok(product) = currency.multiply(m: m, factor: factor)
  currency.to_string(m: product)
  |> should.equal("JPY 50")
}

pub fn multiply_jpy_small_factor_rounds_to_zero_test() -> Nil {
  let m = currency.from_minor(units: 100, currency: catalog.jpy())
  let assert Ok(factor) = decimal.from_string("0.001")
  let assert Ok(product) = currency.multiply(m: m, factor: factor)
  // 100 * 0.001 = 0.1 → HalfEven rounds to 0 for JPY (exponent 0).
  currency.to_string(m: product)
  |> should.equal("JPY 0")
}

pub fn multiply_usd_keeps_two_decimals_test() -> Nil {
  let m = currency.from_minor(units: 10_000, currency: catalog.usd())
  let assert Ok(factor) = decimal.from_string("0.5")
  let assert Ok(product) = currency.multiply(m: m, factor: factor)
  currency.to_string(m: product)
  |> should.equal("USD 50.00")
}

pub fn divide_test() -> Nil {
  let m = currency.from_minor(units: 1000, currency: catalog.usd())
  let divisor = decimal.from_int(n: 3)
  let assert Ok(quotient) =
    currency.divide(m: m, divisor: divisor, mode: rounding.HalfEven)
  // $10.00 / 3 = $3.3333..., rounded to 2 dp = $3.33
  let assert Ok(units) = currency.to_minor(m: quotient, mode: rounding.HalfEven)
  units
  |> should.equal(333)
}

pub fn negate_test() -> Nil {
  let m = currency.from_minor(units: 500, currency: catalog.usd())
  let neg = currency.negate(m: m)
  let assert Ok(units) = currency.to_minor(m: neg, mode: rounding.HalfEven)
  units
  |> should.equal(-500)
}

// --- Allocation --------------------------------------------------------

pub fn allocate_even_test() -> Nil {
  // $10.00 split 3 ways → $3.34, $3.33, $3.33 (remainder to first slot)
  let m = currency.from_minor(units: 1000, currency: catalog.usd())
  let assert Ok(parts) = currency.allocate(m: m, ratios: [1, 1, 1])
  parts
  |> list_map(fn(p) {
    let assert Ok(units) = currency.to_minor(m: p, mode: rounding.HalfEven)
    units
  })
  |> should.equal([334, 333, 333])
}

pub fn allocate_weighted_test() -> Nil {
  // $10.00 split 1:2:1 → $2.50, $5.00, $2.50
  let m = currency.from_minor(units: 1000, currency: catalog.usd())
  let assert Ok(parts) = currency.allocate(m: m, ratios: [1, 2, 1])
  parts
  |> list_map(fn(p) {
    let assert Ok(units) = currency.to_minor(m: p, mode: rounding.HalfEven)
    units
  })
  |> should.equal([250, 500, 250])
}

pub fn allocate_preserves_total_test() -> Nil {
  // Property: sum of allocated parts equals the original
  let m = currency.from_minor(units: 9999, currency: catalog.usd())
  let assert Ok(parts) = currency.allocate(m: m, ratios: [3, 5, 2])
  let total =
    parts
    |> list_fold(0, fn(acc, p) {
      let assert Ok(units) = currency.to_minor(m: p, mode: rounding.HalfEven)
      acc + units
    })
  total
  |> should.equal(9999)
}

pub fn allocate_rejects_empty_ratios_test() -> Nil {
  let m = currency.from_minor(units: 100, currency: catalog.usd())
  currency.allocate(m: m, ratios: [])
  |> should.equal(Error(currency.EmptyRatios))
}

pub fn allocate_accepts_zero_in_mixed_list_test() -> Nil {
  // `[1, 0, 1]` is the "skip the middle recipient" pattern. As of
  // #49 the function distributes across the non-zero slots and
  // assigns zero to the skipped slot.
  let m = currency.from_minor(units: 10_000, currency: catalog.usd())
  let assert Ok(parts) = currency.allocate(m: m, ratios: [1, 0, 1])
  let amounts =
    list.map(parts, fn(p) {
      let assert Ok(units) = currency.to_minor(m: p, mode: rounding.HalfEven)
      units
    })
  amounts |> should.equal([5000, 0, 5000])
}

pub fn allocate_accepts_zero_at_edges_test() -> Nil {
  let m = currency.from_minor(units: 10_000, currency: catalog.usd())
  let assert Ok(parts) = currency.allocate(m: m, ratios: [0, 1, 0])
  let amounts =
    list.map(parts, fn(p) {
      let assert Ok(units) = currency.to_minor(m: p, mode: rounding.HalfEven)
      units
    })
  amounts |> should.equal([0, 10_000, 0])
}

pub fn allocate_rejects_all_zeros_test() -> Nil {
  let m = currency.from_minor(units: 100, currency: catalog.usd())
  currency.allocate(m: m, ratios: [0, 0, 0])
  |> should.equal(Error(currency.NonPositiveRatio))
}

pub fn allocate_rejects_negative_ratio_test() -> Nil {
  let m = currency.from_minor(units: 100, currency: catalog.usd())
  currency.allocate(m: m, ratios: [1, -1, 1])
  |> should.equal(Error(currency.NonPositiveRatio))
}

// --- Compare / equal ----------------------------------------------------

pub fn compare_test() -> Nil {
  let a = currency.from_minor(units: 100, currency: catalog.usd())
  let b = currency.from_minor(units: 200, currency: catalog.usd())
  currency.compare(a: a, b: b)
  |> should.equal(Ok(order.Lt))
  currency.compare(a: b, b: a)
  |> should.equal(Ok(order.Gt))
  currency.compare(a: a, b: a)
  |> should.equal(Ok(order.Eq))
}

pub fn compare_mismatch_test() -> Nil {
  let a = currency.from_minor(units: 100, currency: catalog.usd())
  let b = currency.from_minor(units: 100, currency: catalog.eur())
  currency.compare(a: a, b: b)
  |> result.is_error
  |> should.be_true
}

pub fn equal_same_test() -> Nil {
  let a = currency.from_minor(units: 100, currency: catalog.usd())
  let b = currency.from_minor(units: 100, currency: catalog.usd())
  currency.equal(a: a, b: b)
  |> should.be_true
}

pub fn equal_different_currency_returns_false_test() -> Nil {
  let a = currency.from_minor(units: 100, currency: catalog.usd())
  let b = currency.from_minor(units: 100, currency: catalog.eur())
  currency.equal(a: a, b: b)
  |> should.be_false
}

// --- Formatting --------------------------------------------------------

pub fn to_string_default_test() -> Nil {
  let m = currency.from_minor(units: 1234, currency: catalog.usd())
  currency.to_string(m: m)
  |> should.equal("USD 12.34")
}

pub fn format_default_prefix_test() -> Nil {
  let m = currency.from_minor(units: 123_456, currency: catalog.usd())
  currency.format(m: m, options: currency.default_format())
  |> should.equal("$1,234.56")
}

pub fn format_suffix_test() -> Nil {
  let m = currency.from_minor(units: 123_456, currency: catalog.eur())
  let opts =
    currency.with_symbol_position(
      options: currency.default_format(),
      position: currency.Suffix,
    )
  currency.format(m: m, options: opts)
  |> should.equal("1,234.56€")
}

pub fn format_no_symbol_test() -> Nil {
  let m = currency.from_minor(units: 123_456, currency: catalog.usd())
  let opts =
    currency.with_symbol_position(
      options: currency.default_format(),
      position: currency.NoSymbol,
    )
  currency.format(m: m, options: opts)
  |> should.equal("1,234.56")
}

pub fn format_negative_minus_test() -> Nil {
  let m = currency.from_minor(units: -123_456, currency: catalog.usd())
  currency.format(m: m, options: currency.default_format())
  |> should.equal("-$1,234.56")
}

pub fn format_negative_parentheses_test() -> Nil {
  let m = currency.from_minor(units: -123_456, currency: catalog.usd())
  let opts =
    currency.with_negative_style(
      options: currency.default_format(),
      style: currency.Parentheses,
    )
  currency.format(m: m, options: opts)
  |> should.equal("($1,234.56)")
}

pub fn format_custom_separators_test() -> Nil {
  let m = currency.from_minor(units: 123_456, currency: catalog.eur())
  let opts =
    currency.default_format()
    |> currency.with_thousands_separator(separator: ".")
    |> currency.with_decimal_separator(separator: ",")
    |> currency.with_symbol_position(position: currency.Suffix)
  currency.format(m: m, options: opts)
  |> should.equal("1.234,56€")
}

pub fn format_with_currency_code_test() -> Nil {
  let m = currency.from_minor(units: 1234, currency: catalog.usd())
  let opts =
    currency.default_format()
    |> currency.with_currency_code(enabled: True)
  currency.format(m: m, options: opts)
  |> should.equal("$12.34 USD")
}

pub fn format_jpy_no_decimals_test() -> Nil {
  let m = currency.from_minor(units: 12_345, currency: catalog.jpy())
  currency.format(m: m, options: currency.default_format())
  |> should.equal("¥12,345")
}

pub fn format_normalises_integer_amount_to_minor_units_test() -> Nil {
  // Whole dollars should render with two cents and a thousands sep.
  let m =
    currency.new_money(
      amount: decimal.from_int(n: 200_000),
      currency: catalog.usd(),
    )
  currency.format(m: m, options: currency.default_format())
  |> should.equal("$200,000.00")
}

pub fn format_minor_units_disabled_preserves_precision_test() -> Nil {
  // For FX-style four-decimal precision, opt out of minor-unit rescale.
  let assert Ok(amount) = decimal.from_string("1.2345")
  let m = currency.new_money(amount: amount, currency: catalog.usd())
  let opts =
    currency.default_format()
    |> currency.with_minor_units(enabled: False)
  currency.format(m: m, options: opts)
  |> should.equal("$1.2345")
}

pub fn format_minor_units_rounds_excess_precision_test() -> Nil {
  let assert Ok(amount) = decimal.from_string("12.345")
  let m = currency.new_money(amount: amount, currency: catalog.usd())
  // Default minor_units = True, HalfEven rounding: 12.345 → 12.34 (tie, even).
  currency.format(m: m, options: currency.default_format())
  |> should.equal("$12.34")
}

pub fn currency_of_test() -> Nil {
  let m = currency.from_minor(units: 100, currency: catalog.eur())
  m
  |> currency.currency_of
  |> currency.code
  |> should.equal("EUR")
}

// --- Helpers ------------------------------------------------------------

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

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
