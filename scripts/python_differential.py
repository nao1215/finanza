#!/usr/bin/env python3
"""Generate test/differential/python_cases.gleam from Python's decimal.

Each case is an operation, its inputs as text and the text finanza must
return, computed here with Python's decimal module at 200 digits. The
interest values are also computed exactly with fractions.Fraction, and
the script stops if the two disagree, so a value in the fixture is the
exact answer rounded once.

Python's decimal has no bounded range, so the range rules from the
finanza/decimal documentation are applied on top: an exponent between
-28 and 15, and a coefficient (and the integer a positive exponent
stands for) within 2^53 - 1. A result that does not fit drops the
fewest trailing zeros that bring it into range, and an error otherwise.

Usage: python3 scripts/python_differential.py > test/differential/python_cases.gleam
then run `gleam format test/`.

Only the Python standard library is used, and the output depends only on
the seed below.
"""

import decimal
import random
import sys
from decimal import Decimal
from fractions import Fraction

SEED = 20261123
MAX = 2**53 - 1
MIN_EXPONENT = -28
MAX_EXPONENT = 15
MAX_PERIODS = 1200

decimal.getcontext().prec = 200
decimal.getcontext().Emax = 10**9
decimal.getcontext().Emin = -(10**9)
for trap in (decimal.Inexact, decimal.Rounded):
    decimal.getcontext().traps[trap] = False

MODES = {
    "HalfEven": decimal.ROUND_HALF_EVEN,
    "HalfUp": decimal.ROUND_HALF_UP,
    "HalfDown": decimal.ROUND_HALF_DOWN,
    "Up": decimal.ROUND_UP,
    "Down": decimal.ROUND_DOWN,
    "Ceiling": decimal.ROUND_CEILING,
    "Floor": decimal.ROUND_FLOOR,
}


class Failure(Exception):
    def __init__(self, name):
        super().__init__(name)
        self.name = name


def fits(coefficient, exponent):
    if exponent < MIN_EXPONENT or exponent > MAX_EXPONENT:
        return False
    if coefficient == 0:
        return True
    if exponent > 0:
        return abs(coefficient) * 10**exponent <= MAX
    return abs(coefficient) <= MAX


def checked(coefficient, exponent):
    if not fits(coefficient, exponent):
        raise Failure("PrecisionExceeded")
    return (coefficient, exponent)


def fit_dropping_zeros(coefficient, exponent):
    """The fewest trailing zeros dropped that bring the value in range."""
    while not fits(coefficient, exponent):
        if coefficient == 0 or coefficient % 10 != 0:
            raise Failure("PrecisionExceeded")
        coefficient //= 10
        exponent += 1
    return (coefficient, exponent)


def to_string(value):
    coefficient, exponent = value
    digits = str(abs(coefficient))
    sign = "-" if coefficient < 0 else ""
    if exponent >= 0:
        if coefficient == 0:
            return "0"
        return sign + digits + "0" * exponent
    places = -exponent
    padded = "0" * max(0, places + 1 - len(digits)) + digits
    split = len(padded) - places
    return sign + padded[:split] + "." + padded[split:]


def parts(d):
    sign, digits, exponent = d.as_tuple()
    coefficient = int("".join(map(str, digits)) or "0")
    return (-coefficient if sign else coefficient, exponent)


def to_decimal(value):
    coefficient, exponent = value
    return Decimal(coefficient).scaleb(exponent)


def fraction(value):
    coefficient, exponent = value
    return Fraction(coefficient) * Fraction(10) ** exponent


def round_fraction(value, digits):
    """value rounded half-even to `digits` places, as (coefficient, -digits)."""
    scaled = value * Fraction(10) ** digits
    floor = scaled.numerator // scaled.denominator
    remainder = scaled - floor
    if remainder > Fraction(1, 2) or (remainder == Fraction(1, 2) and floor % 2 == 1):
        floor += 1
    return (floor, -digits)


def quantize(d, digits, mode="HalfEven"):
    """d rounded to `digits` places, or None when that needs more than 200 digits."""
    try:
        return parts(d.quantize(Decimal(1).scaleb(-digits), rounding=MODES[mode]))
    except decimal.InvalidOperation:
        return None


# Random decimals --------------------------------------------------------------


