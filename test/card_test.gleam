import gleam/list
import gleam/string
import gleeunit/should

import finanza/card

// --- Normalisation ------------------------------------------------------

pub fn normalize_strips_spaces_and_hyphens_test() -> Nil {
  card.normalize("4111 1111 1111 1111")
  |> should.equal("4111111111111111")
  card.normalize("4111-1111-1111-1111")
  |> should.equal("4111111111111111")
}

pub fn normalize_strips_all_ascii_whitespace_test() -> Nil {
  card.normalize("4242\t4242\t4242\t4242")
  |> should.equal("4242424242424242")
  card.normalize("4242\n4242\n4242\n4242")
  |> should.equal("4242424242424242")
  card.normalize("4242\r4242\r4242\r4242")
  |> should.equal("4242424242424242")
  card.normalize("4242\u{000B}4242\u{000C}4242\t4242")
  |> should.equal("4242424242424242")
  card.normalize("4242\t4242\r4242\n4242")
  |> should.equal("4242424242424242")
}

// --- Luhn ---------------------------------------------------------------

pub fn luhn_wikipedia_example_test() -> Nil {
  // Wikipedia canonical example: 79927398713 passes Luhn.
  card.luhn_valid("79927398713")
  |> should.be_true
}

pub fn luhn_rejects_mutations_test() -> Nil {
  // Wikipedia notes: changing any digit makes the check fail.
  let mutations = [
    "79927398710", "79927398711", "79927398712", "79927398714", "79927398715",
    "79927398716", "79927398717", "79927398718", "79927398719",
  ]
  let result =
    mutations
    |> list_all(fn(s) { !card.luhn_valid(s) })
  result
  |> should.be_true
}

pub fn luhn_test_visa_test() -> Nil {
  card.luhn_valid("4111111111111111")
  |> should.be_true
}

pub fn luhn_test_mastercard_test() -> Nil {
  card.luhn_valid("5555555555554444")
  |> should.be_true
}

pub fn luhn_test_amex_test() -> Nil {
  card.luhn_valid("378282246310005")
  |> should.be_true
}

pub fn luhn_empty_string_test() -> Nil {
  card.luhn_valid("")
  |> should.be_false
}

pub fn luhn_rejects_all_letters_test() -> Nil {
  card.luhn_valid("abc")
  |> should.be_false
}

pub fn luhn_rejects_punctuation_test() -> Nil {
  card.luhn_valid("!@#$")
  |> should.be_false
}

pub fn luhn_rejects_single_space_test() -> Nil {
  card.luhn_valid(" ")
  |> should.be_false
}

pub fn luhn_rejects_emoji_test() -> Nil {
  card.luhn_valid("🙂🙂🙂🙂")
  |> should.be_false
}

pub fn luhn_rejects_mixed_digits_and_spaces_test() -> Nil {
  card.luhn_valid("4242 4242 4242 4242")
  |> should.be_false
}

// --- Brand detection ----------------------------------------------------

pub fn detect_visa_test() -> Nil {
  card.detect_brand("4111 1111 1111 1111")
  |> should.equal(card.Visa)
}

pub fn detect_mastercard_classic_test() -> Nil {
  card.detect_brand("5555555555554444")
  |> should.equal(card.Mastercard)
}

pub fn detect_mastercard_2series_test() -> Nil {
  card.detect_brand("2223003122003222")
  |> should.equal(card.Mastercard)
}

pub fn detect_amex_test() -> Nil {
  card.detect_brand("378282246310005")
  |> should.equal(card.AmericanExpress)
}

pub fn detect_discover_test() -> Nil {
  card.detect_brand("6011111111111117")
  |> should.equal(card.Discover)
}

pub fn detect_jcb_test() -> Nil {
  card.detect_brand("3530111333300000")
  |> should.equal(card.Jcb)
}

pub fn detect_diners_test() -> Nil {
  card.detect_brand("30569309025904")
  |> should.equal(card.DinersClub)
}

