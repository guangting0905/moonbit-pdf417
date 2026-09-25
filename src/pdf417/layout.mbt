// Symbol layout: from a codeword stream to the module matrix.
//
// A PDF417 row is built from five pieces, left to right:
//
//     start(17) | left row indicator(17) | columns x data(17) | right row indicator(17) | stop(18)
//
// so a symbol is `17 * columns + 69` modules wide and `rows` modules tall
// before the renderer stretches rows vertically.
//
// The two row indicators are not decoration: they repeat the symbol geometry
// (row count, column count, error correction level) so a scanner can read a
// symbol whose bottom is damaged. Their values depend on the row's cluster,
// which cycles 0, 3, 6 as you go down.

///|
/// A laid-out PDF417 symbol.
///
/// `matrix` is the logical module grid: one module row per symbol row, no
/// scaling and no quiet zone. The renderers add those.
pub struct Symbol {
  rows : Int
  columns : Int
  ec_level : Int
  data_count : Int
  pad_count : Int
  codewords : Array[Int]
  matrix : BitMatrix
}

///|
/// Number of rows in the symbol.
pub fn Symbol::rows(self : Symbol) -> Int {
  self.rows
}

///|
/// Number of data columns per row.
pub fn Symbol::columns(self : Symbol) -> Int {
  self.columns
}

///|
/// Error correction level in use.
pub fn Symbol::ec_level(self : Symbol) -> Int {
  self.ec_level
}

///|
/// Codewords produced by compaction, before padding, the length descriptor and
/// the error correction block.
pub fn Symbol::data_codeword_count(self : Symbol) -> Int {
  self.data_count
}

///|
/// Padding codewords appended to fill the last row.
pub fn Symbol::padding_codeword_count(self : Symbol) -> Int {
  self.pad_count
}

///|
/// The full high-level codeword stream: length descriptor, data, padding,
/// then the error correction codewords.
pub fn Symbol::codewords(self : Symbol) -> Array[Int] {
  self.codewords
}

///|
/// The logical module matrix.
pub fn Symbol::matrix(self : Symbol) -> BitMatrix {
  self.matrix
}

///|
/// Number of error correction codewords in the symbol.
pub fn Symbol::ec_codeword_count(self : Symbol) -> Int raise Pdf417Error {
  ec_word_count(self.ec_level)
}

///|
/// Module width of a symbol with `columns` data columns.
pub fn symbol_width(columns : Int) -> Int {
  17 * columns + 69
}

///|
/// The codeword value used to pad the last row.
///
/// 900 is the text latch code, and a decoder that reaches it in the padding
/// region simply stops: the real payload length is already known from the
/// length descriptor.
pub let padding_codeword : Int = 900

///|
/// Value of the left row indicator for `row`.
pub fn row_indicator_left(
  row : Int,
  rows : Int,
  columns : Int,
  ec_level : Int,
) -> Int {
  let x = match row % 3 {
    0 => (rows - 1) / 3
    1 => ec_level * 3 + (rows - 1) % 3
    _ => columns - 1
  }
  30 * (row / 3) + x
}

///|
/// Value of the right row indicator for `row`. Same three quantities as the
/// left indicator, rotated so that a single row still carries two of them.
pub fn row_indicator_right(
  row : Int,
  rows : Int,
  columns : Int,
  ec_level : Int,
) -> Int {
  let x = match row % 3 {
    0 => columns - 1
    1 => (rows - 1) / 3
    _ => ec_level * 3 + (rows - 1) % 3
  }
  30 * (row / 3) + x
}

///|
/// How many padding codewords are needed to fill the last row.
///
/// The length descriptor occupies one codeword and the error correction
/// codewords are not counted, so only data and descriptor drive the padding.
pub fn padding_count(data_count : Int, ec_count : Int, columns : Int) -> Int {
  let total = data_count + ec_count + 1
  let modulo = total % columns
  if modulo > 0 {
    columns - modulo
  } else {
    0
  }
}

///|
/// Writes one symbol character's modules, most significant bit first.
fn emit_pattern(m : BitMatrix, x0 : Int, y : Int, value : UInt, width : Int) -> Int {
  let mut x = x0
  for i = width - 1; i >= 0; i = i - 1 {
    m.set(x, y, ((value >> i) & 1U) == 1U)
    x = x + 1
  }
  x
}

