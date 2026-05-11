//// Property-based tests for `finanza/currency` and
//// `finanza/currency/catalog` driven by `metamon`.

import gleam/int
import gleam/list
import metamon
import metamon/generator
import metamon/generator/range

import finanza/currency
import finanza/currency/catalog
import finanza/decimal/rounding

// --- Generators ----------------------------------------------------------

fn catalog_currency_gen() -> generator.Generator(currency.Currency) {
  generator.element_of(catalog.all())
}

fn money_gen() -> generator.Generator(currency.Money) {
  generator.tuple2(
    generator.int(range.constant(-1_000_000, 1_000_000)),
    catalog_currency_gen(),
  )
  |> generator.map(fn(pair) { currency.from_minor(pair.0, pair.1) })
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
      let m = currency.from_minor(pair.0, pair.1)
      case currency.to_minor(m, rounding.HalfEven) {
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
    let twice = currency.negate(currency.negate(m))
    case
      currency.to_minor(m, rounding.HalfEven),
      currency.to_minor(twice, rounding.HalfEven)
    {
      Ok(a), Ok(b) -> a == b
      _, _ -> False
    }
  })
}

pub fn money_add_negate_is_zero_test() {
  // m + negate(m) yields a zero Money (currencies match by construction).
  metamon.forall(money_gen(), fn(m) {
    let neg = currency.negate(m)
    case currency.add(m, neg) {
      Ok(sum) ->
        case currency.to_minor(sum, rounding.HalfEven) {
          Ok(units) -> units == 0
          Error(_) -> False
        }
      Error(_) -> False
    }
  })
}

pub fn money_add_commutative_test() {
  // a + b == b + a for two Money values in the same currency. We pair a
  // single currency with two amounts to enforce the same-currency
  // precondition.
  metamon.forall(
    generator.tuple3(
      generator.int(range.constant(-1_000_000, 1_000_000)),
      generator.int(range.constant(-1_000_000, 1_000_000)),
      catalog_currency_gen(),
    ),
    fn(triple) {
      let a = currency.from_minor(triple.0, triple.2)
      let b = currency.from_minor(triple.1, triple.2)
      case currency.add(a, b), currency.add(b, a) {
        Ok(sum1), Ok(sum2) -> currency.equal(sum1, sum2)
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
      let m = currency.from_minor(triple.0, triple.1)
      case currency.allocate(m, triple.2) {
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
      let m = currency.from_minor(triple.0, triple.1)
      case currency.allocate(m, triple.2) {
        Ok(parts) -> list.length(parts) == list.length(triple.2)
        Error(_) -> False
      }
    },
  )
}

// --- Catalogue invariants ------------------------------------------------

pub fn catalog_codes_are_distinct_test() {
  // Codes in the catalogue are unique. Run once (this is a singleton
  // property but expressing it through metamon keeps the test file
  // self-contained).
  metamon.forall(generator.return(catalog.all()), fn(currencies) {
    let codes = list.map(currencies, currency.code)
    list.length(codes) == list.length(list.unique(codes))
  })
}