pub fn detect_unionpay_test() -> Nil {
  card.detect_brand("6200000000000005")
  |> should.equal(card.UnionPay)
}

pub fn detect_unknown_test() -> Nil {
  card.detect_brand("9999999999999999")
  |> should.equal(card.Unknown)
}

/// `prefix` padded with zeros to `length` digits. Brand detection does
/// not check the Luhn digit, so these synthetic numbers are enough to
/// probe the edges of each prefix range and length window.
fn pan(prefix: String, length: Int) -> String {
  prefix <> string.repeat("0", length - string.length(prefix))
}

pub fn detect_brand_at_the_edges_of_each_range_test() -> Nil {
  // Found by mutation testing: only one PAN per brand was checked, so
  // the range ends and the length windows were never exercised.
  [
    #(pan("4", 13), card.Visa),
    #(pan("4", 19), card.Visa),
    #(pan("4", 14), card.Unknown),
    #(pan("34", 15), card.AmericanExpress),
    #(pan("34", 16), card.Unknown),
    #(pan("300", 14), card.DinersClub),
    #(pan("305", 19), card.DinersClub),
    #(pan("306", 14), card.Unknown),
    #(pan("36", 14), card.DinersClub),
    #(pan("38", 16), card.DinersClub),
    #(pan("39", 14), card.DinersClub),
    #(pan("36", 13), card.Unknown),
    #(pan("3528", 16), card.Jcb),
    #(pan("3589", 19), card.Jcb),
    #(pan("3527", 16), card.Unknown),
    #(pan("3590", 16), card.Unknown),
    #(pan("3528", 15), card.Unknown),
    #(pan("6011", 19), card.Discover),
    #(pan("6011", 15), card.Unknown),
    #(pan("644", 16), card.Discover),
    #(pan("649", 16), card.Discover),
    #(pan("643", 16), card.Unknown),
    #(pan("65", 16), card.Discover),
    #(pan("62", 16), card.UnionPay),
    #(pan("62", 19), card.UnionPay),
    #(pan("62", 15), card.Unknown),
  ]
  |> list.each(fn(case_) {
    let #(number, brand) = case_
    card.detect_brand(number) |> should.equal(brand)
  })
}

pub fn brand_to_string_test() -> Nil {
  card.brand_to_string(card.Visa)
  |> should.equal("VISA")
  card.brand_to_string(card.Unknown)
  |> should.equal("UNKNOWN")
}

// --- Full validation ----------------------------------------------------

pub fn validate_visa_test() -> Nil {
  card.validate("4111 1111 1111 1111")
  |> should.equal(Ok(card.Visa))
}

pub fn validate_rejects_empty_test() -> Nil {
  card.validate("")
  |> should.equal(Error(card.EmptyInput))
  card.validate("  -  ")
  |> should.equal(Error(card.EmptyInput))
}

pub fn validate_rejects_letters_test() -> Nil {
  card.validate("4111A111B111C111D")
  |> should.equal(Error(card.InvalidCharacter))
}

pub fn validate_rejects_short_test() -> Nil {
  card.validate("41111")
  |> should.equal(Error(card.InvalidLength(length: 5)))
}

pub fn validate_rejects_bad_luhn_test() -> Nil {
  card.validate("4111111111111112")
  |> should.equal(Error(card.InvalidLuhn))
}

pub fn validate_rejects_unknown_brand_test() -> Nil {
  // 7 prefix, length 16, valid Luhn — not a recognised brand.
  card.validate("7000000000000000")
  |> should.equal(Error(card.InvalidLuhn))
}

// --- Masking ------------------------------------------------------------

pub fn mask_default_test() -> Nil {
  card.mask("4111111111111111", with: card.default_mask)
  |> should.equal(Ok("4111 **** **** 1111"))
}

pub fn mask_no_grouping_test() -> Nil {
  let opts = card.MaskOptions(..card.default_mask, group_size: 0)
  card.mask("4111111111111111", with: opts)
  |> should.equal(Ok("4111********1111"))
}

