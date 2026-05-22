//// Currency and money types built on top of
//// [`finanza/decimal`](./decimal.html).
////
//// A [`Currency`](#Currency) is a small record describing an ISO 4217
//// alpha-3 code together with display metadata. A
//// [`Money`](#Money) pairs a `Decimal` amount with a `Currency` so
//// arithmetic that crosses currencies is rejected with a typed error.
////
//// Both types are `pub opaque`. Build them through the smart
//// constructors [`new_currency`](#new_currency) and
//// [`new`](#new) (for `Money`), or pick a catalogue value from
//// [`finanza/currency/catalog`](./currency/catalog.html).

import gleam/bool
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

import finanza/decimal
import finanza/decimal/rounding

/// A monetary unit identified by an ISO 4217 alpha-3 code.
pub opaque type Currency {
  Currency(code: String, exponent: Int, symbol: String, name: String)
}

/// An amount denominated in a particular [`Currency`](#Currency).
pub opaque type Money {
  Money(amount: decimal.Decimal, currency: Currency)
}

/// Errors raised by currency and money operations.
pub type CurrencyError {
  /// Two operands had different currencies.
  CurrencyMismatch(left: String, right: String)
  /// `exponent` passed to [`new_currency`](#new_currency) was out of
  /// the supported range (0–8).
  InvalidExponent
  /// `code` passed to [`new_currency`](#new_currency) was empty.
  InvalidCurrencyCode
  /// [`allocate`](#allocate) was called with an empty ratio list.
  EmptyRatios
  /// [`allocate`](#allocate) received a ratio that was zero or
  /// negative.
  NonPositiveRatio
  /// [`sum`](#sum) was called with an empty list. The total has no
  /// well-defined currency in that case. Use
  /// [`sum_with_zero`](#sum_with_zero) when the empty input should
  /// fold to zero in a known currency.
  EmptyList
  /// A decimal operation overflowed the supported precision window.
  /// Inspect `error` for the underlying decimal error.
  ArithmeticError(error: decimal.ArithmeticError)
}

/// Where the currency symbol appears in formatted output.
pub type SymbolPosition {
  Prefix
  Suffix
  NoSymbol
}

/// How negative amounts are rendered in formatted output.
pub type NegativeStyle {
  MinusSign
  Parentheses
}

/// Options passed to [`format`](#format). Build from
/// [`default_format`](#default_format) and the `with_*` setters.
pub opaque type FormatOptions {
  FormatOptions(
    symbol_position: SymbolPosition,
    thousands_separator: String,
    decimal_separator: String,
    negative_style: NegativeStyle,
    show_currency_code: Bool,
    minor_units: Bool,
  )
}

// --- Currency construction & accessors ----------------------------------

/// Build a custom [`Currency`](#Currency). Use this when the desired
/// currency is outside the static catalogue.
///
/// `code` must be a non-empty string. `exponent` is the number of
/// minor-unit digits and must be in the range 0–8.
pub fn new_currency(
  code code: String,
  exponent exponent: Int,
  symbol symbol: String,
  name name: String,
) -> Result(Currency, CurrencyError) {
  use <- bool.guard(when: code == "", return: Error(InvalidCurrencyCode))
  use <- bool.guard(
    when: exponent < 0 || exponent > 8,
    return: Error(InvalidExponent),
  )
  Ok(Currency(code: code, exponent: exponent, symbol: symbol, name: name))
}

/// ISO 4217 alpha-3 code (e.g. `"USD"`).
pub fn code(c c: Currency) -> String {
  c.code
}

/// Minor-unit exponent (USD = 2, JPY = 0, BHD = 3, etc.).
pub fn exponent(c c: Currency) -> Int {
  c.exponent
}

/// Display symbol (e.g. `"$"`, `"¥"`).
pub fn symbol(c c: Currency) -> String {
  c.symbol
}

/// English-language name of the currency.
pub fn name(c c: Currency) -> String {
  c.name
}

// --- Money construction & accessors -------------------------------------

