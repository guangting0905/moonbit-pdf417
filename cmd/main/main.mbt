// pdf417 — command line front end.
//
// Deliberately argument-in / stdout-out: no file system, no `extern`, no
// target restrictions. That keeps `moon build --target all` green and lets the
// same binary be driven from a shell, from CI, or from a test script.
// Redirect to a file if you want one.

///|
fn usage() -> Unit {
  let text = #|pdf417 — PDF417 (ISO/IEC 15438) encoder / decoder in pure MoonBit
  #|
  #|usage:
  #|  pdf417 encode <payload> [--columns N] [--ec-level N] [--format F]
  #|  pdf417 decode --matrix "<rows joined by ;>"
  #|  pdf417 info   <payload> [--columns N] [--ec-level N]
  #|  pdf417 selfcheck
  #|
  #|payload:
  #|  text:<string>        literal text, UTF-8 encoded
  #|  hex:<hexdigits>      raw bytes, two hex digits per byte
  #|  <bare string>        treated as text
  #|
  #|options:
  #|  --columns N          data codewords per row, 1..30    (default 6)
  #|  --ec-level N         error correction level, 0..8     (default 2)
  #|  --format F           text | pbm | svg | codewords | json
  #|                                                        (default text)
  #|  --scale N            render: pixels per module        (default 3)
  #|  --row-height N       render: modules per row, >= 3     (default 3)
  #|  --quiet-zone N       render: quiet zone in modules     (default 4)
  #|
  #|decode input uses `1`/`0` or `#`/`.` cells, one row per `;`-separated
  #|group - the same shape `--format text` prints, so the two compose:
  #|
  #|  pdf417 encode text:hello --format text
  #|
  println(text)
}

///|
fn parse_payload(spec : String) -> Array[Int] raise @pdf417.Pdf417Error {
  if spec.has_prefix("text:") {
    @pdf417.utf8_bytes(spec[5:])
  } else if spec.has_prefix("hex:") {
    @pdf417.bytes_from_hex(spec[4:])
  } else {
    @pdf417.utf8_bytes(spec)
  }
}

///|
/// Parses a decimal integer, returning `None` rather than raising: the CLI
/// turns a bad flag into a usage message, not an error value.
fn parse_int(spec : String) -> Int? {
  try @string.parse_int(spec) catch {
    _ => None
  } noraise {
    v => Some(v)
  }
}

///|
/// Reads the value of a `--flag N` pair, or reports the flag as malformed.
fn int_flag(spec : String, name : String) -> Int? {
  match parse_int(spec) {
    Some(v) => Some(v)
    None => {
      println("pdf417: \{name} expects an integer, got \"\{spec}\"")
      None
    }
  }
}

///|
/// Index of the sub-command in `argv`.
///
/// The js backend prepends the script path to `process.argv` and other
/// backends may prepend nothing, so the command is located by name rather than
/// by a fixed offset.
fn command_index(argv : Array[String]) -> Int {
  for i = 0; i < argv.length(); i = i + 1 {
    let a = argv[i]
    if a == "encode" || a == "decode" || a == "info" || a == "selfcheck" ||
      a == "help" {
      return i
    }
  }
  -1
}

