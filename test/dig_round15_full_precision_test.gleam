//// Two precision limits left after 0.13.3.
////
//// `interest.payment`, `effective_annual_rate` and `schedule` compounded
//// at 7 places, so a payment near a half-cent could round to the wrong
//// cent: 7% a year over 360 months gave 1330.61 against an exact
//// 1330.604990. `effective_annual_rate` also divided the nominal rate at
//// 7 places, so 5% compounded 1200 times a year gave 0.051312 against an
//// exact 0.051270.
////
//// `decimal.add` scaled both operands to the smaller exponent before
//// adding, so `1 + -0.8999999999999999` failed although the sum,
//// 0.1000000000000001, is in range.
////
//// The expected values come from Python's `decimal` module with 200
//// digits of precision, on the same rate as the test passes, rounded
//// half-even with `quantize` to the places the test asks for. The
//// monthly rate is the annual rate divided by 12, rounded half-even to 16
//// places. `schedule` is checked against a Python loop with the same
//// rules and Python's payment: each period's interest is the balance
//// times the rate rounded half-even to cents, every period but the last
//// pays the payment, and the last pays what is left. Every value is
//// asserted exactly, with no tolerance.
////
//// What can still differ: `payment` keeps (1 + rate)^periods − 1 to
//// about 16 significant digits at each period, so the unrounded payment
//// can be off the exact one by about periods × 1e-15 of the larger of the
//// payment and principal × rate. Python measured at most 1.1e-15 for the
//// cases below and 5.3e-14 for random rates, principals and periods. A
//// payment whose exact value is closer than that to a half-unit at
//// `digits` places can round the other way. The closest case below is 7%
//// over 360 months, 9.6e-6 from a half-cent, and at 6 places every case
//// is at least 1.1e-7 from a half-unit.

import gleam/list
import gleam/result

import finanza/decimal
import finanza/interest
import finanza/money
import support

fn text(value: Result(decimal.Decimal, a)) -> Result(String, a) {
  result.map(value, decimal.to_string)
}

// --- payment and schedule against Python ------------------------------------

type Case {
  Case(
    rate: String,
    periods: Int,
    // Python's payment rounded half-even to cents, and to 6 places.
    payment: String,
    payment_6: String,
    first: #(String, String, String, String),
    // The balance after the middle period, 180 or 600.
    middle_balance: String,
    last: #(String, String, String, String),
    total_interest: String,
    // The balances of all the rows added up.
    total_balance: String,
  )
}

