// High-level compaction: bytes in, codewords out.
//
// PDF417 has three compaction modes and a symbol may mix them. This module
// decides *where* to switch, then delegates each run to the matching
// low-level converter.
//
// The segmentation strategy here is deliberately the same greedy one used by
// the reference implementation, so the codewords it produces can be compared
// one-for-one against `tests/vectors` (see cmd/conformance). An optimal
// segmenter lives in `compact_optimal.mbt` and is compared against this one.

///|
/// A run of input bytes that will be compacted with a single mode.
priv struct Chunk {
  mode : CompactionMode
  data : Array[Int]
}

///|
/// True when a byte can be represented by text compaction.
///
/// That is 9 (tab), 10 (LF), 13 (CR) and the printable ASCII range 32..126.
pub fn is_text_byte(c : Int) -> Bool {
  c == 9 || c == 10 || c == 13 || (c >= 32 && c <= 126)
}

///|
/// Decides which mode a byte belongs to when segmenting.
pub fn classify(c : Int) -> CompactionMode {
  if c >= 48 && c <= 57 {
    Numeric
  } else if is_text_byte(c) {
    Text
  } else {
    Byte
  }
}

///|
/// Splits input bytes into runs of one mode each.
fn split_chunks(data : Array[Int]) -> Array[Chunk] {
  let out : Array[Chunk] = []
  let mut i = 0
  while i < data.length() {
    let mode = classify(data[i])
    let run : Array[Int] = []
    while i < data.length() && classify(data[i]) == mode {
      run.push(data[i])
      i = i + 1
    }
    out.push({ mode, data: run })
  }
  out
}

///|
/// Short digit runs are cheaper in text compaction than in numeric
/// compaction, because numeric mode costs a latch code that a 2-digit run
/// cannot earn back. Runs shorter than 13 digits that touch text are
/// re-tagged.
fn demote_short_numeric(chunks : Array[Chunk]) -> Array[Chunk] {
  let out : Array[Chunk] = []
  for i = 0; i < chunks.length(); i = i + 1 {
    let c = chunks[i]
    let short = c.mode == Numeric && c.data.length() < 13
    let touches_text = (i > 0 && chunks[i - 1].mode == Text) ||
      (i + 1 < chunks.length() && chunks[i + 1].mode == Text)
    if short && touches_text {
      out.push({ mode: Text, data: c.data })
    } else {
      out.push(c)
    }
  }
  out
}

///|
/// Merges neighbouring runs that now share a mode. Needed because demoting a
/// numeric run can leave two text runs side by side, and one latch is cheaper
/// than two.
fn merge_adjacent(chunks : Array[Chunk]) -> Array[Chunk] {
  let out : Array[Chunk] = []
  for c in chunks {
    if out.length() > 0 && out[out.length() - 1].mode == c.mode {
      let last = out[out.length() - 1]
      let merged : Array[Int] = []
      for v in last.data {
        merged.push(v)
      }
      for v in c.data {
        merged.push(v)
      }
      out[out.length() - 1] = { mode: last.mode, data: merged }
    } else {
      out.push(c)
    }
  }
  out
}

///|
/// The latch code that switches the decoder into the chunk's mode.
///
/// A byte run whose length is a multiple of 6 uses the alternate latch 924,
/// which also implies "the run ends here" and saves the closing shift.
fn latch_of(chunk : Chunk) -> Int {
  match chunk.mode {
    Text => latch_text
    Numeric => latch_numeric
    Byte => if chunk.data.length() % 6 == 0 { latch_byte_alt } else { latch_byte }
  }
}

///|
/// Converts bytes into high-level codewords, mixing compaction modes.
///
/// The first chunk is text by default, so a leading text run needs no latch;
/// every other chunk is preceded by its latch code.
pub fn compact(data : Array[Int]) -> Array[Int] {
  let chunks = merge_adjacent(demote_short_numeric(split_chunks(data)))
  let out : Array[Int] = []
  for i = 0; i < chunks.length(); i = i + 1 {
    let chunk = chunks[i]
    // Byte and numeric runs always need a latch; a leading text run does not.
    if i > 0 || chunk.mode != Text {
      out.push(latch_of(chunk))
    }
    let words = match chunk.mode {
      Text => compact_text(chunk.data)
      Byte => compact_byte(chunk.data)
      Numeric => compact_numeric(chunk.data)
    }
    for w in words {
      out.push(w)
    }
  }
  out
}

///|
/// Converts a run of text-representable bytes into codewords.
pub fn compact_text(data : Array[Int]) -> Array[Int] {
  let interim = text_interim_codes(data)
  let out : Array[Int] = []
  let mut i = 0
  while i < interim.length() {
    // Two sub-mode values share one codeword, base 30.
    let high = interim[i]
    let low = if i + 1 < interim.length() {
      interim[i + 1]
    } else {
      // Lone trailing character: 29 is a switch code in all four sub-modes,
      // so it carries no data and is the standard's pad value.
      text_padding
    }
    out.push(30 * high + low)
    i = i + 2
  }
  out
}