/// Build a `Money` from a [`Decimal`](./decimal.html#Decimal) and a
/// [`Currency`](#Currency). Named `new_money` rather than `new` to
/// keep symmetry with [`new_currency`](#new_currency) and to avoid
/// the surprise of `currency.new` returning the *other* type from
/// the module's name.
pub fn new_money(
  amount amount: decimal.Decimal,
  currency currency: Currency,
) -> Money {
  Money(amount: amount, currency: currency)
}

/// Build a `Money` from an integer number of minor units. The
/// resulting amount has exponent `-currency.exponent`.
///
/// `from_minor(units: 1234, currency: catalog.usd())` represents
/// `$12.34`.
pub fn from_minor(units units: Int, currency currency: Currency) -> Money {
  Money(
    amount: decimal.new(coefficient: units, exponent: -currency.exponent),
    currency: currency,
  )
}

/// Build a `Money` from an integer number of *major* units — the
/// whole-currency amount a human would read off a price tag.
///
/// `from_major(amount: 35, currency: catalog.usd())` represents `$35`,
/// and `from_major(amount: 3500, currency: catalog.jpy())` represents
/// `¥3,500`. Both calls produce the same kind of value regardless of
/// the currency's `exponent`, so callers do not have to pre-multiply
/// by `10 ^ exponent` to compensate (the silent off-by-100× footgun
/// `from_minor` has on two-exponent currencies like USD or EUR when
/// the input is actually a major-unit integer).
///
/// Use `from_minor` instead when you already hold a minor-unit
/// integer — for example, a value loaded from a `cents` column in a
/// database.
pub fn from_major(amount amount: Int, currency currency: Currency) -> Money {
  Money(amount: decimal.from_int(n: amount), currency: currency)
}

/// Convert a `Money` back to its minor-unit integer count, rounding
/// to the currency's exponent using `mode`.
pub fn to_minor(
  m m: Money,
  mode mode: rounding.Mode,
) -> Result(Int, CurrencyError) {
  use rescaled <- result.map(
    decimal.rescale(m.amount, -m.currency.exponent, mode)
    |> result.map_error(ArithmeticError),
  )
  decimal.coefficient(rescaled)
}

/// The amount component of a `Money`.
pub fn amount(m m: Money) -> decimal.Decimal {
  m.amount
}

/// The currency component of a `Money`. Named `currency_of` to avoid
/// a `currency.currency(m)` call site, which reads awkwardly given
/// the module name.
pub fn currency_of(m m: Money) -> Currency {
  m.currency
}

// --- Money arithmetic ----------------------------------------------------

/// Add two `Money` values. Both operands must share the same
/// currency.
pub fn add(a a: Money, b b: Money) -> Result(Money, CurrencyError) {
  use _ <- result.try(require_same_currency(a, b))
  use sum <- result.map(
    decimal.add(a.amount, b.amount) |> result.map_error(ArithmeticError),
  )
  Money(amount: sum, currency: a.currency)
}

/// Subtract `b` from `a`.
pub fn subtract(a a: Money, b b: Money) -> Result(Money, CurrencyError) {
  use _ <- result.try(require_same_currency(a, b))
  use diff <- result.map(
    decimal.subtract(a.amount, b.amount) |> result.map_error(ArithmeticError),
  )
  Money(amount: diff, currency: a.currency)
}

/// Sum a non-empty list of `Money` values, all of which must share
/// the same currency.
///
/// Removes the per-call-site `list.fold + nested case + propagate
/// CurrencyError` boilerplate that totalling line items, projecting
/// event-sourced balances, and computing batch subtotals all require
/// today.
///
/// Empty input has no well-defined currency, so returns
/// `Error(EmptyList)`. Use [`sum_with_zero`](#sum_with_zero) when an
/// empty list should fold to zero in a caller-supplied currency.
/// Mixed-currency input returns `Error(CurrencyMismatch(..))` at the
/// first divergence.
pub fn sum(items items: List(Money)) -> Result(Money, CurrencyError) {
  case items {
    [] -> Error(EmptyList)
    [head, ..rest] ->
      list.try_fold(rest, head, fn(acc, m) { add(a: acc, b: m) })
  }
}

