#!/usr/bin/env python3
"""Writes the synthetic render test files of tests/corpus/generated/render (standard library only, deterministic).

paths, clip, text-modes, colors-device, colors-special, transparency, softmask, shadings, patterns, optional-content,
annotations and rotated. images.pdf and jpeg.pdf come from make-render-tests.py and make-jpeg-tests.py, ccitt.pdf from the
oracle (Pdf4DOracle make-render-tests ccitt, see generate-render-tests.ps1). Run this script again and the bytes are the same.
"""
import importlib.util
import os
import struct
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
OUT = os.path.join(ROOT, 'tests', 'corpus', 'generated', 'render')
FONTS = os.path.join(ROOT, 'tests', 'fonts')
ICC = os.path.join(ROOT, 'tests', 'icc')

_spec = importlib.util.spec_from_file_location('glyphs', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'make-glyph-path-pdfs.py'))
glyphs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(glyphs)


class Doc:
    """Numbers the objects as they are added; object 1 is the catalog and 2 the page tree."""

    def __init__(self):
        self.objects = {}
        self.pages = []
        self.next_number = 3
        self.catalog_extra = ''

    def add(self, body):
        number = self.next_number
        self.next_number += 1
        self.objects[number] = body.encode('latin-1') if isinstance(body, str) else body
        return number

    def stream(self, dictionary, data, compress=False):
        if isinstance(data, str):
            data = data.encode('latin-1')
        if compress:
            data = zlib.compress(data, 9)
            dictionary += ' /Filter /FlateDecode'
        return self.add(('<< %s /Length %d >>\nstream\n' % (dictionary, len(data))).encode('latin-1') + data + b'\nendstream')

    def page(self, content, resources='', media_box='0 0 400 400', extra=''):
        contents = self.stream('', content)
        number = self.add('<< /Type /Page /Parent 2 0 R /MediaBox [%s] /Contents %d 0 R /Resources << %s >> %s >>'
                          % (media_box, contents, resources, extra))
        self.pages.append(number)
        return number

    def build(self):
        self.objects[1] = ('<< /Type /Catalog /Pages 2 0 R %s >>' % self.catalog_extra).encode('latin-1')
        self.objects[2] = ('<< /Type /Pages /Kids [%s] /Count %d >>' % (' '.join('%d 0 R' % p for p in self.pages), len(self.pages))).encode('latin-1')
        output = bytearray(b'%PDF-1.7\n')
        offsets = {}
        for number in sorted(self.objects):
            offsets[number] = len(output)
            output += b'%d 0 obj\n' % number + self.objects[number] + b'\nendobj\n'
        xref = len(output)
        size = max(self.objects) + 1
        output += b'xref\n0 %d\n0000000000 65535 f \n' % size
        for number in range(1, size):
            output += b'%010d 00000 n \n' % offsets[number]
        output += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (size, xref)
        return bytes(output)


def write(name, doc):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + '.pdf'), 'wb') as stream:
        stream.write(doc.build())
    print(name)


def read(path):
    with open(path, 'rb') as stream:
        return stream.read()


