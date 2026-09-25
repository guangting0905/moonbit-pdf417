// Decoder: from a module matrix back to bytes.
//
// The decoder deliberately works on the *logical* module grid that `encode`
// produces, not on a photograph: locating and deskewing a symbol in a picture
// is a scanner problem (thresholding, row/column detection, perspective), and
// pulling it in here would blur what this project actually claims. What it
// does handle is the part that lives in the codeword layer - symbol character
// lookup, row indicator recovery, and Reed-Solomon error correction.
//
// `docs/DECODING.md` walks through each step.

///|
/// What the decoder saw, and what it had to repair.
pub struct DecodeReport {
  /// Rows in the symbol.
  rows : Int
  /// Data columns per row.
  columns : Int
  /// Error correction level.
  ec_level : Int
  /// Value of the first codeword: length descriptor + data + padding.
  length_descriptor : Int
  /// Total symbol characters in the symbol (data + error correction).
  symbol_characters : Int
  /// Symbol characters whose 17 modules did not match a pattern exactly.
  unmatched_characters : Int
  /// Number of codeword errors Reed-Solomon had to fix. 0 means the
  /// syndromes were already zero.
  corrected_errors : Int
  /// Rows recovered from the row indicators, or 0 when the first three rows
  /// could not be read.
  indicator_rows : Int
  /// Columns recovered from the row indicators, or 0.
  indicator_columns : Int
  /// Error correction level recovered from the row indicators, or -1.
  indicator_ec_level : Int
}

///|
/// A decoded symbol.
pub struct Decoded {
  payload : String
  bytes : Array[Int]
  report : DecodeReport
}

///|
/// The decoded payload as text.
pub fn Decoded::payload(self : Decoded) -> String {
  self.payload
}

///|
/// The decoded payload as raw bytes.
pub fn Decoded::bytes(self : Decoded) -> Array[Int] {
  self.bytes
}

///|
/// Decoding statistics.
pub fn Decoded::report(self : Decoded) -> DecodeReport {
  self.report
}

///|
/// Rows in the decoded symbol.
pub fn DecodeReport::rows(self : DecodeReport) -> Int {
  self.rows
}

///|
/// Columns in the decoded symbol.
pub fn DecodeReport::columns(self : DecodeReport) -> Int {
  self.columns
}

///|
/// Error correction level of the decoded symbol.
pub fn DecodeReport::ec_level(self : DecodeReport) -> Int {
  self.ec_level
}

///|
/// Length descriptor read from the symbol.
pub fn DecodeReport::length_descriptor(self : DecodeReport) -> Int {
  self.length_descriptor
}

///|
/// Symbol characters that failed an exact pattern match.
pub fn DecodeReport::unmatched_characters(self : DecodeReport) -> Int {
  self.unmatched_characters
}

///|
/// Codeword errors corrected by Reed-Solomon.
pub fn DecodeReport::corrected_errors(self : DecodeReport) -> Int {
  self.corrected_errors
}

///|
/// Rows recovered from the row indicators, or 0 when unreadable.
pub fn DecodeReport::indicator_rows(self : DecodeReport) -> Int {
  self.indicator_rows
}

///|
/// Columns recovered from the row indicators, or 0 when unreadable.
pub fn DecodeReport::indicator_columns(self : DecodeReport) -> Int {
  self.indicator_columns
}

///|
/// Error correction level recovered from the row indicators, or -1.
pub fn DecodeReport::indicator_ec_level(self : DecodeReport) -> Int {
  self.indicator_ec_level
}

///|
/// Reads `width` modules of row `y` starting at `x`, most significant first.
fn read_bits(m : BitMatrix, x : Int, y : Int, width : Int) -> UInt {
  let mut v : UInt = 0U
  for i = 0; i < width; i = i + 1 {
    v = (v << 1) | (if m.get(x + i, y) { 1U } else { 0U })
  }
  v
}

///|
/// Finds the codeword whose pattern is closest to `bits` in `cluster`.
///
/// Returns `(codeword, hamming_distance)`. Distance 0 means an exact match;
/// anything else is a damaged symbol character, which Reed-Solomon may still
/// be able to repair.
fn match_pattern(cluster : Int, bits : UInt) -> (Int, Int) {
  let mut best = 0
  let mut best_distance = 99
  for w = 0; w < codeword_count; w = w + 1 {
    let d = (patterns[cluster][w] ^ bits).popcnt()
    if d < best_distance {
      best_distance = d
      best = w
      if d == 0 {
        break
      }
    }
  }
  (best, best_distance)
}

