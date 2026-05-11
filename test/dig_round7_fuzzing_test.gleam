//// dig-bug round 7: extended fuzzing.
////
//// Second fuzzing pass complementing round 4. Round 4 covers the
//// parser surfaces (decimal.from_string, card.validate, card.mask,
//// card.parse_expiry). This round attacks the *arithmetic* and
//// *combinator* surfaces round 4 did not touch:
////
//// - decimal add / subtract / multiply / divide
//// - decimal round / truncate / rescale (including extreme digit
////   counts that exercise the unbounded pow_10 helper)
//// - interest simple / compound / future_value / present_value /
////   payment / effective_annual_rate
//// - amortization.schedule
//// - currency.new_currency, currency.allocate
//// - currency.from_minor / to_minor at extreme unit magnitudes
//// - card.bin / card.last_four (round 4 missed these two)
//// - chained arithmetic over 8 random operations
////
//// All tests use a deterministic LCG PRNG with a fixed per-test seed
//// (so failures are reproducible), enumerate every documented error
//// variant explicitly, and treat any other pattern-match outcome
//// (panic, badmatch, hang) as a counterexample. Iteration counts are
//// capped so total runtime stays well inside CI budgets.

import gleam/int
import gleam/list
import gleam/string

import finanza/card
import finanza/currency
import finanza/currency/catalog
import finanza/decimal
import finanza/decimal/rounding
import finanza/interest
import finanza/interest/amortization

const trials: Int = 500

const schedule_trials: Int = 80

// --- LCG PRNG (matches the style of dig_round4) -------------------------

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
  #(low + int.absolute_value(n) % span, prng2)
}

fn random_decimal(prng: Prng) -> #(decimal.Decimal, Prng) {
  // coefficient in [-1_000_000, 1_000_000], exponent in [-6, 6].
  // Stays well inside the precision window for chained ops.
  let #(c, p1) = int_in_range(prng, -1_000_000, 1_000_000)
  let #(e, p2) = int_in_range(p1, -6, 6)
  #(decimal.new(coefficient: c, exponent: e), p2)
}

fn random_mode(prng: Prng) -> #(rounding.Mode, Prng) {
  let #(idx, p1) = int_in_range(prng, 0, 6)
  let mode = case idx {
    0 -> rounding.HalfEven
    1 -> rounding.HalfUp
    2 -> rounding.HalfDown
    3 -> rounding.Up
    4 -> rounding.Down
    5 -> rounding.Ceiling
    _ -> rounding.Floor
  }
  #(mode, p1)
}

fn iterate(prng: Prng, n: Int, step: fn(Prng) -> Prng) -> Prng {
  case n <= 0 {
    True -> prng
    False -> iterate(step(prng), n - 1, step)
  }
}

// --- Decimal arithmetic fuzz --------------------------------------------

pub fn fuzz_decimal_add_test() -> Nil {
  let prng = Prng(state: 131)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = random_decimal(p)
    let #(b, p2) = random_decimal(p1)
    case decimal.add(a, b) {
      Ok(_) -> p2
      Error(decimal.PrecisionExceeded) -> p2
      Error(decimal.DivisionByZero) -> p2
    }
  })
  Nil
}

pub fn fuzz_decimal_subtract_test() -> Nil {
  let prng = Prng(state: 137)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = random_decimal(p)
    let #(b, p2) = random_decimal(p1)
    case decimal.subtract(a, b) {
      Ok(_) -> p2
      Error(decimal.PrecisionExceeded) -> p2
      Error(decimal.DivisionByZero) -> p2
    }
  })
  Nil
}

pub fn fuzz_decimal_multiply_test() -> Nil {
  let prng = Prng(state: 139)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = random_decimal(p)
    let #(b, p2) = random_decimal(p1)
    case decimal.multiply(a, b) {
      Ok(_) -> p2
      Error(decimal.PrecisionExceeded) -> p2
      Error(decimal.DivisionByZero) -> p2
    }
  })
  Nil
}