/// Sum a list of `Money` values, falling back to `fallback` when the
/// list is empty. `fallback`'s currency is also the expected currency
/// for every element; the first divergence returns
/// `Error(CurrencyMismatch(..))`.
///
/// Use this entry point when the empty case is a meaningful "no
/// activity" outcome in a known currency — e.g. summing a customer's
/// daily transactions, where an empty day means `from_minor(0,
/// account_currency)` rather than an error.
pub fn sum_with_zero(
  items items: List(Money),
  fallback fallback: Money,
) -> Result(Money, CurrencyError) {
  list.try_fold(items, fallback, fn(acc, m) { add(a: acc, b: m) })
}

/// Multiply a money value by a scalar.
///
/// The product is rescaled to the currency's minor-unit exponent
/// using `HalfEven` so the resulting `Money` renders with exactly
/// the digits the currency supports — `JPY 100 × 0.5 → JPY 50`,
/// `USD 100.00 × 0.5 → USD 50.00`, `JPY 100 × 0.001 → JPY 0`.
/// Use `decimal.multiply` directly when you need the unrescaled
/// product (e.g. interest-rate calculations that downstream of
/// the multiply will rescale themselves).
pub fn multiply(
  m m: Money,
  factor factor: decimal.Decimal,
) -> Result(Money, CurrencyError) {
  use product <- result.try(
    decimal.multiply(m.amount, factor) |> result.map_error(ArithmeticError),
  )
  use rescaled <- result.map(
    decimal.rescale(
      d: product,
      target_exponent: -m.currency.exponent,
      mode: rounding.HalfEven,
    )
    |> result.map_error(ArithmeticError),
  )
  Money(amount: rescaled, currency: m.currency)
}

/// Divide a money value by a scalar, rounding the result to the
/// currency's minor-unit exponent using `mode`.
pub fn divide(
  m m: Money,
  divisor divisor: decimal.Decimal,
  mode mode: rounding.Mode,
) -> Result(Money, CurrencyError) {
  use quotient <- result.map(
    decimal.divide(
      a: m.amount,
      b: divisor,
      digits: m.currency.exponent,
      mode: mode,
    )
    |> result.map_error(ArithmeticError),
  )
  Money(amount: quotient, currency: m.currency)
}

/// Negate a money value.
pub fn negate(m m: Money) -> Money {
  Money(amount: decimal.negate(m.amount), currency: m.currency)
}

/// Compare two money values. Both operands must share the same
/// currency.
pub fn compare(a a: Money, b b: Money) -> Result(order.Order, CurrencyError) {
  use _ <- result.map(require_same_currency(a, b))
  decimal.compare(a.amount, b.amount)
}

/// Equality test for two money values. Returns `False` rather than an
/// error on currency mismatch, mirroring `==`.
pub fn equal(a a: Money, b b: Money) -> Bool {
  a.currency.code == b.currency.code && decimal.equal(a.amount, b.amount)
}

// --- Allocation ----------------------------------------------------------

/// Split a `Money` proportionally to `ratios`, distributing rounding
/// remainders to the first slots so the slices sum back to the
/// original amount exactly.
///
/// Zero ratios are accepted in a mixed list and mean "skip this
/// recipient" — `allocate(bill, [1, 0, 1])` distributes the bill
/// across the first and third slots and assigns zero to the middle
/// slot, preserving every slot's position in the result. Negative
/// ratios remain rejected with `NonPositiveRatio`, as does the
/// all-zero list (which has no positive share to distribute).
///
/// ```gleam
/// let bill = from_minor(units: 1000, currency: catalog.usd())
/// allocate(bill, [1, 1, 1])
/// // Ok([$3.34, $3.33, $3.33])
///
/// allocate(bill, [1, 0, 1])
/// // Ok([$5.00, $0.00, $5.00])
/// ```
pub fn allocate(
  m m: Money,
  ratios ratios: List(Int),
) -> Result(List(Money), CurrencyError) {
  use _ <- result.try(check_ratios(ratios))
  use minor_units <- result.map(to_minor(m: m, mode: rounding.HalfEven))
  let total_ratio = list.fold(ratios, 0, int.add)
  let shares =
    allocate_units(total: minor_units, ratios: ratios, total_ratio: total_ratio)
  list.map(shares, fn(s) { from_minor(units: s, currency: m.currency) })
}

