// Field arithmetic invariants for GF(929).
//
// Field axioms are cheap to state and catch exactly the class of bug that is
// invisible in a passing encoder: a wrong inverse, a reduction that mishandles
// negatives, an exponentiation that is off by one.

///|
test "gf/reduce handles negatives correctly" {
  assert_eq(gf_reduce(0), 0)
  assert_eq(gf_reduce(929), 0)
  assert_eq(gf_reduce(-1), 928)
  assert_eq(gf_reduce(-929), 0)
  assert_eq(gf_reduce(-930), 928)
  assert_eq(gf_reduce(1858), 0)
}

///|
test "gf/negation is an involution" {
  for a = 0; a < field_modulus; a = a + 1 {
    assert_eq(gf_neg(gf_neg(a)), a)
    assert_eq(gf_add(a, gf_neg(a)), 0)
  }
  assert_eq(gf_neg(0), 0)
}

///|
test "gf/multiplicative identity and commutativity" {
  for a = 0; a < field_modulus; a = a + 1 {
    assert_eq(gf_mul(a, 1), a)
    assert_eq(gf_mul(a, 0), 0)
  }
  for a = 0; a < 200; a = a + 1 {
    for b = 0; b < 200; b = b + 1 {
      assert_eq(gf_mul(a, b), gf_mul(b, a))
      assert_eq(gf_add(a, b), gf_add(b, a))
    }
  }
}

///|
test "gf/multiplication distributes over addition" {
  for a = 0; a < 60; a = a + 1 {
    for b = 0; b < 60; b = b + 1 {
      for c = 0; c < 12; c = c + 1 {
        assert_eq(gf_mul(a, gf_add(b, c)), gf_add(gf_mul(a, b), gf_mul(a, c)))
      }
    }
  }
}

///|
test "gf/every non-zero element has an inverse" {
  for a = 1; a < field_modulus; a = a + 1 {
    assert_eq(gf_mul(a, gf_inv(a)), 1)
  }
}

///|
test "gf/pow matches repeated multiplication" {
  let mut expected = 1
  for e = 0; e <= 40; e = e + 1 {
    assert_eq(gf_pow(field_generator, e), expected)
    expected = gf_mul(expected, field_generator)
  }
  assert_eq(gf_pow(0, 0), 1)
  assert_eq(gf_pow(0, 5), 0)
}

///|
test "gf/three generates a subgroup of order 928" {
  // 3 is the primitive element PDF417 builds its generator polynomial from.
  // Its order must be exactly 928 = 929 - 1, the size of the multiplicative
  // group; a smaller order would make the generator polynomial degenerate.
  assert_eq(gf_pow(field_generator, field_order), 1)
  for d in [2, 4, 8, 16, 29, 32, 58, 116, 232, 464] {
    assert_true(gf_pow(field_generator, d) != 1)
  }
}

///|
test "gf/three is not a root of any lower-order power shortcut" {
  // Powers of 3 must all be distinct inside one period, otherwise the roots
  // of g(x) would collide and the code would lose distance.
  let seen : Array[Bool] = Array::make(field_modulus, false)
  let mut v = 1
  for i = 1; i <= field_order; i = i + 1 {
    v = gf_mul(v, field_generator)
    assert_true(!seen[v], msg="power \{i} of 3 repeats")
    seen[v] = true
  }
  assert_eq(v, 1)
}