def grid(index, columns, cell, left=10, top=390):
    """The lower left corner of cell `index` of a grid of columns, cells of `cell` points."""
    return left + (index % columns) * cell, top - cell - (index // columns) * cell


NEWLINE = chr(10)
HELVETICA = '/F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'


# ---------------------------------------------------------------------------------------------------------------- paths
def paths():
    doc = Doc()
    c = ['0.95 g 0 0 400 400 re f 0 G 0 g']
    # Line widths including the hairline 0
    for i, w in enumerate([0, 0.25, 0.5, 1, 2, 4, 8]):
        c.append('%s w 20 %d m 120 %d l S' % (w, 380 - i * 10, 380 - i * 10))
    # Caps
    for i in range(3):
        c.append('q 10 w %d J 150 %d m 200 %d l S Q' % (i, 380 - i * 22, 380 - i * 22))
        c.append('q 0.7 G 0 w 150 %d m 200 %d l S Q' % (380 - i * 22, 380 - i * 22))
    # Joins with miter limits
    for i in range(3):
        c.append('q 8 w %d j 2 M %d 300 m %d 330 l %d 300 l S Q' % (i, 230 + i * 55, 245 + i * 55, 260 + i * 55))
    c.append('q 8 w 0 j 1 M 230 270 m 245 300 l 260 270 l S Q')
    c.append('q 8 w 0 j 10 M 290 270 m 305 300 l 320 270 l S Q')
    c.append('q 8 w 0 j 10 M 350 270 m 365 280 l 380 270 l S Q')
    # Dashes, also only zeros, a zero phase, a phase and round caps
    dashes = ['[6 3] 0 d', '[6 3] 4 d', '[1 4] 0 d 1 J', '[0 0] 0 d', '[0 6] 0 d 1 J', '[5] 0 d', '[3 5 1 2] 0 d', '[10 0] 0 d']
    for i, d in enumerate(dashes):
        c.append('q 3 w %s 20 %d m 200 %d l S Q' % (d, 240 - i * 14, 240 - i * 14))
    # Curves, c, v and y, a closed curve and a degenerate one
    c.append('q 2 w 220 130 m 240 200 280 200 300 130 c S 2 w 310 130 m 340 200 380 130 v S 2 w 310 120 m 380 120 340 60 y S Q')
    c.append('q 1 w 220 60 m 220 100 260 100 260 60 c h S 2 w 1 J 280 60 m 280 60 280 60 280 60 c S Q')
    # Fill rules: a star with nonzero and even-odd, a ring with opposite directions
    star = '%d 20 m %d 20 l %d 20 l %d 20 l %d 20 l h'
    for i, op in enumerate(['f', 'f*', 'B', 'B*', 'b', 'b*']):
        x = 20 + i * 62
        c.append('q 0.2 0.5 0.9 rg 0.8 0.1 0.1 RG 2 w %d 100 m %d 20 l %d 90 l %d 90 l %d 20 l h %s Q' % (x + 25, x + 40, x, x + 50, x + 10, op))
    c.append('q 0.1 0.6 0.2 rg 20 110 m 80 110 l 80 170 l 20 170 l h 35 125 m 35 155 l 65 155 l 65 125 l h f Q')
    c.append('q 0.1 0.6 0.2 rg 100 110 m 160 110 l 160 170 l 100 170 l h 115 125 m 145 125 l 145 155 l 115 155 l h f Q')
    c.append('q 0.9 0.6 0.1 rg 1 w 20 180 60 40 re 100 190 40 20 re 110 195 20 10 re B* Q')
    # Rectangles with a negative size, an empty path and a stroke with a transformation
    c.append('q 0.5 0 0.5 rg -10 -10 -30 -20 re f 300 20 -30 20 re f Q')
    c.append('q 2 0 0 0.5 0 0 cm 3 w 30 20 m 100 60 l S Q')
    doc.page('\n'.join(c) + '\n')
    write('paths', doc)


# ------------------------------------------------------------------------------------------------------------------ clip
def clip():
    doc = Doc()
    c = []
    c.append('0.9 g 0 0 400 400 re f')
    # W and W* with a path with a hole
    for i, op in enumerate(['W', 'W*']):
        x = 10 + i * 130
        c.append('q %d 300 m %d 300 l %d 380 l %d 380 l h %d 315 m %d 315 l %d 365 l %d 365 l h %s n 1 0 0 rg %d 290 100 100 re f 0 0 1 rg %d 340 40 20 re f Q'
                 % (x, x + 100, x + 100, x, x + 15, x + 15, x + 85, x + 85, op, x, x + 30))
    # Nested clips with q and Q: the clip of the inner q goes away at Q
    c.append('q 280 290 100 90 re W n 1 0 0 rg 270 280 60 60 re f q 320 320 m 400 320 l 360 400 l h W n 0 0.6 0 rg 270 280 130 130 re f Q 0 0 1 rg 275 285 20 20 re f Q')
    # Two clips cut each other, a clip that is a circle (curves) and an empty clip
    c.append('q 20 180 m 20 235 100 235 100 180 c h W n 1 0.5 0 rg 0 150 200 100 re f Q')
    c.append('q 120 180 80 60 re W n 150 160 80 60 re W n 0.4 0 0.8 rg 100 150 200 100 re f Q')
    c.append('q 250 200 m 250 200 l 250 200 l h W n 1 0 0 rg 200 150 200 100 re f Q')
    c.append('q 0 0 0 0 re W n 1 0 0 rg 0 0 5 5 re f Q')
    # Clip and transformation
    c.append('q 0.7 0.7 -0.7 0.7 340 160 cm 0 0 40 40 re W n 0 0.7 0.7 rg -20 -20 100 100 re f Q')
    # Text clip modes 4 to 7 with Helvetica: the text adds to the clip, the path after ET is drawn through the clip
    for i, mode in enumerate([4, 5, 6, 7]):
        x = 10 + i * 98
        c.append('q BT /F1 30 Tf %d Tr %d 100 Td 1 0 0 rg 0 0 1 RG 1 w (Clip) Tj ET' % (mode, x))
        c.append('0 0.7 0.2 rg %d 90 90 8 re f 0.9 0.7 0 rg %d 100 90 12 re f 0.6 0 0.6 rg %d 112 90 20 re f Q' % (x, x, x))
    # Mode 7 after other text, and the clip of two text objects
    c.append('q BT /F1 40 Tf 7 Tr 20 30 Td (AB) Tj ET BT /F1 40 Tf 7 Tr 90 30 Td (CD) Tj ET 0.8 0.2 0.2 rg 0 20 300 25 re f 0.2 0.2 0.8 rg 0 45 300 25 re f Q')
    doc.page('\n'.join(c) + '\n', '/Font << %s >>' % HELVETICA)
    write('clip', doc)


# ------------------------------------------------------------------------------------------------------------ text-modes
def pfb_segments(data):
    """The three segments of a PFB file without the segment headers: (ascii, binary, trailer)."""
    position = 0
    segments = []
    while position < len(data) and data[position] == 0x80 and data[position + 1] != 3:
        length = struct.unpack('<I', data[position + 2:position + 6])[0]
        segments.append(data[position + 6:position + 6 + length])
        position += 6 + length
    return segments[0], b''.join(segments[1:-1]), segments[-1]


def type3_font(doc):
    square = doc.stream('', '1000 0 0 0 800 800 d1 100 0 700 700 re f')
    triangle = doc.stream('', '1000 0 0 0 800 800 d1 100 0 m 800 0 l 450 700 l f')
    colored = doc.stream('', '1000 0 d0 1 0 0 rg 0 0 800 800 re f 0 0 1 rg 200 200 400 400 re f')
    return doc.add('<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [0.001 0 0 0.001 0 0] '
                   '/CharProcs << /sq %d 0 R /tri %d 0 R /col %d 0 R >> /Encoding << /Type /Encoding /Differences [97 /sq /tri /col] >> '
                   '/FirstChar 97 /LastChar 99 /Widths [1000 1000 1000] >>' % (square, triangle, colored))


def text_modes():
    doc = Doc()
    liberation = read(os.path.join(FONTS, 'LiberationSans-Regular.ttf'))
    truetype = doc.stream('/Length1 %d' % len(liberation), liberation, compress=True)
    cff = doc.stream('/Subtype /Type1C', glyphs.cff_of('SourceSansProBold.otf'), compress=True)
    ascii_part, binary_part, trailer = pfb_segments(read(os.path.join(FONTS, 'OpenSans-Regular.pfb')))
    type1 = doc.stream('/Length1 %d /Length2 %d /Length3 %d' % (len(ascii_part), len(binary_part), len(trailer)),
                       ascii_part + binary_part + trailer, compress=True)
    descriptor = '/Flags 32 /FontBBox [-600 -300 1300 1100] /ItalicAngle 0 /Ascent 900 /Descent -200 /CapHeight 700 /StemV 80'
    d2 = doc.add('<< /Type /FontDescriptor /FontName /LiberationSans %s /FontFile2 %d 0 R >>' % (descriptor, truetype))
    d3 = doc.add('<< /Type /FontDescriptor /FontName /SourceSansPro-Bold %s /FontFile3 %d 0 R >>' % (descriptor, cff))
    d4 = doc.add('<< /Type /FontDescriptor /FontName /OpenSans-Regular %s /FontFile %d 0 R >>' % (descriptor, type1))
    f2 = doc.add('<< /Type /Font /Subtype /TrueType /BaseFont /LiberationSans /Encoding /WinAnsiEncoding /FontDescriptor %d 0 R >>' % d2)
    f3 = doc.add('<< /Type /Font /Subtype /Type1 /BaseFont /SourceSansPro-Bold /Encoding /WinAnsiEncoding /FontDescriptor %d 0 R >>' % d3)
    f4 = doc.add('<< /Type /Font /Subtype /Type1 /BaseFont /OpenSans-Regular /Encoding /WinAnsiEncoding /FontDescriptor %d 0 R >>' % d4)
    f5 = type3_font(doc)
    fonts = [('F1', 'Agy', 'Helvetica'), ('F2', 'Agy', 'TrueType'), ('F3', 'Agy', 'CFF'), ('F4', 'Agy', 'Type 1'), ('F5', 'abc', 'Type 3')]
    # Two pages: modes 0 to 3, and 4 to 7 with a clip painted after each text
    for modes in ([0, 1, 2, 3], [4, 5, 6, 7]):
        c = ['0.95 g 0 0 400 400 re f']
        for row, (name, text, _) in enumerate(fonts):
            for column, mode in enumerate(modes):
                x, y = 10 + column * 98, 330 - row * 72
                c.append('q BT /%s 36 Tf %d Tr 1 w 0.1 0.3 0.8 rg 0.9 0.1 0.1 RG %d %d Td (%s) Tj ET' % (name, mode, x, y, text))
                if mode >= 4:
                    c.append('0 0.7 0.3 rg %d %d 90 8 re f 0.9 0.8 0 rg %d %d 90 10 re f 0.4 0 0.6 rg %d %d 90 20 re f' % (x, y - 2, x, y + 6, x, y + 16))
                c.append('Q')
        # Character and word spacing, scaling, rise, a text matrix with rotation, Tz
        c.append('BT /F1 14 Tf 0 Tr 2 Tc 5 Tw 150 Tz 10 8 Td 0 0 0 rg (Spaced out words) Tj 0 Tc 0 Tw 100 Tz 0 14 Td 5 Ts (rise) Tj 0 Ts ET')
        c.append('BT /F2 14 Tf 0.9 0.4 -0.4 0.9 250 20 Tm 1 0 0 rg (Rotated) Tj ET')
        doc.page('\n'.join(c) + '\n', '/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> '
                 '/F2 %d 0 R /F3 %d 0 R /F4 %d 0 R /F5 %d 0 R >>' % (f2, f3, f4, f5))
    write('text-modes', doc)


# --------------------------------------------------------------------------------------------------------- colors-device
def colors_device():
    doc = Doc()
    srgb = doc.stream('/N 3 /Alternate /DeviceRGB', read(os.path.join(ICC, 'sRGB.icc')), compress=True)
    cmyk = doc.stream('/N 4 /Alternate /DeviceCMYK', read(os.path.join(ICC, 'cmyk-printer.icc')), compress=True)
    gray = doc.stream('/N 1 /Alternate /DeviceGray', read(os.path.join(ICC, 'gray-gamma.icc')), compress=True)
    bad = doc.stream('/N 3 /Alternate /DeviceRGB', b'not an icc profile')
    c = ['1 g 0 0 400 400 re f']
    index = 0

    def swatch(fill, stroke='0 G'):
        nonlocal index
        x, y = grid(index, 8, 48, 8, 392)
        c.append('q %s %s 2 w %d %d 40 40 re B Q' % (fill, stroke, x + 4, y + 4))
        index += 1

    for g in (0, 0.25, 0.5, 0.75, 1):
        swatch('%s g' % g)
    swatch('0.5 G 0.5 g')
    swatch('1 g 1 0 0 RG')
    swatch('2 g')  # clamped
    for rgb in ('1 0 0', '0 1 0', '0 0 1', '1 1 0', '0 1 1', '1 0 1', '0.5 0.5 0.5', '0.2 0.4 0.6'):
        swatch('%s rg' % rgb)
    for k in ('1 0 0 0', '0 1 0 0', '0 0 1 0', '0 0 0 1', '1 1 0 0', '0 1 1 0', '1 0 1 0', '1 1 1 1', '0.5 0.5 0.5 0.5', '0.2 0.4 0.6 0.1'):
        swatch('%s k' % k)
    for rgb in ('1 0 0', '0 1 0', '0 0 1', '0.2 0.4 0.6', '1 1 1', '0 0 0'):
        swatch('/CsRgb cs %s sc' % rgb)
    for k in ('1 0 0 0', '0 1 0 0', '0 0 1 0', '0 0 0 1', '0.5 0.5 0.5 0.5', '0.3 0.6 0.1 0.2', '1 1 1 1', '0 0 0 0'):
        swatch('/CsCmyk cs %s sc' % k)
    for g in (0, 0.3, 0.6, 1):
        swatch('/CsGray cs %s sc' % g)
    # Stroke colours of the three ICC spaces, and an unusable profile (falls back on the alternate)
    swatch('1 g /CsRgb CS 0.1 0.5 0.9 SC', '/CsRgb CS 0.1 0.5 0.9 SC')
    swatch('1 g /CsCmyk CS 0.9 0.1 0.1 0.1 SC', '/CsCmyk CS 0.9 0.1 0.1 0.1 SC')
    swatch('/CsBad cs 0.9 0.5 0.1 sc')
    swatch('/Pattern cs')  # no pattern set: nothing is drawn
    # Gray ramp strips in the three device spaces
    for i in range(20):
        v = i / 19
        c.append('%g g %d 20 15 30 re f %g %g %g rg %d 55 15 30 re f 0 0 0 %g k %d 90 15 30 re f' % (v, 10 + i * 19, v, 1 - v, 0.5, 10 + i * 19, v, 10 + i * 19))
    doc.page('\n'.join(c) + '\n', '/ColorSpace << /CsRgb [/ICCBased %d 0 R] /CsCmyk [/ICCBased %d 0 R] /CsGray [/ICCBased %d 0 R] /CsBad [/ICCBased %d 0 R] >>'
             % (srgb, cmyk, gray, bad))
    write('colors-device', doc)


# -------------------------------------------------------------------------------------------------------- colors-special
def colors_special():
    doc = Doc()
    tint2 = doc.add('<< /FunctionType 2 /Domain [0 1] /C0 [0 0 0 0] /C1 [0 0.8 1 0.1] /N 1.5 >>')
    tint4 = doc.stream('/FunctionType 4 /Domain [0 1] /Range [0 1 0 1 0 1 0 1]', '{ dup 0.5 mul exch dup 0 exch 0.2 mul }')
    devn = doc.stream('/FunctionType 4 /Domain [0 1 0 1] /Range [0 1 0 1 0 1]', '{ 2 copy add 2 div 3 1 roll }')
    lab = '[/Lab << /WhitePoint [0.9642 1 0.8249] /Range [-128 127 -128 127] >>]'
    palette = '<FF0000 00FF00 0000FF FFFF00 FF00FF 00FFFF 808080 000000>'
    items = []
    for g in (0, 0.25, 0.5, 1):
        items.append('/CalG cs %s sc' % g)
    for rgb in ('1 0 0', '0 1 0', '0 0 1', '0.5 0.5 0.5', '1 1 1', '0.2 0.4 0.6'):
        items.append('/CalR cs %s sc' % rgb)
    for lab_value in ('100 0 0', '50 0 0', '50 80 0', '50 -80 0', '50 0 80', '50 0 -80', '75 40 -40', '0 0 0', '50 200 200'):
        items.append('/CsLab cs %s sc' % lab_value)
    for i in range(8):
        items.append('/CsIdx cs %d sc' % i)
    items.append('/CsIdx cs 9 sc')
    items.append('/CsIdx cs -1 sc')
    for t in (0, 0.25, 0.5, 0.75, 1):
        items.append('/CsSep2 cs %s sc' % t)
    for t in (0, 0.25, 0.5, 0.75, 1):
        items.append('/CsSep4 cs %s sc' % t)
    items.append('/CsAll cs 1 sc')
    items.append('/CsNone cs 1 sc')
    for a, b in ((0, 0), (1, 0), (0, 1), (1, 1), (0.5, 0.5), (0.25, 0.75)):
        items.append('/CsDevN cs %s %s sc' % (a, b))
    items.append('/CsIdxLab cs 1 sc')
    c = ['1 g 0 0 400 400 re f']
    for index, item in enumerate(items):
        x, y = grid(index, 8, 48, 8, 392)
        c.append('q %s %d %d 40 40 re f 0 G 0.5 w %d %d 40 40 re S Q' % (item, x + 4, y + 4, x + 4, y + 4))
    resources = ('/ColorSpace << /CalG [/CalGray << /WhitePoint [0.9505 1 1.089] /Gamma 2.2 >>] '
                 '/CalR [/CalRGB << /WhitePoint [0.9505 1 1.089] /Gamma [2.2 2.2 2.2] /Matrix [0.4124 0.2126 0.0193 0.3576 0.7152 0.1192 0.1805 0.0722 0.9505] >>] '
                 '/CsLab %s /CsIdx [/Indexed /DeviceRGB 7 %s] /CsIdxLab [/Indexed %s 1 <0080 80FF 0000>] '
                 '/CsSep2 [/Separation /Spot1 /DeviceCMYK %d 0 R] /CsSep4 [/Separation /Spot2 /DeviceCMYK %d 0 R] '
                 '/CsAll [/Separation /All /DeviceCMYK %d 0 R] /CsNone [/Separation /None /DeviceCMYK %d 0 R] '
                 '/CsDevN [/DeviceN [/Cyan /Magenta] /DeviceRGB %d 0 R] >>' % (lab, palette, lab, tint2, tint4, tint2, tint2, devn))
    doc.page('\n'.join(c) + '\n', resources)
    write('colors-special', doc)


# ----------------------------------------------------------------------------------------------------------- transparency
BLEND_MODES = ['Normal', 'Multiply', 'Screen', 'Overlay', 'Darken', 'Lighten', 'ColorDodge', 'ColorBurn', 'HardLight', 'SoftLight',
               'Difference', 'Exclusion', 'Hue', 'Saturation', 'Color', 'Luminosity']


def transparency():
    doc = Doc()
    states = ['/GsA25 << /CA 0.25 /ca 0.25 >>', '/GsA50 << /CA 0.5 /ca 0.5 >>', '/GsFillOnly << /ca 0.4 >>', '/GsStrokeOnly << /CA 0.4 >>']
    for mode in BLEND_MODES:
        states.append('/Gs%s << /BM /%s >>' % (mode, mode))
    states.append('/GsBmArray << /BM [/Foo /Multiply] >>')
    states.append('/GsAlphaMode << /BM /Multiply /ca 0.7 >>')
    # Page 1: constant alpha and the 16 blend modes over a colourful backdrop
    c = ['1 g 0 0 400 400 re f']
    c.append('1 0 0 rg 20 320 80 60 re f 0 0 1 rg 60 340 80 50 re f')
    c.append('q /GsA50 gs 0 0.7 0 rg 40 300 80 60 re f 0.9 0.7 0 RG 6 w 30 310 100 70 re B Q')
    c.append('q /GsFillOnly gs 0 0 0 rg 0.9 0.1 0.1 RG 8 w 180 320 80 50 re B Q q /GsStrokeOnly gs 0 0 0 rg 0.9 0.1 0.1 RG 8 w 280 320 80 50 re B Q')
    c.append('q /GsA25 gs 0 0 0 rg 150 300 200 10 re f Q')
    for index, mode in enumerate(BLEND_MODES + ['BmArray', 'AlphaMode']):
        x, y = grid(index, 6, 64, 10, 290)
        # backdrop: three coloured stripes and a gray one, then the box with the blend mode
        c.append('q 1 0 0 rg %d %d 18 56 re f 0 0.8 0.2 rg %d %d 18 56 re f 0.2 0.3 1 rg %d %d 18 56 re f 0.5 g %d %d 10 56 re f Q'
                 % (x, y, x + 18, y, x + 36, y, x + 54, y))
        c.append('q /Gs%s gs 0.9 0.6 0.2 rg %d %d 60 24 re f 0.2 0.5 0.9 rg %d %d 60 12 re f Q' % (mode, x - 2, y + 6, x - 2, y + 36))
    doc.page('\n'.join(c) + '\n', '/ExtGState << %s >>' % ' '.join(states))

    # Page 2: transparency groups: isolated, non isolated, knockout, with an alpha on the group and a blend mode inside
    def group(content, isolated, knockout, extra_resources=''):
        entries = '/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceRGB /I %s /K %s >> %s' % (
            'true' if isolated else 'false', 'true' if knockout else 'false', extra_resources)
        return doc.stream(entries, content)

    shapes = '1 0 0 rg 10 10 50 50 re f 0 0 1 rg 40 40 50 50 re f'
    multiply = '/GsMultiply gs 1 0 0 rg 10 10 50 50 re f 0 0 1 rg 40 40 50 50 re f'
    resources = '/Resources << /ExtGState << /GsMultiply << /BM /Multiply >> /GsHalf << /ca 0.5 >> >> >>'
    plain = group(shapes, True, False)
    isolated = group(multiply, True, False, resources)
    nonisolated = group(multiply, False, False, resources)
    knockout = group('/GsHalf gs ' + shapes, True, True, resources)
    nonknockout = group('/GsHalf gs ' + shapes, True, False, resources)
    nested = group('q 0.5 0 0 0.5 0 0 cm /GrPlain Do Q 0 0.8 0 rg 60 5 30 30 re f', False, False, '/Resources << /XObject << /GrPlain %d 0 R >> >>' % plain)
    forms = [plain, isolated, nonisolated, knockout, nonknockout, nested]
    names = ' '.join('/Gr%d %d 0 R' % (i, f) for i, f in enumerate(forms))
    resources = '/ExtGState << /GrA << /ca 1 >> /GsHalf << /ca 0.5 /CA 0.5 >> >> /XObject << %s >>' % names
    # Page 2 draws the groups with ca 1, page 3 with the group alpha (ca 0.5)
    for state in ('GrA', 'GsHalf'):
        c = ['0.9 0.9 0.5 rg 0 0 400 400 re f 0.3 0.6 0.9 rg 0 220 400 60 re f 1 g 0 120 400 20 re f']
        for index, form in enumerate(forms):
            x, y = grid(index, 3, 130, 10, 390)
            c.append('q 1 0 0 1 %d %d cm /%s gs /Gr%d Do Q' % (x, y, state, index))
        doc.page(NEWLINE.join(c) + NEWLINE, resources)
    write('transparency', doc)


# ------------------------------------------------------------------------------------------------------------- softmask
def softmask():
    doc = Doc()
    gradient = ('/ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> '
                '/Extend [true true]')
    alpha_group = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceGray >> '
                             '/Resources << /ExtGState << /H << /ca 0.5 >> >> >>',
                             '0 g 10 10 60 60 re f /H gs 0 g 40 40 55 55 re f')
    luminosity_group = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceGray >> '
                                  '/Resources << /Shading << /Sh1 << %s >> >> >>' % gradient,
                                  '/Sh1 sh 0 g 40 40 20 20 re f')
    # A smaller box: the backdrop outside it is /BC
    small_group = doc.stream('/Type /XObject /Subtype /Form /BBox [20 20 80 80] /Group << /S /Transparency /CS /DeviceGray >>',
                             '1 g 0 0 100 100 re f')
    rgb_group = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceRGB >>',
                           '1 0 0 rg 0 0 50 100 re f 0 1 0 rg 50 0 50 100 re f')
    inverting = '<< /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [0] /N 1 >>'
    identity = '/Identity'
    states = ['/SmAlpha << /SMask << /Type /Mask /S /Alpha /G %d 0 R >> >>' % alpha_group,
              '/SmLum << /SMask << /Type /Mask /S /Luminosity /G %d 0 R >> >>' % luminosity_group,
              '/SmLumBc << /SMask << /Type /Mask /S /Luminosity /G %d 0 R /BC [0.5] >> >>' % small_group,
              '/SmLumBc0 << /SMask << /Type /Mask /S /Luminosity /G %d 0 R /BC [0] >> >>' % small_group,
              '/SmLumTr << /SMask << /Type /Mask /S /Luminosity /G %d 0 R /TR %s >> >>' % (luminosity_group, inverting),
              '/SmLumId << /SMask << /Type /Mask /S /Luminosity /G %d 0 R /TR %s >> >>' % (luminosity_group, identity),
              '/SmRgb << /SMask << /Type /Mask /S /Luminosity /G %d 0 R >> >>' % rgb_group,
              '/SmAlphaTr << /SMask << /Type /Mask /S /Alpha /G %d 0 R /TR %s >> >>' % (alpha_group, inverting),
              '/SmNone << /SMask /None >>']
    c = ['0.95 g 0 0 400 400 re f 0.3 0.6 0.9 rg 0 130 400 40 re f 1 0.9 0 rg 0 270 400 30 re f']
    for index, name in enumerate(['SmAlpha', 'SmLum', 'SmLumBc', 'SmLumBc0', 'SmLumTr', 'SmLumId', 'SmRgb', 'SmAlphaTr']):
        x, y = grid(index, 4, 95, 10, 390)
        c.append('q 1 0 0 1 %d %d cm /%s gs 0.8 0.1 0.1 rg 0 0 100 100 re f 0 0.5 0 rg 0 40 100 20 re f Q' % (x, y, name))
    # A soft mask that is reset, a mask under a transformation and a mask used by an image-like fill later
    c.append('q /SmLum gs 1 0 0 1 20 20 cm /SmNone gs 0 0 0.8 rg 0 0 80 80 re f Q')
    c.append('q 0.6 0 0 0.6 150 20 cm /SmLum gs 0.1 0.5 0.1 rg 0 0 100 100 re f Q')
    c.append('q 1 0 0 1 280 20 cm /SmLum gs q /SmLumTr gs 0.5 0 0.5 rg 0 0 100 100 re f Q 0 0.3 0.8 rg 0 0 50 50 re f Q')
    doc.page('\n'.join(c) + '\n', '/ExtGState << %s >>' % ' '.join(states))
    write('softmask', doc)


