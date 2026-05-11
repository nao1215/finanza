//// dig-bug round 4: fuzzing.
////
//// Pump random/malformed strings through every parser surface and
//// confirm we get a typed error (never a crash, hang, or wrong-type
//// success).

import gleam/int
import gleam/list
import gleam/string
import gleeunit/should

import finanza/card
import finanza/decimal

const trials: Int = 500

// --- Tiny PRNG (LCG, deterministic) -------------------------------------

type Prng {
  Prng(state: Int)
}

fn next_int(prng: Prng) -> #(Int, Prng) {
  let new_state = { prng.state * 1_103_515_245 + 12_345 } % 2_147_483_648
  #(new_state, Prng(state: new_state))
}

fn int_in_range(prng: Prng, low: Int, high: Int) -> #(Int, Prng) {
  let #(n, prng2) = next_int(prng)
  let span = high - low + 1
  let value = low + int.absolute_value(n) % span
  #(value, prng2)
}

// --- Random string generators -------------------------------------------

fn gen_random_byte_string(prng: Prng, length: Int) -> #(String, Prng) {
  random_string_loop(prng, length, [], byte_alphabet())
}

fn gen_pan_like(prng: Prng, length: Int) -> #(String, Prng) {
  random_string_loop(prng, length, [], pan_alphabet())
}

fn gen_expiry_like(prng: Prng, length: Int) -> #(String, Prng) {
  random_string_loop(prng, length, [], expiry_alphabet())
}

fn random_string_loop(
  prng: Prng,
  length: Int,
  acc: List(String),
  alphabet: List(String),
) -> #(String, Prng) {
  case length <= 0 {
    True -> #(string.concat(list.reverse(acc)), prng)
    False -> {
      let #(idx, p2) = int_in_range(prng, 0, list.length(alphabet) - 1)
      let assert Ok(ch) = list_at(alphabet, idx)
      random_string_loop(p2, length - 1, [ch, ..acc], alphabet)
    }
  }
}

fn list_at(items: List(a), index: Int) -> Result(a, Nil) {
  case items, index {
    [], _ -> Error(Nil)
    [head, ..], 0 -> Ok(head)
    [_, ..rest], n -> list_at(rest, n - 1)
  }
}

fn byte_alphabet() -> List(String) {
  // ASCII printable plus a handful of common control / Unicode characters
  // that have caused parsers to panic historically.
  [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "x", "z",
    " ", "\t", "\n", "+", "-", ".", ",", ";", ":", "/", "\\", "_", "(", ")", "[",
    "]", "*", "#", "%", "~", "`", "?", "!", "$", "&", "<", ">", "\"", "'", "é",
    "あ", "💰",
  ]
}

fn pan_alphabet() -> List(String) {
  [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", " ", "-", "_", ".", "x",
    "?", "*", "あ",
  ]
}

fn expiry_alphabet() -> List(String) {
  [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "/", "-", " ", "\\", ".",
    "x",
  ]
}

// --- Fuzz the decimal parser --------------------------------------------

pub fn fuzz_decimal_parser_short_strings_test() -> Nil {
  let prng = Prng(state: 71)
  iterate(prng, trials, fn(p) {
    let #(length, p1) = int_in_range(p, 0, 12)
    let #(s, p2) = gen_random_byte_string(p1, length)
    case decimal.from_string(s) {
      Ok(_) -> p2
      // typed errors are fine
      Error(decimal.EmptyInput) -> p2
      Error(decimal.InvalidCharacter(_, _)) -> p2
      Error(decimal.MultipleDecimalPoints) -> p2
      Error(decimal.MultipleSigns) -> p2
      Error(decimal.NoDigits) -> p2
      Error(decimal.ParsedValueTooLarge) -> p2
    }
  })
  // The loop did not crash → property holds.
  Nil
}

