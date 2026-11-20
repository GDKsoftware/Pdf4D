#!/usr/bin/env python3
"""Writes the test PDF files of tests/corpus/generated/render (standard library only).

images.pdf: one page with image XObjects of every kind that the image decoder handles (1, 2, 4, 8 and 16 bits, /Decode,
a colour key mask, a stencil mask, /SMask and /Mask streams, /Interpolate, DeviceCMYK, an ASCIIHexDecode image) and inline
images. The images are listed in the resource dictionary in the order of IMAGES; the oracle mode "images" writes
PDImageXObject.getImage() of each of them. The files are deterministic: run this script again and the bytes are the same.
"""
import os
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
OUT = os.path.join(ROOT, 'tests', 'corpus', 'generated', 'render')


def gradient_rgb(width, height):
    data = bytearray()
    for y in range(height):
        for x in range(width):
            data += bytes([x * 255 // max(width - 1, 1), y * 255 // max(height - 1, 1),
                           (x + y) * 255 // max(width + height - 2, 1)])
    return bytes(data)


def gray_ramp(width, height, bits):
    # Rows of width samples of `bits` bits, padded to a byte
    maximum = (1 << bits) - 1
    rows = bytearray()
    for y in range(height):
        accumulator = 0
        used = 0
        for x in range(width):
            value = ((x + y * width) * maximum) // max(width * height - 1, 1)
            if bits == 16:
                rows += value.to_bytes(2, 'big')
                continue
            accumulator = (accumulator << bits) | value
            used += bits
            if used == 8:
                rows.append(accumulator)
                accumulator = 0
                used = 0
        if used:
            rows.append(accumulator << (8 - used))
    return bytes(rows)


def checker_1bit(width, height):
    rows = bytearray()
    for y in range(height):
        for byte in range((width + 7) // 8):
            rows.append(0xAA if (y + byte) % 2 == 0 else 0x55)
    return bytes(rows)


def flate(data):
    return zlib.compress(data, 9), '/Filter /FlateDecode'


def raw(data):
    return data, ''


def hexed(data):
    return (data.hex().upper() + '>').encode('ascii'), '/Filter /ASCIIHexDecode'


KEY_PIXELS = bytearray(gradient_rgb(8, 8))
for index in (0, 9, 18, 27):
    KEY_PIXELS[index * 3:index * 3 + 3] = bytes([2, 3, 4])

# name, entries of the dictionary, data and filter, the /SMask or /Mask stream as (key, entries, data and filter)
IMAGES = [
    ('Im1bit', '/Width 8 /Height 8 /ColorSpace /DeviceGray /BitsPerComponent 1', raw(checker_1bit(8, 8)), None),
    ('Im2bit', '/Width 4 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 2', raw(gray_ramp(4, 4, 2)), None),
    ('Im4bit', '/Width 5 /Height 3 /ColorSpace /DeviceGray /BitsPerComponent 4', flate(gray_ramp(5, 3, 4)), None),
    ('Im8rgb', '/Width 8 /Height 8 /ColorSpace /DeviceRGB /BitsPerComponent 8', flate(gradient_rgb(8, 8)), None),
    ('Im16gray', '/Width 4 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 16', flate(gray_ramp(4, 4, 16)), None),
    ('Im1bitDecode', '/Width 8 /Height 8 /ColorSpace /DeviceGray /BitsPerComponent 1 /Decode [1 0]',
     raw(checker_1bit(8, 8)), None),
    ('Im8grayDecode', '/Width 4 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 8 /Decode [1 0]',
     flate(gray_ramp(4, 4, 8)), None),
    ('ImRgbDecode', '/Width 8 /Height 8 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Decode [1 0 0 1 0.2 0.8]',
     flate(gradient_rgb(8, 8)), None),
    ('ImColorKey', '/Width 8 /Height 8 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Mask [0 10 0 10 0 10]',
     flate(bytes(KEY_PIXELS)), None),
    ('ImStencil', '/Width 8 /Height 8 /ImageMask true', raw(checker_1bit(8, 8)), None),
    ('ImStencilDecode', '/Width 8 /Height 8 /ImageMask true /Decode [1 0]', raw(checker_1bit(8, 8)), None),
    ('ImSMask', '/Width 8 /Height 8 /ColorSpace /DeviceRGB /BitsPerComponent 8', flate(gradient_rgb(8, 8)),
     ('SMask', '/Type /XObject /Subtype /Image /Width 4 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 8',
      flate(gray_ramp(4, 4, 8)))),
    ('ImSMaskBig', '/Width 4 /Height 4 /ColorSpace /DeviceRGB /BitsPerComponent 8', flate(gradient_rgb(4, 4)),
     ('SMask', '/Type /XObject /Subtype /Image /Width 8 /Height 8 /ColorSpace /DeviceGray /BitsPerComponent 8',
      flate(gray_ramp(8, 8, 8)))),
    ('ImMask', '/Width 8 /Height 8 /ColorSpace /DeviceRGB /BitsPerComponent 8', flate(gradient_rgb(8, 8)),
     ('Mask', '/Type /XObject /Subtype /Image /Width 8 /Height 8 /ImageMask true /BitsPerComponent 1',
      raw(checker_1bit(8, 8)))),
    ('ImInterpolate', '/Width 4 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 8 /Interpolate true',
     flate(gray_ramp(4, 4, 8)), None),
    ('ImCmyk', '/Width 4 /Height 4 /ColorSpace /DeviceCMYK /BitsPerComponent 8',
     flate(bytes((x * 60 + c * 10) % 256 for y in range(4) for x in range(4) for c in range(4))), None),
    ('ImHex', '/Width 4 /Height 4 /ColorSpace /DeviceGray /BitsPerComponent 8', hexed(gray_ramp(4, 4, 8)), None),
]

INLINE_DATA = bytes(range(0, 240, 15))


def stream(dictionary, data):
    return ('%s /Length %d >>\nstream\n' % (dictionary, len(data))).encode('ascii') + data + b'\nendstream'


def serialize(objects):
    output = bytearray(b'%PDF-1.7\n')
    offsets = {}
    for number in sorted(objects):
        offsets[number] = len(output)
        output += b'%d 0 obj\n' % number + objects[number] + b'\nendobj\n'
    xref = len(output)
    count = max(objects) + 1
    output += b'xref\n0 %d\n' % count
    output += b'0000000000 65535 f \n'
    for number in range(1, count):
        output += b'%010d 00000 n \n' % offsets[number]
    output += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (count, xref)
    return bytes(output)


def build():
    objects = {}
    # 1 catalog, 2 pages, 3 page, 4 contents; the images from 5
    next_number = 5
    xobjects = []
    for name, entries, (data, filter_entry), extra in IMAGES:
        number = next_number
        next_number += 1
        xobjects.append((name, number))
        dictionary = '<< /Type /XObject /Subtype /Image %s %s' % (entries, filter_entry)
        if extra:
            key, extra_entries, (extra_data, extra_filter) = extra
            extra_number = next_number
            next_number += 1
            dictionary += ' /%s %d 0 R' % (key, extra_number)
            objects[extra_number] = stream('<< %s %s' % (extra_entries, extra_filter), extra_data)
        objects[number] = stream(dictionary, data)

    # The images in a grid of 5 columns, 50 x 50 points each
    content = ['0.9 0.9 0.6 rg 0 0 400 400 re f', '1 0 0 rg']
    for index, (name, number) in enumerate(xobjects):
        column = index % 5
        row = index // 5
        content.append('q 50 0 0 50 %d %d cm /%s Do Q' % (10 + column * 76, 330 - row * 76, name))
    # A small image (scaled down) and large ones (scaled up, rotated)
    content.append('q 3 0 0 3 10 10 cm /Im8rgb Do Q')
    content.append('q 120 0 0 60 60 10 cm /Im2bit Do Q')
    content.append('q 0 40 -60 0 300 10 cm /Im8rgb Do Q')
    # The inline images: gray, the abbreviated colour space with an ASCIIHex filter, and a stencil with /D
    inline = b'q 40 0 0 40 200 70 cm BI /W 4 /H 4 /BPC 8 /CS /G ID ' + INLINE_DATA + b' EI Q\n'
    inline += (b'q 40 0 0 40 250 70 cm BI /W 2 /H 2 /BPC 8 /CS /RGB /F /AHx ID '
               b'FF0000 00FF00 0000FF FFFF00 > EI Q\n')
    inline += b'q 40 0 0 40 300 70 cm BI /W 8 /H 8 /IM true /BPC 1 /D [1 0] ID ' + checker_1bit(8, 8) + b' EI Q\n'
    objects[4] = stream('<<', ('\n'.join(content) + '\n').encode('ascii') + inline)

    names = ' '.join('/%s %d 0 R' % item for item in xobjects)
    objects[1] = b'<< /Type /Catalog /Pages 2 0 R >>'
    objects[2] = b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>'
    objects[3] = ('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 400] /Contents 4 0 R '
                  '/Resources << /XObject << %s >> >> >>' % names).encode('ascii')
    return serialize(objects)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, 'images.pdf'), 'wb') as target:
        target.write(build())
