#!/usr/bin/env python3
"""Writes the small PDF files of tests/fonts/glyph-paths from the test fonts (standard library only).

Each file has one page with the font /F1 in its resources. generate-font-widths.ps1 -PdfPaths runs the oracle over them.
The files are deterministic: run this script again and the bytes are the same.
"""
import os
import struct

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
FONTS = os.path.join(ROOT, 'tests', 'fonts')
OUT = os.path.join(FONTS, 'glyph-paths')

DESCRIPTOR_ENTRIES = '/Flags %d /FontBBox [-600 -300 1300 1100] /ItalicAngle 0 /Ascent 900 /Descent -200 /CapHeight 700 /StemV 80'
CONTENT = b'BT /F1 12 Tf 10 10 Td (A) Tj ET'


def read(name):
    with open(os.path.join(FONTS, name), 'rb') as stream:
        return stream.read()


def sfnt_tables(data):
    count = struct.unpack('>H', data[4:6])[0]
    tables = {}
    for index in range(count):
        tag, _, offset, length = struct.unpack('>4sIII', data[12 + 16 * index:28 + 16 * index])
        tables[tag.decode('latin-1')] = data[offset:offset + length]
    return tables


def cff_of(name):
    return sfnt_tables(read(name))['CFF ']


def unicode_glyphs(data):
    """The glyph of every character of the (3, 1) cmap (format 4) of a TrueType font."""
    cmap = sfnt_tables(data)['cmap']
    count = struct.unpack('>H', cmap[2:4])[0]
    for index in range(count):
        platform, encoding, offset = struct.unpack('>HHI', cmap[4 + 8 * index:12 + 8 * index])
        if (platform, encoding) == (3, 1):
            break
    else:
        raise ValueError('no (3, 1) cmap')
    table = cmap[offset:]
    segments = struct.unpack('>H', table[6:8])[0] // 2
    ends = struct.unpack('>%dH' % segments, table[14:14 + 2 * segments])
    starts = struct.unpack('>%dH' % segments, table[16 + 2 * segments:16 + 4 * segments])
    deltas = struct.unpack('>%dh' % segments, table[16 + 4 * segments:16 + 6 * segments])
    range_base = 16 + 6 * segments
    range_offsets = struct.unpack('>%dH' % segments, table[range_base:range_base + 2 * segments])
    glyphs = {}
    for segment in range(segments):
        for code in range(starts[segment], ends[segment] + 1):
            if code == 0xFFFF:
                continue
            if range_offsets[segment] == 0:
                glyph = (code + deltas[segment]) & 0xFFFF
            else:
                position = range_base + 2 * segment + range_offsets[segment] + 2 * (code - starts[segment])
                glyph = struct.unpack('>H', table[position:position + 2])[0]
                if glyph:
                    glyph = (glyph + deltas[segment]) & 0xFFFF
            glyphs[code] = glyph
    return glyphs


def symbol_cmap(glyph_of):
    """A cmap with one (3, 0) subtable: codes 200 to 205 directly and the ASCII glyphs at 0xF020 to 0xF07E."""
    direct = [glyph_of[ord(c)] for c in 'BCDEFG']
    shifted = [glyph_of[code] for code in range(0x20, 0x7F)]
    segments = [(200, 205, direct), (0xF020, 0xF07E, shifted)]
    segment_count = len(segments) + 1
    ends = [last for _, last, _ in segments] + [0xFFFF]
    starts = [first for first, _, _ in segments] + [0xFFFF]
    deltas = [0] * len(segments) + [1]
    glyph_array = []
    offsets = []
    for index, (_, _, values) in enumerate(segments):
        offsets.append((segment_count - index) * 2 + 2 * len(glyph_array))
        glyph_array.extend(values)
    offsets.append(0)
    search_range = 2 * (1 << (segment_count.bit_length() - 1))
    entry_selector = segment_count.bit_length() - 1
    range_shift = 2 * segment_count - search_range
    body = struct.pack('>HHHH', 2 * segment_count, search_range, entry_selector, range_shift)
    body += struct.pack('>%dH' % segment_count, *ends) + struct.pack('>H', 0)
    body += struct.pack('>%dH' % segment_count, *starts)
    body += struct.pack('>%dh' % segment_count, *deltas)
    body += struct.pack('>%dH' % segment_count, *offsets)
    body += struct.pack('>%dH' % len(glyph_array), *glyph_array)
    subtable = struct.pack('>HH', 4, 6 + len(body)) + struct.pack('>H', 0) + body
    return struct.pack('>HH', 0, 1) + struct.pack('>HHI', 3, 0, 12) + subtable


def with_cmap(data, cmap):
    """The font with its cmap table replaced; the new table goes to the end of the file, the checksum is not updated."""
    count = struct.unpack('>H', data[4:6])[0]
    result = bytearray(data)
    for index in range(count):
        position = 12 + 16 * index
        if data[position:position + 4] == b'cmap':
            while len(result) % 4:
                result.append(0)
            offset = len(result)
            result.extend(cmap)
            result[position + 8:position + 16] = struct.pack('>II', offset, len(cmap))
            return bytes(result)
    raise ValueError('no cmap table')