pub fn fuzz_decimal_divide_test() -> Nil {
  let prng = Prng(state: 149)
  iterate(prng, trials, fn(p) {
    let #(a, p1) = random_decimal(p)
    let #(b, p2) = random_decimal(p1)
    let #(digits, p3) = int_in_range(p2, 0, 12)
    let #(mode, p4) = random_mode(p3)
    case decimal.divide(a, b, digits, mode) {
      Ok(_) -> p4
      Error(decimal.PrecisionExceeded) -> p4
      Error(decimal.DivisionByZero) -> p4
    }
  })
  Nil
}

// --- Decimal round / truncate / rescale fuzz ----------------------------

pub fn fuzz_decimal_round_normal_digits_test() -> Nil {
  // digits in [-12, 12] — covers usual currency / scientific use.
  let prng = Prng(state: 151)
  iterate(prng, trials, fn(p) {
    let #(d, p1) = random_decimal(p)
    let #(digits, p2) = int_in_range(p1, -12, 12)
    let #(mode, p3) = random_mode(p2)
    let _ = decimal.round(d, digits, mode)
    p3
  })
  Nil
}

pub fn fuzz_decimal_truncate_normal_digits_test() -> Nil {
  let prng = Prng(state: 157)
  iterate(prng, trials, fn(p) {
    let #(d, p1) = random_decimal(p)
    let #(digits, p2) = int_in_range(p1, -12, 12)
    let _ = decimal.truncate(d, digits)
    p2
  })
  Nil
}

pub fn fuzz_decimal_rescale_test() -> Nil {
  let prng = Prng(state: 163)
  iterate(prng, trials, fn(p) {
    let #(d, p1) = random_decimal(p)
    let #(target, p2) = int_in_range(p1, -12, 12)
    let #(mode, p3) = random_mode(p2)
    case decimal.rescale(d, target, mode) {
      Ok(_) -> p3
      Error(decimal.PrecisionExceeded) -> p3
      Error(decimal.DivisionByZero) -> p3
    }
  })
  Nil
}

// `pow_10` inside decimal is unbounded — exercise round / truncate at
// large positive digit counts to ensure no hang / unbounded recursion.
// Negative digits in `round` produce a *target_exponent* > d.exponent
// and call drop_digits with potentially huge `diff`. Bound digits at
// magnitudes that still complete quickly on both targets.
pub fn fuzz_decimal_round_extreme_digits_test() -> Nil {
  let prng = Prng(state: 167)
  iterate(prng, 100, fn(p) {
    let #(d, p1) = random_decimal(p)
    let #(digits, p2) = int_in_range(p1, -40, 40)
    let #(mode, p3) = random_mode(p2)
    let _ = decimal.round(d, digits, mode)
    p3
  })
  Nil
}

// --- Interest fuzz -------------------------------------------------------

fn random_non_negative_decimal(prng: Prng) -> #(decimal.Decimal, Prng) {
  // Principal / rate must not be negative per check_principal / check_rate.
  let #(c, p1) = int_in_range(prng, 0, 1_000_000)
  let #(e, p2) = int_in_range(p1, -6, 2)
  #(decimal.new(coefficient: c, exponent: e), p2)
}

pub fn fuzz_simple_interest_test() -> Nil {
  let prng = Prng(state: 167)
  iterate(prng, trials, fn(p) {
    let #(principal, p1) = random_non_negative_decimal(p)
    let #(rate, p2) = random_non_negative_decimal(p1)
    let #(periods, p3) = int_in_range(p2, 1, 600)
    let #(digits, p4) = int_in_range(p3, 0, 10)
    case interest.simple_interest(principal, rate, periods, digits) {
      Ok(_) -> p4
      Error(interest.NegativePrincipal) -> p4
      Error(interest.NegativeRate) -> p4
      Error(interest.PeriodsOutOfRange) -> p4
      Error(interest.CompoundsOutOfRange) -> p4
      Error(interest.NegativeDigits) -> p4
      Error(interest.ArithmeticError(_)) -> p4
    }
  })
  Nil
}

