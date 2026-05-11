//// A static snapshot of 15 major ISO 4217 currencies.
////
//// The snapshot is informational and is not refreshed against the
//// ISO 4217 maintenance register. For currencies outside the
//// catalogue, build a [`Currency`](../currency.html#Currency) directly
//// with [`currency.new_currency`](../currency.html#new_currency).

import gleam/list

import finanza/currency

/// US Dollar — `USD`, exponent 2, symbol `$`.
pub fn usd() -> currency.Currency {
  build(code: "USD", exponent: 2, symbol: "$", name: "US Dollar")
}

/// Euro — `EUR`, exponent 2, symbol `€`.
pub fn eur() -> currency.Currency {
  build(code: "EUR", exponent: 2, symbol: "€", name: "Euro")
}

/// Japanese Yen — `JPY`, exponent 0, symbol `¥`.
pub fn jpy() -> currency.Currency {
  build(code: "JPY", exponent: 0, symbol: "¥", name: "Japanese Yen")
}

/// Pound Sterling — `GBP`, exponent 2, symbol `£`.
pub fn gbp() -> currency.Currency {
  build(code: "GBP", exponent: 2, symbol: "£", name: "Pound Sterling")
}

/// Swiss Franc — `CHF`, exponent 2, symbol `CHF`.
pub fn chf() -> currency.Currency {
  build(code: "CHF", exponent: 2, symbol: "CHF", name: "Swiss Franc")
}

/// Canadian Dollar — `CAD`, exponent 2, symbol `$`.
pub fn cad() -> currency.Currency {
  build(code: "CAD", exponent: 2, symbol: "$", name: "Canadian Dollar")
}

/// Australian Dollar — `AUD`, exponent 2, symbol `$`.
pub fn aud() -> currency.Currency {
  build(code: "AUD", exponent: 2, symbol: "$", name: "Australian Dollar")
}

/// Renminbi — `CNY`, exponent 2, symbol `¥`.
pub fn cny() -> currency.Currency {
  build(code: "CNY", exponent: 2, symbol: "¥", name: "Renminbi")
}

/// Hong Kong Dollar — `HKD`, exponent 2, symbol `HK$`.
pub fn hkd() -> currency.Currency {
  build(code: "HKD", exponent: 2, symbol: "HK$", name: "Hong Kong Dollar")
}

/// Singapore Dollar — `SGD`, exponent 2, symbol `S$`.
pub fn sgd() -> currency.Currency {
  build(code: "SGD", exponent: 2, symbol: "S$", name: "Singapore Dollar")
}

/// South Korean Won — `KRW`, exponent 0, symbol `₩`.
pub fn krw() -> currency.Currency {
  build(code: "KRW", exponent: 0, symbol: "₩", name: "South Korean Won")
}

/// Indian Rupee — `INR`, exponent 2, symbol `₹`.
pub fn inr() -> currency.Currency {
  build(code: "INR", exponent: 2, symbol: "₹", name: "Indian Rupee")
}

/// Brazilian Real — `BRL`, exponent 2, symbol `R$`.
pub fn brl() -> currency.Currency {
  build(code: "BRL", exponent: 2, symbol: "R$", name: "Brazilian Real")
}

/// Mexican Peso — `MXN`, exponent 2, symbol `$`.
pub fn mxn() -> currency.Currency {
  build(code: "MXN", exponent: 2, symbol: "$", name: "Mexican Peso")
}

/// South African Rand — `ZAR`, exponent 2, symbol `R`.
pub fn zar() -> currency.Currency {
  build(code: "ZAR", exponent: 2, symbol: "R", name: "South African Rand")
}

/// All currencies in the static catalogue, in the order they appear
/// on this page.
pub fn all() -> List(currency.Currency) {
  [
    usd(),
    eur(),
    jpy(),
    gbp(),
    chf(),
    cad(),
    aud(),
    cny(),
    hkd(),
    sgd(),
    krw(),
    inr(),
    brl(),
    mxn(),
    zar(),
  ]
}

/// Look up a catalogue currency by its ISO 4217 alpha-3 code.
/// Codes are compared case-sensitively in upper case.
pub fn find(code code: String) -> Result(currency.Currency, Nil) {
  list.find(all(), fn(c) { currency.code(c) == code })
}

fn build(
  code code: String,
  exponent exponent: Int,
  symbol symbol: String,
  name name: String,
) -> currency.Currency {
  // nolint: assert_ok_pattern -- catalogue entries are static, hand-curated values that pass new_currency validation by construction.
  let assert Ok(c) =
    currency.new_currency(
      code: code,
      exponent: exponent,
      symbol: symbol,
      name: name,
    )
  c
}
