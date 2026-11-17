#!/usr/bin/env python3
"""
Lumen OS — Gerador de Assets de Branding do Calamares
Gera assets vetoriais (SVG) e raster reais (PNG) para o Calamares:
- logo.svg & logo.png (256x256)
- icon.svg & icon.png (64x64)
- welcome-splash.svg & welcome-splash.png (600x320)

Implementação em Python puro usando apenas a biblioteca padrão (struct, zlib, math).
"""

import math
from pathlib import Path
import struct
import zlib

BRANDING_DIR = Path(__file__).resolve().parent

LOGO_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <defs>
    <linearGradient id="primaryGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#748dff"/>
      <stop offset="100%" stop-color="#a970ff"/>
    </linearGradient>
    <linearGradient id="specularGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.8"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.1"/>
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#748dff" stop-opacity="0.45"/>
      <stop offset="100%" stop-color="#141822" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="256" height="256" rx="54" fill="#141822"/>
  <circle cx="128" cy="128" r="90" fill="url(#glow)"/>
  <rect x="24" y="24" width="208" height="208" rx="46" fill="rgba(255,255,255,0.05)" stroke="url(#specularGrad)" stroke-width="2.5"/>
  <!-- Emblema Lumen brilhante -->
  <path d="M 128 48 C 130 92, 164 126, 208 128 C 164 130, 130 164, 128 208 C 126 164, 92 130, 48 128 C 92 126, 126 92, 128 48 Z" fill="url(#primaryGrad)"/>
  <circle cx="128" cy="128" r="16" fill="#ffffff" opacity="0.9"/>
</svg>"""

ICON_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <defs>
    <linearGradient id="iconGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#748dff"/>
      <stop offset="100%" stop-color="#a970ff"/>
    </linearGradient>
    <linearGradient id="borderGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.7"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.15"/>
    </linearGradient>
  </defs>
  <rect x="3" y="3" width="58" height="58" rx="14" fill="#141822" stroke="url(#borderGrad)" stroke-width="1.5"/>
  <path d="M 32 11 C 33 23, 41 31, 53 32 C 41 33, 33 41, 32 53 C 31 41, 23 33, 11 32 C 23 31, 31 23, 32 11 Z" fill="url(#iconGrad)"/>
  <circle cx="32" cy="32" r="4" fill="#ffffff"/>
</svg>"""

SPLASH_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 320" width="600" height="320">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0d0f14"/>
      <stop offset="50%" stop-color="#141822"/>
      <stop offset="100%" stop-color="#1a1e27"/>
    </linearGradient>
    <linearGradient id="starGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#748dff"/>
      <stop offset="100%" stop-color="#a970ff"/>
    </linearGradient>
    <linearGradient id="borderGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.4"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.08"/>
    </linearGradient>
  </defs>
  <rect width="600" height="320" rx="26" fill="url(#bgGrad)" stroke="url(#borderGrad)" stroke-width="2"/>
  <path d="M -20 220 C 140 110, 300 270, 480 140 C 530 110, 580 130, 620 110" stroke="rgba(255,255,255,0.10)" stroke-width="42" fill="none"/>
  <path d="M -10 100 C 180 180, 360 50, 560 190" stroke="rgba(116,141,255,0.16)" stroke-width="28" fill="none"/>
  <g transform="translate(60, 95)">
    <path d="M 65 10 C 66 38, 92 64, 120 65 C 92 66, 66 92, 65 120 C 64 92, 38 66, 10 65 C 38 64, 64 38, 65 10 Z" fill="url(#starGrad)"/>
    <circle cx="65" cy="65" r="11" fill="#ffffff" opacity="0.95"/>
  </g>
  <text x="220" y="130" font-family="Inter, Ubuntu, sans-serif" font-size="34" font-weight="800" fill="#ffffff" letter-spacing="2">LUMEN OS</text>
  <text x="220" y="165" font-family="Inter, Ubuntu, sans-serif" font-size="16" font-weight="600" fill="#8da2ff">26.04 LTS • Resolute Raccoon</text>
  <text x="220" y="198" font-family="Inter, Ubuntu, sans-serif" font-size="13" fill="#94a3b8">Curved Glass Shell &amp; Developer Edition</text>
