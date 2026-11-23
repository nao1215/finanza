//// Payment card numbers (PANs): Luhn check, brand detection, masking
//// and expiry dates.
////
//// Brands are detected from a fixed snapshot of prefix and length rules
//// taken in May 2026. This is not a BIN database and does not identify
//// issuers.

import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// A card brand. `Unknown` means no prefix and length rule matched.
///
pub type Brand {
  Visa
  Mastercard
  AmericanExpress
  Discover
  Jcb
  DinersClub
  UnionPay
  Unknown
}

/// Why a card number was rejected.
///
pub type ValidationError {
  /// Nothing was left after removing spaces and separators.
  EmptyInput
  /// A character other than a digit was left after `normalize`.
  InvalidCharacter
  /// The number has too few or too many digits.
  InvalidLength(length: Int)
  /// The number fails the Luhn check.
  InvalidLuhn
  /// The number passes the Luhn check but matches no brand.
  UnknownBrand
}

/// Options for `mask`. Start from `default_mask` and change the fields
/// you need.
///
pub type MaskOptions {
  MaskOptions(
    /// Digits to show at the start.
    keep_first: Int,
    /// Digits to show at the end.
    keep_last: Int,
    /// Shown in place of each hidden digit.
    mask_character: String,
    /// Digits per group. 0 or less turns grouping off.
    group_size: Int,
    /// Put between groups.
    group_separator: String,
  )
}

/// Shows the first 4 and last 4 digits, hides the rest with `*`, and
/// groups by 4 with spaces: `"4111 **** **** 1111"`.
///
pub const default_mask =
  MaskOptions(
    keep_first: 4,
    keep_last: 4,
    mask_character: "*",
    group_size: 4,
    group_separator: " ",
  )

/// A card expiry month and four-digit year.
///
pub type Expiry {
  Expiry(month: Int, year: Int)
}

// --- Normalization ------------------------------------------------------

/// Removes ASCII whitespace and the separators `-`, `_` and `.`, and
/// turns fullwidth and Arabic-Indic digits into ASCII digits. Other
/// characters are kept, so the result may still not be all digits.
///
/// ## Examples
///
/// ```gleam
/// card.normalize("4111-1111 1111.1111")
/// // -> "4111111111111111"
/// ```
///
pub fn normalize(pan: String) -> String {
  pan
  |> string.to_graphemes
  |> list.filter(keeping: is_pan_char)
  |> list.map(with: fold_digit_grapheme)
  |> string.concat
}

fn is_pan_char(grapheme: String) -> Bool {
  case grapheme {
    " " | "\t" | "\n" | "\r" | "\r\n" | "\u{000B}" | "\u{000C}" -> False
    "-" | "_" | "." -> False
    _ -> True
  }
}

fn fold_digit_grapheme(grapheme: String) -> String {
  case grapheme {
    "\u{FF10}" -> "0"
    "\u{FF11}" -> "1"
    "\u{FF12}" -> "2"
    "\u{FF13}" -> "3"
    "\u{FF14}" -> "4"
    "\u{FF15}" -> "5"
    "\u{FF16}" -> "6"
    "\u{FF17}" -> "7"
    "\u{FF18}" -> "8"
    "\u{FF19}" -> "9"
    "\u{0660}" -> "0"
    "\u{0661}" -> "1"
    "\u{0662}" -> "2"
    "\u{0663}" -> "3"
    "\u{0664}" -> "4"
    "\u{0665}" -> "5"
    "\u{0666}" -> "6"
    "\u{0667}" -> "7"
    "\u{0668}" -> "8"
    "\u{0669}" -> "9"
    "\u{06F0}" -> "0"
    "\u{06F1}" -> "1"
    "\u{06F2}" -> "2"
    "\u{06F3}" -> "3"
    "\u{06F4}" -> "4"
    "\u{06F5}" -> "5"
    "\u{06F6}" -> "6"
    "\u{06F7}" -> "7"
    "\u{06F8}" -> "8"
    "\u{06F9}" -> "9"
    _ -> grapheme
  }
}

// --- Luhn ---------------------------------------------------------------

/// Returns `True` when `digits` passes the Luhn check. Returns `False`
/// for an empty string or any character other than an ASCII digit, so
/// call `normalize` first on typed input.
///
/// ## Examples
///
/// ```gleam
/// card.luhn_valid("79927398713")
/// // -> True
/// ```
///
/// ```gleam
/// card.luhn_valid("7992 7398 713")
/// // -> False
/// ```
///
pub fn luhn_valid(digits: String) -> Bool {
  let chars = string.to_graphemes(digits)
  case list.is_empty(chars) || !all_digits(chars) {
    True -> False
    False -> luhn_sum(chars) % 10 == 0
  }
}

