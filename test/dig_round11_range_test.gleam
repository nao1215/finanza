//// The supported range of a `Decimal` and the inputs `parse` accepts.
////
//// A decimal's exponent is between -28 and 15, its coefficient is
//// within ±(2^53 - 1), and `parse` reads at most 1,000 bytes. These
//// tests pin each bound from both sides, check that hostile inputs are
//// rejected without building large values, and cover `divide` and
//// `allocate` on values whose intermediate products pass 2^53.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range

import finanza/decimal
import finanza/interest
import finanza/money
import support

// 2^53 - 1, written once so the tests do not repeat the literal.
const max = 9_007_199_254_740_991

fn text(value: Result(decimal.Decimal, a)) -> Result(String, a) {
  result.map(value, decimal.to_string)
}

// --- new: the exponent bounds ---------------------------------------------

pub fn new_accepts_the_smallest_exponent_test() {
  assert decimal.new(coefficient: 1, exponent: -28) |> text
    == Ok("0.0000000000000000000000000001")
  assert decimal.new(coefficient: max, exponent: -28) |> text
    == Ok("0.0000000000009007199254740991")
  assert decimal.new(coefficient: 0, exponent: -28) |> result.is_ok
}

pub fn new_rejects_an_exponent_below_the_smallest_test() {
  assert decimal.new(coefficient: 1, exponent: -29) == Error(Nil)
  assert decimal.new(coefficient: 0, exponent: -29) == Error(Nil)
  assert decimal.new(coefficient: -1, exponent: -29) == Error(Nil)
}

pub fn new_accepts_the_largest_exponent_test() {
  assert decimal.new(coefficient: 1, exponent: 15) |> text
    == Ok("1000000000000000")
  assert decimal.new(coefficient: 0, exponent: 15) |> text == Ok("0")
}

pub fn new_rejects_an_exponent_above_the_largest_test() {
  assert decimal.new(coefficient: 0, exponent: 16) == Error(Nil)
  assert decimal.new(coefficient: 0, exponent: 1_000_000_000) == Error(Nil)
  assert decimal.new(coefficient: 0, exponent: -1_000_000_000) == Error(Nil)
}

pub fn new_bounds_the_coefficient_at_every_exponent_test() {
  assert decimal.new(coefficient: max, exponent: -28) |> result.is_ok
  assert decimal.new(coefficient: max + 1, exponent: -28) == Error(Nil)
  assert decimal.new(coefficient: 0 - max, exponent: -28) |> result.is_ok
  assert decimal.new(coefficient: 0 - max - 1, exponent: -28) == Error(Nil)
}

/// `new` succeeds exactly when the exponent is in -28..15 and the
/// integer the decimal stands for is within ±(2^53 - 1).
pub fn new_matches_the_range_model_test() {
  metamon.forall(
    generator.tuple2(
      generator.one_of([
        generator.int(range.constant(-1000, 1000)),
        generator.element_of([0, 1, -1, 9, max, 0 - max]),
      ]),
      generator.int(range.constant(-40, 25)),
    ),
    fn(input) {
      let #(coefficient, exponent) = input
      let fits =
        exponent >= -28
        && exponent <= 15
        && int.absolute_value(coefficient) * pow10(int.max(exponent, 0)) <= max
      result.is_ok(decimal.new(coefficient:, exponent:)) == fits
    },
  )
}

// --- parse: the same bounds -----------------------------------------------

pub fn parse_accepts_28_places_test() {
  assert decimal.parse("0.0000000000000000000000000001") |> text
    == Ok("0.0000000000000000000000000001")
  assert decimal.parse("-0.0000000000009007199254740991") |> text
    == Ok("-0.0000000000009007199254740991")
  assert decimal.parse("1e-28") |> text == Ok("0.0000000000000000000000000001")
}

