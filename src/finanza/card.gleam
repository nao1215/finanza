//// Payment-card primitives: PAN normalisation, Luhn validation,
//// brand detection by IIN range, masking, BIN/last-four extraction,
//// and expiry parsing.
////
//// IIN ranges are a static snapshot of stable card-brand prefixes
//// and lengths and are *not* a BIN-to-issuer database. See
//// `doc/reference/specs/iso-iec-7812-card.md` for sources.

import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Recognised card brands. `Unknown` is returned when no IIN range
/// matches.
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

/// Errors raised by PAN operations.
pub type ValidationError {
  /// Input was empty or only contained whitespace and separators.
  EmptyInput
  /// Input contained a non-digit character after normalisation.
  InvalidCharacter
  /// The PAN's length is not valid for any recognised brand.
  InvalidLength(length: Int)
  /// The PAN failed the Luhn check.
  InvalidLuhn
  /// The PAN's prefix did not match any recognised brand IIN range.
  UnknownBrand
  /// Expiry parse received a malformed `MM/YY` or `MM/YYYY` value.
  InvalidExpiry
}

/// Options for [`mask`](#mask). Build with [`default_mask`](#default_mask)
/// and the `with_*` setters.
pub opaque type MaskOptions {
  MaskOptions(
    keep_first: Int,
    keep_last: Int,
    mask_char: String,
    group_size: Int,
    group_separator: String,
  )
}

// --- Normalisation ------------------------------------------------------

/// Strip ASCII whitespace (` `, `\t`, `\n`, `\r`, VT, FF) and
/// hyphen-style separators (`-`, `_`, `.`). Does not validate that
/// the result is digits-only. Unicode whitespace (NBSP, ideographic
/// space) is not stripped — pre-normalise if needed.
pub fn normalize(pan pan: String) -> String {
  pan
  |> string.to_graphemes
  |> list.filter(keeping: is_pan_char)
  |> string.concat
}

fn is_pan_char(grapheme: String) -> Bool {
  case grapheme {
    " " | "\t" | "\n" | "\r" | "\u{000B}" | "\u{000C}" -> False
    "-" | "_" | "." -> False
    _ -> True
  }
}

// --- Luhn ---------------------------------------------------------------

