//// Property-based tests for `finanza/money` driven by `metamon`.

import gleam/int
import gleam/list
import gleam/result
import metamon
import metamon/generator

import finanza/decimal
import finanza/money
import support

// --- Generators ----------------------------------------------------------

fn catalog_currency_gen() -> generator.Generator(money.Currency) {
  generator.element_of([
    money.usd, money.eur, money.jpy, money.gbp, money.chf, money.cad, money.aud,
    money.cny, money.hkd, money.sgd, money.krw, money.inr, money.brl, money.mxn,
    money.zar,
  ])
}

fn money_gen() -> generator.Generator(money.Money) {
  generator.tuple2(
    generator.int(generator.range(from: -1_000_000, to: 1_000_000)),
    catalog_currency_gen(),
  )
  |> generator.map(fn(pair) { support.from_minor(pair.0, pair.1) })
}

fn ratios_gen() -> generator.Generator(List(Int)) {
  generator.list_of(
    generator.int(generator.range(from: 1, to: 10)),
    length: generator.range(from: 1, to: 7),
  )
}

// --- Round-trips ---------------------------------------------------------

pub fn from_minor_to_minor_round_trip_test() {
  // from_minor / to_minor preserve the integer count exactly when no
  // rounding is required.
  metamon.forall(
    generator.tuple2(
      generator.int(generator.range(from: -1_000_000, to: 1_000_000)),
      catalog_currency_gen(),
    ),
    fn(pair) {
      let m = support.from_minor(pair.0, pair.1)
      assert money.to_minor(m, decimal.HalfEven) == Ok(pair.0)
    },
  )
}

// --- Money arithmetic algebraic laws -------------------------------------

pub fn money_negate_involution_test() {
  // negate(negate(m)) is numerically equal to m (compare via to_minor).
  metamon.forall(money_gen(), fn(m) {
    let twice = money.negate(money.negate(m))
    let assert Ok(a) = money.to_minor(m, decimal.HalfEven)
    assert money.to_minor(twice, decimal.HalfEven) == Ok(a)
  })
}

pub fn money_add_negate_is_zero_test() {
  // m + negate(m) yields a zero Money (currencies match by construction).
  metamon.forall(money_gen(), fn(m) {
    let neg = money.negate(m)
    let assert Ok(sum) = money.add(m, neg)
    assert money.to_minor(sum, decimal.HalfEven) == Ok(0)
  })
}

pub fn money_add_commutative_test() {
  // a + b == b + a for two Money values in the same money. We pair a
  // single currency with two amounts to enforce the same-currency
  // precondition.
  metamon.forall(
    generator.tuple3(
      generator.int(generator.range(from: -1_000_000, to: 1_000_000)),
      generator.int(generator.range(from: -1_000_000, to: 1_000_000)),
      catalog_currency_gen(),
    ),
    fn(triple) {
      let a = support.from_minor(triple.0, triple.2)
      let b = support.from_minor(triple.1, triple.2)
      let ab = money.add(a, b)
      let ba = money.add(b, a)
      assert result.is_ok(ab) == result.is_ok(ba)
      case ab, ba {
        Ok(sum1), Ok(sum2) -> {
          assert support.money_equal(sum1, sum2)
        }
        _, _ -> Nil
      }
    },
  )
}

// --- Allocation ----------------------------------------------------------

pub fn allocate_preserves_total_test() {
  // Sum of allocated parts equals the original amount in minor units.
  metamon.forall(
    generator.tuple3(
      generator.int(generator.range(from: 1, to: 10_000_000)),
      catalog_currency_gen(),
      ratios_gen(),
    ),
    fn(triple) {
      let m = support.from_minor(triple.0, triple.1)
      let assert Ok(parts) = money.allocate(m, triple.2)
      let total =
        parts
        |> list.map(fn(part) {
          case money.to_minor(part, decimal.HalfEven) {
            Ok(u) -> u
            Error(_) -> 0
          }
        })
        |> list.fold(0, int.add)
      assert total == triple.0
    },
  )
}

pub fn allocate_part_count_matches_ratios_test() {
  // allocate produces exactly one Money per ratio entry.
  metamon.forall(
    generator.tuple3(
      generator.int(generator.range(from: 1, to: 1_000_000)),
      catalog_currency_gen(),
      ratios_gen(),
    ),
    fn(triple) {
      let m = support.from_minor(triple.0, triple.1)
      let assert Ok(parts) = money.allocate(m, triple.2)
      assert list.length(parts) == list.length(triple.2)
    },
  )
}
