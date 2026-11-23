//// Amounts of money in a currency: arithmetic that refuses to mix
//// currencies, allocation without losing a cent, and formatting.
////
//// The 15 currency constants (`usd`, `eur`, `jpy`, ...) are a fixed
//// snapshot of ISO 4217 taken in May 2026. Build a `Currency` record
//// for anything else.

import gleam/bool
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

import finanza/decimal
import finanza/internal/rounded

const max_safe_integer: Int = 9_007_199_254_740_991

/// A currency: its ISO 4217 code, the number of digits in its minor
/// unit (2 for cents, 0 for yen), its symbol and its English name.
///
/// The exponent must be between 0 and 28, the places a `Decimal` can
/// have; `from_minor`, `to_minor`, `sum` and `allocate` return
/// `ArithmeticFailed(PrecisionExceeded)` for a currency outside it.
///
pub type Currency {
  Currency(code: String, exponent: Int, symbol: String, name: String)
}

/// An amount in a currency. The amount may have more or fewer places
/// than the currency's minor unit; `to_minor` and `format` round it.
///
pub type Money {
  Money(amount: decimal.Decimal, currency: Currency)
}

/// Why a money operation failed.
///
pub type MoneyError {
  /// The two amounts have different currency codes.
  CurrencyMismatch(left: String, right: String)
  /// `allocate` was given no ratios.
  EmptyRatios
  /// `allocate` was given a negative ratio, or only zeros.
  NonPositiveRatio
  /// The decimal arithmetic underneath failed.
  ArithmeticFailed(decimal.ArithmeticError)
}

/// Where `format` puts the currency symbol.
///
pub type SymbolPosition {
  Prefix
  Suffix
  NoSymbol
}

/// How `format` marks a negative amount.
///
pub type NegativeStyle {
  MinusSign
  Parentheses
}

/// Options for `format`. Start from `default_format` and change the
/// fields you need:
///
/// ```gleam
/// money.FormatOptions(..money.default_format, symbol_position: money.Suffix)
/// ```
///
pub type FormatOptions {
  FormatOptions(
    symbol_position: SymbolPosition,
    thousands_separator: String,
    decimal_separator: String,
    negative_style: NegativeStyle,
    /// Append a space and the currency code, as in `"$1.00 USD"`.
    show_currency_code: Bool,
    /// Round the amount half-even to the currency's minor unit, so
    /// dollars always have two places and yen none.
    round_to_minor_units: Bool,
  )
}

/// Formats as `"-$1,234.56"`: symbol first, comma thousands, a dot
/// before the cents, a minus sign, no code, and rounding to the minor
/// unit.
///
pub const default_format =
  FormatOptions(
    symbol_position: Prefix,
    thousands_separator: ",",
    decimal_separator: ".",
    negative_style: MinusSign,
    show_currency_code: False,
    round_to_minor_units: True,
  )

// Currencies -----------------------------------------------------------------

/// US Dollar.
///
pub const usd =
  Currency(code: "USD", exponent: 2, symbol: "$", name: "US Dollar")

/// Euro.
///
pub const eur = Currency(code: "EUR", exponent: 2, symbol: "€", name: "Euro")

/// Japanese Yen.
///
pub const jpy =
  Currency(code: "JPY", exponent: 0, symbol: "¥", name: "Japanese Yen")

/// Pound Sterling.
///
pub const gbp =
  Currency(code: "GBP", exponent: 2, symbol: "£", name: "Pound Sterling")

/// Swiss Franc.
///
pub const chf =
  Currency(code: "CHF", exponent: 2, symbol: "CHF", name: "Swiss Franc")

/// Canadian Dollar.
///
pub const cad =
  Currency(code: "CAD", exponent: 2, symbol: "$", name: "Canadian Dollar")

/// Australian Dollar.
///
pub const aud =
  Currency(code: "AUD", exponent: 2, symbol: "$", name: "Australian Dollar")

/// Renminbi.
///
pub const cny = Currency(code: "CNY", exponent: 2, symbol: "¥", name: "Renminbi")

/// Hong Kong Dollar.
///
pub const hkd =
  Currency(code: "HKD", exponent: 2, symbol: "HK$", name: "Hong Kong Dollar")

/// Singapore Dollar.
///
pub const sgd =
  Currency(code: "SGD", exponent: 2, symbol: "S$", name: "Singapore Dollar")