# ------------------------------------------------------------------------------------------------------------- shadings
def mesh_stream(vertices, flags=True):
    data = bytearray()
    for vertex in vertices:
        if flags:
            data.append(vertex[0])
            vertex = vertex[1:]
        x, y, r, g, b = vertex
        data += struct.pack('>HH', x, y) + bytes([r, g, b])
    return bytes(data)


def patch_stream(points, colors):
    data = bytearray([0])
    for x, y in points:
        data += struct.pack('>HH', x, y)
    for r, g, b in colors:
        data += bytes([r, g, b])
    return bytes(data)


def shadings():
    doc = Doc()
    f_axial = '<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>'
    f_stitch = ('<< /FunctionType 3 /Domain [0 1] /Functions [<< /FunctionType 2 /Domain [0 1] /C0 [1 1 0] /C1 [0 0.6 0] /N 1 >> '
                '<< /FunctionType 2 /Domain [0 1] /C0 [0 0.6 0] /C1 [0 0 0.6] /N 1 >>] /Bounds [0.4] /Encode [0 1 0 1] >>')
    f_xy = doc.stream('/FunctionType 4 /Domain [0 1 0 1] /Range [0 1 0 1 0 1]', '{ 2 copy mul }')
    decode = '/Decode [0 100 0 100 0 1 0 1 0 1]'
    mesh = '/ColorSpace /DeviceRGB /BitsPerCoordinate 16 /BitsPerComponent 8 '
    scale = 65535 // 100
    s4 = doc.stream('/ShadingType 4 %s /BitsPerFlag 8 %s' % (mesh, decode),
                    mesh_stream([(0, 0, 0, 255, 0, 0), (0, 100 * scale, 0, 0, 255, 0), (0, 50 * scale, 100 * scale, 0, 0, 255),
                                 (1, 100 * scale, 100 * scale, 255, 255, 0)]))
    s5 = doc.stream('/ShadingType 5 %s /VerticesPerRow 3 %s' % (mesh, decode),
                    mesh_stream([(0, 0, 255, 0, 0), (50 * scale, 5 * scale, 0, 255, 0), (100 * scale, 0, 0, 0, 255),
                                 (0, 50 * scale, 255, 255, 0), (50 * scale, 55 * scale, 255, 255, 255), (100 * scale, 50 * scale, 0, 255, 255),
                                 (0, 100 * scale, 0, 0, 0), (50 * scale, 95 * scale, 255, 0, 255), (100 * scale, 100 * scale, 255, 128, 0)], flags=False))
    coons = [(5, 5), (5, 35), (5, 65), (5, 95), (35, 99), (65, 75), (95, 95), (95, 65), (95, 35), (95, 5), (65, 1), (35, 25)]
    coons = [(x * scale, y * scale) for x, y in coons]
    s6 = doc.stream('/ShadingType 6 %s /BitsPerFlag 8 %s' % (mesh, decode),
                    patch_stream(coons, [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)]))
    tensor = coons + [(33 * scale, 33 * scale), (33 * scale, 66 * scale), (66 * scale, 66 * scale), (66 * scale, 33 * scale)]
    s7 = doc.stream('/ShadingType 7 %s /BitsPerFlag 8 %s' % (mesh, decode),
                    patch_stream(tensor, [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0)]))
    shadings_ = {
        'S1': '<< /ShadingType 1 /ColorSpace /DeviceRGB /Domain [0 1 0 1] /Matrix [100 0 0 100 0 0] /Function %d 0 R >>' % f_xy,
        'S2': '<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [10 10 90 90] /Function %s >>' % f_axial,
        'S2x': '<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [30 30 70 70] /Function %s /Extend [true true] >>' % f_stitch,
        'S3': '<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [50 50 0 50 50 45] /Function %s >>' % f_axial,
        'S3x': '<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [35 50 10 65 50 25] /Function %s /Extend [true true] >>' % f_stitch,
        'S4': '%d 0 R' % s4, 'S5': '%d 0 R' % s5, 'S6': '%d 0 R' % s6, 'S7': '%d 0 R' % s7,
    }
    # Page 1: the sh operator with every type, each in a clipped cell of 100 x 100 points; the BBox and the clip of the cell
    order = ['S1', 'S2', 'S2x', 'S3', 'S3x', 'S4', 'S5', 'S6', 'S7']
    c = ['0.85 g 0 0 400 400 re f']
    for index, name in enumerate(order):
        x, y = grid(index, 3, 125, 10, 390)
        c.append('q 1 0 0 1 %d %d cm 0 0 100 100 re W n /%s sh Q' % (x + 5, y + 5, name))
    # A shading with a /BBox and with /Background (the background is ignored by sh), and an axial shading with an alpha
    bbox = '<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] /Function %s /BBox [20 20 80 80] /Extend [true true] /Background [0 1 0] >>' % f_axial
    c.append('q 1 0 0 1 10 10 cm 0 0 100 100 re W n /SBox sh Q')
    c.append('q 1 0 0 1 130 10 cm 0 0 100 100 re W n /GsHalf gs /S2 sh Q')
    resources = '/Shading << %s /SBox %s >> /ExtGState << /GsHalf << /ca 0.5 >> >>' % (' '.join('/%s %s' % item for item in shadings_.items()), bbox)
    doc.page('\n'.join(c) + '\n', resources)

    # Page 2: the same as shading patterns (fill and stroke), with a pattern matrix, /Extend, /BBox and /Background
    patterns = {}
    pattern_dicts = []
    for index, name in enumerate(['S1', 'S2', 'S2x', 'S3', 'S3x', 'S4', 'S5', 'S6', 'S7']):
        pattern_dicts.append(('P%s' % name, '<< /PatternType 2 /Shading %s /Matrix [1 0 0 1 %d %d] >>' % (shadings_[name], grid(index, 3, 125, 10, 390)[0] + 5,
                                                                                                        grid(index, 3, 125, 10, 390)[1] + 5)))
    pattern_dicts.append(('PBg', '<< /PatternType 2 /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [30 0 70 0] /Function %s /Background [0 1 0] '
                                 '/BBox [10 10 90 90] >> /Matrix [1 0 0 1 10 10] >>' % f_axial))
    pattern_dicts.append(('PBgNoExtend', '<< /PatternType 2 /Shading << /ShadingType 3 /ColorSpace /DeviceRGB /Coords [50 50 10 50 50 30] /Function %s /Background [1 1 0] >> '
                                         '/Matrix [1 0 0 1 130 10] >>' % f_axial))
    pattern_dicts.append(('PScaled', '<< /PatternType 2 /Shading %s /Matrix [0.5 0 0 0.5 250 10] >>' % shadings_['S2x']))
    pattern_dicts.append(('PGs', '<< /PatternType 2 /Shading %s /Matrix [1 0 0 1 130 10] /ExtGState << /ca 0.5 >> >>' % shadings_['S2']))
    c = ['0.85 g 0 0 400 400 re f /Pattern cs']
    for index, name in enumerate(['S1', 'S2', 'S2x', 'S3', 'S3x', 'S4', 'S5', 'S6', 'S7']):
        x, y = grid(index, 3, 125, 10, 390)
        c.append('/P%s scn %d %d 100 100 re f' % (name, x + 5, y + 5))
    c.append('/PBg scn 10 10 100 100 re f /PBgNoExtend scn 130 10 100 100 re f /PScaled scn 250 10 120 100 re f')
    c.append('/Pattern CS /PS2x SCN 10 w 250 120 m 380 120 l S')
    pattern_dicts.append(('PS2x', '<< /PatternType 2 /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [250 0 380 0] /Function %s >> >>' % f_axial))
    # A shading pattern as text fill
    c.append('BT /F1 60 Tf 250 60 Td /PS2x scn (Ab) Tj ET')
    pattern_ids = ' '.join('/%s %d 0 R' % (name, doc.add(body)) for name, body in pattern_dicts)
    doc.page('\n'.join(c) + '\n', '/Pattern << %s >> /Font << %s >>' % (pattern_ids, HELVETICA))
    write('shadings', doc)


