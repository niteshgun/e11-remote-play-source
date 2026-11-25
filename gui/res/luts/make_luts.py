# Generates e11's built-in creative LUTs (.cube, 17^3, normalized Rec.709-encoded RGB in/out).
import numpy as np, sys, os
N = 17
out = sys.argv[1]
g = np.linspace(0, 1, N)
# .cube order: R fastest, then G, then B
b, gg, r = np.meshgrid(g, g, g, indexing='ij')
rgb = np.stack([r, gg, b], -1).reshape(-1, 3)

def luma(c): return c @ np.array([0.2126, 0.7152, 0.0722])
def sat(c, s):
    y = luma(c)[:, None]; return y + (c - y) * s
def scurve(c, k):  # contrast around 0.5, smooth
    return np.clip(0.5 + (c - 0.5) * k - 4 * (k - 1) * (c - 0.5) ** 3, 0, 1)
def tint(c, shadows, highs, amt):
    y = luma(c)[:, None]
    ws = np.clip(1 - y * 2, 0, 1) ** 1.5; wh = np.clip(y * 2 - 1, 0, 1) ** 1.5
    return c + amt * (ws * (np.array(shadows) - 0.5) + wh * (np.array(highs) - 0.5))
def lift(c, black, white=1.0): return black + c * (white - black)

looks = {
  "Cinematic": lambda c: sat(tint(scurve(c, 1.12), (0.30, 0.52, 0.60), (0.66, 0.52, 0.38), 0.32), 1.05),
  "Warm Film": lambda c: sat(lift(tint(scurve(c, 1.05), (0.52, 0.48, 0.42), (0.62, 0.53, 0.42), 0.30), 0.035, 0.97), 0.92),
  "Cool Night": lambda c: sat(tint(scurve(c, 1.08) ** 1.06, (0.38, 0.46, 0.66), (0.46, 0.52, 0.60), 0.35), 0.85),
  "Vivid Pop": lambda c: sat(scurve(c, 1.10), 1.28),
  "Vice Sunset": lambda c: sat(tint(scurve(c, 1.10), (0.34, 0.50, 0.66), (0.72, 0.46, 0.56), 0.38), 1.18),
  "Noir": lambda c: np.repeat(scurve(luma(c), 1.25)[:, None], 3, 1),
}
os.makedirs(out, exist_ok=True)
for name, f in looks.items():
    o = np.clip(f(rgb.copy()), 0, 1)
    fn = os.path.join(out, name.lower().replace(' ', '_') + '.cube')
    with open(fn, 'w') as fh:
        fh.write(f'TITLE "e11 {name}"\nLUT_3D_SIZE {N}\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 1 1 1\n')
        for row in o: fh.write(f'{row[0]:.5f} {row[1]:.5f} {row[2]:.5f}\n')
    # sanity: grey ramp stays monotonic, black/white
    print(name, 'black', o[0].round(3), 'white', o[-1].round(3))
