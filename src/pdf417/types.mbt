// Core types for the PDF417 codec.
//
// Everything the public API needs to talk about: the three compaction modes,
// the symbol geometry, and a structured error type.

///|
/// The three compaction modes defined by ISO/IEC 15438.
///
/// * `Text` packs 2 characters per codeword in base 30.
/// * `Byte` packs 6 bytes into 5 codewords in base 900; short runs stay 1:1.
/// * `Numeric` packs up to 44 digits into ~15 codewords in base 900.
pub enum CompactionMode {
  Text
  Byte
  Numeric
} derive(Eq, Debug)

///|
/// Errors raised by this package.
///
/// Every failure mode is a distinct variant so callers can react to them
/// instead of matching on message text.
pub suberror Pdf417Error {
  /// A parameter is out of range: `(name, value, expected)`.
  InvalidParameter(String, Int, String)
  /// The length descriptor exceeded `max_codewords`: `(got, limit)`.
  DataTooLong(Int, Int)
  /// The requested geometry cannot hold the data: `(field, value, why)`.
  SizeOutOfRange(String, Int, String)
  /// The module matrix could not be decoded: `(reason)`.
  DecodeFailed(String)
}

///|
/// Human-readable message for an error.
pub fn Pdf417Error::message(self : Pdf417Error) -> String {
  match self {
    InvalidParameter(name, value, expected) =>
      "invalid parameter " +
      name +
      ": " +
      value.to_string() +
      " (expected " +
      expected +
      ")"
    DataTooLong(got, limit) =>
      "data too long: length descriptor is " +
      got.to_string() +
      ", the maximum is " +
      limit.to_string()
    SizeOutOfRange(field, value, why) =>
      "symbol size out of range: " +
      field +
      " = " +
      value.to_string() +
      " (" +
      why +
      ")"
    DecodeFailed(reason) => "decode failed: " + reason
  }
}

///|
/// Geometry and error correction settings for encoding.
///
/// These change the *symbol*: how many codewords sit on a row and how many
/// error correction codewords are appended. Rendering knobs live in
/// `RenderOptions` instead.
pub struct EncodeOptions {
  /// Data codewords per row, 1..30.
  columns : Int
  /// Error correction level, 0..8. Level `k` adds `2^(k+1)` codewords.
  ec_level : Int
}

///|
/// The defaults used by most real-world symbols: 6 columns, level 2.
pub fn EncodeOptions::default() -> EncodeOptions {
  { columns: 6, ec_level: 2 }
}

///|
/// Builds encoding options.
pub fn EncodeOptions::new(columns : Int, ec_level : Int) -> EncodeOptions {
  { columns, ec_level }
}

///|
/// Data codewords per row.
pub fn EncodeOptions::columns(self : EncodeOptions) -> Int {
  self.columns
}

///|
/// Error correction level.
pub fn EncodeOptions::ec_level(self : EncodeOptions) -> Int {
  self.ec_level
}

///|
/// A copy with a different column count.
pub fn EncodeOptions::with_columns(
  self : EncodeOptions,
  columns : Int,
) -> EncodeOptions {
  { columns, ec_level: self.ec_level }
}

///|
/// A copy with a different error correction level.
pub fn EncodeOptions::with_ec_level(
  self : EncodeOptions,
  ec_level : Int,
) -> EncodeOptions {
  { columns: self.columns, ec_level }
}

///|
/// How a symbol is drawn. None of these change the module matrix the decoder
/// sees, they only affect the picture.
pub struct RenderOptions {
  /// Width of one module in pixels, >= 1.
  scale : Int
  /// Height of one row in modules, >= 3 per ISO/IEC 15438.
  row_height : Int
  /// Quiet zone around the symbol, in modules.
  quiet_zone : Int
  /// Colour of dark modules.
  dark : String
  /// Colour of light modules and the quiet zone.
  light : String
}

///|
/// Rendering defaults: 3x module scale, 3:1 row aspect, 4-module quiet zone.
pub fn RenderOptions::default() -> RenderOptions {
  { scale: 3, row_height: 3, quiet_zone: 4, dark: "#000000", light: "#ffffff" }
}

///|
/// Builds rendering options.
pub fn RenderOptions::new(
  scale : Int,
  row_height : Int,
  quiet_zone : Int,
  dark : String,
  light : String,
) -> RenderOptions {
  { scale, row_height, quiet_zone, dark, light }
}

///|
/// A copy with a different module scale.
pub fn RenderOptions::with_scale(self : RenderOptions, scale : Int) -> RenderOptions {
  {
    scale,
    row_height: self.row_height,
    quiet_zone: self.quiet_zone,
    dark: self.dark,
    light: self.light,
  }
}

///|
/// A copy with a different row height in modules.
pub fn RenderOptions::with_row_height(
  self : RenderOptions,
  row_height : Int,
) -> RenderOptions {
  {
    scale: self.scale,
    row_height,
    quiet_zone: self.quiet_zone,
    dark: self.dark,
    light: self.light,
  }
}

///|
/// A copy with a different quiet zone.
pub fn RenderOptions::with_quiet_zone(
  self : RenderOptions,
  quiet_zone : Int,
) -> RenderOptions {
  {
    scale: self.scale,
    row_height: self.row_height,
    quiet_zone,
    dark: self.dark,
    light: self.light,
  }
}