# ------------------------------------------------------------------------------------------------------------- patterns
def patterns():
    doc = Doc()
    colored = doc.stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 20 20] /XStep 20 /YStep 20 /Resources << >>',
                         '1 0 0 rg 0 0 10 10 re f 0 0 1 rg 10 10 10 10 re f 0 0.6 0 RG 2 w 0 20 m 20 0 l S')
    uncolored = doc.stream('/Type /Pattern /PatternType 1 /PaintType 2 /TilingType 1 /BBox [0 0 16 16] /XStep 16 /YStep 16 /Resources << >>',
                           '8 8 m 16 8 l 8 16 l h f 0 0 4 4 re f')
    overlapping = doc.stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 2 /BBox [0 0 30 30] /XStep 12 /YStep 12 /Resources << >>',
                             '0.9 0.5 0 rg 0 0 30 30 re f 0 0.3 0.6 RG 1 w 0 0 30 30 re S')
    spaced = doc.stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 3 /BBox [0 0 10 10] /XStep 25 /YStep 18 /Resources << >>',
                        '0.5 0 0.5 rg 5 5 m 10 5 l 5 10 l h f 0 0 10 10 re S')
    inner = doc.stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 8 8] /XStep 8 /YStep 8 /Resources << >>',
                       '0 0.7 0.7 rg 0 0 4 4 re f 0 0 0 rg 4 4 4 4 re f')
    nested = doc.stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 40 40] /XStep 40 /YStep 40 '
                        '/Resources << /Pattern << /PIn %d 0 R >> >>' % inner,
                        '/Pattern cs /PIn scn 0 0 40 40 re f 1 0 0 RG 2 w 0 0 40 40 re S')
    matrixed = doc.stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 20 20] /XStep 20 /YStep 20 '
                          '/Matrix [0.7 0.7 -0.7 0.7 0 0] /Resources << >>', '0.2 0.2 0.8 rg 0 0 10 20 re f 0.8 0.8 0.1 rg 10 0 10 20 re f')
    big = doc.stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 60 60] /XStep 60 /YStep 60 '
                     '/Resources << /Font << %s >> >>' % HELVETICA, '0.9 g 0 0 60 60 re f BT /F1 24 Tf 0 g 5 20 Td (Pa) Tj ET')
    pattern_names = '/PC %d 0 R /PU %d 0 R /PO %d 0 R /PS %d 0 R /PN %d 0 R /PM %d 0 R /PB %d 0 R' % (colored, uncolored, overlapping, spaced, nested, matrixed, big)
    c = ['0.9 g 0 0 400 400 re f']
    c.append('/Pattern cs /PC scn 10 290 100 100 re f')
    c.append('/CsU cs 1 0 0 /PU scn 120 290 100 100 re f 0 0.6 0 /PU scn 230 290 100 100 re f')
    c.append('/Pattern cs /PO scn 10 170 100 100 re f /PS scn 120 170 100 100 re f /PN scn 230 170 100 100 re f')
    c.append('/PM scn 10 50 100 100 re f /PB scn 120 50 100 100 re f')
    c.append('/Pattern CS /PC SCN 8 w 235 55 m 320 140 l S')
    c.append('/Pattern cs /PC scn 340 50 m 390 50 l 365 140 l f')
    c.append('/Pattern cs /PO scn 340 160 40 40 re f')
    c.append('BT /F1 70 Tf 10 5 Td /Pattern cs /PC scn (Tile) Tj ET')
    doc.page('\n'.join(c) + '\n', '/Pattern << %s >> /ColorSpace << /CsU [/Pattern /DeviceRGB] >> /Font << %s >>' % (pattern_names, HELVETICA))
    write('patterns', doc)