class Pdf:
    def __init__(self):
        self.objects = {}

    def add(self, number, body):
        self.objects[number] = body.encode('latin-1') if isinstance(body, str) else body

    def stream(self, number, dictionary, data):
        header = '<< %s /Length %d >>\nstream\n' % (dictionary, len(data))
        self.objects[number] = header.encode('latin-1') + data + b'\nendstream'

    def build(self):
        output = bytearray(b'%PDF-1.7\n')
        offsets = {}
        for number in sorted(self.objects):
            offsets[number] = len(output)
            output += b'%d 0 obj\n' % number + self.objects[number] + b'\nendobj\n'
        xref = len(output)
        size = max(self.objects) + 1
        output += b'xref\n0 %d\n' % size
        output += b'0000000000 65535 f \n'
        for number in range(1, size):
            if number in offsets:
                output += b'%010d 00000 n \n' % offsets[number]
            else:
                output += b'0000000000 65535 f \n'
        output += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (size, xref)
        return bytes(output)


def document(font_body):
    """The catalog (1), page tree (2), page (3) and content (4); the font /F1 is object 10."""
    pdf = Pdf()
    pdf.add(1, '<< /Type /Catalog /Pages 2 0 R >>')
    pdf.add(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>')
    pdf.add(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 10 0 R >> >> >>')
    pdf.stream(4, '', CONTENT)
    pdf.add(10, font_body)
    return pdf


def simple_font(subtype, base_font, descriptor_entries, file_key, file_dictionary, file_data, encoding='/Encoding /WinAnsiEncoding'):
    pdf = document('<< /Type /Font /Subtype /%s /BaseFont /%s %s /FontDescriptor 11 0 R >>' % (subtype, base_font, encoding))
    pdf.add(11, '<< /Type /FontDescriptor /FontName /%s %s /%s 12 0 R >>' % (base_font, descriptor_entries, file_key))
    pdf.stream(12, file_dictionary, file_data)
    return pdf


def composite_font(descendant_subtype, base_font, file_key, file_dictionary, file_data, descendant_extra):
    pdf = document('<< /Type /Font /Subtype /Type0 /BaseFont /%s /Encoding /Identity-H /DescendantFonts [11 0 R] >>' % base_font)
    pdf.add(11, '<< /Type /Font /Subtype /%s /BaseFont /%s /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> '
                '/FontDescriptor 12 0 R /DW 1000 %s >>' % (descendant_subtype, base_font, descendant_extra))
    pdf.add(12, '<< /Type /FontDescriptor /FontName /%s %s /%s 13 0 R >>' % (base_font, DESCRIPTOR_ENTRIES % 4, file_key))
    pdf.stream(13, file_dictionary, file_data)
    return pdf


def garbage(length):
    return bytes((index * 131 + 7) & 0xFF for index in range(length))


def main():
    os.makedirs(OUT, exist_ok=True)
    liberation = read('LiberationSans-Regular.ttf')
    symbol_font = with_cmap(liberation, symbol_cmap(unicode_glyphs(liberation)))
    files = {
        'std14-helvetica': document('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'),
        'embedded-type1': simple_font('Type1', 'OpenSans-Regular', DESCRIPTOR_ENTRIES % 32, 'FontFile', '/Length1 0 /Length2 0 /Length3 0',
                                      read('OpenSans-Regular.pfb')),
        'embedded-cff': simple_font('Type1', 'SourceSansPro-Bold', DESCRIPTOR_ENTRIES % 32, 'FontFile3', '/Subtype /Type1C',
                                    cff_of('SourceSansProBold.otf')),
        'embedded-truetype': simple_font('TrueType', 'LiberationSans', DESCRIPTOR_ENTRIES % 32, 'FontFile2',
                                         '/Length1 %d' % len(liberation), liberation),
        'embedded-truetype-symbolic': simple_font('TrueType', 'LiberationSansSymbol', DESCRIPTOR_ENTRIES % 4, 'FontFile2',
                                                  '/Length1 %d' % len(symbol_font), symbol_font, encoding=''),
        'damaged-truetype': simple_font('TrueType', 'ArialMT', DESCRIPTOR_ENTRIES % 32, 'FontFile2', '/Length1 3000', garbage(3000)),
        'cid-type2-identity': composite_font('CIDFontType2', 'LiberationSans', 'FontFile2', '/Length1 %d' % len(liberation), liberation,
                                             '/CIDToGIDMap /Identity'),
        'cid-type0': composite_font('CIDFontType0', 'SourceSansPro-Bold', 'FontFile3', '/Subtype /CIDFontType0C',
                                    cff_of('SourceSansProBold.otf'), ''),
    }
    for name, pdf in files.items():
        with open(os.path.join(OUT, name + '.pdf'), 'wb') as stream:
            stream.write(pdf.build())
        print(name)


if __name__ == '__main__':
    main()