fn all_digits(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    [head, ..rest] ->
      case digit_value(head) {
        Ok(_) -> all_digits(rest)
        Error(Nil) -> False
      }
  }
}

fn luhn_sum(chars: List(String)) -> Int {
  chars
  |> list.reverse
  |> list.index_fold(0, fn(acc, char, index) {
    case digit_value(char) {
      Ok(v) -> acc + luhn_contribution(value: v, index: index)
      Error(Nil) -> acc
    }
  })
}

fn luhn_contribution(value value: Int, index index: Int) -> Int {
  use <- bool.guard(when: index % 2 == 0, return: value)
  let doubled = value * 2
  use <- bool.guard(when: doubled > 9, return: doubled - 9)
  doubled
}

fn digit_value(char: String) -> Result(Int, Nil) {
  case char {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    _ -> Error(Nil)
  }
}

// --- Brand detection ----------------------------------------------------

/// Returns the brand that the prefix and length of the normalized
/// number match, without the Luhn check. Use `validate` to check both.
///
pub fn detect_brand(pan: String) -> Brand {
  let normalized = normalize(pan)
  case digits_only(normalized) {
    Ok(_) -> classify_brand(normalized)
    Error(InvalidCharacter)
    | Error(EmptyInput)
    | Error(InvalidLength(_))
    | Error(InvalidLuhn)
    | Error(UnknownBrand) -> Unknown
  }
}

fn classify_brand(pan: String) -> Brand {
  let length = string.length(pan)
  // UnionPay is checked before Discover, so the co-branded range
  // 622126-622925 is reported as UnionPay.
  use <- bool.lazy_guard(when: amex_matches(pan, length), return: fn() {
    AmericanExpress
  })
  use <- bool.lazy_guard(when: diners_matches(pan, length), return: fn() {
    DinersClub
  })
  use <- bool.lazy_guard(when: jcb_matches(pan, length), return: fn() { Jcb })
  use <- bool.lazy_guard(when: mastercard_matches(pan, length), return: fn() {
    Mastercard
  })
  use <- bool.lazy_guard(when: visa_matches(pan, length), return: fn() { Visa })
  use <- bool.lazy_guard(when: unionpay_matches(pan, length), return: fn() {
    UnionPay
  })
  use <- bool.lazy_guard(when: discover_matches(pan, length), return: fn() {
    Discover
  })
  Unknown
}

fn visa_matches(pan: String, length: Int) -> Bool {
  starts_with(pan, "4") && { length == 13 || length == 16 || length == 19 }
}

fn mastercard_matches(pan: String, length: Int) -> Bool {
  use <- bool.guard(when: length != 16, return: False)
  prefix_in_range(pan: pan, prefix_len: 2, low: 51, high: 55)
  || prefix_in_range(pan: pan, prefix_len: 4, low: 2221, high: 2720)
}

fn amex_matches(pan: String, length: Int) -> Bool {
  length == 15 && { starts_with(pan, "34") || starts_with(pan, "37") }
}

fn discover_matches(pan: String, length: Int) -> Bool {
  use <- bool.guard(when: length < 16 || length > 19, return: False)
  starts_with(pan, "6011")
  || starts_with(pan, "65")
  || prefix_in_range(pan: pan, prefix_len: 3, low: 644, high: 649)
}

fn jcb_matches(pan: String, length: Int) -> Bool {
  use <- bool.guard(when: length < 16 || length > 19, return: False)
  prefix_in_range(pan: pan, prefix_len: 4, low: 3528, high: 3589)
}

fn diners_matches(pan: String, length: Int) -> Bool {
  // Diners numbers are 14 to 19 digits; payment providers publish
  // 16-digit test numbers such as 3056930009020004.
  use <- bool.guard(when: length < 14 || length > 19, return: False)
  prefix_in_range(pan: pan, prefix_len: 3, low: 300, high: 305)
  || starts_with(pan, "36")
  || starts_with(pan, "38")
  || starts_with(pan, "39")
}

fn unionpay_matches(pan: String, length: Int) -> Bool {
  starts_with(pan, "62") && length >= 16 && length <= 19
}

fn starts_with(pan: String, prefix: String) -> Bool {
  string.starts_with(pan, prefix)
}

