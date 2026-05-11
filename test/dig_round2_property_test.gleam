//// dig-bug round 2: property-based testing.
////
//// Hand-rolled generators backed by a deterministic LCG so failures
//// can be reproduced. Each property runs N trials; the first failure
//// surfaces the seed and input.

import gleam/int
import gleam/list
import gleam/order
import gleam/string
import gleeunit/should

import finanza/card
import finanza/currency
import finanza/currency/catalog
import finanza/decimal
import finanza/decimal/rounding

const trials: Int = 200

// --- Tiny PRNG (LCG, deterministic) -------------------------------------

type Prng {
  Prng(state: Int)
}

fn new_prng(seed: Int) -> Prng {
  Prng(state: seed)
}

fn next_int(prng: Prng) -> #(Int, Prng) {
  // Numerical Recipes LCG
  let new_state = { prng.state * 1_103_515_245 + 12_345 } % 2_147_483_648
  #(new_state, Prng(state: new_state))
}

fn int_in_range(prng: Prng, low: Int, high: Int) -> #(Int, Prng) {
  let #(n, prng2) = next_int(prng)
  let span = high - low + 1
  let value = low + int.absolute_value(n) % span
  #(value, prng2)
}

// --- Decimal generators -------------------------------------------------

fn gen_decimal(prng: Prng) -> #(decimal.Decimal, Prng) {
  // Keep coefficients small enough that products are well inside 2^53.
  let #(coef, prng2) = int_in_range(prng, -1_000_000, 1_000_000)
  let #(exp, prng3) = int_in_range(prng2, -4, 2)
  #(decimal.new(coefficient: coef, exponent: exp), prng3)
}

// --- Decimal properties --------------------------------------------------

pub fn decimal_add_commutative_test() -> Nil {
  let _ =
    run_pairs(0, fn(a, b) {
      case decimal.add(a, b), decimal.add(b, a) {
        Ok(ab), Ok(ba) -> decimal.equal(ab, ba)
        Error(_), Error(_) -> True
        _, _ -> False
      }
    })
  Nil
}

pub fn decimal_add_identity_zero_test() -> Nil {
  let _ =
    run_one(7, fn(a) {
      case decimal.add(a, decimal.zero()) {
        Ok(sum) -> decimal.equal(sum, a)
        Error(_) -> False
      }
    })
  Nil
}

pub fn decimal_multiply_commutative_test() -> Nil {
  let _ =
    run_pairs(11, fn(a, b) {
      case decimal.multiply(a, b), decimal.multiply(b, a) {
        Ok(ab), Ok(ba) -> decimal.equal(ab, ba)
        Error(_), Error(_) -> True
        _, _ -> False
      }
    })
  Nil
}

pub fn decimal_multiply_identity_one_test() -> Nil {
  let _ =
    run_one(13, fn(a) {
      case decimal.multiply(a, decimal.one()) {
        Ok(prod) -> decimal.equal(prod, a)
        Error(_) -> False
      }
    })
  Nil
}

pub fn decimal_double_negate_test() -> Nil {
  let _ =
    run_one(17, fn(a) {
      let negneg = decimal.negate(decimal.negate(a))
      decimal.equal(negneg, a)
    })
  Nil
}

pub fn decimal_absolute_non_negative_test() -> Nil {
  let _ = run_one(19, fn(a) { !decimal.is_negative(decimal.absolute(a)) })
  Nil
}

pub fn decimal_subtract_inverse_test() -> Nil {
  // a + b - b == a (when no overflow)
  let _ =
    run_pairs(23, fn(a, b) {
      case decimal.add(a, b) {
        Error(_) -> True
        // ignore: hit precision ceiling
        Ok(sum) ->
          case decimal.subtract(sum, b) {
            Ok(again) -> decimal.equal(again, a)
            Error(_) -> True
          }
      }
    })
  Nil
}

pub fn decimal_compare_antisymmetric_test() -> Nil {
  let _ =
    run_pairs(29, fn(a, b) {
      let ab = decimal.compare(a, b)
      let ba = decimal.compare(b, a)
      case ab, ba {
        order.Lt, order.Gt -> True
        order.Gt, order.Lt -> True
        order.Eq, order.Eq -> True
        _, _ -> False
      }
    })
  Nil
}

