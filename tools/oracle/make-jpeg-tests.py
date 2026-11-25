#!/usr/bin/env python3
"""Writes tests/corpus/generated/render/jpeg.pdf and the JPEG files of tests/reference/jpeg (needs Pillow, only to run this script).

The test images are drawn deterministically (gradients, shapes and a fixed pseudo random texture) in sizes that are no multiple of
8 or 16, and saved as baseline gray, baseline RGB 4:2:0 and 4:4:4, progressive, with a restart interval, and CMYK. Three JPEG
files of the PDFBox test resources (jpeg.jpg, jpeg256.jpg, jpegcmyk.jpg, a YCCK file) are copied from tools/pdfbox-src when it is
there (tools/fetch-pdfbox-src.ps1). The images are listed in the resource dictionary in the order of IMAGES; the oracle mode
"images" writes PDImageXObject.getImage() of each of them. The JPEG files are committed, so the output does not depend on the
version of Pillow that is installed when this script runs again.
"""
import io
import os
import shutil

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
OUT = os.path.join(ROOT, 'tests', 'corpus', 'generated', 'render')
REFERENCE = os.path.join(ROOT, 'tests', 'reference', 'jpeg')
PDFBOX_RESOURCES = os.path.join(ROOT, 'tools', 'pdfbox-src', 'pdfbox', 'src', 'test', 'resources', 'org', 'apache', 'pdfbox',
                                'pdmodel', 'graphics', 'image')


def texture(width, height):
    image = Image.new('RGB', (width, height))
    pixels = image.load()
    state = 12345
    for y in range(height):
        for x in range(width):
            state = (state * 1103515245 + 12345) & 0x7FFFFFFF
            noise = (state >> 16) % 24
            pixels[x, y] = ((x * 255 // max(width - 1, 1) + noise) % 256, (y * 255 // max(height - 1, 1) + noise) % 256,
                            ((x + y) * 255 // max(width + height - 2, 1) + 2 * noise) % 256)
    draw = ImageDraw.Draw(image)
    draw.ellipse((width // 8, height // 8, width * 5 // 8, height * 6 // 8), fill=(200, 30, 40), outline=(255, 255, 255))
    draw.rectangle((width // 2, height // 2, width * 7 // 8, height * 7 // 8), fill=(20, 60, 220))
    draw.line((0, height - 1, width - 1, 0), fill=(255, 255, 0), width=2)
    # Soft edges: a JPEG of hard saturated edges differs most between nearest neighbour and interpolating upsampling
    return image.filter(ImageFilter.GaussianBlur(1.2))


def encode(image, **options):
    buffer = io.BytesIO()
    image.save(buffer, 'JPEG', **options)
    return buffer.getvalue()


def generated_files():
    rgb = texture(61, 45)
    files = {
        'gray.jpg': encode(rgb.convert('L'), quality=85),
        'rgb420.jpg': encode(rgb, quality=85, subsampling=2),
        'rgb444.jpg': encode(rgb, quality=90, subsampling=0),
        'progressive.jpg': encode(rgb, quality=85, subsampling=2, progressive=True),
        'restart.jpg': encode(rgb, quality=85, subsampling=2, restart_marker_blocks=3),
        'cmyk.jpg': encode(rgb.convert('CMYK'), quality=90),
    }
    return files


def copied_files():
    files = {}
    for name in ('jpeg.jpg', 'jpeg256.jpg', 'jpegcmyk.jpg'):
        path = os.path.join(PDFBOX_RESOURCES, name)
        if os.path.exists(path):
            with open(path, 'rb') as source:
                files['pdfbox-' + name] = source.read()
    return files


# name, file, size, colour space entries; the last two entries of a CMYK image carry /Decode
IMAGES = [
    ('JpegGray', 'gray.jpg', (61, 45), '/DeviceGray', ''),
    ('JpegRgb420', 'rgb420.jpg', (61, 45), '/DeviceRGB', ''),
    ('JpegRgb444', 'rgb444.jpg', (61, 45), '/DeviceRGB', ''),
    ('JpegProgressive', 'progressive.jpg', (61, 45), '/DeviceRGB', ''),
    ('JpegRestart', 'restart.jpg', (61, 45), '/DeviceRGB', ''),
    ('JpegCmyk', 'cmyk.jpg', (61, 45), '/DeviceCMYK', ''),
    ('JpegCmykInverted', 'cmyk.jpg', (61, 45), '/DeviceCMYK', '/Decode [1 0 1 0 1 0 1 0]'),
    ('PdfboxRgb', 'pdfbox-jpeg.jpg', (344, 287), '/DeviceRGB', ''),
    ('PdfboxGray', 'pdfbox-jpeg256.jpg', (344, 287), '/DeviceGray', ''),
    ('PdfboxYcck', 'pdfbox-jpegcmyk.jpg', (343, 287), '/DeviceCMYK', ''),
    ('PdfboxYcckInverted', 'pdfbox-jpegcmyk.jpg', (343, 287), '/DeviceCMYK', '/Decode [1 0 1 0 1 0 1 0]'),
]


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


def build(files):
    objects = {}
    next_number = 5
    xobjects = []
    for name, file, (width, height), color_space, extra in IMAGES:
        number = next_number
        next_number += 1
        xobjects.append((name, number))
        objects[number] = stream('<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace %s /BitsPerComponent 8 '
                                 '/Filter /DCTDecode %s' % (width, height, color_space, extra), files[file])
    content = ['0.9 0.9 0.6 rg 0 0 400 400 re f']
    for index, (name, number) in enumerate(xobjects):
        column = index % 4
        row = index // 4
        content.append('q 80 0 0 70 %d %d cm /%s Do Q' % (10 + column * 95, 320 - row * 90, name))
    objects[4] = stream('<<', ('\n'.join(content) + '\n').encode('ascii'))
    names = ' '.join('/%s %d 0 R' % item for item in xobjects)
    objects[1] = b'<< /Type /Catalog /Pages 2 0 R >>'
    objects[2] = b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>'
    objects[3] = ('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 400] /Contents 4 0 R '
                  '/Resources << /XObject << %s >> >> >>' % names).encode('ascii')
    return serialize(objects)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(REFERENCE, exist_ok=True)
    files = {}
    existing = os.listdir(REFERENCE)
    for name in existing:
        with open(os.path.join(REFERENCE, name), 'rb') as source:
            files[name] = source.read()
    files.update(copied_files())
    if not os.path.exists(os.path.join(REFERENCE, 'rgb420.jpg')):
        files.update(generated_files())
    for name, data in files.items():
        with open(os.path.join(REFERENCE, name), 'wb') as target:
            target.write(data)
    with open(os.path.join(OUT, 'jpeg.pdf'), 'wb') as target:
        target.write(build(files))