// A 200,000 loan at the monthly rates of 1% to 20% a year, over 360 and
// 1200 months.
const cases = [
  // 1% a year: exact 643.279040893, 4.0e-03 from a half-cent, 3.9e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0008333333333333",
    periods: 360,
    payment: "643.28",
    payment_6: "643.279041",
    first: #("643.28", "166.67", "476.61", "199523.39"),
    middle_balance: "107482.67",
    last: #("642.89", "0.54", "642.35", "0.00"),
    total_interest: "31580.41",
    total_balance: "37696482.10",
  ),
  // 2% a year: exact 739.238945378, 3.9e-03 from a half-cent, 1.2e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0016666666666667",
    periods: 360,
    payment: "739.24",
    payment_6: "739.238945",
    first: #("739.24", "333.33", "405.91", "199594.09"),
    middle_balance: "114876.03",
    last: #("738.63", "1.23", "737.40", "0.00"),
    total_interest: "66125.79",
    total_balance: "39475515.35",
  ),
  // 3% a year: exact 843.208067459, 3.1e-03 from a half-cent, 4.1e-08 from a half-unit at 6 places.
  Case(
    rate: "0.0025",
    periods: 360,
    payment: "843.21",
    payment_6: "843.208067",
    first: #("843.21", "500.00", "343.21", "199656.79"),
    middle_balance: "122100.68",
    last: #("842.14", "2.10", "840.04", "0.00"),
    total_interest: "103554.53",
    total_balance: "41221786.31",
  ),
  // 4% a year: exact 954.830590931, 4.4e-03 from a half-cent, 4.3e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0033333333333333",
    periods: 360,
    payment: "954.83",
    payment_6: "954.830591",
    first: #("954.83", "666.67", "288.16", "199711.84"),
    middle_balance: "129085.82",
    last: #("955.41", "3.17", "952.24", "0.00"),
    total_interest: "143739.38",
    total_balance: "42921797.65",
  ),
  // 5% a year: exact 1073.643246024, 1.8e-03 from a half-cent, 4.8e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0041666666666667",
    periods: 360,
    payment: "1073.64",
    payment_6: "1073.643246",
    first: #("1073.64", "833.33", "240.31", "199759.69"),
    middle_balance: "135768.76",
    last: #("1076.48", "4.47", "1072.01", "0.00"),
    total_interest: "186513.24",
    total_balance: "44563171.53",
  ),
  // 6% a year: exact 1199.101050306, 3.9e-03 from a half-cent, 1.9e-07 from a half-unit at 6 places.
  Case(
    rate: "0.005",
    periods: 360,
    payment: "1199.10",
    payment_6: "1199.101050",
    first: #("1199.10", "1000.00", "199.10", "199800.90"),
    middle_balance: "142097.98",
    last: #("1200.14", "5.97", "1194.17", "0.00"),
    total_interest: "231677.04",
    total_balance: "46135406.75",
  ),
  // 7% a year: exact 1330.604990358, 9.6e-06 from a half-cent, 1.4e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0058333333333333",
    periods: 360,
    payment: "1330.60",
    payment_6: "1330.604990",
    first: #("1330.60", "1166.67", "163.93", "199836.07"),
    middle_balance: "148039.28",
    last: #("1336.54", "7.75", "1328.79", "0.00"),
    total_interest: "279021.94",
    total_balance: "47632342.20",
  ),
  // 8% a year: exact 1467.529147759, 4.1e-03 from a half-cent, 2.6e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0066666666666667",
    periods: 360,
    payment: "1467.53",
    payment_6: "1467.529148",
    first: #("1467.53", "1333.33", "134.20", "199865.80"),
    middle_balance: "153562.80",
    last: #("1466.25", "9.71", "1456.54", "0.00"),
    total_interest: "328309.52",
    total_balance: "49046422.38",
  ),
  // 9% a year: exact 1609.245233890, 2.3e-04 from a half-cent, 3.9e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0075",
    periods: 360,
    payment: "1609.25",
    payment_6: "1609.245234",
    first: #("1609.25", "1500.00", "109.25", "199890.75"),
    middle_balance: "158659.11",
    last: #("1600.25", "11.91", "1588.34", "0.00"),
    total_interest: "379321.00",
    total_balance: "50376140.07",
  ),
  // 10% a year: exact 1755.143140178, 1.9e-03 from a half-cent, 3.2e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0083333333333333",
    periods: 360,
    payment: "1755.14",
    payment_6: "1755.143140",
    first: #("1755.14", "1666.67", "88.47", "199911.53"),
    middle_balance: "163330.46",
    last: #("1762.38", "14.57", "1747.81", "0.00"),
    total_interest: "431857.64",
    total_balance: "51622915.67",
  ),
  // 11% a year: exact 1904.646791179, 1.8e-03 from a half-cent, 3.2e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0091666666666667",
    periods: 360,
    payment: "1904.65",
    payment_6: "1904.646791",
    first: #("1904.65", "1833.33", "71.32", "199928.68"),
    middle_balance: "167573.08",
    last: #("1895.68", "17.22", "1878.46", "0.00"),
    total_interest: "485665.03",
    total_balance: "52781644.09",
  ),
  // 12% a year: exact 2057.225193851, 1.9e-04 from a half-cent, 3.5e-07 from a half-unit at 6 places.
  Case(
    rate: "0.01",
    periods: 360,
    payment: "2057.23",
    payment_6: "2057.225194",
    first: #("2057.23", "2000.00", "57.23", "199942.77"),
    middle_balance: "171409.13",
    last: #("2040.82", "20.21", "2020.61", "0.00"),
    total_interest: "540586.39",
    total_balance: "53858647.83",
  ),
  // 13% a year: exact 2212.399038533, 4.0e-03 from a half-cent, 3.3e-08 from a half-unit at 6 places.
  Case(
    rate: "0.0108333333333333",
    periods: 360,
    payment: "2212.40",
    payment_6: "2212.399039",
    first: #("2212.40", "2166.67", "45.73", "199954.27"),
    middle_balance: "174858.99",
    last: #("2206.92", "23.65", "2183.27", "0.00"),
    total_interest: "596458.52",
    total_balance: "54857715.55",
  ),
  // 14% a year: exact 2369.743502113, 1.5e-03 from a half-cent, 3.9e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0116666666666667",
    periods: 360,
    payment: "2369.74",
    payment_6: "2369.743502",
    first: #("2369.74", "2333.33", "36.41", "199963.59"),
    middle_balance: "177945.28",
    last: #("2388.41", "27.54", "2360.87", "0.00"),
    total_interest: "653125.07",
    total_balance: "55782155.81",
  ),
  // 15% a year: exact 2528.888043130, 3.0e-03 from a half-cent, 3.7e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0125",
    periods: 360,
    payment: "2528.89",
    payment_6: "2528.888043",
    first: #("2528.89", "2500.00", "28.89", "199971.11"),
    middle_balance: "180686.85",
    last: #("2515.43", "31.05", "2484.38", "0.00"),
    total_interest: "710386.94",
    total_balance: "56630958.20",
  ),
  // 16% a year: exact 2689.513994233, 1.0e-03 from a half-cent, 2.7e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0133333333333333",
    periods: 360,
    payment: "2689.51",
    payment_6: "2689.513994",
    first: #("2689.51", "2666.67", "22.84", "199977.16"),
    middle_balance: "183124.97",
    last: #("2725.08", "35.86", "2689.22", "0.00"),
    total_interest: "768259.17",
    total_balance: "57419434.36",
  ),
  // 17% a year: exact 2851.350688887, 4.3e-03 from a half-cent, 3.9e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0141666666666667",
    periods: 360,
    payment: "2851.35",
    payment_6: "2851.350689",
    first: #("2851.35", "2833.33", "18.02", "199981.98"),
    middle_balance: "185273.07",
    last: #("2859.95", "39.95", "2820.00", "0.00"),
    total_interest: "826494.60",
    total_balance: "58140790.50",
  ),
  // 18% a year: exact 3014.170743609, 4.3e-03 from a half-cent, 1.1e-07 from a half-unit at 6 places.
  Case(
    rate: "0.015",
    periods: 360,
    payment: "3014.17",
    payment_6: "3014.170744",
    first: #("3014.17", "3000.00", "14.17", "199985.83"),
    middle_balance: "187167.38",
    last: #("3025.87", "44.72", "2981.15", "0.00"),
    total_interest: "885112.90",
    total_balance: "58807528.16",
  ),
  // 19% a year: exact 3177.784983943, 1.6e-05 from a half-cent, 4.4e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0158333333333333",
    periods: 360,
    payment: "3177.78",
    payment_6: "3177.784984",
    first: #("3177.78", "3166.67", "11.11", "199988.89"),
    middle_balance: "188835.86",
    last: #("3271.32", "50.99", "3220.33", "0.00"),
    total_interest: "944094.34",
    total_balance: "59427011.58",
  ),
  // 20% a year: exact 3342.037372495, 2.4e-03 from a half-cent, 5.4e-09 from a half-unit at 6 places.
  Case(
    rate: "0.0166666666666667",
    periods: 360,
    payment: "3342.04",
    payment_6: "3342.037372",
    first: #("3342.04", "3333.33", "8.71", "199991.29"),
    middle_balance: "190286.12",
    last: #("3285.01", "53.85", "3231.16", "0.00"),
    total_interest: "1003077.37",
    total_balance: "59984640.01",
  ),
  // 1% a year: exact 263.726713451, 1.7e-03 from a half-cent, 4.9e-08 from a half-unit at 6 places.
  Case(
    rate: "0.0008333333333333",
    periods: 1200,
    payment: "263.73",
    payment_6: "263.726713",
    first: #("263.73", "166.67", "97.06", "199902.94"),
    middle_balance: "124479.57",
    last: #("256.83", "0.21", "256.62", "0.00"),
    total_interest: "116469.10",
    total_balance: "139563067.21",
  ),
  // 2% a year: exact 385.606443327, 1.4e-03 from a half-cent, 1.7e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0016666666666667",
    periods: 1200,
    payment: "385.61",
    payment_6: "385.606443",
    first: #("385.61", "333.33", "52.28", "199947.72"),
    middle_balance: "146175.27",
    last: #("372.06", "0.62", "371.44", "0.00"),
    total_interest: "262718.45",
    total_balance: "157431000.86",
  ),
  // 3% a year: exact 526.301279417, 3.7e-03 from a half-cent, 8.3e-08 from a half-unit at 6 places.
  Case(
    rate: "0.0025",
    periods: 1200,
    payment: "526.30",
    payment_6: "526.301279",
    first: #("526.30", "500.00", "26.30", "199973.70"),
    middle_balance: "163460.84",
    last: #("536.45", "1.34", "535.11", "0.00"),
    total_interest: "431570.15",
    total_balance: "172427996.76",
  ),
  // 4% a year: exact 679.189479838, 4.5e-03 from a half-cent, 3.4e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0033333333333333",
    periods: 1200,
    payment: "679.19",
    payment_6: "679.189480",
    first: #("679.19", "666.67", "12.52", "199987.48"),
    middle_balance: "176088.46",
    last: #("670.86", "2.23", "668.63", "0.00"),
    total_interest: "615019.67",
    total_balance: "184305900.70",
  ),
  // 5% a year: exact 839.045812621, 8.1e-04 from a half-cent, 1.2e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0041666666666667",
    periods: 1200,
    payment: "839.05",
    payment_6: "839.045813",
    first: #("839.05", "833.33", "5.72", "199994.28"),
    middle_balance: "184744.01",
    last: #("689.95", "2.86", "687.09", "0.00"),
    total_interest: "806710.90",
    total_balance: "193410617.57",
  ),
  // 6% a year: exact 1002.522435050, 2.6e-03 from a half-cent, 4.5e-07 from a half-unit at 6 places.
  Case(
    rate: "0.005",
    periods: 1200,
    payment: "1002.52",
    payment_6: "1002.522435",
    first: #("1002.52", "1000.00", "2.52", "199997.48"),
    middle_balance: "190455.36",
    last: #("1176.55", "5.85", "1170.70", "0.00"),
    total_interest: "1003198.03",
    total_balance: "200439631.64",
  ),
  // 7% a year: exact 1167.753398228, 1.6e-03 from a half-cent, 2.7e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0058333333333333",
    periods: 1200,
    payment: "1167.75",
    payment_6: "1167.753398",
    first: #("1167.75", "1166.67", "1.08", "199998.92"),
    middle_balance: "194096.85",
    last: #("1757.77", "10.19", "1747.58", "0.00"),
    total_interest: "1201890.02",
    total_balance: "205838298.49",
  ),
  // 8% a year: exact 1333.792808968, 2.2e-03 from a half-cent, 4.7e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0066666666666667",
    periods: 1200,
    payment: "1333.79",
    payment_6: "1333.792809",
    first: #("1333.79", "1333.33", "0.46", "199999.54"),
    middle_balance: "196379.22",
    last: #("2630.41", "17.42", "2612.99", "0.00"),
    total_interest: "1401844.62",
    total_balance: "210076702.99",
  ),
  // 9% a year: exact 1500.191461260, 3.5e-03 from a half-cent, 2.4e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0075",
    periods: 1200,
    payment: "1500.19",
    payment_6: "1500.191461",
    first: #("1500.19", "1500.00", "0.19", "199999.81"),
    middle_balance: "197781.08",
    last: #("2868.08", "21.35", "2846.73", "0.00"),
    total_interest: "1601595.89",
    total_balance: "213346136.73",
  ),
  // 10% a year: exact 1666.745538181, 5.4e-04 from a half-cent, 3.2e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0083333333333333",
    periods: 1200,
    payment: "1666.75",
    payment_6: "1666.745538",
    first: #("1666.75", "1666.67", "0.08", "199999.92"),
    middle_balance: "198555.49",
    last: #("-9764.74", "-80.70", "-9684.04", "0.00"),
    total_interest: "1788668.51",
    total_balance: "214440223.94",
  ),
  // 11% a year: exact 1833.365527156, 5.3e-04 from a half-cent, 3.4e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0091666666666667",
    periods: 1200,
    payment: "1833.37",
    payment_6: "1833.365527",
    first: #("1833.37", "1833.33", "0.04", "199999.96"),
    middle_balance: "199048.94",
    last: #("-26070.04", "-236.80", "-25833.24", "0.00"),
    total_interest: "1972140.59",
    total_balance: "214942604.83",
  ),
  // 12% a year: exact 2000.013043204, 2.0e-03 from a half-cent, 3.0e-07 from a half-unit at 6 places.
  Case(
    rate: "0.01",
    periods: 1200,
    payment: "2000.01",
    payment_6: "2000.013043",
    first: #("2000.01", "2000.00", "0.01", "199999.99"),
    middle_balance: "199639.43",
    last: #("60416.23", "598.18", "59818.05", "0.00"),
    total_interest: "2258428.22",
    total_balance: "225642799.37",
  ),
  // 13% a year: exact 2166.671918699, 3.1e-03 from a half-cent, 2.0e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0108333333333333",
    periods: 1200,
    payment: "2166.67",
    payment_6: "2166.671919",
    first: #("2166.67", "2166.67", "0.00", "200000.00"),
    middle_balance: "200000.00",
    last: #("202166.67", "2166.67", "200000.00", "0.00"),
    total_interest: "2600004.00",
    total_balance: "239800000.00",
  ),
  // 14% a year: exact 2333.335437346, 4.4e-04 from a half-cent, 1.5e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0116666666666667",
    periods: 1200,
    payment: "2333.34",
    payment_6: "2333.335437",
    first: #("2333.34", "2333.33", "0.01", "199999.99"),
    middle_balance: "199399.18",
    last: #("-431010.43", "-4970.47", "-426039.96", "0.00"),
    total_interest: "2166664.23",
    total_balance: "185514083.00",
  ),
  // 15% a year: exact 2500.000839270, 4.2e-03 from a half-cent, 2.3e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0125",
    periods: 1200,
    payment: "2500.00",
    payment_6: "2500.000839",
    first: #("2500.00", "2500.00", "0.00", "200000.00"),
    middle_balance: "200000.00",
    last: #("202500.00", "2500.00", "200000.00", "0.00"),
    total_interest: "3000000.00",
    total_balance: "239800000.00",
  ),
  // 16% a year: exact 2666.667000227, 2.0e-03 from a half-cent, 2.7e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0133333333333333",
    periods: 1200,
    payment: "2666.67",
    payment_6: "2666.667000",
    first: #("2666.67", "2666.67", "0.00", "200000.00"),
    middle_balance: "200000.00",
    last: #("202666.67", "2666.67", "200000.00", "0.00"),
    total_interest: "3200004.00",
    total_balance: "239800000.00",
  ),
  // 17% a year: exact 2833.333465493, 1.5e-03 from a half-cent, 7.0e-09 from a half-unit at 6 places.
  Case(
    rate: "0.0141666666666667",
    periods: 1200,
    payment: "2833.33",
    payment_6: "2833.333465",
    first: #("2833.33", "2833.33", "0.00", "200000.00"),
    middle_balance: "200000.00",
    last: #("202833.33", "2833.33", "200000.00", "0.00"),
    total_interest: "3399996.00",
    total_balance: "239800000.00",
  ),
  // 18% a year: exact 3000.000052224, 4.9e-03 from a half-cent, 2.8e-07 from a half-unit at 6 places.
  Case(
    rate: "0.015",
    periods: 1200,
    payment: "3000.00",
    payment_6: "3000.000052",
    first: #("3000.00", "3000.00", "0.00", "200000.00"),
    middle_balance: "200000.00",
    last: #("203000.00", "3000.00", "200000.00", "0.00"),
    total_interest: "3600000.00",
    total_balance: "239800000.00",
  ),
  // 19% a year: exact 3166.666687256, 1.7e-03 from a half-cent, 2.4e-07 from a half-unit at 6 places.
  Case(
    rate: "0.0158333333333333",
    periods: 1200,
    payment: "3166.67",
    payment_6: "3166.666687",
    first: #("3166.67", "3166.67", "0.00", "200000.00"),
    middle_balance: "200000.00",
    last: #("203166.67", "3166.67", "200000.00", "0.00"),
    total_interest: "3800004.00",
    total_balance: "239800000.00",
  ),
  // 20% a year: exact 3333.333341435, 1.7e-03 from a half-cent, 6.5e-08 from a half-unit at 6 places.
  Case(
    rate: "0.0166666666666667",
    periods: 1200,
    payment: "3333.33",
    payment_6: "3333.333341",
    first: #("3333.33", "3333.33", "0.00", "200000.00"),
    middle_balance: "200000.00",
    last: #("203333.33", "3333.33", "200000.00", "0.00"),
    total_interest: "3999996.00",
    total_balance: "239800000.00",
  ),
]