/// South Korean Won.
///
pub const krw =
  Currency(code: "KRW", exponent: 0, symbol: "₩", name: "South Korean Won")

/// Indian Rupee.
///
pub const inr =
  Currency(code: "INR", exponent: 2, symbol: "₹", name: "Indian Rupee")

/// Brazilian Real.
///
pub const brl =
  Currency(code: "BRL", exponent: 2, symbol: "R$", name: "Brazilian Real")

/// Mexican Peso.
///
pub const mxn =
  Currency(code: "MXN", exponent: 2, symbol: "$", name: "Mexican Peso")

/// South African Rand.
///
pub const zar =
  Currency(code: "ZAR", exponent: 2, symbol: "R", name: "South African Rand")

const currencies = [
  usd, eur, jpy, gbp, chf, cad, aud, cny, hkd, sgd, krw, inr, brl, mxn, zar,
]

/// Finds one of the 15 built-in currencies by its upper-case code.
///
/// ## Examples
///
/// ```gleam
/// money.find_currency("JPY")
/// // -> Ok(money.jpy)
/// ```
///
/// ```gleam
/// money.find_currency("XYZ")
/// // -> Error(Nil)
/// ```
///
pub fn find_currency(code: String) -> Result(Currency, Nil) {
  list.find(currencies, fn(currency) { currency.code == code })
}

// Construction ---------------------------------------------------------------

/// Creates money from a count of minor units, so 1234 cents is $12.34.
///
/// Returns `Error(ArithmeticFailed(PrecisionExceeded))` when the count
/// is outside ±9,007,199,254,740,991.
///
pub fn from_minor(
  units: Int,
  in currency: Currency,
) -> Result(Money, MoneyError) {
  decimal.new(coefficient: units, exponent: -currency.exponent)
  |> result.replace_error(ArithmeticFailed(decimal.PrecisionExceeded))
  |> result.map(Money(_, currency))
}

/// Creates money from a whole number of major units, so 35 is $35 and
/// 3500 is ¥3,500.
///
pub fn from_major(
  amount: Int,
  in currency: Currency,
) -> Result(Money, MoneyError) {
  decimal.from_int(amount)
  |> result.replace_error(ArithmeticFailed(decimal.PrecisionExceeded))
  |> result.map(Money(_, currency))
}

/// Rounds the amount to the currency's minor unit and returns the
/// count of minor units, so $12.345 rounded half-even is 1234.
///
pub fn to_minor(
  money: Money,
  rounding mode: decimal.RoundingMode,
) -> Result(Int, MoneyError) {
  decimal.round(money.amount, digits: money.currency.exponent, rounding: mode)
  |> result.map(decimal.coefficient)
  |> result.map_error(ArithmeticFailed)
}

// Arithmetic -----------------------------------------------------------------

/// Adds two amounts in the same currency.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(a) = money.from_minor(150, in: money.usd)
/// let assert Ok(b) = money.from_minor(1, in: money.eur)
/// money.add(a, b)
/// // -> Error(money.CurrencyMismatch(left: "USD", right: "EUR"))
/// ```
///
pub fn add(a: Money, b: Money) -> Result(Money, MoneyError) {
  combine(a, b, decimal.add)
}

/// Subtracts `b` from `a`. Both must be in the same currency.
///
pub fn subtract(a: Money, b: Money) -> Result(Money, MoneyError) {
  combine(a, b, decimal.subtract)
}

fn combine(
  a: Money,
  b: Money,
  operation: fn(decimal.Decimal, decimal.Decimal) ->
    Result(decimal.Decimal, decimal.ArithmeticError),
) -> Result(Money, MoneyError) {
  use <- bool.guard(
    when: a.currency.code != b.currency.code,
    return: Error(CurrencyMismatch(
      left: a.currency.code,
      right: b.currency.code,
    )),
  )
  operation(a.amount, b.amount)
  |> result.map(Money(_, a.currency))
  |> result.map_error(ArithmeticFailed)
}

/// Adds up amounts that are all in `currency`. An empty list sums to
/// zero.
///
pub fn sum(
  items: List(Money),
  in currency: Currency,
) -> Result(Money, MoneyError) {
  use zero <- result.try(from_minor(0, in: currency))
  list.try_fold(items, zero, add)
}

