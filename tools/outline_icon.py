"""Give a transparent icon a clean dark outline around its silhouette (not every inner edge, which is
what Blender's Freestyle does), so it reads at ~20 px on any background.

  python tools/outline_icon.py blender/textures/icons/CoinIcon.png [thickness] [hex colour]
"""

import sys

from PIL import Image, ImageFilter

path = sys.argv[1]
thickness = int(sys.argv[2]) if len(sys.argv) > 2 else 14
color = sys.argv[3] if len(sys.argv) > 3 else "2a1600"

image = Image.open(path).convert("RGBA")
alpha = image.getchannel("A").point(lambda a: 255 if a > 40 else 0)
# Grow the silhouette by `thickness` pixels (MaxFilter needs an odd size)
grown = alpha
for _ in range(max(1, thickness // 6)):
    grown = grown.filter(ImageFilter.MaxFilter(13))
grown = grown.filter(ImageFilter.GaussianBlur(1.2))
rgb = tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))
outline = Image.new("RGBA", image.size, (*rgb, 0))
outline.putalpha(grown)
outline.alpha_composite(image)
outline.save(path)
print(f"outlined {path}")