pub fn parse_rejects_29_places_test() {
  assert decimal.parse("0.00000000000000000000000000001")
    == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("1e-29") == Error(decimal.ParsedValueTooLarge)
  // The exponent is kept, so trailing zeros count as places.
  assert decimal.parse("0.10000000000000000000000000000")
    == Error(decimal.ParsedValueTooLarge)
}

pub fn parse_bounds_a_zero_like_any_value_test() {
  assert decimal.parse("0e15") |> result.map(decimal.is_zero) == Ok(True)
  assert decimal.parse("0e16") == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("0e-28") |> result.map(decimal.is_zero) == Ok(True)
  assert decimal.parse("0e-29") == Error(decimal.ParsedValueTooLarge)
}

pub fn parse_rejects_huge_exponents_test() {
  assert decimal.parse("1e-999999999") == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("1e999999999") == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("0e999999999") == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("0e-999999999") == Error(decimal.ParsedValueTooLarge)
  let nines = string.repeat("9", 900)
  assert decimal.parse("1e-" <> nines) == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("1e" <> nines) == Error(decimal.ParsedValueTooLarge)
}

pub fn parse_rejects_huge_digit_counts_test() {
  assert decimal.parse(string.repeat("9", 999))
    == Error(decimal.ParsedValueTooLarge)
  assert decimal.parse("0." <> string.repeat("0", 990) <> "1")
    == Error(decimal.ParsedValueTooLarge)
}

pub fn parse_accepts_1000_bytes_test() {
  // Leading zeros keep the value in range however many there are.
  assert decimal.parse(string.repeat("0", 999) <> "7") |> text == Ok("7")
  assert decimal.parse(string.repeat(" ", 997) <> "1.5") |> text == Ok("1.5")
}

pub fn parse_rejects_1001_bytes_test() {
  assert decimal.parse(string.repeat("0", 1000) <> "7")
    == Error(decimal.InputTooLong)
  assert decimal.parse(string.repeat(" ", 998) <> "1.5")
    == Error(decimal.InputTooLong)
  // The limit counts bytes: 334 ideographic spaces are 1,002 bytes.
  assert decimal.parse(string.repeat("\u{3000}", 334) <> "1")
    == Error(decimal.InputTooLong)
}

pub fn parse_rejects_a_very_long_input_at_once_test() {
  // Ten megabytes of digits or junk would take a full scan to read.
  let long = string.repeat("1234567890", 1_000_000)
  assert decimal.parse(long) == Error(decimal.InputTooLong)
  assert decimal.parse("x" <> long) == Error(decimal.InputTooLong)
}

/// Every value in range survives `to_string` and `parse` unchanged,
/// with the same coefficient and exponent.
pub fn in_range_values_round_trip_through_text_test() {
  metamon.forall(
    generator.tuple2(
      generator.one_of([
        generator.int(range.constant(0 - max, max)),
        generator.int(range.constant(-1000, 1000)),
      ]),
      generator.int(range.constant(-28, 0)),
    ),
    fn(input) {
      let #(coefficient, exponent) = input
      let value = support.new(coefficient:, exponent:)
      decimal.parse(decimal.to_string(value)) == Ok(value)
    },
  )
}

/// A positive exponent is rendered as an integer, so the value comes
/// back with exponent 0.
pub fn positive_exponents_round_trip_by_value_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-9, 9)),
      generator.int(range.constant(0, 15)),
    ),
    fn(input) {
      let #(coefficient, exponent) = input
      let value = support.new(coefficient:, exponent:)
      case decimal.parse(decimal.to_string(value)) {
        Ok(parsed) -> decimal.equal(parsed, value)
        Error(_) -> False
      }
    },
  )
}

/// Scientific notation is accepted exactly when the value it names is in
/// range.
pub fn scientific_notation_matches_the_range_model_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-99, 99)),
      generator.int(range.constant(-60, 40)),
    ),
    fn(input) {
      let #(coefficient, exponent) = input
      let source = int.to_string(coefficient) <> "e" <> int.to_string(exponent)
      let fits =
        exponent >= -28
        && exponent <= 15
        && int.absolute_value(coefficient) * pow10(int.max(exponent, 0)) <= max
      result.is_ok(decimal.parse(source)) == fits
    },
  )
}

