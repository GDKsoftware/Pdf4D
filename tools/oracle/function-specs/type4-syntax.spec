# The text of type 4 functions: numbers, braces, comments and what PDFBox does with them. See docs/golden-format.md.
case: integer-forms
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 00012 +3 add }
in: 0
case: real-with-point-only-after-digits
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 5. .5 add }
in: 0
case: real-with-minus-and-point
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop -.5 1 add }
in: 0
case: real-with-exponent
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 1.5e2 1 add }
in: 0
case: real-with-upper-case-exponent
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 1.5E2 1 add }
in: 0
case: real-with-exponent-without-digits-after-the-point
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 1.e1 1 add }
in: 0
case: exponent-without-point-is-a-name
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 1e1 1 add }
in: 0
case: plus-in-exponent-is-a-name
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 1.5e+2 1 add }
in: 0
case: hexadecimal-is-a-name
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 0x10 1 add }
in: 0
case: radix-is-a-name
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 16#FF 1 add }
in: 0
case: two-points-is-a-name
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 1.2.3 1 add }
in: 0
case: double-sign-is-a-name
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop --1 1 add }
in: 0
case: lone-sign-is-a-name
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop + 1 add }
in: 0
case: integer-too-large-cannot-be-created
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 2147483648 1 add }
in: 0
case: lone-point-cannot-be-created
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop . 1 add }
in: 0
case: minus-point-cannot-be-created
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop -. 1 add }
in: 0
case: largest-integer-overflows-into-real
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 2147483647 1 add }
in: 0
case: smallest-integer
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop -2147483648 1 add }
in: 0
case: operator-names-are-case-sensitive
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 1 2 ADD }
in: 0
case: comment-to-the-end-of-the-line
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { % a comment\n 2 mul }
in: 1
case: comment-after-the-program
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 1 } % trailing
in: 0
case: braces-need-no-blanks
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop true {1}{2} ifelse }
in: 0
case: program-without-outer-braces
type: 4
domain: 0 1
range: -100000000000 100000000000
code: pop 3
in: 0
case: instructions-after-the-closing-brace
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 3 } 5
in: 0
case: missing-closing-brace
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 3
in: 0
case: extra-closing-brace
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 3 } }
in: 0
case: empty-program
type: 4
domain: 0 1
range: 0 1
code: { }
in: 0.25
case: procedure-left-on-the-stack
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop { 1 } 2 }
in: 0
case: nested-conditionals
type: 4
domain: 0 1
range: 0 10
code: { dup 0.5 gt { dup 0.8 gt { pop 2 } { pop 1 } ifelse } { pop 0 } ifelse }
in: 0.9
in: 0.6
in: 0.1
case: results-of-rounding-stay-real
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 2.7 floor 2 idiv }
in: 0
case: results-of-cvi-are-integers
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 7.9 cvi 2 idiv }
in: 0
case: cvr-gives-a-real
type: 4
domain: 0 1
range: -100000000000 100000000000
code: { pop 7 cvr 2 idiv }
in: 0
case: inputs-are-reals
type: 4
domain: 0 10
range: -100000000000 100000000000
code: { 2 idiv }
in: 7
case: many-pushes-and-pops
type: 4
domain: 0 1
range: 0 1
code: { 0.5 pop 0.5 pop 0.5 pop 0.5 pop 0.5 pop 0.5 pop 0.5 pop 0.5 pop }
in: 0.25