pub fn fuzz_compound_interest_test() -> Nil {
  let prng = Prng(state: 173)
  iterate(prng, trials, fn(p) {
    let #(principal, p1) = random_non_negative_decimal(p)
    let #(rate, p2) = random_non_negative_decimal(p1)
    let #(years, p3) = int_in_range(p2, 1, 50)
    let #(freq, p4) = int_in_range(p3, 1, 12)
    let #(digits, p5) = int_in_range(p4, 0, 8)
    case interest.compound_interest(principal, rate, years, freq, digits) {
      Ok(_) -> p5
      Error(interest.NegativePrincipal) -> p5
      Error(interest.NegativeRate) -> p5
      Error(interest.PeriodsOutOfRange) -> p5
      Error(interest.CompoundsOutOfRange) -> p5
      Error(interest.NegativeDigits) -> p5
      Error(interest.ArithmeticError(_)) -> p5
    }
  })
  Nil
}

pub fn fuzz_future_value_test() -> Nil {
  let prng = Prng(state: 179)
  iterate(prng, trials, fn(p) {
    let #(present, p1) = random_non_negative_decimal(p)
    let #(rate, p2) = random_non_negative_decimal(p1)
    let #(periods, p3) = int_in_range(p2, 1, 600)
    let #(digits, p4) = int_in_range(p3, 0, 8)
    case interest.future_value(present, rate, periods, digits) {
      Ok(_) -> p4
      Error(interest.NegativePrincipal) -> p4
      Error(interest.NegativeRate) -> p4
      Error(interest.PeriodsOutOfRange) -> p4
      Error(interest.CompoundsOutOfRange) -> p4
      Error(interest.NegativeDigits) -> p4
      Error(interest.ArithmeticError(_)) -> p4
    }
  })
  Nil
}

pub fn fuzz_present_value_test() -> Nil {
  let prng = Prng(state: 181)
  iterate(prng, trials, fn(p) {
    let #(future, p1) = random_non_negative_decimal(p)
    let #(rate, p2) = random_non_negative_decimal(p1)
    let #(periods, p3) = int_in_range(p2, 1, 600)
    let #(digits, p4) = int_in_range(p3, 0, 8)
    case interest.present_value(future, rate, periods, digits) {
      Ok(_) -> p4
      Error(interest.NegativePrincipal) -> p4
      Error(interest.NegativeRate) -> p4
      Error(interest.PeriodsOutOfRange) -> p4
      Error(interest.CompoundsOutOfRange) -> p4
      Error(interest.NegativeDigits) -> p4
      Error(interest.ArithmeticError(_)) -> p4
    }
  })
  Nil
}

pub fn fuzz_payment_test() -> Nil {
  let prng = Prng(state: 191)
  iterate(prng, trials, fn(p) {
    let #(principal, p1) = random_non_negative_decimal(p)
    let #(rate, p2) = random_non_negative_decimal(p1)
    let #(periods, p3) = int_in_range(p2, 1, 600)
    let #(digits, p4) = int_in_range(p3, 0, 8)
    case interest.payment(principal, rate, periods, digits) {
      Ok(_) -> p4
      Error(interest.NegativePrincipal) -> p4
      Error(interest.NegativeRate) -> p4
      Error(interest.PeriodsOutOfRange) -> p4
      Error(interest.CompoundsOutOfRange) -> p4
      Error(interest.NegativeDigits) -> p4
      Error(interest.ArithmeticError(_)) -> p4
    }
  })
  Nil
}