/// Whatever text `parse` accepts, `to_string` of the result is at most
/// 31 characters, as in `"-0.0000000000009007199254740991"`, so a short
/// hostile input cannot make a long output.
pub fn accepted_inputs_render_short_text_test() {
  metamon.forall(
    generator.tuple4(
      generator.element_of(["", "-", "+"]),
      generator.string_digit(range.constant(1, 40)),
      generator.element_of(["", ".", ".5", ".000"]),
      generator.one_of([
        generator.int(range.constant(-40, 40)),
        generator.element_of([
          -1_000_000_000,
          1_000_000_000,
          -999_999_999_999,
          max,
          0 - max,
        ]),
      ]),
    ),
    fn(input) {
      let #(sign, digits, fraction, exponent) = input
      let source = sign <> digits <> fraction <> "e" <> int.to_string(exponent)
      case decimal.parse(source) {
        Ok(value) -> string.length(decimal.to_string(value)) <= 31
        Error(decimal.ParsedValueTooLarge) -> True
        Error(_) -> False
      }
    },
  )
}

// --- arithmetic at the bounds ---------------------------------------------

pub fn multiply_fails_below_the_smallest_exponent_test() {
  let a = support.parse("1e-14")
  assert decimal.multiply(a, a) |> text == Ok("0.0000000000000000000000000001")
  assert decimal.multiply(a, support.parse("1e-15"))
    == Error(decimal.PrecisionExceeded)
}

pub fn multiply_drops_trailing_zeros_to_reach_the_smallest_exponent_test() {
  // 0.10 × 1e-27 has the exponent -29 but the value 1e-28.
  assert decimal.multiply(support.parse("0.10"), support.parse("1e-27")) |> text
    == Ok("0.0000000000000000000000000001")
  assert decimal.multiply(
      support.parse("1000.00"),
      support.parse("0.000000000000000000000000001"),
    )
    |> text
    == Ok("0.0000000000000000000000010000")
  // A non-zero digit at place 29 cannot be kept.
  assert decimal.multiply(
      support.parse("1000.01"),
      support.parse("0.000000000000000000000000001"),
    )
    == Error(decimal.PrecisionExceeded)
}

pub fn multiply_moves_a_zero_product_into_range_test() {
  let zero = support.parse("0.00000000000000")
  assert decimal.multiply(zero, support.parse("0.000000000000001")) |> text
    == Ok("0.0000000000000000000000000000")
  let big_zero = support.new(coefficient: 0, exponent: 15)
  assert decimal.multiply(big_zero, big_zero)
    == Ok(support.new(coefficient: 0, exponent: 15))
}

pub fn money_multiply_by_a_tiny_factor_rounds_to_zero_test() {
  let amount = support.from_minor(units: 100_000, currency: money.usd)
  assert money.multiply(
      amount,
      by: support.parse("0.000000000000000000000000001"),
      rounding: decimal.HalfEven,
    )
    |> result.map(money.to_string)
    == Ok("USD 0.00")
}

pub fn currency_exponents_follow_the_decimal_range_test() {
  let fine = money.Currency(..money.usd, exponent: 28)
  let too_fine = money.Currency(..money.usd, exponent: 29)
  assert money.from_minor(1, in: fine) |> result.is_ok
  assert money.from_minor(1, in: too_fine)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
}