def random_coefficient(rng):
    kind = rng.randrange(6)
    if kind == 0:
        return rng.randint(-MAX, MAX)
    if kind == 1:
        return rng.randint(-999, 999)
    if kind == 2:
        return rng.randint(-999_999, 999_999) * 10 ** rng.randint(0, 9)
    if kind == 3:
        return rng.choice([0, 1, -1, 5, -5, 15, 25, 50, MAX, -MAX, 2**52, 10**15])
    if kind == 4:
        return rng.randint(-(10**8), 10**8)
    return rng.choice([1, -1]) * (MAX - rng.randint(0, 1000))


def random_decimal(rng, low=MIN_EXPONENT, high=MAX_EXPONENT):
    while True:
        coefficient = random_coefficient(rng)
        exponent = rng.randint(low, high)
        if fits(coefficient, exponent):
            # to_string writes a positive exponent as zeros, which parse
            # reads back with the exponent 0.
            if exponent > 0:
                return (coefficient * 10**exponent, 0)
            return (coefficient, exponent)


def random_mode(rng):
    return rng.choice(list(MODES))


# Decimal operations -----------------------------------------------------------


def run(function):
    try:
        return to_string(function())
    except Failure as failure:
        return "!" + failure.name


def parse_model(text):
    if len(text.encode()) > 1000:
        raise Failure("InputTooLong")
    coefficient, exponent = parts(Decimal(text))
    if coefficient == 0:
        return (0, min(max(exponent, MIN_EXPONENT), MAX_EXPONENT))
    try:
        return fit_dropping_zeros(coefficient, exponent)
    except Failure:
        raise Failure("ParsedValueTooLarge")


def add_model(a, b):
    exponent = min(a[1], b[1])
    total = (to_decimal(a) + to_decimal(b)).scaleb(-exponent)
    coefficient = int(total)
    return fit_dropping_zeros(coefficient, exponent)


def multiply_model(a, b):
    exponent = a[1] + b[1]
    coefficient = a[0] * b[0]
    if coefficient == 0:
        return (0, min(max(exponent, MIN_EXPONENT), MAX_EXPONENT))
    while exponent < MIN_EXPONENT and coefficient % 10 == 0:
        coefficient //= 10
        exponent += 1
    return fit_dropping_zeros(coefficient, exponent)


def divide_model(a, b, digits, mode):
    if b[0] == 0:
        raise Failure("DivisionByZero")
    if -digits < MIN_EXPONENT or -digits > MAX_EXPONENT:
        raise Failure("PrecisionExceeded")
    return checked_quantized(quantize(to_decimal(a) / to_decimal(b), digits, mode))


def checked_quantized(value):
    if value is None:
        raise Failure("PrecisionExceeded")
    return checked(*value)


def round_model(a, digits, mode):
    if -digits < MIN_EXPONENT or -digits > MAX_EXPONENT:
        raise Failure("PrecisionExceeded")
    return checked_quantized(quantize(to_decimal(a), digits, mode))


def random_parse_text(rng):
    kind = rng.randrange(7)
    coefficient, exponent = random_decimal(rng)
    text = to_string((coefficient, exponent))
    if kind == 0:
        return text
    if kind == 1:
        # Trailing zeros past 28 places.
        if "." not in text:
            text += "."
        return text + "0" * rng.randint(1, 40)
    if kind == 2:
        return f"{coefficient}e{exponent + rng.randint(-20, 20)}"
    if kind == 3:
        return f"{coefficient}{'0' * rng.randint(0, 5)}E{rng.randint(-40, 20)}"
    if kind == 4:
        return "0." + "0" * rng.randint(0, 40) + str(rng.randint(1, 9)) + "0" * rng.randint(0, 20)
    if kind == 5:
        return rng.choice(["+", "-", ""]) + "0" * rng.randint(1, 5) + "." + "0" * rng.randint(0, 40)
    return str(rng.randint(1, 9)) + "0" * rng.randint(10, 20) + "." + "0" * rng.randint(0, 10)


