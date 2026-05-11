import gleeunit/should

import finanza/card

// --- Normalisation ------------------------------------------------------

pub fn normalize_strips_spaces_and_hyphens_test() -> Nil {
  card.normalize(pan: "4111 1111 1111 1111")
  |> should.equal("4111111111111111")
  card.normalize(pan: "4111-1111-1111-1111")
  |> should.equal("4111111111111111")
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
  card.mask(pan: "4111111111111111", options: card.mask_defaults())
  |> should.equal(Ok("4111 **** **** 1111"))
}

pub fn mask_no_grouping_test() -> Nil {
  let opts =
    card.mask_defaults()
    |> card.with_group_size(size: 0)
  card.mask(pan: "4111111111111111", options: opts)
  |> should.equal(Ok("4111********1111"))
}

pub fn mask_custom_keep_test() -> Nil {
  let opts =
    card.mask_defaults()
    |> card.with_keep_first(count: 6)
    |> card.with_keep_last(count: 2)
    |> card.with_group_size(size: 0)
  card.mask(pan: "4111111111111111", options: opts)
  |> should.equal(Ok("411111********11"))
}

pub fn mask_custom_char_test() -> Nil {
  let opts =
    card.mask_defaults()
    |> card.with_mask_char(char: "X")
  card.mask(pan: "4111111111111111", options: opts)
  |> should.equal(Ok("4111 XXXX XXXX 1111"))
}

pub fn mask_rejects_empty_test() -> Nil {
  card.mask(pan: "", options: card.mask_defaults())
  |> should.equal(Error(card.EmptyInput))
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
  card.expiry_valid(month: 5, year: 2028, today_year: 2026, today_month: 5)
  |> should.be_true
}

pub fn expiry_valid_current_month_test() -> Nil {
  card.expiry_valid(month: 5, year: 2026, today_year: 2026, today_month: 5)
  |> should.be_true
}

pub fn expiry_valid_past_test() -> Nil {
  card.expiry_valid(month: 4, year: 2026, today_year: 2026, today_month: 5)
  |> should.be_false
  card.expiry_valid(month: 12, year: 2025, today_year: 2026, today_month: 5)
  |> should.be_false
}

pub fn expiry_invalid_month_test() -> Nil {
  card.expiry_valid(month: 13, year: 2028, today_year: 2026, today_month: 5)
  |> should.be_false
  card.expiry_valid(month: 0, year: 2028, today_year: 2026, today_month: 5)
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
