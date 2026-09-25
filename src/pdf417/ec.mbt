// Reed-Solomon error correction over GF(929).
//
// PDF417 appends `2^(level+1)` error correction codewords to every symbol.
// Level 0 -> 2 codewords, level 8 -> 512.
//
// The generator polynomial is *derived*, not tabulated:
//
//     g(x) = (x - 3^1)(x - 3^2) ... (x - 3^k)   over GF(929)
//
// The coefficients this produces are checked against the table published with
// ISO/IEC 15438 in `tests/vectors/ec_coefficients.json` (see
// cmd/conformance), so the derivation is not taken on faith.

///|
/// Number of error correction codewords for a level: `2^(level+1)`.
pub fn ec_word_count(level : Int) -> Int raise Pdf417Error {
  if level < 0 || level > max_ec_level {
    raise InvalidParameter("ec_level", level, "0..\{max_ec_level}")
  }
  1 << (level + 1)
}

///|
/// Generator polynomial coefficients for `level`, in ascending order
/// (constant term first) with the monic leading coefficient dropped.
///
/// The length of the result equals `ec_word_count(level)`.
pub fn generator_coefficients(level : Int) -> Array[Int] raise Pdf417Error {
  let k = ec_word_count(level)
  // Ascending-order coefficient list; starts as the constant polynomial 1.
  let mut poly : Array[Int] = [1]
  for i = 1; i <= k; i = i + 1 {
    let root = gf_pow(field_generator, i)
    let next : Array[Int] = Array::make(poly.length() + 1, 0)
    // Multiply by (x - root):
    //   ascending shift       poly[j]   -> next[j + 1]
    //   constant scaling      -root*poly[j] -> next[j]
    for j = 0; j < poly.length(); j = j + 1 {
      next[j] = gf_sub(next[j], gf_mul(poly[j], root))
      next[j + 1] = gf_add(next[j + 1], poly[j])
    }
    poly = next
  }
  // `poly[k]` is the leading coefficient and must be 1.
  if poly[k] != 1 {
    abort("RS generator polynomial lost its monic leading coefficient")
  }
  let out : Array[Int] = Array::make(k, 0)
  for i = 0; i < k; i = i + 1 {
    out[i] = gf_reduce(poly[i])
  }
  out
}

///|
/// Computes the error correction codewords for a block of data codewords.
///
/// All inputs must already be reduced into 0..928.
pub fn encode_ec(data : Array[Int], level : Int) -> Array[Int] raise Pdf417Error {
  let count = ec_word_count(level)
  let factors = generator_coefficients(level)
  let ec : Array[Int] = Array::make(count, 0)
  for di = 0; di < data.length(); di = di + 1 {
    let temp = gf_add(data[di], ec[count - 1])
    for xi = count - 1; xi >= 0; xi = xi - 1 {
      let word = if xi > 0 { ec[xi - 1] } else { 0 }
      ec[xi] = gf_sub(word, gf_mul(temp, factors[xi]))
    }
  }
  let out : Array[Int] = Array::make(count, 0)
  for i = 0; i < count; i = i + 1 {
    out[i] = gf_neg(ec[count - 1 - i])
  }
  out
}

///|
/// Evaluates the codeword polynomial
/// `c(x) = c[0] * x^(n-1) + ... + c[n-1]` at `x`, using Horner's rule.
///
/// This is **descending** order, which is how a received codeword block is
/// written. The error locator and evaluator polynomials are ascending and use
/// `poly_eval_asc` instead.
pub fn poly_eval(coeffs : Array[Int], x : Int) -> Int {
  let mut acc = 0
  for i = 0; i < coeffs.length(); i = i + 1 {
    acc = gf_add(gf_mul(acc, x), coeffs[i])
  }
  acc
}

///|
/// Evaluates a polynomial written in **ascending** order
/// (`p[0] + p[1]*x + p[2]*x^2 + ...`) at `x`.
///
/// Note the contrast with `poly_eval`, which takes descending order because
/// codeword blocks are naturally written most-significant first. Mixing the
/// two up fails silently: the result is still a field element, just not the
/// one you wanted, and it surfaces only as "error correction does not
/// correct". The locator and evaluator polynomials in `decode.mbt` are
/// ascending, so they use this one.
pub fn poly_eval_asc(p : Array[Int], x : Int) -> Int {
  let mut acc = 0
  let mut i = p.length() - 1
  while i >= 0 {
    acc = gf_add(gf_mul(acc, x), p[i])
    i = i - 1
  }
  acc
}

///|
/// Syndromes of a received block: `S_i = c(3^i)` for `i = 1..count`.
///
/// An all-zero syndrome vector means the block is a valid codeword; that is
/// the check `decode` uses before attempting any correction.
pub fn syndromes(received : Array[Int], count : Int) -> Array[Int] {
  let out : Array[Int] = Array::make(count, 0)
  for i = 0; i < count; i = i + 1 {
    out[i] = poly_eval(received, gf_pow(field_generator, i + 1))
  }
  out
}

///|
/// True when every syndrome is zero, i.e. the block is a valid codeword.
pub fn is_codeword(received : Array[Int], count : Int) -> Bool {
  let s = syndromes(received, count)
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] != 0 {
      return false
    }
  }
  true
}

///|
/// How many codeword errors a level can correct: `2^(level+1) / 2`.
pub fn correction_capacity(level : Int) -> Int raise Pdf417Error {
  ec_word_count(level) / 2
}
