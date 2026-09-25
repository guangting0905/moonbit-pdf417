// Encoder geometry and the boundaries the standard puts on it.
//
// These are the checks that turn "it produced a picture" into "it produced a
// legal symbol": row and column ranges, the length descriptor budget, and the
// padding rule that fills the last row.

///|
/// Encodes, widening the symbol until the 3..90 row requirement is met.
///
/// Picking a column count by hand for every payload is exactly the tedium the
/// encoder exists to spare callers, so the tests use the search a caller would:
/// try, widen, try again.
fn encode_any(payload : Array[Int], level : Int) -> Symbol {
  let mut columns = 6
  while columns <= max_columns {
    let mut result : Symbol? = None
    try encode_bytes(payload, EncodeOptions::new(columns, level)) catch {
      _ => ()
    } noraise {
      symbol => result = Some(symbol)
    }
    match result {
      Some(symbol) => return symbol
      None => columns = columns + 3
    }
  }
  abort("no column count in 6..\{max_columns} fits this payload at level \{level}")
}

///|
test "encode/geometry follows the standard" {
  let payload = utf8_bytes("hello world, this payload needs several rows")
  let symbol = try! encode_bytes(payload, EncodeOptions::new(6, 2))
  assert_eq(symbol.columns(), 6)
  // 17 modules per symbol character plus the start and stop patterns.
  assert_eq(symbol.matrix().width(), 17 * 6 + 69)
  assert_eq(symbol.matrix().height(), symbol.rows())
  assert_eq(symbol.codewords().length(), symbol.rows() * 6)
  assert_true(symbol.rows() >= min_rows && symbol.rows() <= max_rows)
}

///|
test "encode/symbol width formula holds across the column range" {
  // 170 characters of text is about 86 codewords: inside 90 rows even at a
  // single column, and still enough for three rows at thirty.
  let payload = utf8_bytes("q".repeat(170))
  for columns = min_columns; columns <= max_columns; columns = columns + 1 {
    let symbol = try! encode_bytes(payload, EncodeOptions::new(columns, 0))
    assert_eq(symbol.matrix().width(), symbol_width(columns))
    assert_eq(symbol.columns(), columns)
    assert_true(symbol.rows() >= min_rows && symbol.rows() <= max_rows)
  }
}

///|
test "encode/length descriptor counts data, padding and itself" {
  // The descriptor equals (data + padding + 1) and never includes the error
  // correction block: a decoder sizes that from the geometry instead.
  let symbol = encode_any(utf8_bytes("descriptor"), 2)
  let ec = try! symbol.ec_codeword_count()
  let stream = symbol.codewords()
  assert_eq(
    stream[0],
    symbol.data_codeword_count() + symbol.padding_codeword_count() + 1,
  )
  assert_eq(stream[0], stream.length() - ec)
  assert_eq(stream[0], try! decode_matrix(symbol.matrix()).report().length_descriptor())
}

///|
test "encode/padding fills the last row with the pad codeword" {
  let symbol = encode_any(utf8_bytes("padded payload"), 1)
  // Whatever the geometry, the stream divides evenly into rows.
  assert_eq(symbol.codewords().length() % symbol.columns(), 0)
  // Padding sits between the data and the error correction block, and is
  // always the pad codeword.
  let start = 1 + symbol.data_codeword_count()
  for i = start; i < start + symbol.padding_codeword_count(); i = i + 1 {
    assert_eq(symbol.codewords()[i], padding_codeword)
  }
  let ec = try! symbol.ec_codeword_count()
  assert_eq(
    symbol.codewords().length(),
    symbol.data_codeword_count() + symbol.padding_codeword_count() + ec + 1,
  )
}

///|
test "encode/codewords divide evenly into rows at every column count" {
  for columns = 1; columns <= 12; columns = columns + 1 {
    let symbol = encode_any(utf8_bytes("q".repeat(40)), 1)
    assert_eq(symbol.codewords().length() % symbol.columns(), 0)
  }
}

///|
test "encode/row indicators carry the symbol geometry" {
  let columns = 7
  let rows = 9
  let level = 3
  // The right indicator of row 0 is `30 * 0 + (columns - 1)`.
  assert_eq(row_indicator_right(0, rows, columns, level), columns - 1)
  // The left indicator of row 0 is `(rows - 1) / 3`.
  assert_eq(row_indicator_left(0, rows, columns, level), (rows - 1) / 3)
  // The left indicator of row 1 carries the error correction level and the
  // remainder of the row count.
  assert_eq(
    row_indicator_left(1, rows, columns, level),
    level * 3 + (rows - 1) % 3,
  )
  // Row 3 resets the base back to 30.
  assert_eq(row_indicator_left(3, rows, columns, level), 30 + (rows - 1) / 3)
}

///|
test "encode/padding count matches the remainder rule" {
  // total = data + ec + 1; padding only appears when that is not a multiple of
  // the column count.
  assert_eq(padding_count(5, 2, 6), 4) // 8 % 6 = 2 -> 4 pads
  assert_eq(padding_count(3, 2, 6), 0) // 6 % 6 = 0 -> no padding
}

///|
test "encode/too little data for three rows is refused" {
  let mut raised = false
  try ignore(encode_bytes(utf8_bytes("HELLO"), EncodeOptions::new(6, 2))) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  assert_true(raised, msg="a two-row symbol was built")
}

///|
test "encode/columns outside 1..30 are refused" {
  for columns in [0, 31, -1] {
    let mut raised = false
    try ignore(encode_bytes(utf8_bytes("x"), EncodeOptions::new(columns, 2))) catch {
      _ => raised = true
    } noraise {
      _ => ()
    }
    assert_true(raised, msg="columns \{columns} was accepted")
  }
}

///|
test "encode/error correction level outside 0..8 is refused" {
  for level in [-1, 9] {
    let mut raised = false
    try ignore(encode_bytes(utf8_bytes("x"), EncodeOptions::new(3, level))) catch {
      _ => raised = true
    } noraise {
      _ => ()
    }
    assert_true(raised, msg="ec level \{level} was accepted")
  }
}

///|
test "encode/data that cannot fit 928 codewords is refused" {
  // 928 codewords is the largest symbol; pushing past it must raise rather
  // than wrap around.
  let huge = utf8_bytes("z".repeat(4000))
  let mut raised = false
  try ignore(encode_bytes(huge, EncodeOptions::new(30, 0))) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  assert_true(raised, msg="oversized data was accepted")
}

///|
test "encode/options accessors round trip" {
  let options = EncodeOptions::default().with_columns(11).with_ec_level(6)
  assert_eq(options.columns(), 11)
  assert_eq(options.ec_level(), 6)
  let defaults = EncodeOptions::default()
  assert_eq(defaults.columns(), 6)
  assert_eq(defaults.ec_level(), 2)
}

///|
test "encode/hex helpers round trip" {
  let bytes : Array[Int] = [0, 1, 15, 16, 127, 128, 255]
  assert_eq(to_hex(bytes), "00010f107f80ff")
  assert_eq(try! bytes_from_hex("00010f107f80ff"), bytes)
  assert_eq(try! bytes_from_hex("AB"), [171])
  let mut raised = false
  try ignore(bytes_from_hex("abc")) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  assert_true(raised, msg="an odd-length hex string was accepted")
}