///|
/// Reads the three geometry quantities that the row indicators carry.
///
/// Every row repeats two of the three quantities, and the row's cluster decides
/// which two. Rather than trusting the first readable indicator - which a
/// single damaged row can poison - each quantity is decided by majority vote
/// across all rows, the same way a scanner averages over many rows.
///
/// Returns `(rows, columns, ec_level)`, or zeros when nothing could be read.
pub fn read_row_indicators(m : BitMatrix) -> (Int, Int, Int) {
  // x = (rows - 1) / 3, x = columns - 1, x = 3 * ec_level + (rows - 1) % 3.
  // All three are below 30, so 30 counters each is enough for a vote.
  let rows_votes : Array[Int] = Array::make(30, 0)
  let columns_votes : Array[Int] = Array::make(30, 0)
  let ec_votes : Array[Int] = Array::make(30, 0)
  for row = 0; row < m.height(); row = row + 1 {
    let cluster = row % 3
    let left = match_pattern(cluster, read_bits(m, 17, row, 17))
    let right = match_pattern(cluster, read_bits(m, m.width() - 35, row, 17))
    // Only exact matches count as votes; a near-miss is damage, not evidence.
    let left_x = if left.1 == 0 { left.0 % 30 } else { -1 }
    let right_x = if right.1 == 0 { right.0 % 30 } else { -1 }
    match cluster {
      0 => {
        if left_x >= 0 {
          rows_votes[left_x] = rows_votes[left_x] + 1
        }
        if right_x >= 0 {
          columns_votes[right_x] = columns_votes[right_x] + 1
        }
      }
      1 => {
        if left_x >= 0 {
          ec_votes[left_x] = ec_votes[left_x] + 1
        }
        if right_x >= 0 {
          rows_votes[right_x] = rows_votes[right_x] + 1
        }
      }
      _ => {
        if left_x >= 0 {
          columns_votes[left_x] = columns_votes[left_x] + 1
        }
        if right_x >= 0 {
          ec_votes[right_x] = ec_votes[right_x] + 1
        }
      }
    }
  }
  let rows_x = winner(rows_votes)
  let columns_x = winner(columns_votes)
  let ec_x = winner(ec_votes)
  if rows_x < 0 || columns_x < 0 || ec_x < 0 {
    return (0, 0, -1)
  }
  // rows = 3 * ((rows - 1) / 3) + ((rows - 1) % 3) + 1, and the low digits of
  // ec_x are exactly (rows - 1) % 3.
  (3 * rows_x + (ec_x % 3) + 1, columns_x + 1, ec_x / 3)
}

///|
/// Index of the highest counter, or -1 when every counter is zero.
fn winner(votes : Array[Int]) -> Int {
  let mut best = -1
  let mut best_votes = 0
  for i = 0; i < votes.length(); i = i + 1 {
    if votes[i] > best_votes {
      best_votes = votes[i]
      best = i
    }
  }
  best
}

///|
/// Reads every symbol character out of the matrix.
///
/// Returns the codeword stream (data codewords only, row by row) and the
/// number of characters that needed a nearest-pattern match.
fn read_codewords(m : BitMatrix, columns : Int) -> (Array[Int], Int) {
  let rows = m.height()
  let out : Array[Int] = []
  let mut unmatched = 0
  for row = 0; row < rows; row = row + 1 {
    let cluster = row % 3
    for c = 0; c < columns; c = c + 1 {
      let x = 34 + c * 17
      let (word, distance) = match_pattern(cluster, read_bits(m, x, row, 17))
      if distance != 0 {
        unmatched = unmatched + 1
      }
      out.push(word)
    }
  }
  (out, unmatched)
}

///|
/// Ascending-order polynomial multiplication over GF(929).
fn poly_mul(a : Array[Int], b : Array[Int], limit : Int) -> Array[Int] {
  let size = if a.length() + b.length() - 1 > limit {
    limit
  } else {
    a.length() + b.length() - 1
  }
  let out : Array[Int] = Array::make(size, 0)
  for i = 0; i < a.length(); i = i + 1 {
    for j = 0; j < b.length(); j = j + 1 {
      if i + j < size {
        out[i + j] = gf_add(out[i + j], gf_mul(a[i], b[j]))
      }
    }
  }
  out
}