def decimal_cases(rng, count):
    cases = []
    fixed_parse = [
        "0.10000000000000000000000000000",
        "0.1000000000000000000000000000000000000000",
        "9007199254740991.0",
        "9007199254740991.000",
        "9007199254740992.0",
        "1.0e-28",
        "10e-29",
        "1e-29",
        "0e-40",
        "0e16",
        "-0.000",
        "100e14",
        "1e15",
        "1e16",
        "0." + "0" * 50,
        "1" + "0" * 900,
        "1." + "0" * 990,
        "1." + "0" * 1000,
    ]
    for text in fixed_parse + [random_parse_text(rng) for _ in range(count)]:
        cases.append(("parse", text, "", 0, "HalfEven", run(lambda: parse_model(text))))
    for _ in range(count):
        a = random_decimal(rng)
        cases.append(("to_string", repr_input(a), "", 0, "HalfEven", to_string(a)))
    zero_cases = [((0, -2), (5, 0)), ((0, 0), (123, -2)), ((5, 0), (0, -2)), ((0, -3), (0, -1)), ((0, -28), (MAX, 0))]
    pairs = zero_cases + [random_pair(rng) for _ in range(count)]
    for a, b in pairs:
        cases.append(("add", repr_input(a), repr_input(b), 0, "HalfEven", run(lambda: add_model(a, b))))
        cases.append(("subtract", repr_input(a), repr_input(b), 0, "HalfEven", run(lambda: add_model(a, (-b[0], b[1])))))
    for _ in range(count):
        a, b = random_pair(rng)
        cases.append(("multiply", repr_input(a), repr_input(b), 0, "HalfEven", run(lambda: multiply_model(a, b))))
    for _ in range(count):
        a, b = random_decimal(rng), random_decimal(rng)
        digits = rng.randint(-15, 28) if rng.random() < 0.9 else rng.choice([-16, 29])
        mode = random_mode(rng)
        cases.append(("divide", repr_input(a), repr_input(b), digits, mode, run(lambda: divide_model(a, b, digits, mode))))
    for _ in range(count):
        a = random_decimal(rng)
        digits = rng.randint(-15, 28) if rng.random() < 0.9 else rng.choice([-16, 29])
        mode = random_mode(rng)
        cases.append(("round", repr_input(a), "", digits, mode, run(lambda: round_model(a, digits, mode))))
    for _ in range(count):
        a = random_decimal(rng)
        b = random_decimal(rng) if rng.random() < 0.7 else (a[0] * 10, a[1] - 1) if fits(a[0] * 10, a[1] - 1) else a
        order = to_decimal(a).compare(to_decimal(b))
        expected = {-1: "Lt", 0: "Eq", 1: "Gt"}[int(order)]
        cases.append(("compare", repr_input(a), repr_input(b), 0, "HalfEven", expected))
    return cases


def random_pair(rng):
    a = random_decimal(rng)
    if rng.random() < 0.5:
        return (a, random_decimal(rng))
    low = max(MIN_EXPONENT, a[1] - 3)
    return (a, random_decimal(rng, low, min(MAX_EXPONENT, a[1] + 3)))


def repr_input(value):
    return to_string(value)


# Interest ---------------------------------------------------------------------


def check_digits(digits):
    if digits < 0 or digits > 28:
        raise Failure("DigitsOutOfRange")


def check_rate(rate):
    if fraction(rate) < -1:
        raise Failure("RateBelowMinusOne")


def check_principal(principal):
    if principal[0] < 0:
        raise Failure("NegativePrincipal")


def check_periods(periods, minimum):
    if periods < minimum or periods > MAX_PERIODS:
        raise Failure("PeriodsOutOfRange")


def both(exact, approximate):
    """Stops when Python's decimal and the exact fraction disagree."""
    if approximate is None and not fits(*exact):
        raise Failure("ArithmeticFailed(PrecisionExceeded)")
    if exact != approximate:
        sys.exit(f"decimal and Fraction disagree: {exact} != {approximate}")
    return exact


def checked_interest(value):
    if not fits(*value):
        raise Failure("ArithmeticFailed(PrecisionExceeded)")
    return value


def simple_model(principal, rate, periods, digits):
    check_principal(principal)
    check_rate(rate)
    check_periods(periods, 0)
    check_digits(digits)
    exact = round_fraction(fraction(principal) * fraction(rate) * periods, digits)
    approximate = quantize(to_decimal(principal) * to_decimal(rate) * periods, digits)
    return checked_interest(both(exact, approximate))


def future_value_model(present, rate, periods, digits):
    check_rate(rate)
    check_periods(periods, 0)
    check_digits(digits)
    exact = round_fraction(fraction(present) * (1 + fraction(rate)) ** periods, digits)
    approximate = quantize(to_decimal(present) * (1 + to_decimal(rate)) ** periods, digits)
    return checked_interest(both(exact, approximate))


def present_value_model(future, rate, periods, digits):
    check_rate(rate)
    check_periods(periods, 0)
    check_digits(digits)
    growth = (1 + fraction(rate)) ** periods
    if growth == 0:
        raise Failure("ArithmeticFailed(DivisionByZero)")
    exact = round_fraction(fraction(future) / growth, digits)
    approximate = quantize(to_decimal(future) / (1 + to_decimal(rate)) ** periods, digits)
    return checked_interest(both(exact, approximate))


