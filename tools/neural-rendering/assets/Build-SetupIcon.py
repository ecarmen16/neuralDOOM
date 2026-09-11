# SPDX-License-Identifier: GPL-3.0-or-later
"""Original neuralDOOM doorway/circuit emblem. Requires Pillow, for asset authoring only."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).parent
image = Image.new('RGBA', (1024, 1024))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((24, 24, 1000, 1000), radius=200, fill='#13161b')
# Beveled, open doorway with a neural circuit crossing its dark interior.
draw.polygon([(236, 160), (656, 160), (816, 320), (816, 704),
              (656, 864), (236, 864)], fill='#e84a3a')
draw.polygon([(368, 296), (596, 296), (680, 380), (680, 644),
              (596, 728), (368, 728)], fill='#13161b')
draw.line([(160, 640), (432, 640), (552, 464), (864, 464)], fill='#f0efec', width=40)
for x, y in [(160, 640), (552, 464), (864, 464)]:
    draw.ellipse((x-38, y-38, x+38, y+38), fill='#f0efec')
image.save(root / 'neuraldoom-setup.ico', sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