pub fn fuzz_effective_annual_rate_test() -> Nil {
  let prng = Prng(state: 193)
  iterate(prng, trials, fn(p) {
    let #(rate, p1) = random_non_negative_decimal(p)
    let #(freq, p2) = int_in_range(p1, 1, 365)
    let #(digits, p3) = int_in_range(p2, 0, 10)
    case interest.effective_annual_rate(rate, freq, digits) {
      Ok(_) -> p3
      Error(interest.NegativePrincipal) -> p3
      Error(interest.NegativeRate) -> p3
      Error(interest.PeriodsOutOfRange) -> p3
      Error(interest.CompoundsOutOfRange) -> p3
      Error(interest.NegativeDigits) -> p3
      Error(interest.ArithmeticError(_)) -> p3
    }
  })
  Nil
}

// --- Amortization schedule fuzz -----------------------------------------

pub fn fuzz_amortization_schedule_test() -> Nil {
  let prng = Prng(state: 197)
  iterate(prng, schedule_trials, fn(p) {
    let #(principal, p1) = random_non_negative_decimal(p)
    let #(rate, p2) = random_non_negative_decimal(p1)
    // bound periods to keep list size reasonable
    let #(periods, p3) = int_in_range(p2, 1, 60)
    let #(digits, p4) = int_in_range(p3, 0, 6)
    case amortization.schedule(principal, rate, periods, digits) {
      Ok(_) -> p4
      Error(interest.NegativePrincipal) -> p4
      Error(interest.NegativeRate) -> p4
      Error(interest.PeriodsOutOfRange) -> p4
      Error(interest.CompoundsOutOfRange) -> p4
      Error(interest.NegativeDigits) -> p4
      Error(interest.ArithmeticError(_)) -> p4
    }
  })
  Nil
}

// --- currency.new_currency fuzz -----------------------------------------

const code_alphabet: List(String) = [
  "U", "S", "D", "E", "R", "J", "P", "Y", "X", "Z", "1", "2", "9", "あ", "💰", " ",
  "-", "_", "",
]

fn random_short_string(prng: Prng, alphabet: List(String)) -> #(String, Prng) {
  let #(length, p1) = int_in_range(prng, 0, 6)
  random_string_loop(p1, length, [], alphabet)
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

pub fn fuzz_new_currency_test() -> Nil {
  let prng = Prng(state: 199)
  iterate(prng, trials, fn(p) {
    let #(code, p1) = random_short_string(p, code_alphabet)
    let #(exponent, p2) = int_in_range(p1, -2, 12)
    let #(symbol, p3) = random_short_string(p2, code_alphabet)
    let #(name, p4) = random_short_string(p3, code_alphabet)
    case currency.new_currency(code, exponent, symbol, name) {
      Ok(_) -> p4
      Error(currency.InvalidExponent) -> p4
      Error(currency.InvalidCurrencyCode) -> p4
      Error(currency.EmptyRatios) -> p4
      Error(currency.NonPositiveRatio) -> p4
      Error(currency.CurrencyMismatch(_, _)) -> p4
      Error(currency.ArithmeticError(_)) -> p4
    }
  })
  Nil
}

// --- currency.allocate fuzz ---------------------------------------------

fn random_ratios(prng: Prng) -> #(List(Int), Prng) {
  let #(length, p1) = int_in_range(prng, 0, 10)
  ratios_loop(p1, length, [])
}

fn ratios_loop(prng: Prng, remaining: Int, acc: List(Int)) -> #(List(Int), Prng) {
  case remaining <= 0 {
    True -> #(acc, prng)
    False -> {
      let #(r, p1) = int_in_range(prng, -2, 100)
      ratios_loop(p1, remaining - 1, [r, ..acc])
    }
  }
}

pub fn fuzz_currency_allocate_test() -> Nil {
  let prng = Prng(state: 211)
  iterate(prng, trials, fn(p) {
    let #(units, p1) = int_in_range(p, -1_000_000, 1_000_000)
    let #(ratios, p2) = random_ratios(p1)
    let money = currency.from_minor(units, catalog.usd())
    case currency.allocate(money, ratios) {
      Ok(_) -> p2
      Error(currency.EmptyRatios) -> p2
      Error(currency.NonPositiveRatio) -> p2
      Error(currency.InvalidExponent) -> p2
      Error(currency.InvalidCurrencyCode) -> p2
      Error(currency.CurrencyMismatch(_, _)) -> p2
      Error(currency.ArithmeticError(_)) -> p2
    }
  })
  Nil
}

