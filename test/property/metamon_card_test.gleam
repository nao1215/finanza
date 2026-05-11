//// Property-based tests for `finanza/card` driven by `metamon`.
////
//// Focus areas: Luhn algorithm soundness, normalisation idempotence,
//// brand-detection invariance under separators.

import gleam/int
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range

import finanza/card

// --- Generators ----------------------------------------------------------

fn digit_string_gen(min_len: Int, max_len: Int) -> generator.Generator(String) {
  generator.list_of(
    generator.int(range.constant(0, 9)) |> generator.map(int.to_string),
    range.constant(min_len, max_len),
  )
  |> generator.map(string.concat)
}

fn pan_with_separators_gen() -> generator.Generator(String) {
  let token =
    generator.frequency([
      #(8, generator.int(range.constant(0, 9)) |> generator.map(int.to_string)),
      #(1, generator.return(" ")),
      #(1, generator.return("-")),
    ])
  generator.list_of(token, range.constant(0, 20))
  |> generator.map(string.concat)
}

// --- Luhn properties -----------------------------------------------------

pub fn luhn_check_digit_makes_valid_test() {
  // For every digit string D, there exists a digit C such that D <> C is
  // Luhn-valid. The property: appending the right check digit yields
  // True. We compute C by brute force (0..9) and assert validity.
  metamon.forall(digit_string_gen(1, 18), fn(prefix) {
    let with_check = append_luhn_check_digit(prefix)
    card.luhn_valid(with_check)
  })
}

fn append_luhn_check_digit(prefix: String) -> String {
  prefix <> int.to_string(find_check_digit(prefix, 0))
}

fn find_check_digit(prefix: String, candidate: Int) -> Int {
  case candidate > 9 {
    True -> 0
    False ->
      case card.luhn_valid(prefix <> int.to_string(candidate)) {
        True -> candidate
        False -> find_check_digit(prefix, candidate + 1)
      }
  }
}

pub fn luhn_prepend_zero_preserves_validity_test() {
  // Prepending "0" to a Luhn-valid string leaves it Luhn-valid: the new
  // leftmost digit contributes 0 to the sum regardless of its parity
  // class. This is an algebraic property of the Luhn weighting scheme.
  metamon.forall(digit_string_gen(1, 18), fn(prefix) {
    let with_check = append_luhn_check_digit(prefix)
    card.luhn_valid("0" <> with_check)
  })
}

// --- Normalisation -------------------------------------------------------

pub fn normalize_idempotent_test() {
  let mr =
    metamon.idempotency_of(
      name: "card_normalize_idempotent",
      of: card.normalize,
    )
  metamon.forall_morph(pan_with_separators_gen(), mr, card.normalize)
}

pub fn normalize_strips_separators_test() {
  // After normalisation, no space or hyphen should remain.
  metamon.forall(pan_with_separators_gen(), fn(input) {
    let n = card.normalize(input)
    !string.contains(n, " ") && !string.contains(n, "-")
  })
}

pub fn validate_invariant_under_normalisation_test() {
  // Validating a PAN with separators must yield the same result as
  // validating the already-normalised form.
  metamon.forall(pan_with_separators_gen(), fn(input) {
    card.validate(input) == card.validate(card.normalize(input))
  })
}

// --- Brand detection -----------------------------------------------------

pub fn detect_brand_invariant_under_separators_test() {
  // Adding/removing whitespace and hyphens must not change the detected
  // brand.
  let brands_with_separators =
    pan_with_separators_gen()
    |> generator.filter(fn(s) {
      let n = card.normalize(s)
      string.length(n) >= 12 && string.length(n) <= 19
    })
  metamon.forall(brands_with_separators, fn(input) {
    card.detect_brand(input) == card.detect_brand(card.normalize(input))
  })
}

// --- Last-four / BIN -----------------------------------------------------

pub fn last_four_is_suffix_test() {
  // `last_four(pan)` always equals the last 4 digits of `normalize(pan)`
  // when the input has at least 4 digits.
  metamon.forall(digit_string_gen(4, 19), fn(pan) {
    case card.last_four(pan) {
      Ok(suffix) -> {
        let length = string.length(pan)
        suffix == string.slice(pan, length - 4, 4)
      }
      Error(_) -> False
    }
  })
}

pub fn bin_is_prefix_test() {
  // `bin(pan)` always equals the first 6 digits of `normalize(pan)`
  // when the input has at least 6 digits.
  metamon.forall(digit_string_gen(6, 19), fn(pan) {
    case card.bin(pan) {
      Ok(prefix) -> prefix == string.slice(pan, 0, 6)
      Error(_) -> False
    }
  })
}

// --- brand_to_string deterministic --------------------------------------

pub fn brand_to_string_deterministic_test() {
  // brand_to_string is a pure function — repeated invocations return the
  // same string.
  let brands = [
    card.Visa, card.Mastercard, card.AmericanExpress, card.Discover, card.Jcb,
    card.DinersClub, card.UnionPay, card.Unknown,
  ]
  metamon.forall(generator.element_of(brands), fn(b) {
    card.brand_to_string(b) == card.brand_to_string(b)
  })
}
