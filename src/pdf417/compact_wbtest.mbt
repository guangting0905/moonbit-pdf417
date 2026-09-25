// Compaction tests.
//
// The three modes are easy to get subtly wrong: an off-by-one in the text
// sub-mode switch tables produces a valid-looking symbol that says the wrong
// thing, and the base conversions are exactly where a 32-bit accumulator
// silently wraps.

///|
test "compact/classification covers the three modes" {
  assert_eq(classify(65), Text) // 'A'
  assert_eq(classify(97), Text) // 'a'
  assert_eq(classify(32), Text) // space
  assert_eq(classify(9), Text) // tab
  assert_eq(classify(10), Text) // LF
  assert_eq(classify(13), Text) // CR
  assert_eq(classify(48), Numeric) // '0'
  assert_eq(classify(57), Numeric) // '9'
  assert_eq(classify(0), Byte)
  assert_eq(classify(31), Byte)
  assert_eq(classify(127), Byte)
  assert_eq(classify(200), Byte)
}

///|
test "compact/text packs two characters per codeword" {
  // "AB" is one codeword: 30 * 0 + 1 (both in upper sub-mode).
  assert_eq(compact_text([65, 66]), [1])
  // A single trailing character is padded with 29, the switch code that
  // carries no data in any sub-mode.
  assert_eq(compact_text([65]), [30 * 0 + text_padding])
  assert_eq(compact_text([65, 66, 67]), [1, 30 * 2 + text_padding])
}

///|
test "compact/text switches sub-modes for lower case" {
  // Starting in upper, 'a' forces a switch to lower (code 27), then 'a' is
  // value 0 and 'b' is value 1.
  assert_eq(text_interim_codes([97, 98]), [27, 0, 1])
  assert_eq(compact_text([97, 98]), [30 * 27 + 0, 30 * 1 + text_padding])
}

///|
test "compact/text handles digits through the mixed sub-mode" {
  // '1' lives only in mixed, so upper -> mixed (28) then values 1, 2.
  assert_eq(text_interim_codes([49, 50]), [28, 1, 2])
}

///|
test "compact/byte packs six bytes into five codewords" {
  // Zero bytes convert to five zero codewords, which is the case the left
  // padding exists for.
  assert_eq(compact_byte([0, 0, 0, 0, 0, 0]), [0, 0, 0, 0, 0])
  // Six bytes always become exactly five codewords, and decoding them returns
  // the original bytes. The intermediate values are not worth pinning down;
  // the round trip is the property that matters, and a 48-bit accumulator is
  // exactly where a 32-bit one would wrap silently.
  for seed = 0; seed < 8; seed = seed + 1 {
    let bytes : Array[Int] = Array::make(6, 0)
    for i = 0; i < 6; i = i + 1 {
      bytes[i] = (seed * 41 + i * 17) % 256
    }
    let words = compact_byte(bytes)
    assert_eq(words.length(), 5)
    assert_eq(decode_byte_run_for_test(words, true), bytes)
  }
  // The largest six-byte value is what five base-900 digits can hold.
  let max_bytes : Array[Int] = [255, 255, 255, 255, 255, 255]
  assert_eq(decode_byte_run_for_test(compact_byte(max_bytes), true), max_bytes)
  // A short run is passed through as literal byte values.
  assert_eq(compact_byte([1, 2, 3, 4, 5]), [1, 2, 3, 4, 5])
  // Seven bytes are one sixpack plus one literal.
  assert_eq(compact_byte([0, 0, 0, 0, 0, 0, 7]).length(), 6)
}

///|
test "compact/numeric round trips through base conversion" {
  // Twenty digits become a 21-digit number once the leading 1 is added, which
  // takes seven base-900 codewords.
  let digits : Array[Int] = []
  for c in "12345678901234567890" {
    digits.push(c.to_int())
  }
  let words = compact_numeric(digits)
  assert_eq(words.length(), 7)
  assert_eq(decode_numeric(words), digits)
  // A group whose leading digits are zeros still round trips, because of the
  // marker digit numeric compaction prepends.
  assert_eq(decode_numeric(compact_numeric([48, 48, 48, 55])), [48, 48, 48, 55])
}

