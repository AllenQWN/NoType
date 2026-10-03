#!/usr/bin/env python3
"""用纯 Python 组装 .icns（绕过 iconutil / sips 转格式在沙箱里的限制）。
用法: make_icns.py <out.icns> <png1> <png2> ...
每个 PNG 的实际尺寸从 IHDR 读取，自动匹配 icns 类型。"""
import struct
import sys

TYPE_MAP = {
    16: 'icp4', 32: 'icp5', 64: 'icp6',
    128: 'ic07', 256: 'ic08', 512: 'ic09', 1024: 'ic10',
}


def png_size(data: bytes) -> int:
    # IHDR 里 width 在 offset 16，height 在 20
    return struct.unpack('>I', data[16:20])[0]


def build(out: str, pngs):
    chunks = []
    for path in pngs:
        with open(path, 'rb') as f:
            data = f.read()
        if data[:8] != b'\x89PNG\r\n\x1a\n':
            print(f'skip not-png: {path}', file=sys.stderr)
            continue
        w = png_size(data)
        t = TYPE_MAP.get(w)
        if not t:
            print(f'skip unknown size {w}: {path}', file=sys.stderr)
            continue
        chunks.append(t.encode('latin1') + struct.pack('>I', len(data) + 8) + data)

    if not chunks:
        print('no valid png', file=sys.stderr)
        sys.exit(1)

    total = 8 + sum(len(c) for c in chunks)
    with open(out, 'wb') as f:
        f.write(b'icns' + struct.pack('>I', total))
        for c in chunks:
            f.write(c)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('usage: make_icns.py out.icns png1 [png2 ...]', file=sys.stderr)
        sys.exit(1)
    build(sys.argv[1], sys.argv[2:])