# ------------------------------------------------------------------------------------------------------ optional-content
def optional_content():
    doc = Doc()
    on = doc.add('<< /Type /OCG /Name (On) >>')
    off = doc.add('<< /Type /OCG /Name (Off) >>')
    other = doc.add('<< /Type /OCG /Name (Other) >>')
    view_off = doc.add('<< /Type /OCG /Name (ViewOff) /Usage << /View << /ViewState /OFF >> >> >>')
    print_off = doc.add('<< /Type /OCG /Name (PrintOff) /Usage << /Print << /PrintState /OFF >> >> >>')
    all_on = doc.add('<< /Type /OCMD /OCGs [%d 0 R %d 0 R] /P /AllOn >>' % (on, other))
    any_on = doc.add('<< /Type /OCMD /OCGs [%d 0 R %d 0 R] /P /AnyOn >>' % (on, off))
    any_off = doc.add('<< /Type /OCMD /OCGs [%d 0 R %d 0 R] /P /AnyOff >>' % (on, off))
    all_off = doc.add('<< /Type /OCMD /OCGs [%d 0 R %d 0 R] /P /AllOff >>' % (off, view_off))
    default_p = doc.add('<< /Type /OCMD /OCGs %d 0 R >>' % off)
    ve = doc.add('<< /Type /OCMD /VE [/And %d 0 R [/Not %d 0 R]] >>' % (on, off))
    ve_false = doc.add('<< /Type /OCMD /VE [/Or %d 0 R %d 0 R] >>' % (off, view_off))
    empty = doc.add('<< /Type /OCMD /OCGs [] >>')
    doc.catalog_extra = ('/OCProperties << /OCGs [%d 0 R %d 0 R %d 0 R %d 0 R %d 0 R] /D << /BaseState /ON /OFF [%d 0 R %d 0 R] /Order [%d 0 R %d 0 R] >> >>'
                         % (on, off, other, view_off, print_off, off, view_off, on, off))
    image = doc.stream('/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /OC %d 0 R' % off,
                       bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]))
    image_on = doc.stream('/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /OC %d 0 R' % on,
                          bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]))
    form_off = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 50 50] /OC %d 0 R' % off, '1 0 0 rg 0 0 50 50 re f')
    form_on = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 50 50] /OC %d 0 R' % on, '0 0.7 0 rg 0 0 50 50 re f')
    form_inner = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 50 50] /Resources << /Properties << /OcOff %d 0 R >> >>' % off,
                            '0 0 1 rg 0 0 50 50 re f /OC /OcOff BDC 1 0 0 rg 10 10 30 30 re f EMC')
    properties = ' '.join('/%s %d 0 R' % item for item in [('OcOn', on), ('OcOff', off), ('OcOther', other), ('OcViewOff', view_off), ('OcPrintOff', print_off),
                                                         ('OcAllOn', all_on), ('OcAnyOn', any_on), ('OcAnyOff', any_off), ('OcAllOff', all_off),
                                                         ('OcDefault', default_p), ('OcVe', ve), ('OcVeFalse', ve_false), ('OcEmpty', empty)])
    cells = [('OcOn', True), ('OcOff', False), ('OcOther', True), ('OcViewOff', False), ('OcPrintOff', True), ('OcAllOn', True), ('OcAnyOn', True),
             ('OcAnyOff', True), ('OcAllOff', False), ('OcDefault', False), ('OcVe', True), ('OcVeFalse', False), ('OcEmpty', True)]
    c = ['0.9 g 0 0 400 400 re f']
    for index, (name, _) in enumerate(cells):
        x, y = grid(index, 5, 76, 10, 390)
        c.append('0.6 G %d %d 60 60 re S /OC /%s BDC 0 0.5 0.9 rg %d %d 60 60 re f EMC' % (x, y, name, x, y))
    # Nested marked content: an inner section of a visible section is hidden when the outer one is hidden
    c.append('/OC /OcOn BDC 0.8 0.2 0.2 rg 10 100 60 40 re f /OC /OcOff BDC 0 0 0 rg 20 110 40 20 re f EMC 0.2 0.8 0.2 rg 80 100 30 40 re f EMC')
    c.append('/OC /OcOff BDC /OC /OcOn BDC 0 0 0 rg 130 100 60 40 re f EMC 1 0 0 rg 200 100 20 40 re f EMC')
    # A non-OC marked content, BMC and an unknown property
    c.append('/Span BMC 0.4 0.4 0.9 rg 240 100 40 40 re f EMC /OC /Missing BDC 0.9 0.9 0 rg 290 100 40 40 re f EMC /OC /OcOff BDC EMC')
    # OC on an image and on a form
    c.append('q 50 0 0 50 10 20 cm /ImOff Do Q q 50 0 0 50 70 20 cm /ImOn Do Q q 1 0 0 1 130 20 cm /FmOff Do Q q 1 0 0 1 190 20 cm /FmOn Do Q q 1 0 0 1 250 20 cm /FmIn Do Q')
    doc.page('\n'.join(c) + '\n', '/Properties << %s >> /XObject << /ImOff %d 0 R /ImOn %d 0 R /FmOff %d 0 R /FmOn %d 0 R /FmIn %d 0 R >>'
             % (properties, image, image_on, form_off, form_on, form_inner))
    write('optional-content', doc)


