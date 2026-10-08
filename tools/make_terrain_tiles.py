#!/usr/bin/env python3
"""Achata os tiles de terreno do kit de ruínas em PNG de paleta (ColorType 3).

Os PNGs originais são RGBA8 com borda transparente. Num sandbox com driver
problemático, textura sem canal de paleta não renderiza (volta branco), e num
tile quadrado a transparência não serve para nada mesmo. Então: achata sobre
fundo opaco e quantiza para <=256 cores.

Uso:  python tools/make_terrain_tiles.py
"""
import os
import struct
import zlib

SRC = r"C:\Repos\the-game\assets\top-down-ruins-pixel-art\PNG\Assets"
DST = r"C:\Repos\the-game\assets\generated\terrain"
BG = (29, 26, 38, 255)

MAPPING = {
    "water": "Water_ruins5.png",
    "fire": "Yellow_ruins5.png",
    "earth": "Brown_ruins5.png",
    "frost": "Snow_ruins5.png",
    "shadow": "Blue-gray_ruins5.png",
}

SIZE = 32


def read_rgba(path):
    """Decodifica PNG 8-bit (color types 2, 3 e 6) via zlib + unfilter."""
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "nao e png"
    pos, idat, pal, trns = 8, b"", [], b""
    w = h = depth = ctype = None
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8, f"bit depth {depth} nao suportado"
        elif typ == b"PLTE":
            pal = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif typ == b"tRNS":
            trns = body
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
        pos += 12 + ln

    raw = zlib.decompress(idat)
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    stride = w * nch
    out, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        ft = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        for i in range(stride):
            a = line[i - nch] if i >= nch else 0
            b = prev[i]
            c = prev[i - nch] if i >= nch else 0
            x = line[i]
            if ft == 1:
                x += a
            elif ft == 2:
                x += b
            elif ft == 3:
                x += (a + b) // 2
            elif ft == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                x += a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            line[i] = x & 0xFF
        out.append(bytes(line))
        prev = line

    px = []
    for y in range(h):
        row = out[y]
        r = []
        for x in range(w):
            if ctype == 6:
                q = row[x * 4:x * 4 + 4]
            elif ctype == 2:
                q = row[x * 3:x * 3 + 3] + b"\xff"
            elif ctype == 3:
                idx = row[x]
                q = bytes(pal[idx]) + (bytes([trns[idx]]) if idx < len(trns) else b"\xff")
            elif ctype == 0:
                q = bytes([row[x]] * 3) + b"\xff"
            else:
                q = row[x * 2:x * 2 + 2] + b"\xff"
            r.append(tuple(q))
        px.append(r)
    return w, h, px


def write_palette_png(path, pixels):
    """Grava PNG 8-bit ColorType 3 (paleta), que e o formato que os sprites
    deste projeto ja usam."""
    flat = [c for row in pixels for c in row]
    colors = []
    index = {}
    for c in flat:
        if c not in index:
            index[c] = len(colors)
            colors.append(c)
    assert len(colors) <= 256, f"precisa de {len(colors)} cores, o maximo e 256"

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 3, 0, 0, 0)
    plte = b"".join(bytes(c[:3]) for c in colors)

    raw = b"".join(
        b"\x00" + bytes(index[c] for c in row) for row in pixels
    )

    def chunk(typ, body):
        return (struct.pack(">I", len(body)) + typ + body
                + struct.pack(">I", zlib.crc32(typ + body) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"PLTE", plte)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(png)
    return len(colors)


def flatten(src):
    _, _, px = read_rgba(src)
    return [
        [
            BG if c[3] < 128 else (c[0], c[1], c[2], 255)
            for c in row
        ]
        for row in px
    ]


os.makedirs(DST, exist_ok=True)
for name, fname in MAPPING.items():
    flat = flatten(os.path.join(SRC, fname))
    n = write_palette_png(os.path.join(DST, f"{name}.png"), flat)
    print(f"{name:7s} <- {fname:22s} {n} cores")
