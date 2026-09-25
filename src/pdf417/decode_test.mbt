// Round trip and damage recovery, against the public API.
//
// The interesting tests here are the damaged ones. A round trip on a clean
// symbol only proves the encoder and decoder share a convention; damaging the
// symbol is what proves the error correction layer is actually wired up, and
// that the decoder does not read protected data before repairing it.

///|
/// Replaces one data symbol character with a *different* codeword's pattern.
///
/// The replacement is derived from the codeword actually stored there, so the
/// damage is guaranteed to be an error rather than a coin flip that might
/// rewrite the same pattern. The result is still a valid symbol character, just
/// for the wrong value, so the decoder matches it exactly.
fn damage(symbol : Symbol, row : Int, column : Int, delta : Int) -> Unit {
  let index = row * symbol.columns() + column
  let replacement = (symbol.codewords()[index] + delta) % codeword_count
  write_character(symbol, row, column, patterns[row % 3][replacement])
}

///|
/// Flips modules inside one symbol character, producing a pattern that is not
/// in the table at all: the shape of damage a smudge or a torn edge produces.
/// The decoder has to fall back to a nearest-pattern match.
fn smudge(symbol : Symbol, row : Int, column : Int, mask : UInt) -> Unit {
  let index = row * symbol.columns() + column
  let original = patterns[row % 3][symbol.codewords()[index]]
  write_character(symbol, row, column, original ^ mask)
}

///|
fn write_character(
  symbol : Symbol,
  row : Int,
  column : Int,
  value : UInt,
) -> Unit {
  let x = 34 + column * 17
  for i = 0; i < 17; i = i + 1 {
    symbol.matrix().set(x + i, row, ((value >> (16 - i)) & 1U) == 1U)
  }
}

///|
fn round_trip(payload : Array[Int], options : EncodeOptions) -> Unit raise {
  let symbol = encode_bytes(payload, options)
  let decoded = decode_matrix(symbol.matrix())
  assert_eq(decoded.bytes(), payload)
  assert_eq(decoded.report().corrected_errors(), 0)
}

///|
test "decode/round trip covers all three compaction modes" {
  let options = EncodeOptions::new(3, 2)
  round_trip(utf8_bytes("HELLO WORLD"), options)
  round_trip(utf8_bytes("lower case text"), options)
  round_trip(utf8_bytes("12345678901234567890"), options)
  round_trip(utf8_bytes("Mix 12345 text 67890"), options)
  round_trip([0, 255, 128, 1, 2, 3], options)
  round_trip(utf8_bytes("你好，世界"), options)
  round_trip(utf8_bytes("PDF417 🐉"), options)
}

///|
test "decode/round trip at both ends of the column range" {
  round_trip([65, 66, 67], EncodeOptions::new(1, 3))
  round_trip(
    utf8_bytes("x".repeat(200)),
    EncodeOptions::new(30, 2),
  )
}

///|
test "decode/round trip at every error correction level" {
  for level = 0; level <= max_ec_level; level = level + 1 {
    let payload = utf8_bytes("level \{level} payload, long enough to need real geometry")
    let columns = encode_any(payload, level).columns()
    round_trip(payload, EncodeOptions::new(columns, level))
  }
}

///|
test "decode/empty payload round trips" {
  round_trip([], EncodeOptions::new(3, 2))
}

///|
test "decode/row indicators repeat the geometry" {
  let symbol = try! encode_bytes(
    utf8_bytes("indicator check"),
    EncodeOptions::new(9, 5),
  )
  let (rows, columns, ec) = read_row_indicators(symbol.matrix())
  assert_eq(rows, symbol.rows())
  assert_eq(columns, symbol.columns())
  assert_eq(ec, symbol.ec_level())
  let report = try! decode_matrix(symbol.matrix()).report()
  assert_eq(report.indicator_rows(), symbol.rows())
  assert_eq(report.indicator_columns(), symbol.columns())
  assert_eq(report.indicator_ec_level(), symbol.ec_level())
}

///|
test "decode/a replaced symbol character is repaired" {
  // Replacing a symbol character with another valid pattern produces no
  // pattern mismatch - it decodes cleanly to the wrong codeword - so
  // `unmatched_characters` stays zero and Reed-Solomon is the only thing that
  // can notice.
  let payload = utf8_bytes("repair me")
  let symbol = encode_any(payload, 3)
  damage(symbol, 1, 2, 1)
  let decoded = try! decode_matrix(symbol.matrix())
  assert_eq(decoded.bytes(), payload)
  assert_eq(decoded.report().corrected_errors(), 1)
  assert_eq(decoded.report().unmatched_characters(), 0)
}