///|
/// Expands text bytes into a stream of base-30 sub-mode values, inserting
/// sub-mode switch codes as needed.
///
/// Text compaction starts in upper sub-mode.
pub fn text_interim_codes(data : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  let mut submode = submode_upper
  for c in data {
    if c < 0 || c >= 128 {
      abort("text compaction got a byte above 127: \{c}")
    }
    if (text_submode_mask[c] & (1 << submode)) == 0 {
      let previous = submode
      submode = preferred_submode(c)
      for code in switch_codes[previous][submode] {
        out.push(code)
      }
    }
    out.push(text_values[c][submode])
  }
  out
}

///|
/// The sub-mode a character is encoded in when the current one cannot hold it.
///
/// Preference order is lower, upper, mixed, punct: the first is what the
/// reference implementation uses, and matching it keeps the codeword stream
/// comparable.
pub fn preferred_submode(c : Int) -> Int {
  let mask = text_submode_mask[c]
  if (mask & (1 << submode_lower)) != 0 {
    submode_lower
  } else if (mask & (1 << submode_upper)) != 0 {
    submode_upper
  } else if (mask & (1 << submode_mixed)) != 0 {
    submode_mixed
  } else {
    submode_punct
  }
}

///|
/// Converts a base-`source_base` big-endian digit array to base 900.
///
/// Long division by 900, repeated. The quotient stays inside the source
/// base's digit range because each partial remainder is below the source base:
/// for base 256 the largest intermediate is `899*256+255`, and dividing it by
/// 900 yields at most 255.
///
/// Returns big-endian base-900 digits, and an empty array for the value zero -
/// which is what the reference implementation does, and what byte compaction
/// relies on when left-padding.
fn to_base900(source : Array[Int], source_base : Int) -> Array[Int] {
  let digits : Array[Int] = Array::make(source.length(), 0)
  for i = 0; i < source.length(); i = i + 1 {
    digits[i] = source[i]
  }
  let mut zero = true
  for i = 0; i < digits.length(); i = i + 1 {
    if digits[i] != 0 {
      zero = false
    }
  }
  if zero {
    return []
  }
  let remainders : Array[Int] = []
  while !zero {
    let mut rem = 0
    for i = 0; i < digits.length(); i = i + 1 {
      let cur = rem * source_base + digits[i]
      digits[i] = cur / 900
      rem = cur % 900
    }
    remainders.push(rem)
    zero = true
    for i = 0; i < digits.length(); i = i + 1 {
      if digits[i] != 0 {
        zero = false
      }
    }
  }
  let out : Array[Int] = Array::make(remainders.length(), 0)
  for i = 0; i < remainders.length(); i = i + 1 {
    out[i] = remainders[remainders.length() - 1 - i]
  }
  out
}

///|
/// Converts a run of bytes into codewords.
///
/// Exactly 6 bytes become 5 codewords (base 256 -> base 900, left-padded with
/// zeros). A short trailing run of 1..5 bytes is passed through unchanged.
pub fn compact_byte(data : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  let mut i = 0
  while i < data.length() {
    let n = if i + 6 <= data.length() { 6 } else { data.length() - i }
    if n == 6 {
      let group : Array[Int] = Array::make(6, 0)
      for k = 0; k < 6; k = k + 1 {
        group[k] = data[i + k]
      }
      let words = to_base900(group, 256)
      for _k = 0; _k < 5 - words.length(); _k = _k + 1 {
        out.push(0)
      }
      for w in words {
        out.push(w)
      }
    } else {
      for k = 0; k < n; k = k + 1 {
        out.push(data[i + k])
      }
    }
    i = i + 6
  }
  out
}

///|
/// Converts a run of ASCII digits into codewords.
///
/// Groups of up to 44 digits are prefixed with a leading 1 (so leading zeros
/// survive) and converted from base 10 to base 900.
pub fn compact_numeric(data : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  let mut i = 0
  while i < data.length() {
    let n = if i + 44 <= data.length() { 44 } else { data.length() - i }
    let number : Array[Int] = Array::make(n + 1, 0)
    number[0] = 1
    for k = 0; k < n; k = k + 1 {
      let digit = data[i + k] - 48
      if digit < 0 || digit > 9 {
        abort("numeric compaction got a non-digit byte: \{data[i + k]}")
      }
      number[k + 1] = digit
    }
    for w in to_base900(number, 10) {
      out.push(w)
    }
    i = i + 44
  }
  out
}