///|
/// Parses a module matrix written as rows joined by `;`, where each cell is
/// `1`/`0` or `#`/`.`. Rows are separated by `;` so the whole symbol survives
/// as a single shell argument; `columns` is inferred from the row length.
fn parse_matrix(spec : String) -> @pdf417.BitMatrix? {
  let rows : Array[StringView] = []
  for part in spec.split(";") {
    if part.length() > 0 {
      rows.push(part)
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
    let chars = rows[y].to_array()
    for x = 0; x < width; x = x + 1 {
      let c = chars[x]
      if c == '1' || c == '#' {
        m.set(x, y, true)
      }
    }
  }
  Some(m)
}

///|
fn decode_command(spec : String) -> Unit {
  match parse_matrix(spec) {
    None => println("pdf417: --matrix needs rows of equal length separated by ';'")
    Some(m) =>
      try @pdf417.decode_matrix(m) catch {
        e => println("pdf417: \{e.message()}")
      } noraise {
        decoded => {
          let report = decoded.report()
          println("payload        : \{decoded.payload()}")
          println("bytes          : \{@pdf417.to_hex(decoded.bytes())}")
          println("rows x columns : \{report.rows()} x \{report.columns()}")
          println("ec level       : \{report.ec_level()}")
          println("length descr.  : \{report.length_descriptor()}")
          println(
            "indicators     : rows=\{report.indicator_rows()} columns=\{report.indicator_columns()} ec=\{report.indicator_ec_level()}",
          )
          println("unmatched      : \{report.unmatched_characters()}")
          println("corrected      : \{report.corrected_errors()}")
        }
      }
  }
}

///|
fn main {
  let argv = @env.args()
  let base = command_index(argv)
  if base < 0 {
    usage()
    return
  }
  let command = argv[base]
  if command == "selfcheck" {
    selfcheck()
    return
  }
  if command == "help" {
    usage()
    return
  }
  let mut payload = ""
  let mut matrix = ""
  let mut columns = 6
  let mut ec_level = 2
  let mut format = "text"
  let mut scale = 3
  let mut row_height = 3
  let mut quiet_zone = 4
  let mut i = base + 1
  let mut bad_flag = false
  while i < argv.length() && !bad_flag {
    let a = argv[i]
    let has_next = i + 1 < argv.length()
    if has_next && a == "--columns" {
      match int_flag(argv[i + 1], "columns") {
        Some(v) => columns = v
        None => bad_flag = true
      }
      i = i + 2
    } else if has_next && a == "--ec-level" {
      match int_flag(argv[i + 1], "ec-level") {
        Some(v) => ec_level = v
        None => bad_flag = true
      }
      i = i + 2
    } else if has_next && a == "--format" {
      format = argv[i + 1]
      i = i + 2
    } else if has_next && a == "--matrix" {
      matrix = argv[i + 1]
      i = i + 2
    } else if has_next && a == "--scale" {
      match int_flag(argv[i + 1], "scale") {
        Some(v) => scale = v
        None => bad_flag = true
      }
      i = i + 2
    } else if has_next && a == "--row-height" {
      match int_flag(argv[i + 1], "row-height") {
        Some(v) => row_height = v
        None => bad_flag = true
      }
      i = i + 2
    } else if has_next && a == "--quiet-zone" {
      match int_flag(argv[i + 1], "quiet-zone") {
        Some(v) => quiet_zone = v
        None => bad_flag = true
      }
      i = i + 2
    } else if payload == "" {
      payload = a
      i = i + 1
    } else {
      println("pdf417: unrecognised argument \"\{a}\"")
      bad_flag = true
    }
  }
  if bad_flag {
    return
  }
  if command == "decode" {
    if matrix == "" {
      println("pdf417: decode needs --matrix \"<rows joined by ;>\"")
      return
    }
    decode_command(matrix)
    return
  }
  if payload == "" {
    usage()
    return
  }
  let data = try! parse_payload(payload)
  let options = @pdf417.EncodeOptions::new(columns, ec_level)
  let render = @pdf417.RenderOptions::default()
    .with_scale(scale)
    .with_row_height(row_height)
    .with_quiet_zone(quiet_zone)
  if command == "info" {
    info_command(data, options)
  } else {
    encode_command(data, options, render, format)
  }
}

///|
fn encode_command(
  data : Array[Int],
  options : @pdf417.EncodeOptions,
  render : @pdf417.RenderOptions,
  format : String,
) -> Unit {
  let symbol = try! @pdf417.encode_bytes(data, options)
  match format {
    // One character per module so the output feeds straight back into
    // `decode --matrix`.
    "text" => println(symbol.matrix().to_text("#", "."))
    "pbm" => println(@pdf417.to_pbm(symbol.matrix(), render))
    "svg" => println(@pdf417.to_svg(symbol.matrix(), render))
    "codewords" => {
      let sb = StringBuilder()
      for w in symbol.codewords() {
        sb.write_string(w.to_string())
        sb.write_char(' ')
      }
      println(sb.to_string())
    }
    "json" => println(symbol_json(symbol))
    _ => println("pdf417: unknown format \"\{format}\"")
  }
}

///|
fn symbol_json(symbol : @pdf417.Symbol) -> String {
  let sb = StringBuilder(size_hint=2048)
  sb.write_string("{\"rows\":")
  sb.write_string(symbol.rows().to_string())
  sb.write_string(",\"columns\":")
  sb.write_string(symbol.columns().to_string())
  sb.write_string(",\"ec_level\":")
  sb.write_string(symbol.ec_level().to_string())
  sb.write_string(",\"width\":")
  sb.write_string(symbol.matrix().width().to_string())
  sb.write_string(",\"height\":")
  sb.write_string(symbol.matrix().height().to_string())
  sb.write_string(",\"dark\":")
  sb.write_string(symbol.matrix().dark_count().to_string())
  sb.write_string(",\"digest\":")
  sb.write_string(symbol.matrix().digest().to_string())
  sb.write_string(",\"codewords\":[")
  let words = symbol.codewords()
  for i = 0; i < words.length(); i = i + 1 {
    if i > 0 {
      sb.write_char(',')
    }
    sb.write_string(words[i].to_string())
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
fn info_command(data : Array[Int], options : @pdf417.EncodeOptions) -> Unit {
  let words = @pdf417.compact(data)
  let symbol = try! @pdf417.encode_bytes(data, options)
  println("payload bytes  : \{data.length()}")
  println("mode segments  : \{segment_summary(data)}")
  println("data codewords : \{words.length()}")
  println("ec codewords   : \{try! symbol.ec_codeword_count()}")
  println("rows           : \{symbol.rows()}")
  println("columns        : \{symbol.columns()}")
  println(
    "modules        : \{symbol.matrix().width()} x \{symbol.matrix().height()}",
  )
  println("dark modules   : \{symbol.matrix().dark_count()}")
}

///|
fn segment_summary(data : Array[Int]) -> String {
  let sb = StringBuilder()
  let mut i = 0
  let mut first = true
  while i < data.length() {
    let mode = @pdf417.classify(data[i])
    let mut n = 0
    while i < data.length() && @pdf417.classify(data[i]) == mode {
      n = n + 1
      i = i + 1
    }
    if !first {
      sb.write_string(", ")
    }
    first = false
    sb.write_string(
      match mode {
        @pdf417.Text => "text"
        @pdf417.Byte => "byte"
        @pdf417.Numeric => "numeric"
      },
    )
    sb.write_string(":")
    sb.write_string(n.to_string())
  }
  sb.to_string()
}

///|
/// Encodes a small corpus, decodes each symbol back, and compares. This is the
/// every-build smoke test: it exercises the whole loop, not just the encoder.
fn selfcheck() -> Unit {
  let corpus : Array[(String, Array[Int])] = [
    ("empty", []),
    ("ascii", @pdf417.utf8_bytes("HELLO WORLD")),
    ("digits", @pdf417.utf8_bytes("12345678901234567890")),
    ("mixed", @pdf417.utf8_bytes("Order 100000000000 for MoonBit")),
    ("short-digits", @pdf417.utf8_bytes("ab12cd")),
    ("cjk", @pdf417.utf8_bytes("你好，世界")),
  ]
  // Three columns keeps even the empty payload inside the 3..90 row range.
  let options = @pdf417.EncodeOptions::new(3, 2)
  let mut failures = 0
  for entry in corpus {
    let (name, data) = entry
    try @pdf417.encode_bytes(data, options) catch {
      _ => {
        failures = failures + 1
        println("\{name}: FAILED to build a symbol")
      }
    } noraise {
      symbol =>
        try @pdf417.decode_matrix(symbol.matrix()) catch {
          _ => {
            failures = failures + 1
            println("\{name}: FAILED to decode the symbol back")
          }
        } noraise {
          decoded =>
            if decoded.bytes() == data {
              println(
                "\{name}: rows=\{symbol.rows()} modules=\{symbol.matrix().width()}x\{symbol.matrix().height()} corrected=\{decoded.report().corrected_errors()} round trip OK",
              )
            } else {
              failures = failures + 1
              println("\{name}: ROUND TRIP MISMATCH")
            }
        }
    }
  }
  println("selfcheck: \{corpus.length() - failures}/\{corpus.length()} round trips OK")
}