pub fn round_accepts_digits_from_minus_15_to_28_test() {
  let tiny = support.parse("1e-20")
  assert decimal.round(tiny, digits: 28, rounding: decimal.HalfEven) |> text
    == Ok("0.0000000000000000000100000000")
  assert decimal.round(tiny, digits: 29, rounding: decimal.HalfEven)
    == Error(decimal.PrecisionExceeded)
  assert decimal.round(decimal.zero(), digits: 29, rounding: decimal.HalfEven)
    == Error(decimal.PrecisionExceeded)
  assert decimal.round(support.parse("123"), digits: -15, rounding: decimal.Up)
    |> text
    == Ok("1000000000000000")
  assert decimal.round(
      support.parse("123"),
      digits: -15,
      rounding: decimal.Down,
    )
    |> text
    == Ok("0")
  assert decimal.round(
      support.parse("123"),
      digits: -16,
      rounding: decimal.Down,
    )
    == Error(decimal.PrecisionExceeded)
}

pub fn round_rejects_huge_digits_at_once_test() {
  let one = decimal.one()
  assert decimal.round(one, digits: 1_000_000_000, rounding: decimal.HalfEven)
    == Error(decimal.PrecisionExceeded)
  assert decimal.round(one, digits: -1_000_000_000, rounding: decimal.HalfEven)
    == Error(decimal.PrecisionExceeded)
}

pub fn divide_accepts_digits_up_to_28_test() {
  let tiny = support.parse("1e-20")
  assert decimal.divide(
      tiny,
      decimal.one(),
      digits: 28,
      rounding: decimal.HalfEven,
    )
    |> text
    == Ok("0.0000000000000000000100000000")
  assert decimal.divide(
      tiny,
      decimal.one(),
      digits: 29,
      rounding: decimal.HalfEven,
    )
    == Error(decimal.PrecisionExceeded)
  assert decimal.divide(
      decimal.zero(),
      decimal.one(),
      digits: 29,
      rounding: decimal.HalfEven,
    )
    == Error(decimal.PrecisionExceeded)
}

pub fn divide_rejects_huge_digits_at_once_test() {
  let one = decimal.one()
  let three = support.int(3)
  assert decimal.divide(
      one,
      three,
      digits: 1_000_000_000,
      rounding: decimal.HalfEven,
    )
    == Error(decimal.PrecisionExceeded)
  assert decimal.divide(
      one,
      three,
      digits: -1_000_000_000,
      rounding: decimal.HalfEven,
    )
    == Error(decimal.PrecisionExceeded)
}

pub fn dividing_the_smallest_value_rounds_to_zero_test() {
  let tiny = support.parse("1e-28")
  assert decimal.divide(
      tiny,
      decimal.one(),
      digits: 0,
      rounding: decimal.HalfEven,
    )
    |> text
    == Ok("0")
  assert decimal.divide(tiny, support.int(max), digits: 0, rounding: decimal.Up)
    |> text
    == Ok("1")
}

// --- divide: dividends scaled past 2^53 ------------------------------------

pub fn divide_scales_the_dividend_past_2_53_test() {
  let assert Ok(divisor) = decimal.parse("1.234567890123456")
  let one = decimal.one()
  assert decimal.divide(one, divisor, digits: 2, rounding: decimal.HalfEven)
    |> text
    == Ok("0.81")
  assert decimal.divide(one, divisor, digits: 15, rounding: decimal.HalfEven)
    |> text
    == Ok("0.810000007290001")
}

pub fn divide_with_large_shifts_matches_python_test() {
  let cases = [
    #(
      "7",
      "9007199254740991",
      28,
      decimal.HalfEven,
      "0.0000000000000007771561172376",
    ),
    #(
      "0.0000000000009007199254740991",
      "3",
      28,
      decimal.HalfEven,
      "0.0000000000003002399751580330",
    ),
    #("1", "3", 15, decimal.HalfEven, "0.333333333333333"),
    #("2", "3", 15, decimal.HalfEven, "0.666666666666667"),
    #("1e-28", "9007199254740991", 0, decimal.Up, "1"),
    #("5", "0.0000000000000007", 0, decimal.HalfEven, "7142857142857143"),
    #("1", "0.9007199254740991", 15, decimal.HalfEven, "1.110223024625157"),
    #("-2", "7.000000000000001", 14, decimal.Floor, "-0.28571428571429"),
  ]
  list.each(cases, fn(row) {
    let #(a, b, digits, mode, expected) = row
    assert decimal.divide(
        support.parse(a),
        support.parse(b),
        digits:,
        rounding: mode,
      )
      |> text
      == Ok(expected)
  })
}

