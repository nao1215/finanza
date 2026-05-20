import gleeunit/should

import finanza/card

// --- Normalisation ------------------------------------------------------

pub fn normalize_strips_spaces_and_hyphens_test() -> Nil {
  card.normalize(pan: "4111 1111 1111 1111")
  |> should.equal("4111111111111111")
  card.normalize(pan: "4111-1111-1111-1111")
  |> should.equal("4111111111111111")
}

pub fn normalize_strips_all_ascii_whitespace_test() -> Nil {
  card.normalize(pan: "4242\t4242\t4242\t4242")
  |> should.equal("4242424242424242")
  card.normalize(pan: "4242\n4242\n4242\n4242")
  |> should.equal("4242424242424242")
  card.normalize(pan: "4242\r4242\r4242\r4242")
  |> should.equal("4242424242424242")
  card.normalize(pan: "4242\u{000B}4242\u{000C}4242\t4242")
  |> should.equal("4242424242424242")
  card.normalize(pan: "4242\t4242\r4242\n4242")
  |> should.equal("4242424242424242")
}

// --- Luhn ---------------------------------------------------------------

pub fn luhn_wikipedia_example_test() -> Nil {
  // Wikipedia canonical example: 79927398713 passes Luhn.
  card.luhn_valid(digits: "79927398713")
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
    |> list_all(fn(s) { !card.luhn_valid(digits: s) })
  result
  |> should.be_true
}

pub fn luhn_test_visa_test() -> Nil {
  card.luhn_valid(digits: "4111111111111111")
  |> should.be_true
}

pub fn luhn_test_mastercard_test() -> Nil {
  card.luhn_valid(digits: "5555555555554444")
  |> should.be_true
}

pub fn luhn_test_amex_test() -> Nil {
  card.luhn_valid(digits: "378282246310005")
  |> should.be_true
}

pub fn luhn_empty_string_test() -> Nil {
  card.luhn_valid(digits: "")
  |> should.be_false
}

pub fn luhn_rejects_all_letters_test() -> Nil {
  card.luhn_valid(digits: "abc")
  |> should.be_false
}

pub fn luhn_rejects_punctuation_test() -> Nil {
  card.luhn_valid(digits: "!@#$")
  |> should.be_false
}

pub fn luhn_rejects_single_space_test() -> Nil {
  card.luhn_valid(digits: " ")
  |> should.be_false
}

pub fn luhn_rejects_emoji_test() -> Nil {
  card.luhn_valid(digits: "🙂🙂🙂🙂")
  |> should.be_false
}

pub fn luhn_rejects_mixed_digits_and_spaces_test() -> Nil {
  card.luhn_valid(digits: "4242 4242 4242 4242")
  |> should.be_false
}

// --- Brand detection ----------------------------------------------------

pub fn detect_visa_test() -> Nil {
  card.detect_brand(pan: "4111 1111 1111 1111")
  |> should.equal(card.Visa)
}

pub fn detect_mastercard_classic_test() -> Nil {
  card.detect_brand(pan: "5555555555554444")
  |> should.equal(card.Mastercard)
}

pub fn detect_mastercard_2series_test() -> Nil {
  card.detect_brand(pan: "2223003122003222")
  |> should.equal(card.Mastercard)
}

pub fn detect_amex_test() -> Nil {
  card.detect_brand(pan: "378282246310005")
  |> should.equal(card.AmericanExpress)
}

pub fn detect_discover_test() -> Nil {
  card.detect_brand(pan: "6011111111111117")
  |> should.equal(card.Discover)
}

pub fn detect_jcb_test() -> Nil {
  card.detect_brand(pan: "3530111333300000")
  |> should.equal(card.Jcb)
}

pub fn detect_diners_test() -> Nil {
  card.detect_brand(pan: "30569309025904")
  |> should.equal(card.DinersClub)
}

pub fn detect_unionpay_test() -> Nil {
  card.detect_brand(pan: "6200000000000005")
  |> should.equal(card.UnionPay)
}

pub fn detect_unknown_test() -> Nil {
  card.detect_brand(pan: "9999999999999999")
  |> should.equal(card.Unknown)
}

pub fn brand_to_string_test() -> Nil {
  card.brand_to_string(brand: card.Visa)
  |> should.equal("VISA")
  card.brand_to_string(brand: card.Unknown)
  |> should.equal("UNKNOWN")
}

// --- Full validation ----------------------------------------------------

pub fn validate_visa_test() -> Nil {
  card.validate(pan: "4111 1111 1111 1111")
  |> should.equal(Ok(card.Visa))
}

pub fn validate_rejects_empty_test() -> Nil {
  card.validate(pan: "")
  |> should.equal(Error(card.EmptyInput))
  card.validate(pan: "  -  ")
  |> should.equal(Error(card.EmptyInput))
}

pub fn validate_rejects_letters_test() -> Nil {
  card.validate(pan: "4111A111B111C111D")
  |> should.equal(Error(card.InvalidCharacter))
}

pub fn validate_rejects_short_test() -> Nil {
  card.validate(pan: "41111")
  |> should.equal(Error(card.InvalidLength(length: 5)))
}

pub fn validate_rejects_bad_luhn_test() -> Nil {
  card.validate(pan: "4111111111111112")
  |> should.equal(Error(card.InvalidLuhn))
}

