//// Property-based tests for `finanza/money` driven by `metamon`.

import gleam/int
import gleam/list
import metamon
import metamon/generator
import metamon/generator/range

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
    generator.int(range.constant(-1_000_000, 1_000_000)),
    catalog_currency_gen(),
  )
  |> generator.map(fn(pair) { support.from_minor(pair.0, pair.1) })
}

fn ratios_gen() -> generator.Generator(List(Int)) {
  generator.list_of(generator.int(range.constant(1, 10)), range.constant(1, 7))
}

// --- Round-trips ---------------------------------------------------------

pub fn from_minor_to_minor_round_trip_test() {
  // from_minor / to_minor preserve the integer count exactly when no
  // rounding is required.
  metamon.forall(
    generator.tuple2(
      generator.int(range.constant(-1_000_000, 1_000_000)),
      catalog_currency_gen(),
    ),
    fn(pair) {
      let m = support.from_minor(pair.0, pair.1)
      case money.to_minor(m, decimal.HalfEven) {
        Ok(back) -> back == pair.0
        Error(_) -> False
      }
    },
  )
}

// --- Money arithmetic algebraic laws -------------------------------------

pub fn money_negate_involution_test() {
  // negate(negate(m)) is numerically equal to m (compare via to_minor).
  metamon.forall(money_gen(), fn(m) {
    let twice = money.negate(money.negate(m))
    case
      money.to_minor(m, decimal.HalfEven),
      money.to_minor(twice, decimal.HalfEven)
    {
      Ok(a), Ok(b) -> a == b
      _, _ -> False
    }
  })
}

pub fn money_add_negate_is_zero_test() {
  // m + negate(m) yields a zero Money (currencies match by construction).
  metamon.forall(money_gen(), fn(m) {
    let neg = money.negate(m)
    case money.add(m, neg) {
      Ok(sum) ->
        case money.to_minor(sum, decimal.HalfEven) {
          Ok(units) -> units == 0
          Error(_) -> False
        }
      Error(_) -> False
    }
  })
}

pub fn money_add_commutative_test() {
  // a + b == b + a for two Money values in the same money. We pair a
  // single currency with two amounts to enforce the same-currency
  // precondition.
  metamon.forall(
    generator.tuple3(
      generator.int(range.constant(-1_000_000, 1_000_000)),
      generator.int(range.constant(-1_000_000, 1_000_000)),
      catalog_currency_gen(),
    ),
    fn(triple) {
      let a = support.from_minor(triple.0, triple.2)
      let b = support.from_minor(triple.1, triple.2)
      case money.add(a, b), money.add(b, a) {
        Ok(sum1), Ok(sum2) -> support.money_equal(sum1, sum2)
        Error(_), Error(_) -> True
        _, _ -> False
      }
    },
  )
}

// --- Allocation ----------------------------------------------------------

pub fn allocate_preserves_total_test() {
  // Sum of allocated parts equals the original amount in minor units.
  metamon.forall(
    generator.tuple3(
      generator.int(range.constant(1, 10_000_000)),
      catalog_currency_gen(),
      ratios_gen(),
    ),
    fn(triple) {
      let m = support.from_minor(triple.0, triple.1)
      case money.allocate(m, triple.2) {
        Ok(parts) -> {
          let total =
            parts
            |> list.map(fn(part) {
              case money.to_minor(part, decimal.HalfEven) {
                Ok(u) -> u
                Error(_) -> 0
              }
            })
            |> list.fold(0, int.add)
          total == triple.0
        }
        Error(_) -> False
      }
    },
  )
}

pub fn allocate_part_count_matches_ratios_test() {
  // allocate produces exactly one Money per ratio entry.
  metamon.forall(
    generator.tuple3(
      generator.int(range.constant(1, 1_000_000)),
      catalog_currency_gen(),
      ratios_gen(),
    ),
    fn(triple) {
      let m = support.from_minor(triple.0, triple.1)
      case money.allocate(m, triple.2) {
        Ok(parts) -> list.length(parts) == list.length(triple.2)
        Error(_) -> False
      }
    },
  )
}