pub fn monthly_payment_matches_python_exactly_test() {
  list.each(cases, fn(case_) {
    let rate = support.parse(case_.rate)
    assert interest.payment(
        principal: support.int(200_000),
        rate_per_period: rate,
        periods: case_.periods,
        digits: 2,
      )
      |> text
      == Ok(case_.payment)
    assert interest.payment(
        principal: support.int(200_000),
        rate_per_period: rate,
        periods: case_.periods,
        digits: 6,
      )
      |> text
      == Ok(case_.payment_6)
  })
}

pub fn monthly_schedule_matches_python_exactly_test() {
  list.each(cases, fn(case_) {
    let assert Ok(rows) =
      interest.schedule(
        principal: support.int(200_000),
        rate_per_period: support.parse(case_.rate),
        periods: case_.periods,
        digits: 2,
      )
    assert summary(rows, case_.periods / 2)
      == Summary(
        count: case_.periods,
        first: case_.first,
        middle_balance: case_.middle_balance,
        last: case_.last,
        total_interest: case_.total_interest,
        total_balance: case_.total_balance,
      )
  })
}

pub fn the_reported_payment_test() {
  // 7% a year over 360 months: the exact payment is 1330.604990, so the
  // cent is 1330.60. Compounding at 7 places gave 1330.61.
  assert interest.payment(
      principal: support.int(200_000),
      rate_per_period: support.parse("0.0058333333333333"),
      periods: 360,
      digits: 2,
    )
    |> text
    == Ok("1330.60")
}

