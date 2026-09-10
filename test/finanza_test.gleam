import finanza
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn version_matches_gleam_toml_test() -> Nil {
  // Must equal `version` in gleam.toml; the release checklist updates both.
  finanza.version()
  |> should.equal("0.10.0")
}
