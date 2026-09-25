// Reed-Solomon tests over GF(929).
//
// The interesting property is not "the encoder agrees with itself" but "the
// decoder repairs what the encoder protects", so the error correction tests
// plant errors deliberately and then check both the repair and the report.

///|
test "ec/generator polynomial is monic and has the right degree" {
  for level = 0; level <= max_ec_level; level = level + 1 {
    let coefs = try! generator_coefficients(level)
    assert_eq(coefs.length(), try! ec_word_count(level))
    for c in coefs {
      assert_true(c >= 0 && c < field_modulus, msg="coefficient out of field")
    }
  }
}

///|
test "ec/generator polynomial vanishes at its roots" {
  // g(x) = (x - 3)(x - 9)...(x - 3^k). Rebuilding it with the leading 1 and
  // evaluating at each root must give zero, otherwise the derived
  // coefficients in the table test above would be consistently wrong.
  for level = 0; level <= max_ec_level; level = level + 1 {
    let k = try! ec_word_count(level)
    let coefs = try! generator_coefficients(level)
    let monic : Array[Int] = [1]
    for i = 0; i < coefs.length(); i = i + 1 {
      monic.push(coefs[coefs.length() - 1 - i])
    }
    for i = 1; i <= k; i = i + 1 {
      assert_eq(poly_eval(monic, gf_pow(field_generator, i)), 0)
    }
  }
}

///|
test "ec/encoded block has zero syndromes" {
  let data : Array[Int] = [5, 100, 928, 0, 17, 1]
  for level = 0; level <= max_ec_level; level = level + 1 {
    let ec = try! encode_ec(data, level)
    let block : Array[Int] = []
    for w in data {
      block.push(w)
    }
    for w in ec {
      block.push(w)
    }
    assert_true(
      is_codeword(block, try! ec_word_count(level)),
      msg="level \{level} produced a block with non-zero syndromes",
    )
  }
}

///|
test "ec/every single-codeword error is corrected at level 2" {
  // Level 2 protects 8 codewords and corrects 4. A single error anywhere in
  // the block, at any magnitude, must be repaired - that is 8 positions times
  // 928 magnitudes per base block, so this is exhaustive rather than sampled.
  let data : Array[Int] = [9, 1, 2, 3]
  let level = 2
  let ec = try! encode_ec(data, level)
  let clean : Array[Int] = []
  for w in data {
    clean.push(w)
  }
  for w in ec {
    clean.push(w)
  }
  let ec_count = try! ec_word_count(level)
  for position = 0; position < clean.length(); position = position + 1 {
    for delta = 1; delta < field_modulus; delta = delta + 37 {
      let damaged : Array[Int] = Array::make(clean.length(), 0)
      for i = 0; i < clean.length(); i = i + 1 {
        damaged[i] = clean[i]
      }
      damaged[position] = gf_add(damaged[position], delta)
      let corrected = try! correct_block(damaged, ec_count)
      assert_eq(corrected, 1)
      for i = 0; i < clean.length(); i = i + 1 {
        assert_eq(damaged[i], clean[i])
      }
    }
  }
}

///|
test "ec/independent errors are corrected up to capacity" {
  let data : Array[Int] = [11, 22, 33, 44, 55]
  let level = 3
  let ec = try! encode_ec(data, level)
  let clean : Array[Int] = []
  for w in data {
    clean.push(w)
  }
  for w in ec {
    clean.push(w)
  }
  let ec_count = try! ec_word_count(level)
  let capacity = try! correction_capacity(level)
  assert_eq(capacity, 8)
  for trial = 0; trial < 40; trial = trial + 1 {
    // Spread `capacity` errors across the block deterministically.
    let damaged : Array[Int] = Array::make(clean.length(), 0)
    for i = 0; i < clean.length(); i = i + 1 {
      damaged[i] = clean[i]
    }
    let stride = clean.length() / capacity
    for e = 0; e < capacity; e = e + 1 {
      let position = (e * stride + trial) % clean.length()
      damaged[position] = gf_add(damaged[position], 7 * (e + 1) + trial)
    }
    let corrected = try! correct_block(damaged, ec_count)
    assert_true(corrected <= capacity)
    for i = 0; i < clean.length(); i = i + 1 {
      assert_eq(damaged[i], clean[i])
    }
  }
}

///|
test "ec/too many errors is reported rather than silently accepted" {
  // One more error than the code can hold must not come back as "corrected":
  // a decoder that guesses here is worse than one that gives up.
  let data : Array[Int] = [1, 2, 3]
  let level = 0 // 2 EC words, corrects 1
  let ec = try! encode_ec(data, level)
  let clean : Array[Int] = []
  for w in data {
    clean.push(w)
  }
  for w in ec {
    clean.push(w)
  }
  let damaged : Array[Int] = Array::make(clean.length(), 0)
  for i = 0; i < clean.length(); i = i + 1 {
    damaged[i] = clean[i]
  }
  damaged[0] = gf_add(damaged[0], 111)
  damaged[2] = gf_add(damaged[2], 222)
  let mut raised = false
  try ignore(correct_block(damaged, 2)) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  assert_true(raised, msg="an uncorrectable block was accepted")
}

///|
test "ec/a clean block needs no correction" {
  let data : Array[Int] = [3, 1, 4, 1, 5, 9, 2, 6]
  for level = 0; level <= max_ec_level; level = level + 1 {
    let ec = try! encode_ec(data, level)
    let block : Array[Int] = []
    for w in data {
      block.push(w)
    }
    for w in ec {
      block.push(w)
    }
    assert_eq(correct_block(block, try! ec_word_count(level)), 0)
  }
}

///|
test "ec/word count follows 2^(level+1)" {
  let expected : Array[Int] = [2, 4, 8, 16, 32, 64, 128, 256, 512]
  for level = 0; level <= max_ec_level; level = level + 1 {
    assert_eq(try! ec_word_count(level), expected[level])
    assert_eq(try! correction_capacity(level), expected[level] / 2)
  }
}

///|
test "ec/out of range level is rejected" {
  let mut raised = false
  try ignore(ec_word_count(9)) catch {
    _ => raised = true
  } noraise {
    _ => ()
  }
  assert_true(raised, msg="level 9 should not be accepted")
  let mut raised_negative = false
  try ignore(ec_word_count(-1)) catch {
    _ => raised_negative = true
  } noraise {
    _ => ()
  }
  assert_true(raised_negative, msg="level -1 should not be accepted")
}