///|
/// Solves the key equation with Berlekamp-Massey, returning the error locator
/// polynomial `sigma(x) = 1 + s1*x + ...` in ascending order.
///
/// `syndromes` is `S[0..2t-1]`, where `S[k] = c(3^(k+1))`.
fn berlekamp_massey(s : Array[Int]) -> Array[Int] {
  let mut c : Array[Int] = [1]
  let mut b : Array[Int] = [1]
  let mut l = 0
  let mut m = 1
  let mut bb = 1
  for k = 0; k < s.length(); k = k + 1 {
    // discrepancy
    let mut d = s[k]
    for i = 1; i <= l; i = i + 1 {
      if i < c.length() {
        d = gf_add(d, gf_mul(c[i], s[k - i]))
      }
    }
    if d == 0 {
      m = m + 1
    } else {
      let coef = gf_mul(d, gf_inv(bb))
      let previous = c
      // c(x) <- c(x) - coef * x^m * b(x)
      let shifted : Array[Int] = Array::make(m + b.length(), 0)
      for i = 0; i < b.length(); i = i + 1 {
        shifted[i + m] = gf_mul(coef, b[i])
      }
      let size = if shifted.length() > c.length() {
        shifted.length()
      } else {
        c.length()
      }
      let next : Array[Int] = Array::make(size, 0)
      for i = 0; i < size; i = i + 1 {
        let ci = if i < c.length() { c[i] } else { 0 }
        let si = if i < shifted.length() { shifted[i] } else { 0 }
        next[i] = gf_sub(ci, si)
      }
      c = next
      if 2 * l <= k {
        l = k + 1 - l
        b = previous
        bb = d
        m = 1
      } else {
        m = m + 1
      }
    }
  }
  c
}

///|
/// Applies Reed-Solomon error correction to `words` in place.
///
/// Returns the number of codewords repaired. Raises when the block has more
/// errors than the level can hold.
fn correct_block(words : Array[Int], ec_count : Int) -> Int raise Pdf417Error {
  let s = syndromes(words, ec_count)
  let mut clean = true
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] != 0 {
      clean = false
    }
  }
  if clean {
    return 0
  }
  let sigma = berlekamp_massey(s)
  let n = words.length()
  // Error locator roots via Chien search: position j has locator
  // X = 3^(n-1-j), and the locator poly is satisfied at X^-1.
  let positions : Array[Int] = []
  let locators : Array[Int] = []
  for j = 0; j < n; j = j + 1 {
    let x = gf_pow(field_generator, n - 1 - j)
    let x_inv = gf_inv(x)
    if poly_eval_asc(sigma, x_inv) == 0 {
      positions.push(j)
      locators.push(x)
    }
  }
  if positions.length() == 0 || positions.length() * 2 > ec_count {
    raise DecodeFailed(
      "Reed-Solomon: \{positions.length()} locator roots found, cannot correct",
    )
  }
  // Omega(x) = S(x) * sigma(x) mod x^(2t), with S(x) = sum S_i x^i (i from 1).
  //
  // The truncation to exactly 2t terms is load-bearing. Keeping one term more
  // leaves a residual x^(2t) contribution that exactly cancels the leading
  // coefficient when the evaluator is sampled at an error locator - the
  // correction then silently comes out as zero and the block stays broken.
  let s_poly : Array[Int] = Array::make(ec_count + 1, 0)
  for i = 0; i < ec_count; i = i + 1 {
    s_poly[i + 1] = s[i]
  }
  let omega = poly_mul(s_poly, sigma, ec_count)
  for k = 0; k < positions.length(); k = k + 1 {
    let x = locators[k]
    let x_inv = gf_inv(x)
    let numerator = poly_eval_asc(omega, x_inv)
    // sigma'(x) = sum i * sigma_i * x^(i-1)
    let mut derivative = 0
    for i = 1; i < sigma.length(); i = i + 1 {
      derivative = gf_add(
        derivative,
        gf_mul(gf_mul(i % field_modulus, sigma[i]), gf_pow(x_inv, i - 1)),
      )
    }
    if derivative == 0 {
      raise DecodeFailed("Reed-Solomon: zero derivative at an error locator")
    }
    // Forney: X * Omega(X^-1) / sigma'(X^-1) equals minus the error magnitude,
    // so the repair is an addition rather than a subtraction.
    let magnitude = gf_mul(gf_mul(x, numerator), gf_inv(derivative))
    let j = positions[k]
    words[j] = gf_add(words[j], magnitude)
  }
  let after = syndromes(words, ec_count)
  for i = 0; i < after.length(); i = i + 1 {
    if after[i] != 0 {
      raise DecodeFailed(
        "Reed-Solomon: syndrome \{i} still non-zero after correcting \{positions.length()} codewords",
      )
    }
  }
  positions.length()
}