fn check_ratios(ratios: List(Int)) -> Result(Nil, CurrencyError) {
  use <- bool.guard(when: list.is_empty(ratios), return: Error(EmptyRatios))
  use <- bool.guard(
    when: list.any(ratios, fn(r) { r < 0 }),
    return: Error(NonPositiveRatio),
  )
  use <- bool.guard(
    when: list.all(ratios, fn(r) { r == 0 }),
    return: Error(NonPositiveRatio),
  )
  Ok(Nil)
}

fn allocate_units(
  total total: Int,
  ratios ratios: List(Int),
  total_ratio total_ratio: Int,
) -> List(Int) {
  let sign = case total < 0 {
    True -> -1
    False -> 1
  }
  let abs_total = int.absolute_value(total)
  let initial_shares = list.map(ratios, fn(r) { abs_total * r / total_ratio })
  let used = list.fold(initial_shares, 0, int.add)
  let remainder = abs_total - used
  let distributed = distribute(initial_shares, remainder)
  list.map(distributed, fn(s) { sign * s })
}

fn distribute(shares: List(Int), remainder: Int) -> List(Int) {
  case shares, remainder {
    _, 0 -> shares
    [], _ -> shares
    [head, ..tail], _ -> [head + 1, ..distribute(tail, remainder - 1)]
  }
}

// --- Formatting ----------------------------------------------------------

/// Render a money value using the default ISO-style format:
/// `"USD 1234.56"`.
pub fn to_string(m m: Money) -> String {
  m.currency.code <> " " <> decimal.to_string(m.amount)
}

/// Default [`FormatOptions`](#FormatOptions): symbol prefix, `,`
/// thousands separator, `.` decimal separator, leading minus sign,
/// no currency code suffix, and the amount is rescaled to the
/// currency's minor-unit exponent (so USD always renders with two
/// cents, JPY with none, etc.).
pub fn default_format() -> FormatOptions {
  FormatOptions(
    symbol_position: Prefix,
    thousands_separator: ",",
    decimal_separator: ".",
    negative_style: MinusSign,
    show_currency_code: False,
    minor_units: True,
  )
}

/// Override the symbol position.
pub fn with_symbol_position(
  options options: FormatOptions,
  position position: SymbolPosition,
) -> FormatOptions {
  FormatOptions(..options, symbol_position: position)
}

/// Override the thousands separator.
pub fn with_thousands_separator(
  options options: FormatOptions,
  separator separator: String,
) -> FormatOptions {
  FormatOptions(..options, thousands_separator: separator)
}

/// Override the decimal separator.
pub fn with_decimal_separator(
  options options: FormatOptions,
  separator separator: String,
) -> FormatOptions {
  FormatOptions(..options, decimal_separator: separator)
}

/// Override the negative-amount style.
pub fn with_negative_style(
  options options: FormatOptions,
  style style: NegativeStyle,
) -> FormatOptions {
  FormatOptions(..options, negative_style: style)
}

/// Toggle whether the ISO code is appended to the rendered string.
pub fn with_currency_code(
  options options: FormatOptions,
  enabled enabled: Bool,
) -> FormatOptions {
  FormatOptions(..options, show_currency_code: enabled)
}