fn prefix_in_range(
  pan pan: String,
  prefix_len prefix_len: Int,
  low low: Int,
  high high: Int,
) -> Bool {
  let prefix = string.slice(pan, 0, prefix_len)
  case int.parse(prefix) {
    Ok(value) -> value >= low && value <= high
    Error(Nil) -> False
  }
}

/// Returns a short upper-case name for the brand, such as `"VISA"` or
/// `"AMEX"`.
///
pub fn brand_to_string(brand: Brand) -> String {
  case brand {
    Visa -> "VISA"
    Mastercard -> "MASTERCARD"
    AmericanExpress -> "AMEX"
    Discover -> "DISCOVER"
    Jcb -> "JCB"
    DinersClub -> "DINERS"
    UnionPay -> "UNIONPAY"
    Unknown -> "UNKNOWN"
  }
}

// --- Full validation ----------------------------------------------------

/// Normalizes the number, then checks that it has 12 to 19 digits,
/// passes the Luhn check and matches a brand.
///
/// ## Examples
///
/// ```gleam
/// card.validate("4111 1111 1111 1111")
/// // -> Ok(card.Visa)
/// ```
///
/// ```gleam
/// card.validate("4111 1111 1111 1112")
/// // -> Error(card.InvalidLuhn)
/// ```
///
pub fn validate(pan: String) -> Result(Brand, ValidationError) {
  let normalized = normalize(pan)
  use <- bool.guard(when: normalized == "", return: Error(EmptyInput))
  use _ <- result.try(digits_only(normalized))
  let length = string.length(normalized)
  use <- bool.guard(
    when: length < 12 || length > 19,
    return: Error(InvalidLength(length: length)),
  )
  use <- bool.guard(when: !luhn_valid(normalized), return: Error(InvalidLuhn))
  case classify_brand(normalized) {
    Unknown -> Error(UnknownBrand)
    brand -> Ok(brand)
  }
}

fn digits_only(pan: String) -> Result(Nil, ValidationError) {
  let bad =
    pan
    |> string.to_graphemes
    |> list.any(fn(c) {
      case digit_value(c) {
        Ok(_) -> False
        Error(Nil) -> True
      }
    })
  case bad {
    True -> Error(InvalidCharacter)
    False -> Ok(Nil)
  }
}

// --- Masking and extraction --------------------------------------------

/// Normalizes the number and hides the middle digits. The shown start,
/// the hidden middle and the shown end are grouped separately, so a
/// 15-digit Amex keeps its last 4 digits together.
///
/// ## Examples
///
/// ```gleam
/// card.mask("378282246310005", with: card.default_mask)
/// // -> Ok("3782 **** *** 0005")
/// ```
///
pub fn mask(
  pan: String,
  with options: MaskOptions,
) -> Result(String, ValidationError) {
  let normalized = normalize(pan)
  use <- bool.guard(when: normalized == "", return: Error(EmptyInput))
  use _ <- result.try(digits_only(normalized))
  let length = string.length(normalized)
  let keep_first = clamp(value: options.keep_first, low: 0, high: length)
  let keep_last =
    clamp(value: options.keep_last, low: 0, high: length - keep_first)
  let mask_count = length - keep_first - keep_last
  let first_block = string.slice(normalized, 0, keep_first)
  let mask_block = string.repeat(options.mask_character, mask_count)
  let last_block = string.slice(normalized, length - keep_last, keep_last)
  let separator = case options.group_size <= 0 {
    True -> ""
    False -> options.group_separator
  }
  let segments =
    [first_block, mask_block, last_block]
    |> list.filter(keeping: fn(s) { s != "" })
    |> list.flat_map(with: fn(seg) {
      chunks(value: seg, size: options.group_size)
    })
  Ok(string.join(segments, with: separator))
}

fn clamp(value value: Int, low low: Int, high high: Int) -> Int {
  use <- bool.guard(when: value < low, return: low)
  use <- bool.guard(when: value > high, return: high)
  value
}

fn chunks(value value: String, size size: Int) -> List(String) {
  use <- bool.guard(when: size <= 0, return: [value])
  let chars = string.to_graphemes(value)
  chunks_loop(chars: chars, size: size, acc: [])
  |> list.reverse
  |> list.map(string.concat)
}

fn chunks_loop(
  chars chars: List(String),
  size size: Int,
  acc acc: List(List(String)),
) -> List(List(String)) {
  case chars {
    [] -> acc
    _ -> {
      let head = list.take(chars, size)
      let tail = list.drop(chars, size)
      chunks_loop(chars: tail, size: size, acc: [head, ..acc])
    }
  }
}