///|
/// Decodes a symbol from its logical module matrix.
pub fn decode_matrix(m : BitMatrix) -> Decoded raise Pdf417Error {
  let width = m.width()
  if width < 17 * min_columns + 69 {
    raise DecodeFailed(
      "matrix is \{width} modules wide; the narrowest symbol is \{17 * min_columns + 69}",
    )
  }
  if (width - 69) % 17 != 0 {
    raise DecodeFailed(
      "matrix width \{width} is not 17*n + 69, so it is not a PDF417 row",
    )
  }
  let columns = (width - 69) / 17
  if columns > max_columns {
    raise DecodeFailed("matrix implies \{columns} columns, the maximum is \{max_columns}")
  }
  let rows = m.height()
  if rows < min_rows || rows > max_rows {
    raise DecodeFailed(
      "matrix is \{rows} rows; a symbol has \{min_rows}..\{max_rows}",
    )
  }

  let (indicator_rows, indicator_columns, indicator_ec) = read_row_indicators(m)
  let (codewords, unmatched) = read_codewords(m, columns)

  // The error correction level comes from the row indicators, never from the
  // data: the length descriptor is itself protected data, and reading it
  // before correction is how a single damaged codeword truncates a payload.
  if indicator_ec < 0 {
    raise DecodeFailed(
      "no row indicator could be read, so the error correction block size is unknown",
    )
  }
  let ec_count = 1 << (indicator_ec + 1)
  if ec_count <= 0 || ec_count >= codewords.length() {
    raise DecodeFailed(
      "error correction block of \{ec_count} codewords does not fit \{codewords.length()} symbol characters",
    )
  }
  let corrected = correct_block(codewords, ec_count)

  // Symbol characters = length descriptor + data + padding + error correction,
  // so with the correction block size known the descriptor is determined. The
  // stored descriptor is then a second opinion on the same number, and the two
  // disagreeing means the block was not actually repaired.
  let length_descriptor = codewords.length() - ec_count
  if codewords[0] != length_descriptor {
    raise DecodeFailed(
      "length descriptor says \{codewords[0]} but the geometry implies \{length_descriptor}",
    )
  }

  // Reverse the high level compaction over the data region only.
  let data : Array[Int] = Array::make(length_descriptor - 1, 0)
  for i = 0; i < length_descriptor - 1; i = i + 1 {
    data[i] = codewords[i + 1]
  }
  let bytes = uncompact(data)
  let payload = match try_utf8(bytes) {
    Some(text) => text
    None => to_hex(bytes)
  }
  {
    payload,
    bytes,
    report: {
      rows,
      columns,
      ec_level: indicator_ec,
      length_descriptor,
      symbol_characters: codewords.length(),
      unmatched_characters: unmatched,
      corrected_errors: corrected,
      indicator_rows,
      indicator_columns,
      indicator_ec_level: indicator_ec,
    },
  }
}

///|
/// UTF-8 decode that returns `None` instead of raising.
fn try_utf8(bytes : Array[Int]) -> String? {
  try utf8_string(bytes) catch {
    _ => None
  } noraise {
    text => Some(text)
  }
}

///|
/// Decodes a symbol and returns the raw payload bytes.
pub fn decode_matrix_bytes(m : BitMatrix) -> Array[Int] raise Pdf417Error {
  decode_matrix(m).bytes()
}