pub fn validate_rejects_unknown_brand_test() -> Nil {
  // 7 prefix, length 16, valid Luhn — not a recognised brand.
  card.validate(pan: "7000000000000000")
  |> should.equal(Error(card.InvalidLuhn))
}

// --- Masking ------------------------------------------------------------

pub fn mask_default_test() -> Nil {
  card.mask(pan: "4111111111111111", options: card.default_mask())
  |> should.equal(Ok("4111 **** **** 1111"))
}

pub fn mask_no_grouping_test() -> Nil {
  let opts =
    card.default_mask()
    |> card.with_group_size(size: 0)
  card.mask(pan: "4111111111111111", options: opts)
  |> should.equal(Ok("4111********1111"))
}

pub fn mask_custom_keep_test() -> Nil {
  let opts =
    card.default_mask()
    |> card.with_keep_first(count: 6)
    |> card.with_keep_last(count: 2)
    |> card.with_group_size(size: 0)
  card.mask(pan: "4111111111111111", options: opts)
  |> should.equal(Ok("411111********11"))
}

pub fn mask_custom_char_test() -> Nil {
  let opts =
    card.default_mask()
    |> card.with_mask_char(char: "X")
  card.mask(pan: "4111111111111111", options: opts)
  |> should.equal(Ok("4111 XXXX XXXX 1111"))
}

pub fn mask_rejects_empty_test() -> Nil {
  card.mask(pan: "", options: card.default_mask())
  |> should.equal(Error(card.EmptyInput))
}

pub fn mask_amex_segment_aware_test() -> Nil {
  // 15-digit AMEX: keep_first=4, keep_last=4, group_size=4.
  // Old behaviour leaked the last "0005" into the previous block as
  // "***0 005". Segment-aware grouping keeps the trailing 4 intact.
  card.mask(pan: "378282246310005", options: card.default_mask())
  |> should.equal(Ok("3782 **** *** 0005"))
}

pub fn mask_diners_segment_aware_test() -> Nil {
  // 14-digit Diners Club. keep_first=4, keep_last=4, group_size=4.
  // Mask block is 6 chars ("******"); chunked left-to-right that's
  // a "****" followed by "**".
  card.mask(pan: "30569309025904", options: card.default_mask())
  |> should.equal(Ok("3056 **** ** 5904"))
}

// --- BIN / last four ---------------------------------------------------

pub fn last_four_test() -> Nil {
  card.last_four(pan: "4111 1111 1111 1111")
  |> should.equal(Ok("1111"))
}

pub fn bin_test() -> Nil {
  card.bin(pan: "4111 1111 1111 1111")
  |> should.equal(Ok("411111"))
}

// --- Expiry -------------------------------------------------------------

pub fn expiry_valid_future_test() -> Nil {
  card.expiry_valid(expiry: #(5, 2028), today: #(5, 2026))
  |> should.be_true
}

pub fn expiry_valid_current_month_test() -> Nil {
  card.expiry_valid(expiry: #(5, 2026), today: #(5, 2026))
  |> should.be_true
}

pub fn expiry_valid_past_test() -> Nil {
  card.expiry_valid(expiry: #(4, 2026), today: #(5, 2026))
  |> should.be_false
  card.expiry_valid(expiry: #(12, 2025), today: #(5, 2026))
  |> should.be_false
}

pub fn expiry_invalid_month_test() -> Nil {
  card.expiry_valid(expiry: #(13, 2028), today: #(5, 2026))
  |> should.be_false
  card.expiry_valid(expiry: #(0, 2028), today: #(5, 2026))
  |> should.be_false
}

pub fn parse_expiry_short_year_test() -> Nil {
  card.parse_expiry(input: "12/28")
  |> should.equal(Ok(#(12, 2028)))
}

pub fn parse_expiry_long_year_test() -> Nil {
  card.parse_expiry(input: "12/2028")
  |> should.equal(Ok(#(12, 2028)))
}

pub fn parse_expiry_with_spaces_test() -> Nil {
  card.parse_expiry(input: " 5 / 28 ")
  |> should.equal(Ok(#(5, 2028)))
}

pub fn parse_expiry_invalid_month_test() -> Nil {
  card.parse_expiry(input: "13/28")
  |> should.equal(Error(card.InvalidExpiry))
}

pub fn parse_expiry_invalid_year_length_test() -> Nil {
  card.parse_expiry(input: "12/3")
  |> should.equal(Error(card.InvalidExpiry))
  card.parse_expiry(input: "12/123")
  |> should.equal(Error(card.InvalidExpiry))
}

pub fn parse_expiry_missing_separator_test() -> Nil {
  card.parse_expiry(input: "1228")
  |> should.equal(Error(card.InvalidExpiry))
}

pub fn parse_expiry_rejects_negative_two_digit_year_test() -> Nil {
  // `"-1"` previously slipped through the length check (length 2)
  // and was silently coerced to `2000 + (-1) = 1999`.
  card.parse_expiry(input: "12/-1")
  |> should.equal(Error(card.InvalidExpiry))
}

pub fn parse_expiry_rejects_negative_month_test() -> Nil {
  card.parse_expiry(input: "-1/26")
  |> should.equal(Error(card.InvalidExpiry))
}

pub fn parse_expiry_rejects_zero_month_test() -> Nil {
  card.parse_expiry(input: "0/26")
  |> should.equal(Error(card.InvalidExpiry))
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
