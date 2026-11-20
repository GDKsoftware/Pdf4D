# Type 0 (sampled) functions. See docs/golden-format.md.
case: linear
type: 0
domain: 0 1
range: 0 1
size: 2
bps: 8
samples: 00FF
in: 0
in: 0.5
in: 1
in: 2
in: -1
in: NaN
case: short-data-gives-zeros
type: 0
domain: 0 1
range: 0 1
size: 4
bps: 8
samples: 00FF
in: 0.5
in: 0.9
case: two-inputs
type: 0
domain: 0 1 0 1
range: 0 1
size: 2 2
bps: 8
samples: 00 FF 80 20
in: 0.5 0.5
in: 1 0
in: 0 1
in: 1 1
in: 0.25 0.75
case: three-inputs
type: 0
domain: 0 1 0 1 0 1
range: 0 1
size: 2 2 2
bps: 8
samples: 00 20 40 60 80 A0 C0 E0
in: 0.5 0.5 0.5
in: 1 0 1
in: 0.2 0.4 0.9
case: bps12-cut-in-the-third-sample
type: 0
domain: 0 1
range: 0 1
size: 3
bps: 12
samples: 000 800 FFF
in: 0.25
in: 0.75
case: bps1
type: 0
domain: 0 1
range: 0 1
size: 8
bps: 1
samples: A5
in: 0
in: 0.3
in: 0.5
case: bps3
type: 0
domain: 0 1
range: 0 1
size: 2
bps: 3
samples: 1C
in: 0.5
case: bps4
type: 0
domain: 0 1
range: 0 1
size: 3
bps: 4
samples: 0F F0
in: 0.5
case: bps16
type: 0
domain: 0 1
range: 0 1
size: 2
bps: 16
samples: 0000 FFFF
in: 0.3
case: bps24
type: 0
domain: 0 1
range: 0 1
size: 2
bps: 24
samples: 000000 FFFFFF
in: 0.3
case: bps32-wraps-to-negative
type: 0
domain: 0 1
range: 0 1
size: 2
bps: 32
samples: 00000000 FFFFFFFF
in: 0.3
in: 1
case: two-outputs
type: 0
domain: 0 1
range: 0 1 0 1
size: 2
bps: 8
samples: 00 FF FF 00
in: 0.5
in: 1
case: decode-reversed
type: 0
domain: 0 1
range: 0 1
size: 2
bps: 8
decode: 1 0
samples: 00FF
in: 0.25
case: decode-outside-the-range
type: 0
domain: 0 1
range: 0 1
size: 2
bps: 8
decode: -1 2
samples: 00FF
in: 0.25
in: 1
case: range-narrower-than-the-samples
type: 0
domain: 0 1
range: 0.2 0.6
size: 2
bps: 8
samples: 00FF
in: 0.1
in: 0.9
case: encode-reversed
type: 0
domain: 0 1
range: 0 1
size: 3
bps: 8
encode: 2 0
samples: 00 80 FF
in: 0.25
case: encode-outside-the-table
type: 0
domain: 0 1
range: 0 1
size: 3
bps: 8
encode: -5 7
samples: 00 80 FF
in: 0.5
in: 0
case: encode-of-zero-width
type: 0
domain: 0 1
range: 0 1
size: 2
bps: 8
encode: 1 1
samples: 00FF
in: 0.5
case: domain-of-zero-width
type: 0
domain: 0 0
range: 0 1
size: 2
bps: 8
samples: 00FF
in: 0
in: 1
case: size-one
type: 0
domain: 0 1
range: 0 1
size: 1
bps: 8
samples: 80
in: 0.5