///|
/// Reverses high level compaction: codewords back to bytes.
pub fn uncompact(words : Array[Int]) -> Array[Int] raise Pdf417Error {
  let out : Array[Int] = []
  let mut i = 0
  // Text is the starting mode, which is why a leading text run carries no latch.
  let mut mode = Text
  let mut padded = false
  while i < words.length() {
    let w = words[i]
    if w == latch_text {
      mode = Text
      i = i + 1
    } else if w == latch_byte {
      mode = Byte
      padded = false
      i = i + 1
    } else if w == latch_byte_alt {
      mode = Byte
      padded = true
      i = i + 1
    } else if w == latch_numeric {
      mode = Numeric
      i = i + 1
    } else if w == shift_byte {
      // A single byte, then back to text compaction.
      if i + 1 >= words.length() {
        raise DecodeFailed("shift-to-byte at the end of the data region")
      }
      out.push(words[i + 1])
      i = i + 2
      mode = Text
    } else {
      match mode {
        Text => i = decode_text_run(words, i, out)
        Byte => i = decode_byte_run(words, i, padded, out)
        Numeric => i = decode_numeric_run(words, i, out)
      }
    }
  }
  out
}

///|
/// Decodes a text compaction run starting at `i`. Returns the next index.
fn decode_text_run(words : Array[Int], start : Int, out : Array[Int]) -> Int {
  let mut i = start
  let interim : Array[Int] = []
  while i < words.length() && words[i] < latch_text {
    interim.push(words[i] / 30)
    interim.push(words[i] % 30)
    i = i + 1
  }
  decode_text_values(interim, out)
  i
}

///|
/// The punctuation sub-mode table: value -> byte.
pub fn punct_value(v : Int) -> Int {
  let table : Array[Int] = [
    59, 60, 62, 64, 91, 92, 93, 95, 96, 126, 33, 13, 9, 44, 58, 10, 45, 46, 36,
    47, 34, 124, 42, 40, 41, 63, 123, 125, 39,
  ]
  if v < 0 || v >= table.length() {
    -1
  } else {
    table[v]
  }
}

///|
/// The mixed sub-mode table: value -> byte, or -1 for switch codes.
pub fn mixed_value(v : Int) -> Int {
  let table : Array[Int] = [
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 38, 13, 9, 44, 58, 35, 45, 46, 36,
    47, 43, 37, 42, 61, 94, -1, 32, -1, -1, -1,
  ]
  if v < 0 || v >= table.length() {
    -1
  } else {
    table[v]
  }
}

///|
/// Expands base-30 sub-mode values into bytes, honouring the sub-mode state
/// machine: latches change the current sub-mode, shifts apply to one value.
fn decode_text_values(values : Array[Int], out : Array[Int]) -> Unit {
  let mut mode = submode_upper
  let mut i = 0
  while i < values.length() {
    let v = values[i]
    if mode == submode_upper {
      if v < 26 {
        out.push(65 + v)
      } else if v == 26 {
        out.push(32)
      } else if v == 27 {
        mode = submode_lower
      } else if v == 28 {
        mode = submode_mixed
      } else if v == 29 {
        // Punct shift: one value in the punctuation sub-mode, then back.
        i = i + 1
        if i < values.length() {
          let c = punct_value(values[i])
          if c >= 0 {
            out.push(c)
          }
        }
      }
    } else if mode == submode_lower {
      if v < 26 {
        out.push(97 + v)
      } else if v == 26 {
        out.push(32)
      } else if v == 27 {
        // Alpha shift: one value in the upper sub-mode.
        i = i + 1
        if i < values.length() && values[i] < 26 {
          out.push(65 + values[i])
        }
      } else if v == 28 {
        mode = submode_mixed
      } else if v == 29 {
        i = i + 1
        if i < values.length() {
          let c = punct_value(values[i])
          if c >= 0 {
            out.push(c)
          }
        }
      }
    } else if mode == submode_mixed {
      if v == 25 {
        mode = submode_punct
      } else if v == 26 {
        out.push(32)
      } else if v == 27 {
        mode = submode_lower
      } else if v == 28 {
        mode = submode_upper
      } else if v == 29 {
        i = i + 1
        if i < values.length() {
          let c = punct_value(values[i])
          if c >= 0 {
            out.push(c)
          }
        }
      } else {
        let c = mixed_value(v)
        if c >= 0 {
          out.push(c)
        }
      }
    } else {
      // Punctuation sub-mode.
      if v == 29 {
        mode = submode_upper
      } else {
        let c = punct_value(v)
        if c >= 0 {
          out.push(c)
        }
      }
    }
    i = i + 1
  }
}