/// Multiplies the amount by `factor` and rounds the product to the
/// currency's minor unit.
///
/// The exact product is rounded, so only the rounded amount has to be
/// in the `Decimal` range: `USD 1234.57 × 1.234567890123456` is
/// `USD 1524.16` with `HalfEven`. Returns
/// `Error(ArithmeticFailed(PrecisionExceeded))` when the rounded amount
/// is out of range, or the currency's exponent is outside -15 to 28.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(price) = money.from_minor(999, in: money.usd)
/// let assert Ok(rate) = decimal.parse("0.08")
/// money.multiply(price, by: rate, rounding: decimal.HalfEven)
/// |> result.map(money.to_string)
/// // -> Ok("USD 0.80")
/// ```
///
pub fn multiply(
  money: Money,
  by factor: decimal.Decimal,
  rounding mode: decimal.RoundingMode,
) -> Result(Money, MoneyError) {
  rounded.multiply(
    money.amount,
    factor,
    digits: money.currency.exponent,
    rounding: mode,
  )
  |> result.map(Money(_, money.currency))
  |> result.map_error(ArithmeticFailed)
}

/// Divides the amount by `divisor` and rounds the quotient to the
/// currency's minor unit. Use `allocate` to split a bill without losing
/// the remainder.
///
pub fn divide(
  money: Money,
  by divisor: decimal.Decimal,
  rounding mode: decimal.RoundingMode,
) -> Result(Money, MoneyError) {
  decimal.divide(
    money.amount,
    divisor,
    digits: money.currency.exponent,
    rounding: mode,
  )
  |> result.map(Money(_, money.currency))
  |> result.map_error(ArithmeticFailed)
}

/// Returns the amount with its sign flipped.
///
pub fn negate(money: Money) -> Money {
  Money(..money, amount: decimal.negate(money.amount))
}

/// Compares two amounts in the same currency by value.
///
pub fn compare(a: Money, b: Money) -> Result(order.Order, MoneyError) {
  use <- bool.guard(
    when: a.currency.code != b.currency.code,
    return: Error(CurrencyMismatch(
      left: a.currency.code,
      right: b.currency.code,
    )),
  )
  Ok(decimal.compare(a.amount, b.amount))
}

/// Splits the amount in proportion to `ratios`. The amount is first
/// rounded half-even to the minor unit, and the minor units left over
/// go one each to the first slots with a non-zero ratio, so the parts
/// add up to the rounded amount. A zero ratio gets nothing.
///
/// Each share is exact on both targets, also for amounts near 2^53 − 1
/// minor units. Returns `Error(ArithmeticFailed(PrecisionExceeded))`
/// when the ratios add up to more than 2^53 − 1.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(bill) = money.from_minor(1000, in: money.usd)
/// money.allocate(bill, [1, 1, 1])
/// |> result.map(list.map(_, money.to_string))
/// // -> Ok(["USD 3.34", "USD 3.33", "USD 3.33"])
/// ```
///
/// ```gleam
/// money.allocate(bill, [0, 0])
/// // -> Error(money.NonPositiveRatio)
/// ```
///
pub fn allocate(
  money: Money,
  ratios: List(Int),
) -> Result(List(Money), MoneyError) {
  use <- bool.guard(when: ratios == [], return: Error(EmptyRatios))
  use <- bool.guard(
    when: list.any(ratios, fn(ratio) { ratio < 0 })
      || list.all(ratios, fn(ratio) { ratio == 0 }),
    return: Error(NonPositiveRatio),
  )
  let total_ratio = int.sum(ratios)
  use <- bool.guard(
    when: total_ratio > max_safe_integer,
    return: Error(ArithmeticFailed(decimal.PrecisionExceeded)),
  )
  use units <- result.try(to_minor(money, rounding: decimal.HalfEven))
  let magnitude = int.absolute_value(units)
  let whole = magnitude / total_ratio
  let rest = magnitude % total_ratio
  // magnitude × ratio / total_ratio, split so that no product passes
  // 2^53 − 1: whole × ratio is at most the magnitude, and the rest of
  // the share comes from multiplying modulo total_ratio.
  let shares =
    list.map(ratios, fn(ratio) {
      let #(extra, _) = multiply_modulo(rest, ratio, total_ratio)
      #(ratio, whole * ratio + extra)
    })
  let used = list.fold(shares, 0, fn(total, share) { total + share.1 })
  let sign = case units < 0 {
    True -> -1
    False -> 1
  }
  distribute(shares, magnitude - used, [])
  |> list.try_map(fn(share) { from_minor(sign * share, in: money.currency) })
}

