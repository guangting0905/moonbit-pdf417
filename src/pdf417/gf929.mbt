// Arithmetic in GF(929).
//
// PDF417 error correction lives in the prime field GF(929), not in the
// characteristic-2 field most Reed-Solomon codecs use. Elements are the
// integers 0..928, addition and multiplication are done modulo 929, and the
// multiplicative group has order 928 = 2^5 * 29.

///|
/// The field modulus.
pub let field_modulus : Int = 929

///|
/// Order of the multiplicative group, `929 - 1`.
pub let field_order : Int = 928

///|
/// The primitive element PDF417 uses. The generator polynomial is built from
/// its powers: `g(x) = (x - 3^1)(x - 3^2)...(x - 3^k)`.
pub let field_generator : Int = 3

///|
/// Reduces an arbitrary integer into 0..928, handling negative inputs
/// correctly (MoonBit's `%` truncates toward zero).
pub fn gf_reduce(v : Int) -> Int {
  let r = v % field_modulus
  if r < 0 {
    r + field_modulus
  } else {
    r
  }
}

///|
/// Addition in GF(929).
pub fn gf_add(a : Int, b : Int) -> Int {
  gf_reduce(a + b)
}

///|
/// Subtraction in GF(929).
pub fn gf_sub(a : Int, b : Int) -> Int {
  gf_reduce(a - b)
}

///|
/// Negation, with `-0 = 0`.
pub fn gf_neg(a : Int) -> Int {
  if a == 0 {
    0
  } else {
    field_modulus - gf_reduce(a)
  }
}

///|
/// Multiplication in GF(929).
pub fn gf_mul(a : Int, b : Int) -> Int {
  gf_reduce(a * b)
}

///|
/// Exponentiation by squaring. `gf_pow(a, 0) = 1`, including for `a = 0`.
pub fn gf_pow(a : Int, exp : Int) -> Int {
  let mut base = gf_reduce(a)
  let mut e = exp
  let mut acc = 1
  while e > 0 {
    if e % 2 == 1 {
      acc = gf_mul(acc, base)
    }
    base = gf_mul(base, base)
    e = e / 2
  }
  acc
}

///|
/// Multiplicative inverse via Fermat: `a^(p-2) = a^-1` in a prime field.
///
/// Raises nothing and returns 0 for 0; callers that need a total function
/// check for zero first. Kept as a bare `Int` return so it can be used inside
/// tight loops without error plumbing.
pub fn gf_inv(a : Int) -> Int {
  gf_pow(a, field_modulus - 2)
}