///|
/// Decodes a byte compaction run starting at `i`.
///
/// The run ends at the first codeword that is 900 or above: those are the mode
/// latches, and it is exactly how the padding codeword (900) terminates a byte
/// run without being decoded as data.
///
/// Five base-900 codewords hold up to `900^5 = 5.9e14`, and six bytes need 48
/// bits, so the accumulator is `Int64` - a 32-bit `Int` would silently wrap.
fn decode_byte_run(
  words : Array[Int],
  start : Int,
  padded : Bool,
  out : Array[Int],
) -> Int {
  let mut i = start
  let mut done = false
  while i < words.length() && !done {
    if words[i] >= latch_text {
      done = true
    } else {
      let mut value : Int64 = 0L
      let mut count = 0
      while count < 5 && i < words.length() && words[i] < latch_text {
        value = 900L * value + words[i].to_int64()
        count = count + 1
        i = i + 1
      }
      let more_data = i < words.length() && words[i] < latch_text
      if count == 5 && (padded || more_data) {
        for b = 0; b < 6; b = b + 1 {
          out.push(((value >> (8 * (5 - b))) & 0xFFL).to_int())
        }
      } else {
        // Not a full sixpack: the accumulated codewords were literal bytes.
        i = i - count
        while i < words.length() && words[i] < latch_text {
          out.push(words[i])
          i = i + 1
        }
        done = true
      }
    }
  }
  i
}

///|
/// Decodes a numeric compaction run starting at `i`.
fn decode_numeric_run(
  words : Array[Int],
  start : Int,
  out : Array[Int],
) -> Int raise Pdf417Error {
  let mut i = start
  let values : Array[Int] = []
  while i < words.length() && words[i] < latch_text {
    values.push(words[i])
    i = i + 1
  }
  for b in decode_numeric(values) {
    out.push(b)
  }
  i
}

///|
/// Converts a run of numeric-compaction codewords back to ASCII digits.
///
/// A full 44-digit group is always exactly 15 codewords: the group's value is a
/// 45-digit number, and `900^15` is just above `10^45`, so 14 codewords cannot
/// hold it and 15 always can. Only the last group of a run can be shorter, and
/// it is never followed by another group. That is what makes splitting from the
/// front into 15-codeword groups safe.
pub fn decode_numeric(words : Array[Int]) -> Array[Int] raise Pdf417Error {
  let out : Array[Int] = []
  let mut p = 0
  while p < words.length() {
    let n = if p + 15 <= words.length() { 15 } else { words.length() - p }
    let group : Array[Int] = Array::make(n, 0)
    for k = 0; k < n; k = k + 1 {
      group[k] = words[p + k]
    }
    for b in base900_to_decimal(group) {
      out.push(b)
    }
    p = p + n
  }
  out
}

///|
/// Converts a base-900 group to its decimal digits, dropping the leading `1`
/// that numeric compaction uses to preserve leading zeros.
pub fn base900_to_decimal(group : Array[Int]) -> Array[Int] raise Pdf417Error {
  // Little-endian decimal digits, built by repeated multiply-and-add.
  let digits : Array[Int] = [0]
  for k = 0; k < group.length(); k = k + 1 {
    let mut carry = group[k]
    for j = 0; j < digits.length(); j = j + 1 {
      let cur = digits[j] * 900 + carry
      digits[j] = cur % 10
      carry = cur / 10
    }
    while carry > 0 {
      digits.push(carry % 10)
      carry = carry / 10
    }
  }
  // Find the most significant non-zero digit.
  let mut top = digits.length() - 1
  while top > 0 && digits[top] == 0 {
    top = top - 1
  }
  if digits[top] != 1 {
    raise DecodeFailed(
      "numeric compaction group does not start with the leading 1 marker",
    )
  }
  // `top` is the leading 1; emit the digits below it, most significant first.
  let out : Array[Int] = []
  let mut j = top - 1
  while j >= 0 {
    out.push(48 + digits[j])
    j = j - 1
  }
  out
}