def payment_fraction(principal, rate, periods):
    p, r = fraction(principal), fraction(rate)
    if r == 0:
        return p / periods
    if r == -1:
        raise Failure("ArithmeticFailed(DivisionByZero)")
    growth = (1 + r) ** periods
    return p * r * growth / (growth - 1)


def payment_model(principal, rate, periods, digits):
    check_principal(principal)
    check_rate(rate)
    check_periods(periods, 1)
    check_digits(digits)
    exact = round_fraction(payment_fraction(principal, rate, periods), digits)
    p, r = to_decimal(principal), to_decimal(rate)
    if r == 0:
        approximate = quantize(p / periods, digits)
    else:
        approximate = quantize(p * r / (1 - (1 + r) ** -periods), digits)
    return checked_interest(both(exact, approximate))


def effective_annual_rate_model(nominal, compounds, digits):
    check_rate(nominal)
    if compounds <= 0 or compounds > MAX_PERIODS:
        raise Failure("CompoundsOutOfRange")
    check_digits(digits)
    exact = round_fraction((1 + fraction(nominal) / compounds) ** compounds - 1, digits)
    approximate = quantize((1 + to_decimal(nominal) / compounds) ** compounds - 1, digits)
    return checked_interest(both(exact, approximate))


def add_kept(a, b):
    """decimal.add, failing when the sum had to drop a place."""
    total = add_model(a, b)
    if total[1] > min(a[1], b[1]):
        raise Failure("PrecisionExceeded")
    return total


def schedule_model(principal, rate, periods, digits):
    check_principal(principal)
    check_rate(rate)
    check_digits(digits)
    if periods == 0:
        return []
    amount = payment_model(principal, rate, periods, digits)
    rows = []
    balance = principal
    for index in range(1, periods + 1):
        interest = checked(*round_fraction(fraction(balance) * fraction(rate), digits))
        if index == periods:
            paid = add_kept(interest, balance)
            principal_paid = add_model(paid, (-interest[0], interest[1]))
            rows.append((paid, interest, principal_paid, (0, -digits)))
        else:
            principal_paid = add_model(amount, (-interest[0], interest[1]))
            balance = add_model(balance, (-principal_paid[0], principal_paid[1]))
            rows.append((amount, interest, principal_paid, balance))
    return rows


def interest_failure(failure):
    if failure.name in ("PrecisionExceeded", "DivisionByZero"):
        return f"!ArithmeticFailed({failure.name})"
    return "!" + failure.name


def run_interest(function):
    try:
        return to_string(function())
    except Failure as failure:
        return interest_failure(failure)


def run_schedule(function):
    try:
        rows = function()
    except Failure as failure:
        return interest_failure(failure)
    return ";".join(",".join(to_string(value) for value in row) for row in rows)