// Returns the quotient and remainder of `value × times / modulus`, for
// `0 <= value < modulus`, by doubling and adding modulo `modulus`, so
// every intermediate value stays below `modulus` or the final quotient.
fn multiply_modulo(value: Int, times: Int, modulus: Int) -> #(Int, Int) {
  use <- bool.guard(when: times == 0, return: #(0, 0))
  let #(half_quotient, half_remainder) =
    multiply_modulo(value, times / 2, modulus)
  let #(carry, doubled) = add_modulo(half_remainder, half_remainder, modulus)
  let quotient = 2 * half_quotient + carry
  case times % 2 {
    0 -> #(quotient, doubled)
    _ -> {
      let #(carry, remainder) = add_modulo(doubled, value, modulus)
      #(quotient + carry, remainder)
    }
  }
}

// `a + b` modulo `modulus` and whether it wrapped, for `a` and `b` below
// `modulus`, without computing a sum that passes `modulus`.
fn add_modulo(a: Int, b: Int, modulus: Int) -> #(Int, Int) {
  let room = modulus - b
  case a >= room {
    True -> #(1, a - room)
    False -> #(0, a + b)
  }
}

// Adds one minor unit to each of the first `remainder` shares with a
// non-zero ratio. `done` collects the shares in reverse, so the loop
// calls itself last and runs in constant stack for any number of ratios.
fn distribute(
  shares: List(#(Int, Int)),
  remainder: Int,
  done: List(Int),
) -> List(Int) {
  case shares {
    [] -> list.reverse(done)
    [#(ratio, share), ..rest] if ratio > 0 && remainder > 0 ->
      distribute(rest, remainder - 1, [share + 1, ..done])
    [#(_, share), ..rest] -> distribute(rest, remainder, [share, ..done])
  }
}

// Formatting -----------------------------------------------------------------

/// Renders the code and the amount as stored, as in `"USD 12.30"`.
///
pub fn to_string(money: Money) -> String {
  money.currency.code <> " " <> decimal.to_string(money.amount)
}

/// Renders the amount for display.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(price) = money.from_minor(-123_456, in: money.eur)
/// let options =
///   money.FormatOptions(
///     ..money.default_format,
///     thousands_separator: ".",
///     decimal_separator: ",",
///     symbol_position: money.Suffix,
///     negative_style: money.Parentheses,
///   )
/// money.format(price, with: options)
/// // -> "(1.234,56€)"
/// ```
///
pub fn format(money: Money, with options: FormatOptions) -> String {
  let #(amount, padding) = case options.round_to_minor_units {
    True -> round_for_display(money, options.decimal_separator)
    False -> #(money.amount, "")
  }
  let digits =
    decimal.format(
      decimal.absolute(amount),
      thousands: options.thousands_separator,
      decimal_separator: options.decimal_separator,
    )
    <> padding
  let symbol = money.currency.symbol
  let body = case options.symbol_position {
    Prefix -> symbol <> digits
    Suffix -> digits <> symbol
    NoSymbol -> digits
  }
  let signed = case decimal.is_negative(amount), options.negative_style {
    False, _ -> body
    True, MinusSign -> "-" <> body
    True, Parentheses -> "(" <> body <> ")"
  }
  case options.show_currency_code {
    True -> signed <> " " <> money.currency.code
    False -> signed
  }
}

// Returns the amount rounded to the minor unit and any zeros to append
// to its text. Rounding only fails when padding an amount near the end
// of the decimal range, and then the zeros are added as text.
fn round_for_display(
  money: Money,
  separator: String,
) -> #(decimal.Decimal, String) {
  let places = money.currency.exponent
  case decimal.round(money.amount, digits: places, rounding: decimal.HalfEven) {
    Ok(rounded) -> #(rounded, "")
    Error(decimal.PrecisionExceeded) | Error(decimal.DivisionByZero) -> {
      let exponent = decimal.exponent(money.amount)
      case exponent >= 0 {
        True -> #(money.amount, separator <> string.repeat("0", places))
        False -> #(money.amount, string.repeat("0", places + exponent))
      }
    }
  }
}
