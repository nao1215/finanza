//// Property-based tests for `finanza/decimal` driven by `metamon`.
////
//// metamon performs random generation with shrinking, so any
//// counter-example is reported in minimal form. These tests are the
//// primary algebraic-law checks for the Decimal type.

import gleam/order
import metamon
import metamon/generator
import metamon/generator/range
import metamon/relation
import metamon/transform

import finanza/decimal
import finanza/decimal/rounding

// Decimal coefficients are bounded well within 2^53 so that arithmetic
// across the property runs does not hit `PrecisionExceeded`.
fn decimal_gen() -> generator.Generator(decimal.Decimal) {
  generator.tuple2(
    generator.int(range.constant(-10_000, 10_000)),
    generator.int(range.constant(-4, 2)),
  )
  |> generator.map(fn(pair) {
    decimal.new(coefficient: pair.0, exponent: pair.1)
  })
}

pub fn decimal_absolute_idempotent_test() {
  let mr =
    metamon.idempotency_of(
      name: "decimal_absolute_idempotent",
      of: decimal.absolute,
    )
  metamon.forall_morph(decimal_gen(), mr, decimal.absolute)
}

pub fn decimal_negate_involution_test() {
  // negate ∘ negate == identity (not idempotent — that would shrink to a
  // constant value).
  metamon.forall(decimal_gen(), fn(d) {
    decimal.equal(decimal.negate(decimal.negate(d)), d)
  })
}

pub fn decimal_round_idempotent_test() {
  let round_two = fn(d) { decimal.round(d, 2, rounding.HalfEven) }
  let mr =
    metamon.idempotency_of(name: "decimal_round_2dp_idempotent", of: round_two)
  metamon.forall_morph(decimal_gen(), mr, round_two)
}

pub fn decimal_truncate_idempotent_test() {
  let trunc_two = fn(d) { decimal.truncate(d, 2) }
  let mr =
    metamon.idempotency_of(
      name: "decimal_truncate_2dp_idempotent",
      of: trunc_two,
    )
  metamon.forall_morph(decimal_gen(), mr, trunc_two)
}

pub fn decimal_string_round_trip_test() {
  // to_string ∘ from_string preserves the *value* but not necessarily
  // the structural representation: trailing zeros are absorbed into
  // the coefficient on the way back (e.g. `Decimal(0, 1)` renders as
  // `"0"` which parses to `Decimal(0, 0)`). Compare with the numerical
  // `decimal.equal` so the property covers what users actually care
  // about.
  metamon.forall_round_trip_under(
    gen: decimal_gen(),
    name: "decimal_string_round_trip",
    encode: decimal.to_string,
    decode: decimal.from_string,
    equality: relation.new("decimal_equal", decimal.equal),
  )
}

pub fn decimal_add_commutative_test() {
  let mr = metamon.commutativity_of(name: "decimal_add_commutative")
  metamon.forall_morph(
    generator.tuple2(decimal_gen(), decimal_gen()),
    mr,
    fn(pair) { decimal.add(pair.0, pair.1) },
  )
}

pub fn decimal_multiply_commutative_test() {
  let mr = metamon.commutativity_of(name: "decimal_multiply_commutative")
  metamon.forall_morph(
    generator.tuple2(decimal_gen(), decimal_gen()),
    mr,
    fn(pair) { decimal.multiply(pair.0, pair.1) },
  )
}

pub fn decimal_add_zero_identity_test() {
  // d + 0 numerically equals d. Compare via decimal.equal so trailing
  // zeros in either representation are tolerated.
  let zero_added = fn(d) {
    case decimal.add(d, decimal.zero()) {
      Ok(sum) -> sum
      Error(_) -> d
    }
  }
  let mr =
    metamon.mr(
      name: "decimal_add_zero_identity",
      transform: transform.new("apply add(d, zero)", zero_added),
      relation: relation.new("equal", decimal.equal),
    )
  metamon.forall_morph(decimal_gen(), mr, fn(d) { d })
}

pub fn decimal_compare_antisymmetric_test() {
  // compare(a, b) == reverse(compare(b, a))
  metamon.forall(generator.tuple2(decimal_gen(), decimal_gen()), fn(pair) {
    let a = pair.0
    let b = pair.1
    case decimal.compare(a, b), decimal.compare(b, a) {
      order.Lt, order.Gt -> True
      order.Gt, order.Lt -> True
      order.Eq, order.Eq -> True
      _, _ -> False
    }
  })
}

pub fn decimal_subtract_inverse_test() {
  // (a + b) - b == a, modulo arithmetic errors that we let pass through.
  metamon.forall(generator.tuple2(decimal_gen(), decimal_gen()), fn(pair) {
    let a = pair.0
    let b = pair.1
    case decimal.add(a, b) {
      Error(_) -> True
      Ok(sum) ->
        case decimal.subtract(sum, b) {
          Ok(again) -> decimal.equal(again, a)
          Error(_) -> True
        }
    }
  })
}

pub fn decimal_absolute_non_negative_test() {
  metamon.forall(decimal_gen(), fn(d) {
    !decimal.is_negative(decimal.absolute(d))
  })
}