/// Apply the Luhn check to a digit string.
///
/// Returns `False` when `digits` is empty or contains any non-digit
/// character (`"abc"`, `" "`, `"4242 4242 4242 4242"`, etc.). The
/// caller can still normalise dynamic input through `normalize`, but
/// passing un-normalised input is no longer a silent bug — the
/// previous behaviour treated every non-digit as "skip" and returned
/// `True` for any all-non-digit input because the partial sum
/// landed on zero.
pub fn luhn_valid(digits digits: String) -> Bool {
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

/// Detect the brand of a PAN by inspecting its IIN prefix and length.
/// Returns [`Unknown`](#Brand) when no rule matches.
pub fn detect_brand(pan pan: String) -> Brand {
  let normalised = normalize(pan: pan)
  case digits_only(normalised) {
    Ok(_) -> classify_brand(normalised)
    Error(InvalidCharacter)
    | Error(EmptyInput)
    | Error(InvalidLength(_))
    | Error(InvalidLuhn)
    | Error(UnknownBrand)
    | Error(InvalidExpiry) -> Unknown
  }
}

fn classify_brand(pan: String) -> Brand {
  let length = string.length(pan)
  // Order matters: more specific prefixes (UnionPay 62 vs Discover 622)
  // are checked alongside their length constraints.
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
  || prefix_in_range(pan: pan, prefix_len: 6, low: 622_126, high: 622_925)
}

fn jcb_matches(pan: String, length: Int) -> Bool {
  use <- bool.guard(when: length < 16 || length > 19, return: False)
  prefix_in_range(pan: pan, prefix_len: 4, low: 3528, high: 3589)
}

fn diners_matches(pan: String, length: Int) -> Bool {
  // Diners Club International numbers per ISO/IEC 7812-1 are 14–19
  // digits long. Stripe / Braintree publish 16-digit Diners test
  // PANs (e.g. `3056930009020004`); restricting to length 14 only
  // wrongly classifies those as `Unknown`.
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

/// Render a [`Brand`](#Brand) as a short upper-case identifier.
pub fn brand_to_string(brand brand: Brand) -> String {
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

/// Normalise the input, verify it contains only digits, check length
/// and Luhn, and return the detected [`Brand`](#Brand).
pub fn validate(pan pan: String) -> Result(Brand, ValidationError) {
  let normalised = normalize(pan: pan)
  use <- bool.guard(when: normalised == "", return: Error(EmptyInput))
  use _ <- result.try(digits_only(normalised))
  let length = string.length(normalised)
  use <- bool.guard(
    when: length < 12 || length > 19,
    return: Error(InvalidLength(length: length)),
  )
  use <- bool.guard(
    when: !luhn_valid(digits: normalised),
    return: Error(InvalidLuhn),
  )
  case classify_brand(normalised) {
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

/// Default [`MaskOptions`](#MaskOptions): keep the first 4 and last 4
/// digits, mask the rest with `*`, and group output as 4-digit blocks
/// separated by spaces.
pub fn default_mask() -> MaskOptions {
  MaskOptions(
    keep_first: 4,
    keep_last: 4,
    mask_char: "*",
    group_size: 4,
    group_separator: " ",
  )
}

/// Override the number of leading digits to preserve.
pub fn with_keep_first(
  options options: MaskOptions,
  count count: Int,
) -> MaskOptions {
  MaskOptions(..options, keep_first: count)
}

/// Override the number of trailing digits to preserve.
pub fn with_keep_last(
  options options: MaskOptions,
  count count: Int,
) -> MaskOptions {
  MaskOptions(..options, keep_last: count)
}

/// Override the character used to mask hidden digits.
pub fn with_mask_char(
  options options: MaskOptions,
  char char: String,
) -> MaskOptions {
  MaskOptions(..options, mask_char: char)
}

/// Override the grouping size (set to `0` for no grouping).
pub fn with_group_size(
  options options: MaskOptions,
  size size: Int,
) -> MaskOptions {
  MaskOptions(..options, group_size: size)
}

/// Override the separator inserted between groups.
pub fn with_group_separator(
  options options: MaskOptions,
  separator separator: String,
) -> MaskOptions {
  MaskOptions(..options, group_separator: separator)
}

/// Mask a PAN, preserving the configured number of leading and
/// trailing digits and grouping the output.
///
/// Grouping is segment-aware: the kept-first block, the mask block,
/// and the kept-last block are grouped independently. This keeps the
/// kept regions intact on irregular-length cards (15-digit AMEX,
/// 14-digit Diners Club) instead of letting their final digit bleed
/// into the next group.
pub fn mask(
  pan pan: String,
  options options: MaskOptions,
) -> Result(String, ValidationError) {
  let normalised = normalize(pan: pan)
  use <- bool.guard(when: normalised == "", return: Error(EmptyInput))
  use _ <- result.try(digits_only(normalised))
  let length = string.length(normalised)
  let keep_first = clamp(value: options.keep_first, low: 0, high: length)
  let keep_last =
    clamp(value: options.keep_last, low: 0, high: length - keep_first)
  let mask_count = length - keep_first - keep_last
  let first_block = string.slice(normalised, 0, keep_first)
  let mask_block = string.repeat(options.mask_char, mask_count)
  let last_block = string.slice(normalised, length - keep_last, keep_last)
  // Group size <= 0 disables grouping: emit segments with no
  // separator so callers asking explicitly for an ungrouped string
  // get exactly that.
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

/// Extract the last four digits of a PAN.
pub fn last_four(pan pan: String) -> Result(String, ValidationError) {
  let normalised = normalize(pan: pan)
  use <- bool.guard(when: normalised == "", return: Error(EmptyInput))
  use _ <- result.try(digits_only(normalised))
  let length = string.length(normalised)
  use <- bool.guard(
    when: length < 4,
    return: Error(InvalidLength(length: length)),
  )
  Ok(string.slice(normalised, length - 4, 4))
}

/// Extract the BIN (first six digits) of a PAN.
pub fn bin(pan pan: String) -> Result(String, ValidationError) {
  let normalised = normalize(pan: pan)
  use <- bool.guard(when: normalised == "", return: Error(EmptyInput))
  use _ <- result.try(digits_only(normalised))
  let length = string.length(normalised)
  use <- bool.guard(
    when: length < 6,
    return: Error(InvalidLength(length: length)),
  )
  Ok(string.slice(normalised, 0, 6))
}

// --- Expiry -------------------------------------------------------------

/// Test whether the `expiry` date (`#(month, year)`) is on or after
/// `today` (`#(month, year)`). The month component of both tuples
/// must be in `1..=12`.
///
/// Tuples are used (rather than four labelled `Int` arguments) so that
/// the year/month order cannot be silently swapped at the call site.
pub fn expiry_valid(
  expiry expiry: #(Int, Int),
  today today: #(Int, Int),
) -> Bool {
  let #(month, year) = expiry
  let #(today_month, today_year) = today
  use <- bool.guard(when: month < 1 || month > 12, return: False)
  use <- bool.guard(when: today_month < 1 || today_month > 12, return: False)
  use <- bool.guard(when: year > today_year, return: True)
  use <- bool.guard(when: year < today_year, return: False)
  month >= today_month
}

/// Parse a `"MM/YY"` or `"MM/YYYY"` expiry string into a
/// `#(month, year)` tuple. Years given as two digits are expanded by
/// prefixing `20`.
pub fn parse_expiry(input input: String) -> Result(#(Int, Int), ValidationError) {
  case string.split(input, "/") {
    [month_str, year_str] -> {
      use month <- result.try(parse_month(month_str))
      use year <- result.map(parse_year(year_str))
      #(month, year)
    }
    _ -> Error(InvalidExpiry)
  }
}

fn parse_month(s: String) -> Result(Int, ValidationError) {
  case int.parse(string.trim(s)) {
    Ok(m) if m >= 1 && m <= 12 -> Ok(m)
    _ -> Error(InvalidExpiry)
  }
}

fn parse_year(s: String) -> Result(Int, ValidationError) {
  let trimmed = string.trim(s)
  let length = string.length(trimmed)
  use <- bool.guard(
    when: length != 2 && length != 4,
    return: Error(InvalidExpiry),
  )
  case int.parse(trimmed) {
    Ok(y) if y < 0 -> Error(InvalidExpiry)
    Ok(y) if length == 4 -> Ok(y)
    Ok(y) -> Ok(2000 + y)
    Error(Nil) -> Error(InvalidExpiry)
  }
}