</svg>"""


def make_chunk(tag: bytes, data: bytes) -> bytes:
    chunk = tag + data
    crc = zlib.crc32(chunk) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + chunk + struct.pack(">I", crc)


def generate_png_logo(width=256, height=256) -> bytes:
    """Gera PNG RGBA 256x256 com moldura escura arredondada e emblema de estrela brilhante."""
    raw = bytearray()
    cx, cy = width / 2.0, height / 2.0
    r_corner = 54.0

    for y in range(height):
        raw.append(0)  # tipo de filtro 0
        for x in range(width):
            # Verifica os limites do retângulo arredondado
            dx = max(abs(x - cx) - (cx - r_corner), 0.0)
            dy = max(abs(y - cy) - (cy - r_corner), 0.0)
            dist_sq = dx * dx + dy * dy
            if dist_sq > r_corner * r_corner:
                # Transparente fora do retângulo arredondado
                raw.extend((0, 0, 0, 0))
                continue

            # Distância normalizada a partir do centro
            dist_center = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            nx = abs(x - cx) / cx
            ny = abs(y - cy) / cy

            # Fórmula do formato da estrela: (nx^0.5 + ny^0.5) <= 0.65
            star_val = math.sqrt(nx) + math.sqrt(ny) if nx >= 0 and ny >= 0 else 2.0

            if dist_center <= 16:
                # Ponto branco central
                raw.extend((255, 255, 255, 245))
            elif star_val <= 0.62:
                # Gradiente da estrela de periwinkle para violeta
                t = (x + y) / (width + height)
                r = int(116 + (169 - 116) * t)
                g = int(141 + (112 - 141) * t)
                b = int(255 + (255 - 255) * t)
                raw.extend((r, g, b, 255))
            elif dist_center <= 90:
                # Área de brilho suave
                glow = max(0.0, 1.0 - (dist_center / 90.0))
                r = int(20 + 96 * glow)
                g = int(24 + 117 * glow)
                b = int(34 + 221 * glow)
                raw.extend((r, g, b, 255))
            elif abs(max(dx, dy) - r_corner) < 3.0:
                # Borda especular
                raw.extend((255, 255, 255, 160))
            else:
                # Base escura obsidiana
                raw.extend((20, 24, 34, 255))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    compressed = zlib.compress(bytes(raw), 9)

    png = b"\x89PNG\r\n\x1a\n"
    png += make_chunk(b"IHDR", ihdr)
    png += make_chunk(b"IDAT", compressed)
    png += make_chunk(b"IEND", b"")
    return png


def generate_png_icon(width=64, height=64) -> bytes:
    """Gera PNG RGBA 64x64 com moldura escura arredondada e emblema de estrela central."""
    raw = bytearray()
    cx, cy = width / 2.0, height / 2.0
    r_corner = 14.0

    for y in range(height):
        raw.append(0)  # tipo de filtro 0
        for x in range(width):
            dx = max(abs(x - cx) - (cx - r_corner), 0.0)
            dy = max(abs(y - cy) - (cy - r_corner), 0.0)
            dist_sq = dx * dx + dy * dy
            if dist_sq > r_corner * r_corner:
                raw.extend((0, 0, 0, 0))
                continue

            dist_center = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            nx = abs(x - cx) / cx
            ny = abs(y - cy) / cy
            star_val = math.sqrt(nx) + math.sqrt(ny) if nx >= 0 and ny >= 0 else 2.0

            if dist_center <= 4:
                raw.extend((255, 255, 255, 250))
            elif star_val <= 0.65:
                t = (x + y) / (width + height)
                r = int(116 + (169 - 116) * t)
                g = int(141 + (112 - 141) * t)
                b = int(255)
                raw.extend((r, g, b, 255))
            elif abs(max(dx, dy) - r_corner) < 1.8:
                raw.extend((255, 255, 255, 140))
            else:
                raw.extend((20, 24, 34, 255))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    compressed = zlib.compress(bytes(raw), 9)

    png = b"\x89PNG\r\n\x1a\n"
    png += make_chunk(b"IHDR", ihdr)
    png += make_chunk(b"IDAT", compressed)
    png += make_chunk(b"IEND", b"")
    return png


def generate_png_splash(width=600, height=320) -> bytes:
    """Gera o banner de boas-vindas em PNG RGBA 600x320."""
    raw = bytearray()
    r_corner = 26.0

    # Centro do emblema de estrela no banner
    star_cx, star_cy = 125.0, 160.0

    for y in range(height):
        raw.append(0)  # tipo de filtro 0
        for x in range(width):
            # Verifica os limites do banner arredondado
            dx = max(abs(x - width / 2.0) - (width / 2.0 - r_corner), 0.0)
            dy = max(abs(y - height / 2.0) - (height / 2.0 - r_corner), 0.0)
            dist_sq = dx * dx + dy * dy
            if dist_sq > r_corner * r_corner:
                raw.extend((0, 0, 0, 0))
                continue

            # Borda especular
            if abs(max(dx, dy) - r_corner) < 2.0:
                raw.extend((255, 255, 255, 90))
                continue

            # Coordenadas do emblema de estrela
            dist_star = math.sqrt((x - star_cx) ** 2 + (y - star_cy) ** 2)
            nx = abs(x - star_cx) / 55.0
            ny = abs(y - star_cy) / 55.0
            star_val = (math.sqrt(nx) + math.sqrt(ny)) if (nx <= 1.0 and ny <= 1.0) else 2.0

            # Padrão ambiente de ondas curvas
            wave1 = math.sin((x * 0.012) + (y * 0.015))
            wave2 = math.cos((x * 0.018) - (y * 0.012))
            is_wave = (abs(wave1) < 0.08) or (abs(wave2) < 0.06)

            if dist_star <= 10:
                raw.extend((255, 255, 255, 245))
            elif star_val <= 0.65:
                t = (x + y) / (width + height)
                r = int(116 + (169 - 116) * t)
                g = int(141 + (112 - 141) * t)
                b = 255
                raw.extend((r, g, b, 255))
            elif dist_star <= 80:
                glow = max(0.0, 1.0 - (dist_star / 80.0))
                r = int(14 + 100 * glow)
                g = int(18 + 120 * glow)
                b = int(28 + 220 * glow)
                raw.extend((r, g, b, 255))
            elif is_wave:
                raw.extend((70, 85, 130, 255))
            else:
                # Fundo em gradiente de #0d0f14 para #1a1e27
                t_bg = (x + y) / (width + height)
                r = int(13 + (26 - 13) * t_bg)
                g = int(15 + (30 - 15) * t_bg)
                b = int(20 + (39 - 20) * t_bg)
                raw.extend((r, g, b, 255))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    compressed = zlib.compress(bytes(raw), 9)

    png = b"\x89PNG\r\n\x1a\n"
    png += make_chunk(b"IHDR", ihdr)
    png += make_chunk(b"IDAT", compressed)
    png += make_chunk(b"IEND", b"")
    return png


def main():
    BRANDING_DIR.mkdir(parents=True, exist_ok=True)

    print("[Assets] Gerando SVGs...")
    (BRANDING_DIR / "logo.svg").write_text(LOGO_SVG, encoding="utf-8")
    (BRANDING_DIR / "icon.svg").write_text(ICON_SVG, encoding="utf-8")
    (BRANDING_DIR / "welcome-splash.svg").write_text(SPLASH_SVG, encoding="utf-8")

    print("[Assets] Gerando logo.png (256x256)...")
    logo_png = generate_png_logo(256, 256)
    (BRANDING_DIR / "logo.png").write_bytes(logo_png)

    print("[Assets] Gerando icon.png (64x64)...")
    icon_png = generate_png_icon(64, 64)
    (BRANDING_DIR / "icon.png").write_bytes(icon_png)

    print("[Assets] Gerando welcome-splash.png (600x320)...")
    splash_png = generate_png_splash(600, 320)
    (BRANDING_DIR / "welcome-splash.png").write_bytes(splash_png)

    print("[Assets] Todos os assets de branding foram gerados com sucesso em:", BRANDING_DIR)


if __name__ == "__main__":
    main()
