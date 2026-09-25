// Pattern table integrity and renderer output.
//
// The pattern table is normative data shipped as generated source, so the first
// job is to prove the data itself is well formed. The renderers are then checked
// for the invariants a consumer would rely on: the quiet zone exists, the module
// grid is not resampled, and the three formats agree about the same pixels.

///|
/// A small symbol that fits the three-row minimum at three columns.
fn render_fixture() -> Symbol {
  try! encode_bytes(utf8_bytes("render"), EncodeOptions::new(3, 2))
}

///|
/// Number of significant bits, counting from the leading 1.
fn bit_width(v : UInt) -> Int {
  if v == 0U {
    0
  } else {
    32 - v.clz()
  }
}

///|
test "patterns/table passes its structural audit" {
  // 17 modules, 4 bars and 4 spaces each 1..6 wide, bar/space alternating,
  // and the cluster formula (b1 - b2 + b3 - b4) mod 9 holding per cluster.
  assert_eq(try! check_pattern_table(), 3 * codeword_count)
}

///|
test "patterns/start and stop have the documented widths" {
  assert_eq(bit_width(start_pattern), 17)
  assert_eq(bit_width(stop_pattern), stop_width)
  // A row is the start pattern, two row indicators, `columns` data characters
  // and the 18-module stop pattern.
  assert_eq(symbol_width(1) - stop_width, 17 * 4)
}

///|
test "patterns/cluster index is the row index modulo three" {
  let symbol = render_fixture()
  for row = 0; row < symbol.rows(); row = row + 1 {
    // Read the left indicator back and confirm it decodes in the row's cluster.
    let mut bits : UInt = 0U
    for i = 0; i < 17; i = i + 1 {
      bits = (bits << 1) | (if symbol.matrix().get(17 + i, row) { 1U } else { 0U })
    }
    let (_value, distance) = match_pattern(row % 3, bits)
    assert_eq(distance, 0)
  }
}

///|
test "render/pbm has a header and one sample per rendered module" {
  let symbol = render_fixture()
  let options = RenderOptions::default()
  let (w, h) = rendered_size(symbol.matrix(), options)
  // The quiet zone is 4 modules on every side, at 3 pixels per module.
  assert_eq(w, (symbol.matrix().width() + 2 * 4) * 3)
  assert_eq(h, (symbol.rows() * 3 + 2 * 4) * 3)
  let lines = to_pbm(symbol.matrix(), options).split("\n").to_array()
  assert_eq(lines[0].trim().to_owned(), "P1")
  // Sample lines are `w` characters separated by single spaces, so a trimmed
  // line is 2w - 1 characters long.
  let mut samples = 0
  for i = 2; i < lines.length(); i = i + 1 {
    let n = lines[i].trim().length()
    if n > 0 {
      samples = samples + (n + 1) / 2
    }
  }
  assert_eq(samples, w * h)
}

///|
test "render/quiet zone is light and the first module is a bar" {
  let symbol = render_fixture()
  let options = RenderOptions::default()
  let m = symbol.matrix()
  // Outside the symbol every pixel is light.
  assert_true(!is_dark_pixel(m, options, 0, 0))
  assert_true(!is_dark_pixel(m, options, 1, 1))
  let inset = options.quiet_zone() * options.scale()
  // The start pattern begins with eight bars, so the first module is dark.
  assert_true(is_dark_pixel(m, options, inset, inset))
}

///|
test "render/row height stretches rows without changing the modules" {
  let symbol = render_fixture()
  let flat = RenderOptions::default().with_row_height(3)
  let tall = RenderOptions::default().with_row_height(6)
  let (_, h3) = rendered_size(symbol.matrix(), flat)
  let (_, h6) = rendered_size(symbol.matrix(), tall)
  // The extra height is exactly the extra module rows.
  assert_eq(h6 - h3, symbol.rows() * 3 * 3)
  // Both renderings agree about which modules are dark.
  for row = 0; row < symbol.rows(); row = row + 1 {
    let y3 = (row * 3 + flat.quiet_zone()) * flat.scale()
    let y6 = (row * 6 + tall.quiet_zone()) * tall.scale()
    for x = 0; x < symbol.matrix().width(); x = x + 1 {
      let px = (x + flat.quiet_zone()) * flat.scale()
      assert_eq(
        is_dark_pixel(symbol.matrix(), flat, px, y3),
        is_dark_pixel(symbol.matrix(), tall, px, y6),
      )
    }
  }
}

///|
test "render/svg covers the image and merges horizontal runs" {
  let symbol = render_fixture()
  let options = RenderOptions::default()
  let (w, h) = rendered_size(symbol.matrix(), options)
  let svg = to_svg(symbol.matrix(), options)
  assert_true(svg.has_prefix("<?xml"), msg="not an XML document")
  assert_true(svg.contains("width=\"\{w}\""), msg="missing width attribute")
  assert_true(svg.contains("height=\"\{h}\""), msg="missing height attribute")
  assert_true(svg.contains("</svg>"), msg="unterminated svg")
  assert_true(svg.contains(options.dark()), msg="missing foreground colour")
  // One rect per dark run plus the background rect, and a run is at least one
  // module wide, so the count cannot exceed the number of dark modules.
  let mut rects = 0
  for _part in svg.split("<rect") {
    rects = rects + 1
  }
  assert_true(
    rects - 1 <= symbol.matrix().dark_count() + 1,
    msg="rect count \{rects} is implausible for \{symbol.matrix().dark_count()} dark modules",
  )
}

///|
test "render/text mode is the module grid, one character per module" {
  let symbol = render_fixture()
  let lines = symbol.matrix().to_text("#", ".").split("\n").to_array()
  assert_eq(lines.length(), symbol.rows())
  for line in lines {
    assert_eq(line.length(), symbol.matrix().width())
  }
}

///|
test "render/options are validated" {
  let mut raised = false
  try ignore(RenderOptions::default().with_scale(0).validate()) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  assert_true(raised, msg="scale 0 was accepted")
  let mut raised_rows = false
  try ignore(RenderOptions::default().with_row_height(2).validate()) catch {
    _ => raised_rows = true
  } noraise {
    _ => ()
  }
  assert_true(raised_rows, msg="row height 2 was accepted")
  let mut raised_quiet = false
  try ignore(RenderOptions::default().with_quiet_zone(-1).validate()) catch {
    _ => raised_quiet = true
  } noraise {
    _ => ()
  }
  assert_true(raised_quiet, msg="a negative quiet zone was accepted")
}