pub fn payment_keeps_its_digits_when_principal_times_rate_is_tiny_test() {
  // 0.001 × 1.2e-27 rounds to 0 at 28 places, but over one period the
  // payment is principal × (1 + rate) = 0.001000...00012.
  assert interest.payment(
      principal: support.parse("0.001"),
      rate_per_period: support.parse("1.2e-27"),
      periods: 1,
      digits: 3,
    )
    |> text
    == Ok("0.001")
}

pub fn payment_at_a_rate_of_minus_one_test() {
  // (1 + rate)^-periods divides by zero, as before.
  let rate = support.int(-1)
  assert interest.payment(
      principal: support.int(1000),
      rate_per_period: rate,
      periods: 12,
      digits: 2,
    )
    == Error(interest.ArithmeticFailed(decimal.DivisionByZero))
  assert interest.schedule(
      principal: support.int(1000),
      rate_per_period: rate,
      periods: 12,
      digits: 2,
    )
    == Error(interest.ArithmeticFailed(decimal.DivisionByZero))
}

// --- effective annual rate against Python -----------------------------------

// (1 + annual / m)^m - 1 for annual rates of 1% to 20%, rounded half-even
// to 10 places, for m = 12, 365 and 1200.
const effective_rates = [
  #(12, [
    "0.0100459609", "0.0201843557", "0.0304159569", "0.0407415429",
    "0.0511618979", "0.0616778119", "0.0722900809", "0.0829995068",
    "0.0938068977", "0.1047130674", "0.1157188362", "0.1268250301",
    "0.1380324816", "0.1493420292", "0.1607545177", "0.1722707983",
    "0.1838917282", "0.1956181715", "0.2074509981", "0.2193910849",
  ]),
  #(365, [
    "0.0100500287", "0.0202007810", "0.0304532636", "0.0408084931",
    "0.0512674965", "0.0618313107", "0.0725009832", "0.0832775718",
    "0.0941621449", "0.1051557816", "0.1162595716", "0.1274746156",
    "0.1388020252", "0.1502429231", "0.1617984431", "0.1734697305",
    "0.1852579417", "0.1971642450", "0.2091898200", "0.2213358583",
  ]),
  #(1200, [
    "0.0100501250", "0.0202011700", "0.0304541475", "0.0408100803",
    "0.0512700013", "0.0618349538", "0.0725059916", "0.0832841790",
    "0.0941705911", "0.1051663135", "0.1162724429", "0.1274900871",
    "0.1388203647", "0.1502644057", "0.1618233515", "0.1734983547",
    "0.1852905797", "0.1972012024", "0.2092314106", "0.2213824039",
  ]),
]