///|
/// Lays a complete codeword stream out into rows and paints the module grid.
fn build_matrix(
  codewords : Array[Int],
  rows : Int,
  columns : Int,
  ec_level : Int,
) -> BitMatrix {
  let width = symbol_width(columns)
  let m = BitMatrix::new(width, rows)
  for row = 0; row < rows; row = row + 1 {
    let cluster = row % 3
    let left = row_indicator_left(row, rows, columns, ec_level)
    let right = row_indicator_right(row, rows, columns, ec_level)
    let mut x = emit_pattern(m, 0, row, start_pattern, 17)
    x = emit_pattern(m, x, row, patterns[cluster][left], 17)
    for c = 0; c < columns; c = c + 1 {
      let word = codewords[row * columns + c]
      x = emit_pattern(m, x, row, patterns[cluster][word], 17)
    }
    x = emit_pattern(m, x, row, patterns[cluster][right], 17)
    let _ = emit_pattern(m, x, row, stop_pattern, stop_width)
  }
  m
}

///|
/// Encodes bytes into a PDF417 symbol.
pub fn encode_bytes(
  data : Array[Int],
  options : EncodeOptions,
) -> Symbol raise Pdf417Error {
  options.validate()
  let columns = options.columns
  let level = options.ec_level

  let data_words = compact(data)
  let data_count = data_words.length()
  let ec_count = ec_word_count(level)

  let pad_count = padding_count(data_count, ec_count, columns)
  // The length descriptor counts data, padding and itself - never the error
  // correction codewords.
  let length_descriptor = data_count + pad_count + 1
  let cw_count = data_count + ec_count + pad_count + 1
  let rows = (cw_count + columns - 1) / columns

  if length_descriptor > max_codewords {
    raise DataTooLong(length_descriptor, max_codewords)
  }
  if rows < min_rows {
    raise SizeOutOfRange(
      "rows",
      rows,
      "fewer than \{min_rows}; reduce columns or add data",
    )
  }
  if rows > max_rows {
    raise SizeOutOfRange(
      "rows",
      rows,
      "more than \{max_rows}; increase columns or shorten the data",
    )
  }

  // Length descriptor + data + padding, then the error correction block.
  let body : Array[Int] = []
  body.push(length_descriptor)
  for w in data_words {
    body.push(w)
  }
  for _k = 0; _k < pad_count; _k = _k + 1 {
    body.push(padding_codeword)
  }
  let ec_words = encode_ec(body, level)
  let all : Array[Int] = []
  for w in body {
    all.push(w)
  }
  for w in ec_words {
    all.push(w)
  }

  {
    rows,
    columns,
    ec_level: level,
    data_count,
    pad_count,
    codewords: all,
    matrix: build_matrix(all, rows, columns, level),
  }
}

///|
/// Encodes a string, UTF-8 encoded, into a PDF417 symbol.
pub fn encode(
  text : StringView,
  options : EncodeOptions,
) -> Symbol raise Pdf417Error {
  encode_bytes(utf8_bytes(text), options)
}

///|
/// UTF-8 bytes of a string, as an `Array[Int]` of byte values.
///
/// The codec works on byte values throughout, so the string layer is a thin
/// conversion rather than something the compaction logic has to know about.
pub fn utf8_bytes(text : StringView) -> Array[Int] {
  let encoded = @utf8.encode(text)
  let out : Array[Int] = Array::make(encoded.length(), 0)
  for i = 0; i < encoded.length(); i = i + 1 {
    out[i] = encoded[i].to_int()
  }
  out
}

///|
/// Decodes UTF-8 bytes back into a string.
pub fn utf8_string(bytes : Array[Int]) -> String raise Pdf417Error {
  let buf = Buffer(size_hint=bytes.length())
  for i = 0; i < bytes.length(); i = i + 1 {
    let v = bytes[i]
    if v < 0 || v > 255 {
      raise DecodeFailed("byte out of range at index \{i}: \{v}")
    }
    buf.write_byte(v.to_byte())
  }
  try @utf8.decode(buf.to_bytes()) catch {
    _ => raise DecodeFailed("payload is not valid UTF-8")
  }
}