/// Toggle whether the amount is rescaled to the currency's
/// minor-unit exponent before rendering. Defaults to `True`; pass
/// `False` to preserve the amount's original precision (useful when
/// the value carries finer-than-minor digits, e.g. for an FX rate
/// or a unit price).
pub fn with_minor_units(
  options options: FormatOptions,
  enabled enabled: Bool,
) -> FormatOptions {
  FormatOptions(..options, minor_units: enabled)
}

/// Render a money value with the given [`FormatOptions`](#FormatOptions).
///
/// By default the amount is rescaled to the currency's minor-unit
/// exponent (so $12 renders as `$12.00` and ¥1234 as `¥1,234`). Call
/// [`with_minor_units`](#with_minor_units) with `False` to preserve
/// the amount's original precision.
pub fn format(m m: Money, options options: FormatOptions) -> String {
  let rescaled =
    scale_for_render(amount: m.amount, currency: m.currency, options: options)
  let raw = decimal.to_string(decimal.absolute(rescaled))
  let body = inject_separators(raw, options)
  let with_symbol =
    wrap_with_symbol(body: body, currency: m.currency, options: options)
  let signed =
    wrap_for_sign(
      body: with_symbol,
      is_negative: decimal.is_negative(rescaled),
      options: options,
    )
  case options.show_currency_code {
    True -> signed <> " " <> m.currency.code
    False -> signed
  }
}

fn scale_for_render(
  amount amount: decimal.Decimal,
  currency currency: Currency,
  options options: FormatOptions,
) -> decimal.Decimal {
  use <- bool.guard(when: !options.minor_units, return: amount)
  let target_exponent = -currency.exponent
  case decimal.rescale(amount, target_exponent, rounding.HalfEven) {
    Ok(scaled) -> scaled
    // PrecisionExceeded: fall back to the original amount so that
    // formatting never panics on an over-precise input. The numeric
    // value is preserved; only the cosmetic rescaling is skipped.
    Error(decimal.PrecisionExceeded) -> amount
    Error(decimal.DivisionByZero) -> amount
  }
}

fn inject_separators(raw: String, options: FormatOptions) -> String {
  let parts = string.split(raw, ".")
  case parts {
    [integer_part] ->
      insert_thousands(integer_part, options.thousands_separator)
    [integer_part, fraction_part] ->
      insert_thousands(integer_part, options.thousands_separator)
      <> options.decimal_separator
      <> fraction_part
    _ -> raw
  }
}

fn insert_thousands(digits: String, separator: String) -> String {
  case separator {
    "" -> digits
    _ -> {
      let chars = string.to_graphemes(digits)
      let length = list.length(chars)
      let groups = group_from_right(chars: chars, length: length, acc: [])
      list.map(groups, fn(group) { string.concat(group) })
      |> string.join(with: separator)
    }
  }
}

fn group_from_right(
  chars chars: List(String),
  length length: Int,
  acc acc: List(List(String)),
) -> List(List(String)) {
  use <- bool.guard(when: length <= 3, return: [chars, ..acc])
  let head_size = length - 3
  let head = list.take(chars, head_size)
  let tail = list.drop(chars, head_size)
  group_from_right(chars: head, length: head_size, acc: [tail, ..acc])
}

fn wrap_with_symbol(
  body body: String,
  currency currency: Currency,
  options options: FormatOptions,
) -> String {
  case options.symbol_position {
    Prefix -> currency.symbol <> body
    Suffix -> body <> currency.symbol
    NoSymbol -> body
  }
}

fn wrap_for_sign(
  body body: String,
  is_negative is_negative: Bool,
  options options: FormatOptions,
) -> String {
  use <- bool.guard(when: !is_negative, return: body)
  case options.negative_style {
    MinusSign -> "-" <> body
    Parentheses -> "(" <> body <> ")"
  }
}

// --- Internals -----------------------------------------------------------

fn require_same_currency(a: Money, b: Money) -> Result(Nil, CurrencyError) {
  use <- bool.guard(
    when: a.currency.code != b.currency.code,
    return: Error(CurrencyMismatch(
      left: a.currency.code,
      right: b.currency.code,
    )),
  )
  Ok(Nil)
}