/// Returns the last 4 digits of the normalized number.
///
pub fn last_four(pan: String) -> Result(String, ValidationError) {
  let normalized = normalize(pan)
  use <- bool.guard(when: normalized == "", return: Error(EmptyInput))
  use _ <- result.try(digits_only(normalized))
  let length = string.length(normalized)
  use <- bool.guard(
    when: length < 4,
    return: Error(InvalidLength(length: length)),
  )
  Ok(string.slice(normalized, length - 4, 4))
}

/// Returns the first 6 digits of the normalized number, its bank
/// identification number.
///
pub fn bin(pan: String) -> Result(String, ValidationError) {
  let normalized = normalize(pan)
  use <- bool.guard(when: normalized == "", return: Error(EmptyInput))
  use _ <- result.try(digits_only(normalized))
  let length = string.length(normalized)
  use <- bool.guard(
    when: length < 6,
    return: Error(InvalidLength(length: length)),
  )
  Ok(string.slice(normalized, 0, 6))
}

// --- Expiry -------------------------------------------------------------

/// Returns `True` when a card with this expiry can still be used in the
/// month `today`, that is when `expiry` is not earlier than `today`.
/// Returns `False` when either month is outside 1 to 12.
///
/// ## Examples
///
/// ```gleam
/// card.expiry_valid(card.Expiry(month: 5, year: 2026), today: card.Expiry(month: 5, year: 2026))
/// // -> True
/// ```
///
pub fn expiry_valid(expiry: Expiry, today today: Expiry) -> Bool {
  use <- bool.guard(when: expiry.month < 1 || expiry.month > 12, return: False)
  use <- bool.guard(when: today.month < 1 || today.month > 12, return: False)
  use <- bool.guard(when: expiry.year > today.year, return: True)
  use <- bool.guard(when: expiry.year < today.year, return: False)
  expiry.month >= today.month
}

/// Parses an expiry written as `MM/YY`, `MM/YYYY`, `MMYY` or `MMYYYY`,
/// with `/`, `-` or `.` between the parts. Surrounding whitespace is
/// ignored, and a two-digit year `YY` means `20YY`. A one-digit month
/// needs a separator, since `"126"` could be January 2026 or December
/// 2006.
///
/// ## Examples
///
/// ```gleam
/// card.parse_expiry("12/28")
/// // -> Ok(card.Expiry(month: 12, year: 2028))
/// ```
///
/// ```gleam
/// card.parse_expiry("13/28")
/// // -> Error(Nil)
/// ```
///
pub fn parse_expiry(input: String) -> Result(Expiry, Nil) {
  use #(month, year) <- result.try(extract_month_year(string.trim(input)))
  use month <- result.try(parse_month(month))
  use year <- result.map(parse_year(year))
  Expiry(month:, year:)
}

fn extract_month_year(trimmed: String) -> Result(#(String, String), Nil) {
  case split_on_first(trimmed, ["/", "-", "."]) {
    Ok(parts) -> Ok(parts)
    Error(Nil) ->
      case string.length(trimmed) {
        4 ->
          Ok(#(
            string.slice(from: trimmed, at_index: 0, length: 2),
            string.slice(from: trimmed, at_index: 2, length: 2),
          ))
        6 ->
          Ok(#(
            string.slice(from: trimmed, at_index: 0, length: 2),
            string.slice(from: trimmed, at_index: 2, length: 4),
          ))
        _ -> Error(Nil)
      }
  }
}

fn split_on_first(
  input: String,
  separators: List(String),
) -> Result(#(String, String), Nil) {
  case separators {
    [] -> Error(Nil)
    [head, ..rest] ->
      case string.split_once(input, on: head) {
        Ok(parts) -> Ok(parts)
        Error(Nil) -> split_on_first(input, rest)
      }
  }
}

fn parse_month(text: String) -> Result(Int, Nil) {
  case int.parse(string.trim(text)) {
    Ok(month) if month >= 1 && month <= 12 -> Ok(month)
    _ -> Error(Nil)
  }
}

fn parse_year(text: String) -> Result(Int, Nil) {
  let trimmed = string.trim(text)
  case string.length(trimmed), int.parse(trimmed) {
    _, Ok(year) if year < 0 -> Error(Nil)
    4, Ok(year) -> Ok(year)
    2, Ok(year) -> Ok(2000 + year)
    _, _ -> Error(Nil)
  }
}
