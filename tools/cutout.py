# Converts magenta (1,0,1) marker pixels into transparency (used to cut painted-on wheels out of body textures).
import sys
from PIL import Image
import numpy as np
for f in sys.argv[1:]:
    im = np.array(Image.open(f).convert("RGBA")).astype(np.int16)
    mask = (im[..., 0] > 230) & (im[..., 1] < 30) & (im[..., 2] > 230)
    im[..., 3] = np.where(mask, 0, 255)
    im[mask, :3] = 20
    Image.fromarray(im.astype(np.uint8), "RGBA").save(f)
    print("cutout", f, int(mask.sum()))
