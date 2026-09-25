// Renderers.
//
// Everything here turns a module matrix into text you can pipe somewhere:
// ASCII art for a terminal, ASCII PBM for image tooling, SVG for the web.
// Nothing writes files, so there is no platform dependency and the whole
// package still builds for every target.
//
// Only these three formats ship on purpose. Rasterising to PNG/GIF belongs to
// an image library, not to a barcode codec: `pbm` output here is one line of
// shell away from any of them.

///|
/// Pixel size of a rendered symbol, `(width, height)`.
pub fn rendered_size(m : BitMatrix, options : RenderOptions) -> (Int, Int) {
  let quiet = options.quiet_zone
  let scale = options.scale
  (
    (m.width() + 2 * quiet) * scale,
    (m.height() * options.row_height + 2 * quiet) * scale,
  )
}

///|
/// True when the pixel at `(px, py)` of the rendered image is dark.
///
/// The quiet zone is part of the rendered image but not part of the matrix,
/// so coordinates are translated before the lookup.
pub fn is_dark_pixel(
  m : BitMatrix,
  options : RenderOptions,
  px : Int,
  py : Int,
) -> Bool {
  let scale = options.scale
  let quiet = options.quiet_zone
  let mx = px / scale - quiet
  let my = py / scale - quiet
  if mx < 0 || my < 0 {
    return false
  }
  m.get(mx, my / options.row_height)
}

///|
/// Renders the symbol as ASCII PBM (P1): a plain-text bitmap that Pillow,
/// ImageMagick and friends all read.
pub fn to_pbm(m : BitMatrix, options : RenderOptions) -> String {
  let (w, h) = rendered_size(m, options)
  let sb = StringBuilder(size_hint=w * h / 2)
  sb.write_string("P1\n")
  sb.write_string("\{w} \{h}\n")
  for py = 0; py < h; py = py + 1 {
    for px = 0; px < w; px = px + 1 {
      sb.write_char(if is_dark_pixel(m, options, px, py) { '1' } else { '0' })
      if px + 1 < w {
        sb.write_char(' ')
      }
    }
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
fn write_attr(sb : StringBuilder, name : String, value : String) -> Unit {
  sb.write_string(" ")
  sb.write_string(name)
  sb.write_string("=\"")
  sb.write_string(value)
  sb.write_char('"')
}

///|
/// Renders the symbol as SVG.
///
/// Dark modules are emitted as merged horizontal runs rather than one rect per
/// module: a 6-column symbol comes out several times smaller that way, which
/// matters when the output is pasted into a README.
pub fn to_svg(m : BitMatrix, options : RenderOptions) -> String {
  let (w, h) = rendered_size(m, options)
  let scale = options.scale
  let quiet = options.quiet_zone
  let row_px = options.row_height * scale
  let sb = StringBuilder(size_hint=4096)
  sb.write_string("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  sb.write_string("<svg xmlns=\"http://www.w3.org/2000/svg\"")
  write_attr(sb, "width", w.to_string())
  write_attr(sb, "height", h.to_string())
  write_attr(sb, "viewBox", "0 0 \{w} \{h}")
  write_attr(sb, "shape-rendering", "crispEdges")
  sb.write_string(">\n")
  sb.write_string("<rect width=\"100%\" height=\"100%\"")
  write_attr(sb, "fill", options.light)
  sb.write_string("/>\n<g")
  write_attr(sb, "fill", options.dark)
  sb.write_string(">\n")
  for ry = 0; ry < m.height(); ry = ry + 1 {
    let y = (ry * options.row_height + quiet) * scale
    let mut x = 0
    while x < m.width() {
      if m.get(x, ry) {
        let mut run = 1
        while x + run < m.width() && m.get(x + run, ry) {
          run = run + 1
        }
        sb.write_string("<rect")
        write_attr(sb, "x", ((x + quiet) * scale).to_string())
        write_attr(sb, "y", y.to_string())
        write_attr(sb, "width", (run * scale).to_string())
        write_attr(sb, "height", row_px.to_string())
        sb.write_string("/>\n")
        x = x + run
      } else {
        x = x + 1
      }
    }
  }
  sb.write_string("</g>\n</svg>\n")
  sb.to_string()
}