///|
test "decode/a smudged symbol character is snapped to the nearest pattern" {
  // Flipping a module inside a character leaves a pattern that is not in the
  // table. The decoder picks the closest one - which for a small smudge is the
  // original codeword, so the block needs no correction at all. That is why
  // `unmatched_characters` and `corrected_errors` are separate counters: the
  // first says the pattern was damaged, the second says the codeword was wrong
  // after nearest-match recovery.
  let payload = utf8_bytes("smudged")
  let symbol = encode_any(payload, 3)
  smudge(symbol, 0, 1, 0x1U)
  let decoded = try! decode_matrix(symbol.matrix())
  assert_eq(decoded.bytes(), payload)
  assert_eq(decoded.report().unmatched_characters(), 1)
}

///|
test "decode/damaging the length descriptor does not truncate the payload" {
  // Regression: the decoder used to read the length descriptor before running
  // error correction, so damage to symbol character 0 made it decode only part
  // of the payload while still reporting every error as corrected.
  let payload = utf8_bytes("a payload long enough to need several rows of data")
  let symbol = encode_any(payload, 3)
  let original = try! decode_matrix(symbol.matrix()).payload()
  damage(symbol, 0, 0, 137)
  let decoded = try! decode_matrix(symbol.matrix())
  assert_eq(decoded.bytes(), payload)
  assert_eq(decoded.payload(), original)
  assert_eq(decoded.report().corrected_errors(), 1)
}

///|
test "decode/errors up to capacity are all repaired" {
  let payload = utf8_bytes("capacity test payload with enough rows to spread errors")
  let level = 4
  let symbol = encode_any(payload, level)
  let capacity = try! correction_capacity(level)
  assert_eq(capacity, 16)
  // Slide along the grid so every error lands in a distinct symbol character.
  let mut placed = 0
  let mut index = 0
  while placed < capacity {
    let row = index % symbol.rows()
    let column = (index / symbol.rows()) % symbol.columns()
    damage(symbol, row, column, placed + 1)
    placed = placed + 1
    index = index + 1
  }
  let decoded = try! decode_matrix(symbol.matrix())
  assert_eq(decoded.bytes(), payload)
  assert_eq(decoded.report().corrected_errors(), capacity)
}

///|
test "decode/damage beyond capacity is reported as a failure" {
  // Level 0 protects two codewords and can repair one. Three errors must be
  // refused rather than silently guessed at.
  let payload = utf8_bytes("too much damage to fix")
  let symbol = encode_any(payload, 0)
  damage(symbol, 0, 0, 11)
  damage(symbol, 0, 1, 22)
  damage(symbol, 0, 2, 33)
  let mut raised = false
  try ignore(decode_matrix(symbol.matrix())) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  assert_true(raised, msg="an over-damaged symbol was accepted")
}

///|
test "decode/damaged row indicators are recovered from the other rows" {
  // Every row repeats two of the three geometry quantities, so wiping one
  // row's indicators must not cost the decoder the symbol geometry. This is
  // the whole reason the indicators are repeated on every row.
  let payload = utf8_bytes("indicator redundancy")
  let symbol = encode_any(payload, 3)
  let columns = symbol.columns()
  let width = symbol.matrix().width()
  // Overwrite the start pattern, both indicator characters and the stop
  // pattern of row 0 with another codeword's pattern.
  let value = patterns[0][500]
  for i = 0; i < 17; i = i + 1 {
    symbol.matrix().set(i, 0, ((value >> (16 - i)) & 1U) == 1U)
    symbol.matrix().set(17 + i, 0, ((value >> (16 - i)) & 1U) == 1U)
    symbol.matrix().set(width - 35 + i, 0, ((value >> (16 - i)) & 1U) == 1U)
  }
  let (rows, read_columns, level) = read_row_indicators(symbol.matrix())
  assert_eq(rows, symbol.rows())
  assert_eq(read_columns, columns)
  assert_eq(level, symbol.ec_level())
  let decoded = try! decode_matrix(symbol.matrix())
  assert_eq(decoded.bytes(), payload)
  assert_eq(decoded.report().indicator_rows(), symbol.rows())
}

///|
test "decode/matrix whose width is not 17n + 69 is refused" {
  let mut raised = false
  try ignore(decode_matrix(BitMatrix::new(120, 5))) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  assert_true(raised, msg="a malformed width was accepted")
}

///|
test "decode/too few rows is refused" {
  let mut raised = false
  try ignore(decode_matrix(BitMatrix::new(171, 2))) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  assert_true(raised, msg="a two-row matrix was accepted")
}
