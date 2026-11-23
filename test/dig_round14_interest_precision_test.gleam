//// Two interest bugs found after 0.13.2.
////
//// A rate written to 16 places, such as `0.0041666666666667` for 5% a
//// year over 12 months, made `1 + rate` need a 17-digit coefficient, so
//// `future_value`, `present_value`, `payment` and `schedule` returned
//// `PrecisionExceeded`. `effective_annual_rate` divides the nominal rate
//// at 7 places first, so it did not fail, and is checked here only as a
//// reference.
////
//// On JavaScript, `schedule` recursed once per period without a tail
//// call, so 1200 periods overflowed the call stack. The loops of
//// `future_value`, `present_value`, `payment` and `money.allocate` were
//// not tail calls either; `allocate` overflowed at 100,000 ratios.
////
//// The expected values come from Python's `decimal` module with 200
//// digits of precision, computed on the same rate as the test passes and
//// rounded half-even with `quantize` to the places the test asks for.
//// `schedule` is checked against a Python loop with the same rules:
//// each period's interest is the balance times the rate rounded
//// half-even to cents, every period but the last pays the payment, and
//// the last pays what is left. Given the payment, every row is exact, so
//// the rows are asserted exactly.
////
//// Tolerance: `payment` may be one cent off Python's value, and only
//// `payment`. The fix adds one rounding: `1 + rate` does not fit for any
//// rate here, so it uses the rate rounded half-even to 15 places, which
//// moves the rate by at most 5e-16 and the payments below by at most 2e-10. `payment`
//// compounds at 7 places, as documented in `finanza/interest`, and that
//// moves the unrounded payment by up to 3.2e-4 for the annual rates of 1%
//// to 20% over 360 and 1200 months (measured with the same rounding in
//// Python). When the exact payment is that close to a half-cent, the
//// rounded payment is one cent off: 7% gives 1330.61 against
//// 1330.604990. `future_value` works at `digits + 2` places, at least 7,
//// on the amount itself, so its error stays below 1e-6 here and it is
//// asserted exactly.

import gleam/list
import gleam/order
import gleam/result
import gleam/string

import finanza/decimal
import finanza/interest
import finanza/money
import support

fn text(value: Result(decimal.Decimal, a)) -> Result(String, a) {
  result.map(value, decimal.to_string)
}

// --- the reported rate -------------------------------------------------------

pub fn future_value_with_a_sixteen_place_rate_test() {
  let rate = support.parse("0.0041666666666667")
  assert interest.future_value(
      present: support.int(1000),
      rate_per_period: rate,
      periods: 360,
      digits: 2,
    )
    |> text
    == Ok("4467.74")
}

pub fn present_value_with_a_sixteen_place_rate_test() {
  // 1000 / 1.0041666666666667^1200 = 6.808304...
  let rate = support.parse("0.0041666666666667")
  assert interest.present_value(
      future: support.int(1000),
      rate_per_period: rate,
      periods: 1200,
      digits: 6,
    )
    |> text
    == Ok("6.808304")
}

pub fn payment_with_a_sixteen_place_rate_test() {
  let rate = support.parse("0.0041666666666667")
  assert interest.payment(
      principal: support.int(200_000),
      rate_per_period: rate,
      periods: 360,
      digits: 2,
    )
    |> text
    == Ok("1073.64")
}

pub fn effective_annual_rate_monthly_test() {
  // (1 + 0.05 / 12)^12 - 1 = 0.0511618978...
  assert interest.effective_annual_rate(
      nominal_rate: support.parse("0.05"),
      compounds_per_year: 12,
      digits: 6,
    )
    |> text
    == Ok("0.051162")
}

pub fn schedule_with_a_sixteen_place_rate_test() {
  let rate = support.parse("0.0041666666666667")
  let assert Ok(rows) =
    interest.schedule(
      principal: support.int(200_000),
      rate_per_period: rate,
      periods: 360,
      digits: 2,
    )
  assert summary(rows, 180)
    == Summary(
      count: 360,
      first: #("1073.64", "833.33", "240.31", "199759.69"),
      middle_balance: "135768.76",
      last: #("1076.48", "4.47", "1072.01", "0.00"),
      total_interest: "186513.24",
    )
}

pub fn negative_sixteen_place_rate_test() {
  // 1 + rate is 0.9958333333333333, a 16-digit coefficient past 2^53 - 1,
  // so the rate is used at 15 places: 1000 × 0.995833333333333^12.
  let rate = support.parse("-0.0041666666666667")
  assert interest.future_value(
      present: support.int(1000),
      rate_per_period: rate,
      periods: 12,
      digits: 2,
    )
    |> text
    == Ok("951.13")
}

pub fn sixteen_place_rate_is_rounded_even_when_the_sum_fits_test() {
  // 1 + -0.8999999999999999 = 0.1000000000000001 would fit, but
  // `decimal.add` scales 1 to 16 places first, which is past 2^53 - 1, so
  // the rate is rounded to 15 places: 1000 × 0.100000000000000.
  let rate = support.parse("-0.8999999999999999")
  assert interest.future_value(
      present: support.int(1000),
      rate_per_period: rate,
      periods: 1,
      digits: 13,
    )
    |> text
    == Ok("100.0000000000000")
}

