#!/usr/bin/env python3
"""Writes the small test files of tests/corpus/generated/extract (standard library only, deterministic).

images-rotated: the same image on pages with /Rotate 0, 90, 180 and 270 and a CropBox with an offset.
images-reuse:   one XObject drawn five times, an image in a form, an inline image and a form that draws itself.
images-filters: images with DCT, Flate, Flate and DCT, CCITT, Indexed, CMYK, ICCBased, a soft mask, a mask, a stencil, damaged Flate data and
                a JPX stream that is not valid JPEG 2000 (the files are only listed, not decoded, by the image listing).
Run this script again and the bytes are the same. The CCITT stream comes from tests/corpus/generated/render/ccitt.pdf.
"""
import importlib.util
import os
import re
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
OUT = os.path.join(ROOT, 'tests', 'corpus', 'generated', 'extract')

_spec = importlib.util.spec_from_file_location('render_pdfs', os.path.join(HERE, 'make-render-pdfs.py'))
render_pdfs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(render_pdfs)
Doc = render_pdfs.Doc
read = render_pdfs.read


def write(name, doc):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + '.pdf'), 'wb') as stream:
        stream.write(doc.build())
    print(name)


def rgb_image(doc, extra='', width=2, height=2, compress=False):
    data = bytes((x * 60 + y * 30 + c * 20) % 256 for y in range(height) for x in range(width) for c in range(3))
    return doc.stream('/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 %s'
                      % (width, height, extra), data, compress)


# ---------------------------------------------------------------------------------------------------------- rotated
def images_rotated():
    doc = Doc()
    image = rgb_image(doc)
    for rotate in (0, 90, 180, 270):
        doc.page('q 100 0 0 50 120 200 cm /Im0 Do Q', '/XObject << /Im0 %d 0 R >>' % image, '0 0 600 800',
                 extra='/CropBox [50 100 550 700] /Rotate %d' % rotate)
    write('images-rotated', doc)


# ------------------------------------------------------------------------------------------------------------ reuse
def images_reuse():
    doc = Doc()
    shared = rgb_image(doc)
    other = rgb_image(doc, width=3, height=1)
    third = rgb_image(doc, width=1, height=3)
    form = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Matrix [1 0 0 1 0 0] '
                      '/Resources << /XObject << /ImF %d 0 R >> >>' % other, 'q 40 0 0 20 5 5 cm /ImF Do Q')
    # A form that draws an image and then itself: the engine must stop at the second Do
    loop_number = doc.next_number
    loop = doc.stream('/Type /XObject /Subtype /Form /BBox [0 0 100 100] '
                      '/Resources << /XObject << /ImL %d 0 R /FmLoop %d 0 R >> >>' % (third, loop_number),
                      'q 10 0 0 30 0 0 cm /ImL Do Q /FmLoop Do')
    assert loop == loop_number
    content = []
    for i in range(5):
        content.append('q 30 0 0 30 %d 600 cm /Im0 Do Q' % (20 + i * 50))
    content.append('q 1 0 0 1 300 300 cm /Fm0 Do Q')
    content.append('q 50 0 0 50 100 100 cm BI /W 2 /H 2 /CS /RGB /BPC 8 /F /AHx ID 0000FF 00FF00 FF0000 FFFFFF> EI Q')
    content.append('q 1 0 0 1 200 200 cm /FmLoop Do Q')
    doc.page('\n'.join(content), '/XObject << /Im0 %d 0 R /Fm0 %d 0 R /FmLoop %d 0 R >>' % (shared, form, loop), '0 0 600 800')
    write('images-reuse', doc)


# ---------------------------------------------------------------------------------------------------------- filters
def jpeg_size(data):
    position = 2
    while position < len(data):
        marker = data[position + 1]
        length = int.from_bytes(data[position + 2:position + 4], 'big')
        if marker in (0xC0, 0xC1, 0xC2):
            return int.from_bytes(data[position + 7:position + 9], 'big'), int.from_bytes(data[position + 5:position + 7], 'big')
        position += 2 + length
    raise ValueError('no frame header')