# ----------------------------------------------------------------------------------------------------------- annotations
def annotations():
    doc = Doc()
    red = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 40 40]', '1 0 0 rg 0 0 40 40 re f 1 g 10 10 20 20 re f')
    green = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 40 40]', '0 0.7 0 rg 0 0 40 40 re f')
    blue = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 40 40]', '0 0 1 rg 0 0 40 40 re f')
    scaled = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 100 50] /Matrix [0 1 -1 0 0 0]', '0.9 0.6 0 rg 0 0 100 50 re f 0 g 0 0 10 10 re f')
    arrow = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 60 30]', '0 0.5 0.5 rg 0 0 60 30 re f 1 g 5 5 m 50 15 l 5 25 l f')
    inside = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 40 40] /Resources << /Font << %s >> >>' % HELVETICA,
                        '0.8 g 0 0 40 40 re f BT /F1 14 Tf 0 g 4 14 Td (Hi) Tj ET')

    def annotation(rect, subtype='Widget', flags=4, appearance='', extra=''):
        return '<< /Type /Annot /Subtype /%s /Rect [%s] /F %d %s %s >>' % (subtype, rect, flags, appearance, extra)

    def make(rotate):
        annots = []
        annots.append(annotation('10 340 50 380', 'Stamp', 4, '/AP << /N %d 0 R >>' % red))
        annots.append(annotation('70 340 110 380', 'Stamp', 4, '/AP << /N << /On %d 0 R /Off %d 0 R >> >>' % (green, blue), '/AS /On'))
        annots.append(annotation('120 340 160 380', 'Stamp', 4, '/AP << /N << /On %d 0 R /Off %d 0 R >> >>' % (green, blue), '/AS /Off'))
        annots.append(annotation('170 340 210 380', 'Stamp', 4, '/AP << /N << /On %d 0 R /Off %d 0 R >> >>' % (green, blue), '/AS /Missing'))
        annots.append(annotation('220 340 260 380', 'Stamp', 4 | 2, '/AP << /N %d 0 R >>' % red))  # Hidden
        annots.append(annotation('270 340 310 380', 'Stamp', 4 | 32, '/AP << /N %d 0 R >>' % red))  # NoView
        annots.append(annotation('320 340 360 380', 'Stamp', 4 | 1, '/AP << /N %d 0 R >>' % red))  # Invisible
        annots.append(annotation('10 270 110 320', 'Stamp', 4, '/AP << /N %d 0 R >>' % scaled))  # the form matrix and the scaling to /Rect
        annots.append(annotation('130 270 190 300', 'Stamp', 4 | 16, '/AP << /N %d 0 R >>' % arrow))  # NoRotate
        annots.append(annotation('210 270 270 300', 'Stamp', 4, '/AP << /N %d 0 R >>' % arrow))
        annots.append(annotation('290 270 330 310', 'Stamp', 4 | 16, '/AP << /N %d 0 R >>' % inside))
        annots.append(annotation('10 200 100 250', 'Square', 4, '', '/C [1 0 0] /IC [1 1 0] /BS << /W 3 >>'))  # without /AP
        annots.append(annotation('110 200 200 250', 'Circle', 4, '', '/C [0 0 1] /BS << /W 2 >>'))
        annots.append(annotation('210 200 300 250', 'Line', 4, '', '/L [210 200 300 250] /C [0 0.6 0]'))
        annots.append(annotation('310 200 390 250', 'Highlight', 4, '', '/C [1 1 0] /QuadPoints [310 250 390 250 310 200 390 200]'))
        annots.append(annotation('10 130 100 180', 'Link', 4, '', '/Border [0 0 2] /C [1 0 0]'))
        annots.append(annotation('110 130 200 180', 'Text', 4, '', '/Contents (note)'))
        annots.append(annotation('210 130 300 180', 'Popup', 4))
        annots.append(annotation('310 130 360 180', 'Stamp', 4, '/AP << /D %d 0 R >>' % red))  # only a down appearance
        annots.append(annotation('10 60 60 110', 'Stamp', 4, '/AP << /N %d 0 R >>' % green, '/Rotate 0'))
        annots.append(annotation('70 60 110 100', 'Stamp', 0, '/AP << /N %d 0 R >>' % blue))  # no flags
        return annots

    # Page 1 upright, page 2 with /Rotate 90 (NoRotate), page 3 with the MediaBox offset
    annots = [doc.add(a) for a in make(0)]
    refs = ' '.join('%d 0 R' % a for a in annots)
    doc.page('0.95 g 0 0 400 400 re f 0.7 g 0 0 400 5 re f BT /F1 10 Tf 5 8 Td 0 g (Annotations) Tj ET', '/Font << %s >>' % HELVETICA, extra='/Annots [%s]' % refs)
    annots2 = [doc.add(a) for a in make(90)]
    doc.page('0.95 g 0 0 400 400 re f 0.7 g 0 0 400 5 re f BT /F1 10 Tf 5 8 Td 0 g (Rotated page) Tj ET', '/Font << %s >>' % HELVETICA,
             extra='/Rotate 90 /Annots [%s]' % ' '.join('%d 0 R' % a for a in annots2))
    annots3 = [doc.add(a) for a in make(0)]
    doc.page('0.95 g 0 0 400 400 re f', '', '50 50 450 450', extra='/CropBox [60 70 400 440] /Annots [%s]' % ' '.join('%d 0 R' % a for a in annots3))
    write('annotations', doc)


