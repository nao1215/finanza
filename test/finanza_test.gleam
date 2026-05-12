import finanza
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn version_is_set_test() -> Nil {
  finanza.version()
  |> should.equal("0.2.0")
}
