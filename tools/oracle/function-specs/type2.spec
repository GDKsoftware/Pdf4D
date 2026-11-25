# Type 2 (exponential interpolation) functions. See docs/golden-format.md.
case: basic
type: 2
domain: 0 1
c0: 0
c1: 1
n: 2
in: 0
in: 0.25
in: 0.5
in: 1
case: input-is-not-clipped-to-the-domain
type: 2
domain: 0 1
c0: 0
c1: 1
n: 2
in: 2
in: -1
case: linear-with-range
type: 2
domain: 0 1
range: 0 0.5
c0: 0 0
c1: 1 2
n: 1
in: 0.1
in: 0.7
case: square-root
type: 2
domain: 0 1
c0: 0
c1: 1
n: 0.5
in: 0
in: 0.25
in: -4
in: NaN
in: Infinity
case: missing-n-is-minus-one
type: 2
domain: 0 1
c0: 0
c1: 1
in: 0.5
in: 0
case: missing-c0-and-c1
type: 2
domain: 0 1
n: 1
in: 0.5
case: more-c0-than-c1
type: 2
domain: 0 1
c0: 0 5 7
c1: 1 6
n: 1
in: 0.5
case: exponent-zero
type: 2
domain: 0 1
c0: 0.2
c1: 0.8
n: 0
in: 0
in: 0.5
case: negative-exponent
type: 2
domain: 0 1
c0: 0
c1: 1
n: -1
in: 0
in: 0.5
case: no-domain
type: 2
c0: 0
c1: 1
n: 1
in: 0.5
case: range-has-fewer-pairs-than-c0
type: 2
domain: 0 1
range: 0 0.5
c0: 0 0
c1: 1 1
n: 1
in: 0.9
case: inverted-range
type: 2
domain: 0 1
range: 1 0
c0: 0
c1: 1
n: 1
in: 0.5