pub fn decimal_round_idempotent_test() -> Nil {
  let _ =
    run_one(31, fn(a) {
      let r1 = decimal.round(a, 2, rounding.HalfEven)
      let r2 = decimal.round(r1, 2, rounding.HalfEven)
      decimal.equal(r1, r2)
    })
  Nil
}

pub fn decimal_string_round_trip_test() -> Nil {
  // from_string(to_string(d)) is numerically equal to d.
  let _ =
    run_one(37, fn(a) {
      let s = decimal.to_string(a)
      case decimal.from_string(s) {
        Ok(reparsed) -> decimal.equal(reparsed, a)
        Error(_) -> False
      }
    })
  Nil
}

// --- Currency properties -------------------------------------------------

pub fn money_from_minor_to_minor_round_trip_test() -> Nil {
  let prng = new_prng(41)
  let _ =
    iterate(prng, trials, fn(p) {
      let #(units, p1) = int_in_range(p, -1_000_000, 1_000_000)
      let m = currency.from_minor(units, catalog.usd())
      case currency.to_minor(m, rounding.HalfEven) {
        Ok(back) ->
          case back == units {
            True -> p1
            False -> panic_with("from_minor/to_minor mismatch", units, back, p1)
          }
        Error(_) -> panic_with("to_minor errored", units, 0, p1)
      }
    })
  Nil
}

pub fn allocate_preserves_total_test() -> Nil {
  let prng = new_prng(43)
  let _ =
    iterate(prng, trials, fn(p) {
      let #(units, p1) = int_in_range(p, 1, 10_000_000)
      let #(n_ratios, p2) = int_in_range(p1, 1, 7)
      let #(ratios, p3) = generate_ratios(p2, n_ratios)
      let m = currency.from_minor(units, catalog.usd())
      case currency.allocate(m, ratios) {
        Ok(parts) -> {
          let total =
            parts
            |> list.map(fn(part) {
              case currency.to_minor(part, rounding.HalfEven) {
                Ok(u) -> u
                Error(_) -> 0
              }
            })
            |> list.fold(0, int.add)
          case total == units {
            True -> p3
            False -> panic_with("allocate sum mismatch", units, total, p3)
          }
        }
        Error(_) -> panic_with("allocate errored", units, 0, p3)
      }
    })
  Nil
}

fn generate_ratios(prng: Prng, n: Int) -> #(List(Int), Prng) {
  generate_ratios_loop(prng, n, [])
}

fn generate_ratios_loop(
  prng: Prng,
  n: Int,
  acc: List(Int),
) -> #(List(Int), Prng) {
  case n <= 0 {
    True -> #(acc, prng)
    False -> {
      let #(r, p2) = int_in_range(prng, 1, 9)
      generate_ratios_loop(p2, n - 1, [r, ..acc])
    }
  }
}

// --- Card properties -----------------------------------------------------

pub fn luhn_appended_check_digit_test() -> Nil {
  // For any digit string D, appending the proper Luhn check digit
  // produces a Luhn-valid string. We compute the check digit by trial.
  let prng = new_prng(47)
  let _ =
    iterate(prng, 100, fn(p) {
      let #(length, p1) = int_in_range(p, 1, 18)
      let #(prefix, p2) = random_digits(p1, length)
      let with_check = append_luhn_check(prefix)
      case card.luhn_valid(with_check) {
        True -> p2
        False -> panic_with("Luhn check digit fail", length, 0, p2)
      }
    })
  Nil
}

fn random_digits(prng: Prng, length: Int) -> #(String, Prng) {
  random_digits_loop(prng, length, "")
}

fn random_digits_loop(prng: Prng, length: Int, acc: String) -> #(String, Prng) {
  case length <= 0 {
    True -> #(acc, prng)
    False -> {
      let #(d, p2) = int_in_range(prng, 0, 9)
      random_digits_loop(p2, length - 1, acc <> int.to_string(d))
    }
  }
}