///|
test "compact/numeric handles the 44 digit group boundary" {
  // A full group is 44 digits and always takes exactly 15 codewords. 45 digits
  // is a full group plus a one-digit remainder, so the run splits in two.
  let full : Array[Int] = Array::make(44, 55)
  let over : Array[Int] = Array::make(45, 55)
  assert_eq(compact_numeric(full).length(), 15)
  assert_eq(decode_numeric(compact_numeric(full)), full)
  assert_eq(decode_numeric(compact_numeric(over)), over)
  // 41 nines is the longest run that still fits 14 codewords; 42 needs 15.
  // That is what fixes the group size at 44 digits rather than 45.
  assert_eq(compact_numeric(Array::make(43, 57)).length(), 15)
  assert_eq(compact_numeric(Array::make(41, 57)).length(), 14)
  assert_eq(compact_numeric(Array::make(42, 57)).length(), 15)
  // Runs longer than one group still reconstruct in order.
  for n in [88, 89, 130] {
    let digits : Array[Int] = Array::make(n, 54)
    assert_eq(decode_numeric(compact_numeric(digits)), digits)
  }
}

///|
test "compact/short digit runs next to text stay in text mode" {
  // "ab12cd": the two digits are cheaper as text than as a numeric group that
  // would need its own latch. The reference implementation demotes runs under
  // 13 digits that touch text, and matching it is what makes the vectors
  // comparable.
  let bytes : Array[Int] = []
  for c in "ab12cd" {
    bytes.push(c.to_int())
  }
  let words = compact(bytes)
  // No numeric latch anywhere in the stream.
  for w in words {
    assert_true(w != latch_numeric, msg="a numeric latch was emitted")
  }
}

///|
test "compact/long digit runs switch to numeric mode" {
  let bytes : Array[Int] = []
  for c in "ab12345678901234567890cd" {
    bytes.push(c.to_int())
  }
  let words = compact(bytes)
  let mut saw_numeric = false
  for w in words {
    if w == latch_numeric {
      saw_numeric = true
    }
  }
  assert_true(saw_numeric, msg="a long digit run did not use numeric compaction")
}

///|
test "compact/leading byte run always carries a latch" {
  let words = compact([0x80, 0x81, 0x82])
  assert_eq(words[0], latch_byte)
  // Three bytes are a short run, so they stay literal.
  assert_eq(words, [latch_byte, 0x80, 0x81, 0x82])
}

///|
test "compact/a byte run of a multiple of six uses the alternate latch" {
  // 924 tells the decoder that every group is full, which is how a run whose
  // length is a multiple of six is told apart from one with a tail.
  let words = compact([0x80, 0x81, 0x82, 0x83, 0x84, 0x85])
  assert_eq(words[0], latch_byte_alt)
  assert_eq(words.length(), 6)
}

///|
test "compact/a leading text run carries no latch" {
  let words = compact([65, 66])
  assert_true(words[0] != latch_text, msg="a leading text latch was emitted")
  assert_eq(words, [1])
}

///|
test "compact/base conversion survives a 48-bit value" {
  // Six bytes need 48 bits; the accumulator has to be wider than 32 bits.
  let bytes : Array[Int] = [0x80, 0x81, 0x82, 0x83, 0x84, 0x85]
  let words = compact_byte(bytes)
  assert_eq(decode_byte_run_for_test(words, true), bytes)
}

///|
/// Exposes the byte run decoder to this white box test.
fn decode_byte_run_for_test(words : Array[Int], padded : Bool) -> Array[Int] {
  let out : Array[Int] = []
  let _ = decode_byte_run(words, 0, padded, out)
  out
}

///|
test "compact/text sub-mode tables are internally consistent" {
  // Every character in the table must be reachable, and the reverse lookup
  // used by the decoder must agree with the forward one.
  for c = 0; c < 128; c = c + 1 {
    let mask = text_submode_mask[c]
    for submode = 0; submode < submode_count; submode = submode + 1 {
      let present = (mask & (1 << submode)) != 0
      let value = text_values[c][submode]
      assert_true(
        present == (value >= 0),
        msg="mask and value table disagree for \{c} in sub-mode \{submode}",
      )
    }
  }
}