// --- monthly rates from annual rates of 1% to 20% ----------------------------

type Case {
  Case(
    rate: String,
    // Python's payment, rounded half-even to cents.
    payment: String,
    // What `interest.payment` returns, which `schedule` pays each period.
    returned: String,
    future_value: String,
    future_value_120: String,
    first: #(String, String, String, String),
    middle_balance: String,
    last: #(String, String, String, String),
    total_interest: String,
  )
}

// The annual rate divided by 12, rounded half-even to 16 places, for a
// 200,000 loan over 360 months. `future_value` is of 1000 over 360
// months and of 123456.78 over 120 months.
const cases = [
  Case(
    rate: "0.0008333333333333",
    payment: "643.28",
    returned: "643.28",
    future_value: "1349.69",
    future_value_120: "136435.16",
    first: #("643.28", "166.67", "476.61", "199523.39"),
    middle_balance: "107482.67",
    last: #("642.89", "0.54", "642.35", "0.00"),
    total_interest: "31580.41",
  ),
  Case(
    rate: "0.0016666666666667",
    payment: "739.24",
    returned: "739.24",
    future_value: "1821.21",
    future_value_120: "150765.35",
    first: #("739.24", "333.33", "405.91", "199594.09"),
    middle_balance: "114876.03",
    last: #("738.63", "1.23", "737.40", "0.00"),
    total_interest: "66125.79",
  ),
  Case(
    rate: "0.0041666666666667",
    payment: "1073.64",
    returned: "1073.64",
    future_value: "4467.74",
    future_value_120: "203334.49",
    first: #("1073.64", "833.33", "240.31", "199759.69"),
    middle_balance: "135768.76",
    last: #("1076.48", "4.47", "1072.01", "0.00"),
    total_interest: "186513.24",
  ),
  Case(
    rate: "0.0058333333333333",
    payment: "1330.60",
    // The exact payment is 1330.604990, 1e-5 below a half-cent.
    returned: "1330.61",
    future_value: "8116.50",
    future_value_120: "248106.32",
    first: #("1330.61", "1166.67", "163.94", "199836.06"),
    middle_balance: "148036.14",
    last: #("1324.31", "7.68", "1316.63", "0.00"),
    total_interest: "279013.30",
  ),
  Case(
    rate: "0.0083333333333333",
    payment: "1755.14",
    returned: "1755.14",
    future_value: "19837.40",
    future_value_120: "334202.63",
    first: #("1755.14", "1666.67", "88.47", "199911.53"),
    middle_balance: "163330.46",
    last: #("1762.38", "14.57", "1747.81", "0.00"),
    total_interest: "431857.64",
  ),
  Case(
    rate: "0.0091666666666667",
    payment: "1904.65",
    returned: "1904.65",
    future_value: "26708.10",
    future_value_120: "369030.78",
    first: #("1904.65", "1833.33", "71.32", "199928.68"),
    middle_balance: "167573.08",
    last: #("1895.68", "17.22", "1878.46", "0.00"),
    total_interest: "485665.03",
  ),
  Case(
    rate: "0.0166666666666667",
    payment: "3342.04",
    returned: "3342.04",
    future_value: "383963.96",
    future_value_120: "897315.36",
    first: #("3342.04", "3333.33", "8.71", "199991.29"),
    middle_balance: "190286.12",
    last: #("3285.01", "53.85", "3231.16", "0.00"),
    total_interest: "1003077.37",
  ),
]

pub fn monthly_payment_matches_python_test() {
  list.each(cases, fn(case_) {
    let assert Ok(returned) =
      interest.payment(
        principal: support.int(200_000),
        rate_per_period: support.parse(case_.rate),
        periods: 360,
        digits: 2,
      )
    assert decimal.to_string(returned) == case_.returned
    let assert Ok(difference) =
      decimal.subtract(returned, support.parse(case_.payment))
    assert decimal.compare(decimal.absolute(difference), support.parse("0.01"))
      != order.Gt
  })
}

pub fn monthly_future_value_matches_python_test() {
  list.each(cases, fn(case_) {
    let rate = support.parse(case_.rate)
    assert interest.future_value(
        present: support.int(1000),
        rate_per_period: rate,
        periods: 360,
        digits: 2,
      )
      |> text
      == Ok(case_.future_value)
    assert interest.future_value(
        present: support.parse("123456.78"),
        rate_per_period: rate,
        periods: 120,
        digits: 2,
      )
      |> text
      == Ok(case_.future_value_120)
  })
}

pub fn monthly_schedule_matches_python_test() {
  list.each(cases, fn(case_) {
    let assert Ok(rows) =
      interest.schedule(
        principal: support.int(200_000),
        rate_per_period: support.parse(case_.rate),
        periods: 360,
        digits: 2,
      )
    assert summary(rows, 180)
      == Summary(
        count: 360,
        first: case_.first,
        middle_balance: case_.middle_balance,
        last: case_.last,
        total_interest: case_.total_interest,
      )
  })
}

// --- 1200 periods on JavaScript ----------------------------------------------