def random_rate(rng):
    kind = rng.randrange(6)
    if kind == 0:
        return (rng.randint(1, 10**8), -rng.randint(8, 12))
    if kind == 1:
        return (rng.randint(1, 999), -rng.randint(3, 5))
    if kind == 2:
        return (rng.randint(1, MAX // 10), -16)
    if kind == 3:
        return (-rng.randint(1, 9999), -rng.randint(4, 8))
    if kind == 4:
        return (rng.randint(1, 10**15), -rng.randint(15, 28))
    return (rng.randint(-99, 500), -2)


def monthly_rate(rng):
    annual = Decimal(rng.randint(1, 2000)) / 10000 / 12
    return parts(annual.quantize(Decimal(1).scaleb(-rng.choice([10, 14, 16]))))


def random_money(rng, low=0):
    kind = rng.randrange(8)
    if kind < 3:
        return (rng.randint(low, 10**9), -2)
    if kind < 5:
        return (rng.randint(low, 10**6), 0)
    if kind < 7:
        return (rng.randint(low, 10**12), -rng.randint(0, 4))
    return (rng.randint(low, MAX), -rng.randint(0, 10))


def random_digits(rng):
    return rng.choice([0, 2, 2, 2, 4, 6, rng.randint(0, 12)])


def any_rate(rng):
    if rng.random() < 0.5:
        return monthly_rate(rng)
    rate = random_rate(rng)
    if not fits(*rate) or fraction(rate) < -1:
        return (5, -3)
    return rate


def interest_cases(rng, count):
    cases = []
    for _ in range(count):
        p, r = random_money(rng), any_rate(rng)
        n, digits = rng.choice([0, 1, 12, 360, 1200, rng.randint(0, 1200)]), random_digits(rng)
        cases.append(("simple", to_string(p), to_string(r), n, digits, run_interest(lambda: simple_model(p, r, n, digits))))
    extreme_simple = [((MAX, 0), (1, -28), 1200, 28), ((MAX, -2), (MAX, -16), 1200, 2), ((MAX, 0), (3, -1), 1200, 0)]
    for p, r, n, digits in extreme_simple:
        cases.append(("simple", to_string(p), to_string(r), n, digits, run_interest(lambda: simple_model(p, r, n, digits))))
    for _ in range(count):
        p = random_money(rng, low=-(10**9))
        r = any_rate(rng)
        n = rng.choice([1, 12, 120, 360, rng.randint(0, 400)])
        digits = random_digits(rng)
        cases.append(("future_value", to_string(p), to_string(r), n, digits, run_interest(lambda: future_value_model(p, r, n, digits))))
    for _ in range(count):
        f = random_money(rng, low=-(10**9))
        r = any_rate(rng)
        n = rng.choice([1, 12, 120, 360, rng.randint(0, 400)])
        digits = random_digits(rng)
        cases.append(("present_value", to_string(f), to_string(r), n, digits, run_interest(lambda: present_value_model(f, r, n, digits))))
    for _ in range(count):
        p, r = random_money(rng), any_rate(rng)
        n = rng.choice([1, 2, 12, 360, rng.randint(1, 400)])
        digits = random_digits(rng)
        cases.append(("payment", to_string(p), to_string(r), n, digits, run_interest(lambda: payment_model(p, r, n, digits))))
    for _ in range(count // 2):
        nominal = (rng.randint(-999, 3000), -rng.randint(2, 6))
        if fraction(nominal) < -1:
            nominal = (5, -2)
        m = rng.choice([1, 2, 4, 12, 52, 365, rng.randint(1, 1200)])
        digits = rng.randint(0, 14)
        cases.append(("effective_annual_rate", to_string(nominal), "", m, digits, run_interest(lambda: effective_annual_rate_model(nominal, m, digits))))
    for _ in range(count // 5):
        p, r = random_money(rng), any_rate(rng)
        if r[0] < 0:
            r = (-r[0], r[1])
        n = rng.randint(0, 60)
        digits = rng.randint(0, 6)
        cases.append(("schedule", to_string(p), to_string(r), n, digits, run_schedule(lambda: schedule_model(p, r, n, digits))))
    fixed_schedule = [((200000, 0), (5, -2), 1200, 2)]
    for p, r, n, digits in fixed_schedule:
        rows = run_schedule(lambda: schedule_model(p, r, n, digits))
        # The first three rows, where the principal paid is zero.
        cases.append(("schedule_head", to_string(p), to_string(r), n, digits, ";".join(rows.split(";")[:3])))
    return cases


def gleam_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    rng = random.Random(SEED)
    out = sys.stdout
    out.write("//// Generated by scripts/python_differential.py from Python's decimal\n")
    out.write("//// at 200 digits (and, for interest, exact fractions). Do not edit.\n\n")
    out.write("pub type DecimalCase {\n  DecimalCase(operation: String, a: String, b: String, digits: Int, mode: String, expected: String)\n}\n\n")
    out.write("pub type InterestCase {\n  InterestCase(operation: String, a: String, b: String, periods: Int, digits: Int, expected: String)\n}\n\n")
    out.write("pub fn decimal_cases() -> List(DecimalCase) {\n  [\n")
    for operation, a, b, digits, mode, expected in decimal_cases(rng, 250):
        out.write(f"    DecimalCase({gleam_string(operation)}, {gleam_string(a)}, {gleam_string(b)}, {digits}, {gleam_string(mode)}, {gleam_string(expected)}),\n")
    out.write("  ]\n}\n\n")
    out.write("pub fn interest_cases() -> List(InterestCase) {\n  [\n")
    for operation, a, b, periods, digits, expected in interest_cases(rng, 200):
        out.write(f"    InterestCase({gleam_string(operation)}, {gleam_string(a)}, {gleam_string(b)}, {periods}, {digits}, {gleam_string(expected)}),\n")
    out.write("  ]\n}\n")


if __name__ == "__main__":
    main()
