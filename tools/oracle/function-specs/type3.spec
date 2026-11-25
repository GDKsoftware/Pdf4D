# Type 3 (stitching) functions of type 2 functions. See docs/golden-format.md.
case: two-functions
type: 3
domain: 0 1
range: 0 1
bounds: 0.5
encode: 0 1 0 1
sub2: 0 | 1 | 1
sub2: 1 | 0 | 1
in: 0
in: 0.25
in: 0.5
in: 0.75
in: 1
in: 2
case: one-function
type: 3
domain: 0 1
bounds:
encode: 0 1
sub2: 0 | 1 | 1
in: 0.3
case: one-function-ignores-the-bounds
type: 3
domain: 0 1
bounds: 0.5
encode: 0 1 0 1
sub2: 0 | 1 | 1
in: 0.25
case: three-functions
type: 3
domain: 0 3
bounds: 1 2
encode: 0 1 0 1 1 0
sub2: 0 | 1 | 1
sub2: 1 | 2 | 1
sub2: 5 | 0 | 1
in: 0
in: 1
in: 1.5
in: 2
in: 2.5
in: 3
case: bound-at-the-start-of-the-domain
type: 3
domain: 0 1
range: 0 1
bounds: 0
encode: 0 1 0 1
sub2: 0 | 1 | 1
sub2: 1 | 0 | 1
in: 0
in: 0.5
case: bounds-out-of-order
type: 3
domain: 0 1
bounds: 0.7 0.3
encode: 0 1 0 1 0 1
sub2: 0 | 1 | 1
sub2: 1 | 0 | 1
sub2: 2 | 3 | 1
in: 0.5
in: 0.2
in: 0.8
case: reversed-encode
type: 3
domain: 0 1
bounds: 0.5
encode: 1 0 0 1
sub2: 0 | 1 | 1
sub2: 1 | 0 | 1
in: 0.25
case: range-clips-the-result
type: 3
domain: 0 1
bounds: 0.5
encode: 0 1 0 1
range: 0 0.4
sub2: 0 | 1 | 1
sub2: 1 | 0 | 1
in: 0.25
in: 0.75
case: domain-of-zero-width
type: 3
domain: 0 0
bounds:
encode: 5 7
sub2: 0 | 1 | 1
in: 0