///|
/// Module scale in pixels.
pub fn RenderOptions::scale(self : RenderOptions) -> Int {
  self.scale
}

///|
/// Row height in modules.
pub fn RenderOptions::row_height(self : RenderOptions) -> Int {
  self.row_height
}

///|
/// Quiet zone in modules.
pub fn RenderOptions::quiet_zone(self : RenderOptions) -> Int {
  self.quiet_zone
}

///|
/// Dark module colour.
pub fn RenderOptions::dark(self : RenderOptions) -> String {
  self.dark
}

///|
/// Light module colour.
pub fn RenderOptions::light(self : RenderOptions) -> String {
  self.light
}

///|
/// Validates `RenderOptions`.
pub fn RenderOptions::validate(self : RenderOptions) -> Unit raise Pdf417Error {
  if self.scale < 1 {
    raise InvalidParameter("scale", self.scale, ">= 1")
  }
  if self.row_height < 3 {
    raise InvalidParameter("row_height", self.row_height, ">= 3")
  }
  if self.quiet_zone < 0 {
    raise InvalidParameter("quiet_zone", self.quiet_zone, ">= 0")
  }
}

///|
/// Minimum number of rows in a symbol.
pub let min_rows : Int = 3

///|
/// Maximum number of rows in a symbol.
pub let max_rows : Int = 90

///|
/// Minimum number of data columns in a symbol.
pub let min_columns : Int = 1

///|
/// Maximum number of data columns in a symbol.
pub let max_columns : Int = 30

///|
/// Maximum error correction level.
pub let max_ec_level : Int = 8

///|
/// Validates `EncodeOptions`, raising on anything out of range.
pub fn EncodeOptions::validate(self : EncodeOptions) -> Unit raise Pdf417Error {
  if self.columns < min_columns || self.columns > max_columns {
    raise InvalidParameter(
      "columns",
      self.columns,
      "\{min_columns}..\{max_columns}",
    )
  }
  if self.ec_level < 0 || self.ec_level > max_ec_level {
    raise InvalidParameter("ec_level", self.ec_level, "0..\{max_ec_level}")
  }
}

///|
/// A two-dimensional matrix of black/white modules.
///
/// Row 0 is the top row. `true` means a dark module (a bar).
pub struct BitMatrix {
  width : Int
  height : Int
  bits : FixedArray[Bool]
}

///|
/// Creates an all-white matrix.
pub fn BitMatrix::new(width : Int, height : Int) -> BitMatrix {
  { width, height, bits: FixedArray::make(width * height, false) }
}

///|
/// Width of the matrix in modules.
pub fn BitMatrix::width(self : BitMatrix) -> Int {
  self.width
}

///|
/// Height of the matrix in modules.
pub fn BitMatrix::height(self : BitMatrix) -> Int {
  self.height
}

///|
/// Reads a module. Out-of-range coordinates read as white rather than
/// panicking, which keeps the renderers simple.
pub fn BitMatrix::get(self : BitMatrix, x : Int, y : Int) -> Bool {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    false
  } else {
    self.bits[y * self.width + x]
  }
}

///|
/// Writes a module.
pub fn BitMatrix::set(self : BitMatrix, x : Int, y : Int, value : Bool) -> Unit {
  if x >= 0 && y >= 0 && x < self.width && y < self.height {
    self.bits[y * self.width + x] = value
  }
}

///|
/// Sets a horizontal run of modules starting at `x`.
pub fn BitMatrix::set_run(
  self : BitMatrix,
  x : Int,
  y : Int,
  length : Int,
  value : Bool,
) -> Unit {
  for i = 0; i < length; i = i + 1 {
    self.set(x + i, y, value)
  }
}

///|
/// Renders the matrix as lines of text using two characters per module.
pub fn BitMatrix::to_text(self : BitMatrix, dark : String, light : String) -> String {
  let sb = StringBuilder()
  for y = 0; y < self.height; y = y + 1 {
    for x = 0; x < self.width; x = x + 1 {
      if self.get(x, y) {
        sb.write_string(dark)
      } else {
        sb.write_string(light)
      }
    }
    if y + 1 < self.height {
      sb.write_char('\n')
    }
  }
  sb.to_string()
}

///|
/// Counts dark modules. Used by tests as a cheap structural checksum.
pub fn BitMatrix::dark_count(self : BitMatrix) -> Int {
  let mut n = 0
  for i = 0; i < self.bits.length(); i = i + 1 {
    if self.bits[i] {
      n = n + 1
    }
  }
  n
}

///|
/// A rolling hash of the whole module grid: `h = h * 131 + bit (mod 1e9+7)`,
/// scanning row-major, one step per module.
///
/// Small enough to be worth writing, and wide enough that a layout bug
/// anywhere in the symbol changes it.
///
/// `Int64` is used so the running product cannot overflow: `h` stays below
/// `1e9 + 7` and the factor is 131.
pub fn BitMatrix::digest(self : BitMatrix) -> Int64 {
  let mut h : Int64 = 0L
  for y = 0; y < self.height; y = y + 1 {
    for x = 0; x < self.width; x = x + 1 {
      let bit : Int64 = if self.get(x, y) { 1L } else { 0L }
      h = (h * 131L + bit) % 1000000007L
    }
  }
  h
}