pub fn fuzz_decimal_parser_long_strings_test() -> Nil {
  // Long inputs stress the recursive parser. We expect either a typed
  // error or an Ok with a coefficient that round-trips. Either way: no
  // crash.
  let prng = Prng(state: 73)
  iterate(prng, 50, fn(p) {
    let #(s, p2) = gen_random_byte_string(p, 200)
    case decimal.from_string(s) {
      Ok(_) -> p2
      Error(decimal.EmptyInput) -> p2
      Error(decimal.InvalidCharacter(_, _)) -> p2
      Error(decimal.MultipleDecimalPoints) -> p2
      Error(decimal.MultipleSigns) -> p2
      Error(decimal.NoDigits) -> p2
      Error(decimal.ParsedValueTooLarge) -> p2
    }
  })
  Nil
}

pub fn fuzz_decimal_parser_digit_heavy_test() -> Nil {
  // Strings biased to digits + sign + dot are more likely to hit
  // arithmetic / overflow boundaries.
  let prng = Prng(state: 79)
  iterate(prng, trials, fn(p) {
    let #(length, p1) = int_in_range(p, 1, 30)
    let #(s, p2) = random_digit_heavy(p1, length)
    case decimal.from_string(s) {
      Ok(d) -> {
        // If parsing succeeded, to_string then from_string should round
        // trip exactly.
        let rendered = decimal.to_string(d)
        case decimal.from_string(rendered) {
          Ok(d2) ->
            case decimal.equal(d, d2) {
              True -> p2
              False -> {
                should.equal(s, rendered)
                p2
              }
            }
          Error(_) -> {
            should.equal(s, rendered)
            p2
          }
        }
      }
      Error(_) -> p2
    }
  })
  Nil
}

fn random_digit_heavy(prng: Prng, length: Int) -> #(String, Prng) {
  random_string_loop(prng, length, [], digit_heavy_alphabet())
}

fn digit_heavy_alphabet() -> List(String) {
  // 10 digit chars × 3 (so 30 slots) + sign + dot.
  [
    "0", "0", "0", "1", "1", "1", "2", "2", "2", "3", "3", "3", "4", "4", "4",
    "5", "5", "5", "6", "6", "6", "7", "7", "7", "8", "8", "8", "9", "9", "9",
    "+", "-", ".",
  ]
}

// --- Fuzz the card validators -------------------------------------------

pub fn fuzz_card_validate_test() -> Nil {
  let prng = Prng(state: 83)
  iterate(prng, trials, fn(p) {
    let #(length, p1) = int_in_range(p, 0, 25)
    let #(s, p2) = gen_pan_like(p1, length)
    case card.validate(s) {
      Ok(_) -> p2
      Error(card.EmptyInput) -> p2
      Error(card.InvalidCharacter) -> p2
      Error(card.InvalidLength(_)) -> p2
      Error(card.InvalidLuhn) -> p2
      Error(card.UnknownBrand) -> p2
      Error(card.InvalidExpiry) -> p2
    }
  })
  Nil
}

pub fn fuzz_card_mask_test() -> Nil {
  let prng = Prng(state: 89)
  iterate(prng, trials, fn(p) {
    let #(length, p1) = int_in_range(p, 0, 25)
    let #(s, p2) = gen_pan_like(p1, length)
    case card.mask(s, card.mask_defaults()) {
      Ok(_) -> p2
      Error(card.EmptyInput) -> p2
      Error(card.InvalidCharacter) -> p2
      Error(card.InvalidLength(_)) -> p2
      Error(card.InvalidLuhn) -> p2
      Error(card.UnknownBrand) -> p2
      Error(card.InvalidExpiry) -> p2
    }
  })
  Nil
}

pub fn fuzz_card_parse_expiry_test() -> Nil {
  let prng = Prng(state: 97)
  iterate(prng, trials, fn(p) {
    let #(length, p1) = int_in_range(p, 0, 12)
    let #(s, p2) = gen_expiry_like(p1, length)
    case card.parse_expiry(s) {
      Ok(_) -> p2
      Error(_) -> p2
    }
  })
  Nil
}

// --- Iteration helper ---------------------------------------------------

fn iterate(prng: Prng, n: Int, step: fn(Prng) -> Prng) -> Prng {
  case n <= 0 {
    True -> prng
    False -> iterate(step(prng), n - 1, step)
  }
}