def ccitt_stream():
    """The dictionary entries and the data of the first CCITT image of render/ccitt.pdf, with the decode parameters inline."""
    pdf = read(os.path.join(ROOT, 'tests', 'corpus', 'generated', 'render', 'ccitt.pdf'))
    for match in re.finditer(rb'<<\n/Length (\d+)\n(.*?)>>\nstream\r?\n', pdf, re.DOTALL):
        entries = match.group(2).decode('latin-1')
        if '/CCITTFaxDecode' not in entries:
            continue
        data = pdf[match.end():match.end() + int(match.group(1))]
        # The parameters of the first image are in an object stream: Columns 96, Rows 64, BlackIs1 true, K -1 (Group 4)
        entries = re.sub(r'/DecodeParms \d+ 0 R', '/DecodeParms << /Columns 96 /Rows 64 /BlackIs1 true /K -1 >>', entries)
        return entries.replace('\n', ' '), data
    raise ValueError('no CCITT image in ccitt.pdf')


def images_filters():
    doc = Doc()
    jpeg = read(os.path.join(ROOT, 'tests', 'reference', 'jpeg', 'rgb444.jpg'))
    jpeg_width, jpeg_height = jpeg_size(jpeg)
    jpeg_dict = '/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8' % (jpeg_width, jpeg_height)
    images = []

    # 0 DCT
    images.append(doc.stream(jpeg_dict + ' /Filter /DCTDecode', jpeg))
    # 1 Flate RGB
    images.append(rgb_image(doc, width=4, height=4, compress=True))
    # 2 Flate and DCT
    images.append(doc.stream(jpeg_dict + ' /Filter [/FlateDecode /DCTDecode]', zlib.compress(jpeg, 9)))
    # 3 CCITT
    ccitt_dict, ccitt_data = ccitt_stream()
    images.append(doc.stream(ccitt_dict, ccitt_data))
    # 4 Indexed
    palette = '<FF0000 00FF00 0000FF FFFF00>'
    images.append(doc.stream('/Type /XObject /Subtype /Image /Width 4 /Height 4 /ColorSpace [/Indexed /DeviceRGB 3 %s] /BitsPerComponent 8' % palette,
                             bytes((x + y) % 4 for y in range(4) for x in range(4))))
    # 5 CMYK
    images.append(doc.stream('/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceCMYK /BitsPerComponent 8',
                             bytes(range(0, 64, 4))))
    # 6 SMask
    smask = doc.stream('/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8', bytes([0, 85, 170, 255]))
    images.append(rgb_image(doc, extra='/SMask %d 0 R' % smask, compress=True))
    # 7 stencil mask
    images.append(doc.stream('/Type /XObject /Subtype /Image /Width 8 /Height 8 /ImageMask true /BitsPerComponent 1',
                             bytes([0xAA, 0x55] * 4)))
    # 8 damaged Flate data
    images.append(doc.stream('/Type /XObject /Subtype /Image /Width 4 /Height 4 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode',
                             b'this is not zlib data at all'))
    # 9 JPX that is not valid JPEG 2000
    images.append(doc.stream('/Type /XObject /Subtype /Image /Width 4 /Height 4 /Filter /JPXDecode', b'\x00\x00\x00\x0cjP  \r\n\x87\n stub'))
    # 10 ICCBased
    profile = doc.stream('/N 3 /Alternate /DeviceRGB', read(os.path.join(ROOT, 'tests', 'icc', 'sRGB.icc')), compress=True)
    images.append(doc.stream('/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace [/ICCBased %d 0 R] /BitsPerComponent 8' % profile,
                             bytes(range(12))))
    # 11 explicit /Mask (a stencil image)
    stencil = doc.stream('/Type /XObject /Subtype /Image /Width 2 /Height 2 /ImageMask true /BitsPerComponent 1', bytes([0x80, 0x40]))
    images.append(rgb_image(doc, extra='/Mask %d 0 R' % stencil))

    content = []
    names = []
    for index, number in enumerate(images):
        names.append('/Im%d %d 0 R' % (index, number))
        content.append('q 40 0 0 40 %d %d cm /Im%d Do Q' % (20 + (index % 6) * 60, 700 - (index // 6) * 60, index))
    doc.page('\n'.join(content), '/XObject << %s >>' % ' '.join(names), '0 0 400 800')
    write('images-filters', doc)


if __name__ == '__main__':
    images_rotated()
    images_reuse()
    images_filters()