pub fn divide_still_fails_when_the_quotient_is_out_of_range_test() {
  assert decimal.divide(
      decimal.one(),
      support.int(3),
      digits: 17,
      rounding: decimal.HalfEven,
    )
    == Error(decimal.PrecisionExceeded)
  assert decimal.divide(
      support.int(max),
      support.parse("0.1"),
      digits: 0,
      rounding: decimal.HalfEven,
    )
    == Error(decimal.PrecisionExceeded)
}

@target(erlang)
/// Erlang integers are unbounded, so the exact quotient is one integer
/// division away. `divide` must agree with it wherever the rounded
/// quotient is in range, and fail otherwise.
pub fn divide_matches_a_big_integer_oracle_test() {
  metamon.forall(
    generator.tuple6(
      generator.int(range.constant(0 - max, max)),
      generator.int(range.constant(-28, 0)),
      generator.one_of([
        generator.int(range.constant(1, max)),
        generator.int(range.constant(1, 1000)),
      ]),
      generator.int(range.constant(-28, 0)),
      generator.int(range.constant(0, 28)),
      generator.element_of([
        decimal.HalfEven,
        decimal.HalfUp,
        decimal.HalfDown,
        decimal.Up,
        decimal.Down,
        decimal.Ceiling,
        decimal.Floor,
      ]),
    ),
    fn(input) {
      let #(ca, ea, cb, eb, digits, mode) = input
      let shift = ea - eb + digits
      let #(numerator, denominator) = case shift >= 0 {
        True -> #(ca * pow10(shift), cb)
        False -> #(ca, cb * pow10(0 - shift))
      }
      let quotient = oracle_round(numerator, denominator, mode)
      let expected = decimal.new(coefficient: quotient, exponent: 0 - digits)
      let actual =
        decimal.divide(
          support.new(coefficient: ca, exponent: ea),
          support.new(coefficient: cb, exponent: eb),
          digits:,
          rounding: mode,
        )
      case expected {
        Ok(value) -> actual == Ok(value)
        Error(Nil) -> actual == Error(decimal.PrecisionExceeded)
      }
    },
  )
}

// `numerator / denominator` rounded with `mode`, for `denominator > 0`.
@target(erlang)
fn oracle_round(
  numerator: Int,
  denominator: Int,
  mode: decimal.RoundingMode,
) -> Int {
  let sign = case numerator < 0 {
    True -> -1
    False -> 1
  }
  let magnitude = int.absolute_value(numerator)
  let quotient = magnitude / denominator
  let remainder = magnitude % denominator
  let bump = case remainder == 0, mode {
    True, _ -> False
    False, decimal.Down -> False
    False, decimal.Up -> True
    False, decimal.Ceiling -> sign > 0
    False, decimal.Floor -> sign < 0
    False, decimal.HalfUp -> 2 * remainder >= denominator
    False, decimal.HalfDown -> 2 * remainder > denominator
    False, decimal.HalfEven ->
      2 * remainder > denominator
      || { 2 * remainder == denominator && quotient % 2 == 1 }
  }
  case bump {
    True -> sign * { quotient + 1 }
    False -> sign * quotient
  }
}

// --- allocate: shares of amounts near 2^53 ---------------------------------

fn allocate_units(units: Int, ratios: List(Int)) -> Result(List(Int), Nil) {
  money.allocate(support.from_minor(units:, currency: money.jpy), ratios)
  |> result.map(
    list.map(_, fn(part) {
      let assert Ok(minor) = money.to_minor(part, rounding: decimal.HalfEven)
      minor
    }),
  )
  |> result.replace_error(Nil)
}