// --- from_minor / to_minor extreme units fuzz ---------------------------

pub fn fuzz_from_minor_to_minor_test() -> Nil {
  let prng = Prng(state: 223)
  iterate(prng, trials, fn(p) {
    // units in a wide range, including close to ±max_safe_coefficient.
    let #(units, p1) =
      int_in_range(p, -9_000_000_000_000_000, 9_000_000_000_000_000)
    let money = currency.from_minor(units, catalog.usd())
    case currency.to_minor(money, rounding.HalfEven) {
      Ok(_) -> p1
      Error(currency.EmptyRatios) -> p1
      Error(currency.NonPositiveRatio) -> p1
      Error(currency.InvalidExponent) -> p1
      Error(currency.InvalidCurrencyCode) -> p1
      Error(currency.CurrencyMismatch(_, _)) -> p1
      Error(currency.ArithmeticError(_)) -> p1
    }
  })
  Nil
}

// --- card.bin / card.last_four fuzz -------------------------------------

const pan_alphabet: List(String) = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", " ", "-", "_", ".", "x", "?",
  "*", "あ",
]

fn random_pan_like(prng: Prng) -> #(String, Prng) {
  let #(length, p1) = int_in_range(prng, 0, 25)
  random_string_loop(p1, length, [], pan_alphabet)
}

pub fn fuzz_card_bin_test() -> Nil {
  let prng = Prng(state: 227)
  iterate(prng, trials, fn(p) {
    let #(s, p1) = random_pan_like(p)
    case card.bin(s) {
      Ok(_) -> p1
      Error(card.EmptyInput) -> p1
      Error(card.InvalidCharacter) -> p1
      Error(card.InvalidLength(_)) -> p1
      Error(card.InvalidLuhn) -> p1
      Error(card.UnknownBrand) -> p1
      Error(card.InvalidExpiry) -> p1
    }
  })
  Nil
}

pub fn fuzz_card_last_four_test() -> Nil {
  let prng = Prng(state: 229)
  iterate(prng, trials, fn(p) {
    let #(s, p1) = random_pan_like(p)
    case card.last_four(s) {
      Ok(_) -> p1
      Error(card.EmptyInput) -> p1
      Error(card.InvalidCharacter) -> p1
      Error(card.InvalidLength(_)) -> p1
      Error(card.InvalidLuhn) -> p1
      Error(card.UnknownBrand) -> p1
      Error(card.InvalidExpiry) -> p1
    }
  })
  Nil
}

// --- Multi-step chained arithmetic fuzz ---------------------------------

pub fn fuzz_chained_arithmetic_test() -> Nil {
  // Chain ~8 random binary operations and confirm none of them panic.
  let prng = Prng(state: 233)
  iterate(prng, trials, fn(p) {
    let #(seed_dec, p1) = random_decimal(p)
    chain_step(seed_dec, p1, 8)
  })
  Nil
}

fn chain_step(acc: decimal.Decimal, prng: Prng, n: Int) -> Prng {
  case n <= 0 {
    True -> prng
    False -> {
      let #(other, p1) = random_decimal(prng)
      let #(op, p2) = int_in_range(p1, 0, 3)
      let next_result = case op {
        0 -> decimal.add(acc, other)
        1 -> decimal.subtract(acc, other)
        2 -> decimal.multiply(acc, other)
        _ -> decimal.divide(acc, other, 6, rounding.HalfEven)
      }
      let next = case next_result {
        Ok(v) -> v
        Error(_) -> acc
      }
      chain_step(next, p2, n - 1)
    }
  }
}