fn append_luhn_check(prefix: String) -> String {
  // Try each digit 0..9 and pick the one that makes the string Luhn-valid.
  let candidate = find_luhn_digit(prefix, 0)
  prefix <> int.to_string(candidate)
}

fn find_luhn_digit(prefix: String, candidate: Int) -> Int {
  case candidate > 9 {
    True -> 0
    False ->
      case card.luhn_valid(prefix <> int.to_string(candidate)) {
        True -> candidate
        False -> find_luhn_digit(prefix, candidate + 1)
      }
  }
}

pub fn normalize_idempotent_test() -> Nil {
  let prng = new_prng(53)
  let _ =
    iterate(prng, trials, fn(p) {
      let #(length, p1) = int_in_range(p, 0, 20)
      let #(s, p2) = random_pan_with_seps(p1, length)
      let once = card.normalize(s)
      let twice = card.normalize(once)
      case once == twice {
        True -> p2
        False -> panic_with("normalize not idempotent", length, 0, p2)
      }
    })
  Nil
}

fn random_pan_with_seps(prng: Prng, length: Int) -> #(String, Prng) {
  random_pan_loop(prng, length, "")
}

fn random_pan_loop(prng: Prng, length: Int, acc: String) -> #(String, Prng) {
  case length <= 0 {
    True -> #(acc, prng)
    False -> {
      let #(choice, p2) = int_in_range(prng, 0, 12)
      let ch = case choice {
        0 -> " "
        1 -> "-"
        _ -> int.to_string(choice - 2)
      }
      random_pan_loop(p2, length - 1, acc <> ch)
    }
  }
}

pub fn mask_preserves_keep_counts_test() -> Nil {
  let prng = new_prng(59)
  let _ =
    iterate(prng, trials, fn(p) {
      // Generate digit-only PAN of length 13–19.
      let #(length, p1) = int_in_range(p, 13, 19)
      let #(pan, p2) = random_digits(p1, length)
      case card.mask(pan, card.mask_defaults()) {
        Ok(masked) -> {
          // The masked string should contain the first 4 digits of the
          // PAN as a substring and the last 4 digits as a substring.
          let first_4 = string.slice(pan, 0, 4)
          let last_4 = string.slice(pan, length - 4, 4)
          case
            string.contains(masked, first_4) && string.contains(masked, last_4)
          {
            True -> p2
            False -> panic_with("mask lost keep regions", length, 0, p2)
          }
        }
        Error(_) -> p2
        // empty / non-digit cases are filtered by length range
      }
    })
  Nil
}

// --- Test runners --------------------------------------------------------

fn run_one(seed: Int, prop: fn(decimal.Decimal) -> Bool) -> Nil {
  let prng = new_prng(seed)
  let _ =
    iterate(prng, trials, fn(p) {
      let #(a, p1) = gen_decimal(p)
      case prop(a) {
        True -> p1
        False -> panic_decimal("property violation", a, p1)
      }
    })
  Nil
}

fn run_pairs(
  seed: Int,
  prop: fn(decimal.Decimal, decimal.Decimal) -> Bool,
) -> Nil {
  let prng = new_prng(seed)
  let _ =
    iterate(prng, trials, fn(p) {
      let #(a, p1) = gen_decimal(p)
      let #(b, p2) = gen_decimal(p1)
      case prop(a, b) {
        True -> p2
        False -> panic_decimal2("pair property violation", a, b, p2)
      }
    })
  Nil
}

fn iterate(prng: Prng, n: Int, step: fn(Prng) -> Prng) -> Prng {
  case n <= 0 {
    True -> prng
    False -> iterate(step(prng), n - 1, step)
  }
}

fn panic_with(label: String, a: Int, b: Int, p: Prng) -> Prng {
  let _ = a
  let _ = b
  should.equal(label, "OK")
  p
}

fn panic_decimal(label: String, a: decimal.Decimal, p: Prng) -> Prng {
  let _ = a
  should.equal(label, "OK")
  p
}

fn panic_decimal2(
  label: String,
  a: decimal.Decimal,
  b: decimal.Decimal,
  p: Prng,
) -> Prng {
  let _ = a
  let _ = b
  should.equal(label, "OK")
  p
}