pub fn mask_custom_keep_test() -> Nil {
  let opts =
    card.MaskOptions(
      ..card.default_mask,
      keep_first: 6,
      keep_last: 2,
      group_size: 0,
    )
  card.mask("4111111111111111", with: opts)
  |> should.equal(Ok("411111********11"))
}

pub fn mask_custom_char_test() -> Nil {
  let opts = card.MaskOptions(..card.default_mask, mask_character: "X")
  card.mask("4111111111111111", with: opts)
  |> should.equal(Ok("4111 XXXX XXXX 1111"))
}

pub fn normalize_strips_crlf_test() -> Nil {
  // "\r\n" is one grapheme, not "\r" followed by "\n".
  card.normalize("4111\r\n1111\r\n1111\r\n1111")
  |> should.equal("4111111111111111")
  card.validate(" -_.\r\n")
  |> should.equal(Error(card.EmptyInput))
}

pub fn mask_rejects_empty_test() -> Nil {
  card.mask("", with: card.default_mask)
  |> should.equal(Error(card.EmptyInput))
}

pub fn mask_amex_segment_aware_test() -> Nil {
  // 15-digit AMEX: keep_first=4, keep_last=4, group_size=4.
  // Old behaviour leaked the last "0005" into the previous block as
  // "***0 005". Segment-aware grouping keeps the trailing 4 intact.
  card.mask("378282246310005", with: card.default_mask)
  |> should.equal(Ok("3782 **** *** 0005"))
}

pub fn mask_diners_segment_aware_test() -> Nil {
  // 14-digit Diners Club. keep_first=4, keep_last=4, group_size=4.
  // Mask block is 6 chars ("******"); chunked left-to-right that's
  // a "****" followed by "**".
  card.mask("30569309025904", with: card.default_mask)
  |> should.equal(Ok("3056 **** ** 5904"))
}

// --- BIN / last four ---------------------------------------------------

pub fn last_four_test() -> Nil {
  card.last_four("4111 1111 1111 1111")
  |> should.equal(Ok("1111"))
}

pub fn bin_test() -> Nil {
  card.bin("4111 1111 1111 1111")
  |> should.equal(Ok("411111"))
}

// --- Expiry -------------------------------------------------------------

pub fn expiry_valid_future_test() -> Nil {
  card.expiry_valid(card.Expiry(5, 2028), today: card.Expiry(5, 2026))
  |> should.be_true
}

pub fn expiry_valid_current_month_test() -> Nil {
  card.expiry_valid(card.Expiry(5, 2026), today: card.Expiry(5, 2026))
  |> should.be_true
}

pub fn expiry_valid_past_test() -> Nil {
  card.expiry_valid(card.Expiry(4, 2026), today: card.Expiry(5, 2026))
  |> should.be_false
  card.expiry_valid(card.Expiry(12, 2025), today: card.Expiry(5, 2026))
  |> should.be_false
}

pub fn expiry_invalid_month_test() -> Nil {
  card.expiry_valid(card.Expiry(13, 2028), today: card.Expiry(5, 2026))
  |> should.be_false
  card.expiry_valid(card.Expiry(0, 2028), today: card.Expiry(5, 2026))
  |> should.be_false
}

pub fn parse_expiry_short_year_test() -> Nil {
  card.parse_expiry("12/28")
  |> should.equal(Ok(card.Expiry(12, 2028)))
}

pub fn parse_expiry_long_year_test() -> Nil {
  card.parse_expiry("12/2028")
  |> should.equal(Ok(card.Expiry(12, 2028)))
}

pub fn parse_expiry_with_spaces_test() -> Nil {
  card.parse_expiry(" 5 / 28 ")
  |> should.equal(Ok(card.Expiry(5, 2028)))
}

pub fn parse_expiry_invalid_month_test() -> Nil {
  card.parse_expiry("13/28")
  |> should.equal(Error(Nil))
}

pub fn parse_expiry_invalid_year_length_test() -> Nil {
  card.parse_expiry("12/3")
  |> should.equal(Error(Nil))
  card.parse_expiry("12/123")
  |> should.equal(Error(Nil))
}