pub fn schedule_of_1200_periods_test() {
  let assert Ok(rows) =
    interest.schedule(
      principal: support.int(200_000),
      rate_per_period: support.parse("0.005"),
      periods: 1200,
      digits: 2,
    )
  assert summary(rows, 600)
    == Summary(
      count: 1200,
      first: #("1002.52", "1000.00", "2.52", "199997.48"),
      middle_balance: "190455.36",
      last: #("1176.55", "5.85", "1170.70", "0.00"),
      total_interest: "1003198.03",
    )
  assert list.index_map(rows, fn(row, position) { row.index - position })
    == list.repeat(1, 1200)
}

pub fn schedule_of_1200_periods_at_a_sixteen_place_rate_test() {
  let assert Ok(rows) =
    interest.schedule(
      principal: support.int(200_000),
      rate_per_period: support.parse("0.0041666666666667"),
      periods: 1200,
      digits: 2,
    )
  assert summary(rows, 600)
    == Summary(
      count: 1200,
      first: #("839.05", "833.33", "5.72", "199994.28"),
      middle_balance: "184744.01",
      last: #("689.95", "2.86", "687.09", "0.00"),
      total_interest: "806710.90",
    )
}

pub fn growth_over_1200_periods_test() {
  let rate = support.parse("0.005")
  assert interest.future_value(
      present: support.int(1000),
      rate_per_period: rate,
      periods: 1200,
      digits: 2,
    )
    |> text
    == Ok("397442.32")
  assert interest.present_value(
      future: support.int(1000),
      rate_per_period: rate,
      periods: 1200,
      digits: 6,
    )
    |> text
    == Ok("2.516088")
  assert interest.payment(
      principal: support.int(200_000),
      rate_per_period: rate,
      periods: 1200,
      digits: 2,
    )
    |> text
    == Ok("1002.52")
}

pub fn effective_annual_rate_compounded_1200_times_test() {
  // The rate per period is 0.05 / 1200 at 7 places, 0.0000417, so this
  // is (1.0000417)^1200 - 1 = 0.051312..., not the exact 0.051270.
  assert interest.effective_annual_rate(
      nominal_rate: support.parse("0.05"),
      compounds_per_year: 1200,
      digits: 6,
    )
    |> text
    == Ok("0.051312")
}

pub fn periods_past_1200_are_rejected_test() {
  let rate = support.parse("0.005")
  let principal = support.int(200_000)
  list.each([1201, 10_000], fn(periods) {
    assert interest.schedule(
        principal:,
        rate_per_period: rate,
        periods:,
        digits: 2,
      )
      == Error(interest.PeriodsOutOfRange)
    assert interest.payment(
        principal:,
        rate_per_period: rate,
        periods:,
        digits: 2,
      )
      == Error(interest.PeriodsOutOfRange)
    assert interest.future_value(
        present: principal,
        rate_per_period: rate,
        periods:,
        digits: 2,
      )
      == Error(interest.PeriodsOutOfRange)
    assert interest.present_value(
        future: principal,
        rate_per_period: rate,
        periods:,
        digits: 2,
      )
      == Error(interest.PeriodsOutOfRange)
    assert interest.effective_annual_rate(
        nominal_rate: rate,
        compounds_per_year: periods,
        digits: 2,
      )
      == Error(interest.CompoundsOutOfRange)
  })
}

// --- other loops over the length of the input --------------------------------

pub fn allocate_over_100000_ratios_test() {
  let assert Ok(bill) = money.from_minor(100_001, in: money.usd)
  let assert Ok(parts) = money.allocate(bill, list.repeat(1, 100_000))
  assert list.length(parts) == 100_000
  let assert [first, second, ..] = parts
  assert money.to_string(first) == "USD 0.02"
  assert money.to_string(second) == "USD 0.01"
}

pub fn parse_input_of_1000_bytes_test() {
  // 998 leading zeros after the sign, then 1: every character is read.
  let input = "+" <> string.repeat("0", 998) <> "1"
  assert decimal.parse(input) |> text == Ok("1")
}

// --- helpers -----------------------------------------------------------------

type Summary {
  Summary(
    count: Int,
    first: #(String, String, String, String),
    middle_balance: String,
    last: #(String, String, String, String),
    total_interest: String,
  )
}

fn summary(rows: List(interest.Period), middle: Int) -> Summary {
  let assert [first, ..] = rows
  let assert Ok(last) = list.last(rows)
  let assert Ok(middle_row) = rows |> list.drop(middle - 1) |> list.first
  let assert Ok(total) =
    list.try_fold(rows, decimal.zero(), fn(total, row) {
      decimal.add(total, row.interest)
    })
  Summary(
    count: list.length(rows),
    first: row_text(first),
    middle_balance: decimal.to_string(middle_row.balance),
    last: row_text(last),
    total_interest: decimal.to_string(total),
  )
}

fn row_text(row: interest.Period) -> #(String, String, String, String) {
  #(
    decimal.to_string(row.payment),
    decimal.to_string(row.interest),
    decimal.to_string(row.principal_paid),
    decimal.to_string(row.balance),
  )
}
