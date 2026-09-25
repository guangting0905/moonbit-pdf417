// pdf417 in the browser.
//
// The library is compiled to JavaScript and publishes one function on
// `globalThis`, so the page needs no bundler and no build step beyond
// `moon build --target js`. See web/README.md for how the page is assembled.

///|
/// Publishes the API for `web/index.html` to call.
///
/// A single string-in / string-out function on purpose: passing structured
/// values across the FFI boundary is where browser demos usually grow a
/// marshalling layer nobody wants to maintain.
extern "js" fn js_publish(
  api : (String, String, String, String) -> String,
) -> Unit =
  #| (api) => {
  #|   globalThis.pdf417 = { run: api };
  #|   globalThis.dispatchEvent(new Event("pdf417-ready"));
  #| }

///|
fn main {
  js_publish(run)
}

///|
/// `kind`    - "text" or "hex", how to read the payload
/// `payload` - the payload, or a matrix when `format` is "decode"
/// `options` - "columns,ecLevel"
/// `format`  - text | pbm | svg | codewords | json | decode
///
/// Returns the rendered result, or a string starting with "error: ".
fn run(
  kind : String,
  payload : String,
  options : String,
  format : String,
) -> String {
  if format == "decode" {
    return decode(payload)
  }
  let columns = option_at(options, 0)
  let ec_level = option_at(options, 1)
  let mut data : Array[Int] = []
  try parse_payload(kind, payload) catch {
    e => return "error: " + e.message()
  } noraise {
    bytes => data = bytes
  }
  let mut result = ""
  try @pdf417.encode_bytes(data, @pdf417.EncodeOptions::new(columns, ec_level)) catch {
    e => result = "error: " + e.message()
  } noraise {
    symbol => result = render_symbol(symbol, format)
  }
  result
}

///|
fn render_symbol(symbol : @pdf417.Symbol, format : String) -> String {
  match format {
    "text" => symbol.matrix().to_text("#", ".")
    "pbm" => @pdf417.to_pbm(symbol.matrix(), @pdf417.RenderOptions::default())
    "svg" => @pdf417.to_svg(symbol.matrix(), @pdf417.RenderOptions::default())
    "codewords" => codeword_list(symbol)
    "json" => summary(symbol)
    _ => "error: unknown format " + format
  }
}

///|
fn parse_payload(kind : String, payload : String) -> Array[Int] raise @pdf417.Pdf417Error {
  if kind == "hex" {
    @pdf417.bytes_from_hex(payload)
  } else {
    @pdf417.utf8_bytes(payload)
  }
}

///|
fn decode(payload : String) -> String {
  let mut result = "error: expected rows of equal length separated by newlines"
  match parse_matrix(payload) {
    None => ()
    Some(m) =>
      try @pdf417.decode_matrix(m) catch {
        e => result = "error: " + e.message()
      } noraise {
        decoded => result = decode_report(decoded)
      }
  }
  result
}

///|
fn decode_report(decoded : @pdf417.Decoded) -> String {
  let report = decoded.report()
  "payload    : " + decoded.payload() + "\n" +
  "bytes      : " + @pdf417.to_hex(decoded.bytes()) + "\n" +
  "geometry   : " + report.rows().to_string() + " rows x " +
  report.columns().to_string() + " columns\n" +
  "ec level   : " + report.ec_level().to_string() + "\n" +
  "indicators : rows=" + report.indicator_rows().to_string() +
  " columns=" + report.indicator_columns().to_string() +
  " ec=" + report.indicator_ec_level().to_string() + "\n" +
  "unmatched  : " + report.unmatched_characters().to_string() + "\n" +
  "corrected  : " + report.corrected_errors().to_string()
}

///|
fn codeword_list(symbol : @pdf417.Symbol) -> String {
  let sb = StringBuilder(size_hint=1024)
  let words = symbol.codewords()
  for i = 0; i < words.length(); i = i + 1 {
    if i > 0 {
      sb.write_char(' ')
    }
    sb.write_string(words[i].to_string())
  }
  sb.to_string()
}

///|
fn summary(symbol : @pdf417.Symbol) -> String {
  let m = symbol.matrix()
  let ec = try! symbol.ec_codeword_count()
  "rows      : " + symbol.rows().to_string() + "\n" +
  "columns   : " + symbol.columns().to_string() + "\n" +
  "ec level  : " + symbol.ec_level().to_string() + "\n" +
  "codewords : " + symbol.data_codeword_count().to_string() + " data + " +
  symbol.padding_codeword_count().to_string() + " padding + " +
  ec.to_string() + " ec\n" +
  "modules   : " + m.width().to_string() + " x " + m.height().to_string() + "\n" +
  "dark      : " + m.dark_count().to_string()
}

///|
fn option_at(options : String, index : Int) -> Int {
  let parts = options.split(",").to_array()
  if index >= parts.length() {
    abort("option " + index.to_string() + " is missing from " + options)
  }
  try! @string.parse_int(parts[index].trim())
}

///|
/// Parses rows of `#`/`.` or `1`/`0` separated by newlines.
fn parse_matrix(spec : String) -> @pdf417.BitMatrix? {
  let rows : Array[Array[Char]] = []
  for line in spec.split("\n") {
    let chars = line.trim().to_array()
    if chars.length() > 0 {
      rows.push(chars)
    }
  }
  if rows.length() == 0 {
    return None
  }
  let width = rows[0].length()
  for r in rows {
    if r.length() != width {
      return None
    }
  }
  let m = @pdf417.BitMatrix::new(width, rows.length())
  for y = 0; y < rows.length(); y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      let c = rows[y][x]
      if c == '#' || c == '1' {
        m.set(x, y, true)
      }
    }
  }
  Some(m)
}