// `parse_expiry_missing_separator_test` used to pin `"1228"` as
// `Error(InvalidExpiry)`. As of #42, `MMYY` and `MMYYYY` are
// accepted formats, so the four-digit "1228" now parses to
// `Ok(card.Expiry(12, 2028))`. The new acceptance contract is covered by
// `parse_expiry_mmyy_no_separator_test` /
// `parse_expiry_mmyyyy_no_separator_test`; the three-digit
// ambiguous case is pinned by `parse_expiry_rejects_three_digit_unseparated_test`.

pub fn normalize_folds_fullwidth_digits_test() -> Nil {
  card.normalize("４２４２４２４２４２４２４２４２")
  |> should.equal("4242424242424242")
}

pub fn normalize_folds_arabic_indic_digits_test() -> Nil {
  // ٤ = U+0664, ٢ = U+0662 — "4242"
  card.normalize("٤٢٤٢")
  |> should.equal("4242")
}

pub fn normalize_folds_extended_arabic_indic_digits_test() -> Nil {
  // ۴ = U+06F4, ۲ = U+06F2 — "4242"
  card.normalize("۴۲۴۲")
  |> should.equal("4242")
}

pub fn normalize_strips_separators_and_folds_test() -> Nil {
  card.normalize("４２４２-４２４２ ４２４２.４２４２")
  |> should.equal("4242424242424242")
}

pub fn parse_expiry_rejects_negative_two_digit_year_test() -> Nil {
  // `"-1"` previously slipped through the length check (length 2)
  // and was silently coerced to `2000 + (-1) = 1999`.
  card.parse_expiry("12/-1")
  |> should.equal(Error(Nil))
}

pub fn parse_expiry_rejects_negative_month_test() -> Nil {
  card.parse_expiry("-1/26")
  |> should.equal(Error(Nil))
}

pub fn parse_expiry_rejects_zero_month_test() -> Nil {
  card.parse_expiry("0/26")
  |> should.equal(Error(Nil))
}

pub fn parse_expiry_hyphen_separator_short_year_test() -> Nil {
  card.parse_expiry("12-26")
  |> should.equal(Ok(card.Expiry(12, 2026)))
}

pub fn parse_expiry_hyphen_separator_long_year_test() -> Nil {
  card.parse_expiry("12-2026")
  |> should.equal(Ok(card.Expiry(12, 2026)))
}

pub fn parse_expiry_dot_separator_short_year_test() -> Nil {
  card.parse_expiry("12.26")
  |> should.equal(Ok(card.Expiry(12, 2026)))
}

pub fn parse_expiry_dot_separator_long_year_test() -> Nil {
  card.parse_expiry("12.2026")
  |> should.equal(Ok(card.Expiry(12, 2026)))
}

pub fn parse_expiry_mmyy_no_separator_test() -> Nil {
  card.parse_expiry("1226")
  |> should.equal(Ok(card.Expiry(12, 2026)))
}

pub fn parse_expiry_mmyyyy_no_separator_test() -> Nil {
  card.parse_expiry("122026")
  |> should.equal(Ok(card.Expiry(12, 2026)))
}

pub fn parse_expiry_rejects_three_digit_unseparated_test() -> Nil {
  // 126 is ambiguous (1/26 vs 12/6); the parser refuses to guess.
  card.parse_expiry("126")
  |> should.equal(Error(Nil))
}

pub fn parse_expiry_legacy_always_20yy_test() -> Nil {
  card.parse_expiry("12/76")
  |> should.equal(Ok(card.Expiry(12, 2076)))
  card.parse_expiry("12/00")
  |> should.equal(Ok(card.Expiry(12, 2000)))
}

// --- Helpers ------------------------------------------------------------

fn list_all(items: List(a), f: fn(a) -> Bool) -> Bool {
  case items {
    [] -> True
    [head, ..rest] ->
      case f(head) {
        True -> list_all(rest, f)
        False -> False
      }
  }
}