# ------------------------------------------------------------------------------------------------------------- rotated
def rotated():
    doc = Doc()
    body = ('0.95 g 0 0 300 400 re f 0 0 0.8 RG 4 w 2 2 296 396 re S 1 0 0 rg 20 340 m 60 340 l 40 380 l h f '
            'BT /F1 24 Tf 1 g 0 g 80 350 Td (TOP) Tj ET 0.2 0.7 0.2 rg 0 0 60 60 re f 0 g BT /F1 12 Tf 70 20 Td (origin) Tj ET '
            '0.7 0.2 0.7 rg 120 150 60 100 re f')
    for rotate in (0, 90, 180, 270, -90, 450):
        doc.page(body, '/Font << %s >>' % HELVETICA, '0 0 300 400', extra='/Rotate %d' % rotate)
    # A CropBox with an offset in a MediaBox that does not start at 0, with and without rotation
    shifted = body.replace('0 0 300 400 re f', '0 0 400 500 re f')
    doc.page(shifted, '/Font << %s >>' % HELVETICA, '0 0 400 500', extra='/CropBox [50 60 250 340]')
    doc.page(shifted, '/Font << %s >>' % HELVETICA, '0 0 400 500', extra='/CropBox [50 60 250 340] /Rotate 90')
    doc.page(shifted, '/Font << %s >>' % HELVETICA, '-50 -50 350 450', extra='/CropBox [-20 -10 200 250] /Rotate 270')
    # A CropBox beyond the MediaBox is cut to it; upside down boxes are normalised
    doc.page(shifted, '/Font << %s >>' % HELVETICA, '0 0 400 500', extra='/CropBox [-100 -100 300 300]')
    doc.page(shifted, '/Font << %s >>' % HELVETICA, '400 500 0 0', extra='/Rotate 180')
    write('rotated', doc)


if __name__ == '__main__':
    paths()
    clip()
    text_modes()
    colors_device()
    colors_special()
    transparency()
    softmask()
    shadings()
    patterns()
    optional_content()
    annotations()
    rotated()