pub fn allocate_is_exact_near_2_53_test() {
  // Expected values are floor(amount × ratio / total) plus the leftover
  // units, computed with Python's unbounded integers.
  assert allocate_units(max, [2, 1])
    == Ok([6_004_799_503_160_661, 3_002_399_751_580_330])
  assert allocate_units(max, [7, 3])
    == Ok([6_305_039_478_318_694, 2_702_159_776_422_297])
  assert allocate_units(max, [1, 1, 1])
    == Ok([3_002_399_751_580_331, 3_002_399_751_580_330, 3_002_399_751_580_330])
  assert allocate_units(max, [1_000_000, 1])
    == Ok([9_007_190_247_550_744, 9_007_190_247])
  assert allocate_units(max, [3, 5, 11])
    == Ok([1_422_189_356_011_736, 2_370_315_593_352_892, 5_214_694_305_376_363])
  // Found by the property below: on JavaScript the product of the amount
  // and the ratio lost its low digits, and the parts did not add up.
  assert allocate_units(9_007_199_254_617_499, [758_743_223, 157_673_713])
    == Ok([7_457_469_547_083_621, 1_549_729_707_533_878])
  assert allocate_units(0 - max, [2, 1])
    == Ok([-6_004_799_503_160_661, -3_002_399_751_580_330])
}

pub fn allocate_rejects_ratios_whose_sum_is_out_of_range_test() {
  let assert Ok(bill) = money.from_minor(100, in: money.usd)
  assert money.allocate(bill, [max, 1])
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  assert money.allocate(bill, [max, 0]) |> result.is_ok
}

/// The parts always add up to the amount, and each part is the floor or
/// the ceiling of its exact share.
pub fn allocate_parts_add_up_near_2_53_test() {
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(max - 1_000_000, max)),
      generator.list_of(
        generator.int(range.constant(0, 1_000_000_000)),
        range.constant(1, 6),
      ),
    ),
    fn(input) {
      let #(units, ratios) = input
      case allocate_units(units, ratios) {
        Ok(parts) -> int.sum(parts) == units
        Error(Nil) -> list.all(ratios, fn(ratio) { ratio == 0 })
      }
    },
  )
}

// --- interest: digits beyond the range -------------------------------------

pub fn interest_rejects_digits_beyond_28_at_once_test() {
  let principal = support.parse("1000")
  let rate = support.parse("0.05")
  let failed = Error(interest.DigitsOutOfRange)
  let huge = 1_000_000_000
  assert interest.simple(principal:, rate:, periods: 3, digits: huge) == failed
  assert interest.future_value(
      present: principal,
      rate_per_period: rate,
      periods: 10,
      digits: huge,
    )
    == failed
  assert interest.present_value(
      future: principal,
      rate_per_period: rate,
      periods: 10,
      digits: huge,
    )
    == failed
  assert interest.payment(
      principal:,
      rate_per_period: rate,
      periods: 12,
      digits: huge,
    )
    == failed
  assert interest.effective_annual_rate(
      nominal_rate: rate,
      compounds_per_year: 12,
      digits: huge,
    )
    == failed
  assert interest.schedule(
      principal:,
      rate_per_period: rate,
      periods: 12,
      digits: huge,
    )
    == Error(interest.DigitsOutOfRange)
  assert interest.future_value(
      present: principal,
      rate_per_period: rate,
      periods: 10,
      digits: 29,
    )
    == failed
}

pub fn future_value_keeps_working_near_a_loss_of_100_percent_test() {
  // Each step multiplies by 0.000001, so the exact product would need
  // more than 28 places after a few periods.
  let rate = support.parse("-0.999999")
  assert interest.future_value(
      present: support.parse("1000"),
      rate_per_period: rate,
      periods: 12,
      digits: 20,
    )
    |> text
    == Ok("0.00000000000000000000")
}

fn pow10(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> 10 * pow10(n - 1)
  }
}