pub fn effective_annual_rate_matches_python_exactly_test() {
  list.each(effective_rates, fn(row) {
    let #(compounds, expected) = row
    let actual =
      list.index_map(expected, fn(_, index) {
        interest.effective_annual_rate(
          nominal_rate: support.new(coefficient: index + 1, exponent: -2),
          compounds_per_year: compounds,
          digits: 10,
        )
        |> result.map(decimal.to_string)
        |> result.unwrap("error")
      })
    assert actual == expected
  })
}

// --- decimal.add and subtract -----------------------------------------------

fn sum(a: String, b: String) -> Result(String, decimal.ArithmeticError) {
  decimal.add(support.parse(a), support.parse(b)) |> text
}

fn difference(a: String, b: String) -> Result(String, decimal.ArithmeticError) {
  decimal.subtract(support.parse(a), support.parse(b)) |> text
}

fn parts(
  value: Result(decimal.Decimal, decimal.ArithmeticError),
) -> Result(#(Int, Int), decimal.ArithmeticError) {
  result.map(value, fn(d) { #(decimal.coefficient(d), decimal.exponent(d)) })
}

pub fn the_reported_sum_test() {
  // 1 at 16 places is past 2^53 - 1, but the sum is not.
  assert sum("1", "-0.8999999999999999") == Ok("0.1000000000000001")
  assert difference("1", "0.8999999999999999") == Ok("0.1000000000000001")
}

pub fn sum_in_all_four_signs_test() {
  assert sum("1", "-0.8999999999999999") == Ok("0.1000000000000001")
  assert sum("-1", "0.8999999999999999") == Ok("-0.1000000000000001")
  // The exact sum 1.1000000000000000 needs 17 digits, so it drops the
  // fewest trailing zeros that bring it within 2^53 - 1: one.
  assert sum("1", "0.1000000000000000") == Ok("1.100000000000000")
  assert sum("-1", "-0.1000000000000000") == Ok("-1.100000000000000")
  assert difference("1", "-0.1000000000000000") == Ok("1.100000000000000")
  assert difference("-0.8999999999999999", "-1") == Ok("0.1000000000000001")
  assert difference("0.8999999999999999", "1") == Ok("-0.1000000000000001")
}

pub fn sum_at_the_coefficient_bound_test() {
  // 1 - 0.0992800745259009 is 0.9007199254740991, 2^53 - 1 at 16 places.
  assert parts(decimal.add(support.int(1), support.parse("-0.0992800745259009")))
    == Ok(#(9_007_199_254_740_991, -16))
  assert parts(decimal.add(support.int(-1), support.parse("0.0992800745259009")))
    == Ok(#(-9_007_199_254_740_991, -16))
  // One more is 2^53 at 16 places, with no zero to drop.
  assert sum("1", "-0.0992800745259008") == Error(decimal.PrecisionExceeded)
  assert sum("-1", "0.0992800745259008") == Error(decimal.PrecisionExceeded)
}

pub fn sum_across_the_whole_exponent_range_test() {
  // 1e15 scaled to one place is past 2^53 - 1, but the sum fits.
  assert parts(decimal.add(
      support.new(coefficient: 1, exponent: 15),
      support.new(coefficient: -9_007_199_254_740_991, exponent: -1),
    ))
    == Ok(#(992_800_745_259_009, -1))
  // 1e15 and 1e-28 are 44 digits apart, and the sum needs all of them.
  assert decimal.add(
      support.new(coefficient: 1, exponent: 15),
      support.new(coefficient: -1, exponent: -28),
    )
    == Error(decimal.PrecisionExceeded)
  assert decimal.add(
      support.new(coefficient: 1, exponent: 15),
      support.new(coefficient: 1, exponent: -28),
    )
    == Error(decimal.PrecisionExceeded)
  // 9e15 + 9e15 is past 2^53 - 1 whatever the exponent.
  assert decimal.add(
      support.new(coefficient: 9, exponent: 15),
      support.new(coefficient: 9, exponent: 15),
    )
    == Error(decimal.PrecisionExceeded)
}

pub fn sum_that_already_fit_keeps_the_smaller_exponent_test() {
  assert parts(decimal.add(support.parse("1.5"), support.parse("0.25")))
    == Ok(#(175, -2))
  assert parts(decimal.add(support.parse("1.50"), support.parse("-1.5")))
    == Ok(#(0, -2))
  assert parts(decimal.add(
      support.new(coefficient: 9_007_199_254_740_990, exponent: -28),
      support.new(coefficient: 1, exponent: -28),
    ))
    == Ok(#(9_007_199_254_740_991, -28))
  assert decimal.add(
      support.new(coefficient: 9_007_199_254_740_991, exponent: -28),
      support.new(coefficient: 1, exponent: -28),
    )
    == Error(decimal.PrecisionExceeded)
}

pub fn sum_with_zero_test() {
  // Adding zero returns the other decimal unchanged, whatever the
  // exponents.
  let small = support.parse("-0.8999999999999999")
  assert decimal.add(support.new(coefficient: 0, exponent: 15), small)
    == Ok(small)
  assert decimal.add(small, support.new(coefficient: 0, exponent: 15))
    == Ok(small)
  assert decimal.subtract(small, decimal.zero()) == Ok(small)
  assert parts(decimal.subtract(decimal.zero(), small))
    == Ok(#(8_999_999_999_999_999, -16))
  assert parts(decimal.add(
      support.new(coefficient: 0, exponent: 15),
      support.new(coefficient: 0, exponent: -28),
    ))
    == Ok(#(0, -28))
}

pub fn money_sum_keeps_the_currency_places_test() {
  // The exact sum 90071992547410.00 needs 2^53 at 2 places. `decimal.add`
  // gives 90071992547410.0, but an amount with fewer places than its
  // currency could not be turned back into minor units.
  let large =
    support.from_minor(units: 9_007_199_254_740_991, currency: money.usd)
  let small = support.from_minor(units: 9, currency: money.usd)
  assert money.add(large, small)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  assert money.subtract(large, money.negate(small))
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  assert money.sum([large, small], in: money.usd)
    == Error(money.ArithmeticFailed(decimal.PrecisionExceeded))
  let assert Ok(total) = money.add(large, money.negate(small))
  assert money.to_string(total) == "USD 90071992547409.82"
  assert money.add(large, support.from_minor(units: 0, currency: money.usd))
    == Ok(large)
}

// --- helpers -----------------------------------------------------------------

type Summary {
  Summary(
    count: Int,
    first: #(String, String, String, String),
    middle_balance: String,
    last: #(String, String, String, String),
    total_interest: String,
    total_balance: String,
  )
}

fn summary(rows: List(interest.Period), middle: Int) -> Summary {
  let assert [first, ..] = rows
  let assert Ok(last) = list.last(rows)
  let assert Ok(middle_row) = rows |> list.drop(middle - 1) |> list.first
  let assert Ok(total_interest) =
    list.try_fold(rows, decimal.zero(), fn(total, row) {
      decimal.add(total, row.interest)
    })
  let assert Ok(total_balance) =
    list.try_fold(rows, decimal.zero(), fn(total, row) {
      decimal.add(total, row.balance)
    })
  Summary(
    count: list.length(rows),
    first: row_text(first),
    middle_balance: cents(middle_row.balance),
    last: row_text(last),
    total_interest: cents(total_interest),
    total_balance: cents(total_balance),
  )
}

fn row_text(row: interest.Period) -> #(String, String, String, String) {
  #(
    cents(row.payment),
    cents(row.interest),
    cents(row.principal_paid),
    cents(row.balance),
  )
}

// Every value here has at most 2 places, but a balance keeps the
// principal's exponent 0 while the principal paid is zero, as in the first
// rows at 13% a year over 1200 months, so the text is taken at 2 places.
fn cents(value: decimal.Decimal) -> String {
  decimal.to_string(support.round(value, digits: 2, rounding: decimal.Down))
}
