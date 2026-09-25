// Hex encoding and decoding.
//
// Small, but it earns its place: the CLI takes payloads as hex so that binary
// data survives a shell, and the conformance test bed stores expected
// codewords as hex strings.

///|
/// The value of one hexadecimal digit, or raises for anything else.
pub fn hex_digit_value(c : Char) -> Int raise Pdf417Error {
  let v = c.to_int()
  if v >= 48 && v <= 57 {
    v - 48
  } else if v >= 97 && v <= 102 {
    v - 97 + 10
  } else if v >= 65 && v <= 70 {
    v - 65 + 10
  } else {
    raise InvalidParameter(
      "hex digit",
      v,
      "0-9, a-f or A-F",
    )
  }
}

///|
/// Parses a hex string into an array of byte values.
pub fn bytes_from_hex(hex : StringView) -> Array[Int] raise Pdf417Error {
  let chars = hex.to_array()
  if chars.length() % 2 != 0 {
    raise InvalidParameter("hex length", chars.length(), "an even number")
  }
  let out : Array[Int] = []
  let mut i = 0
  while i < chars.length() {
    let hi = hex_digit_value(chars[i])
    let lo = hex_digit_value(chars[i + 1])
    out.push(hi * 16 + lo)
    i = i + 2
  }
  out
}

///|
/// Renders byte values as lowercase hex.
pub fn to_hex(bytes : Array[Int]) -> String {
  let digits = "0123456789abcdef".to_array()
  let sb = StringBuilder()
  for b in bytes {
    sb.write_char(digits[b / 16])
    sb.write_char(digits[b % 16])
  }
  sb.to_string()
}
