# Prompts de logo: Ultrawrail

Copia y pega cada bloque tal cual. No hay variables que rellenar.

## 1. Icono de la app

```
macOS app icon for "Ultrawrail", a window manager for ultrawide monitors. Square 1024x1024 canvas with the standard macOS Big Sur squircle shape, transparent background outside the squircle. Inside: a deep blue-to-indigo diagonal gradient background (#1B2A6B to #0E131F). Centered, a horizontal strip of four tall rounded rectangles (window panes) side by side with thin even gaps, each a different width: the second pane from the left is wider and glows bright blue (#2F6BFF to #7AA2FF), the other three are frosted slate-blue glass (#3A4663, soft inner light on the top edge). The outer two panes are cropped by the edges of the icon, as if the strip keeps going beyond the frame. Under the panes runs a thin continuous rounded horizontal rail bar in turquoise (#00C2A8) that spans the whole width of the icon, with a soft glow. Subtle soft shadow under the panes, thin white highlight along the top edge of the squircle, clean geometric flat-vector style with gentle depth, consistent rounded corners. Must stay readable at 16px: few shapes, high contrast. No text, no letters, no logos, no trademarks, no people, no photo, no window title bars, no traffic-light buttons, no train tracks, no scrollbar look. Centered composition, front view, no perspective.
```

## 2. Icono de la barra de menús

```
macOS menu bar template icon, 18x18 pt (export 18, 36 and 54 px), pure black on fully transparent background, no gradients, no shadows, no partial transparency. Simple glyph: three tall rounded vertical rectangles side by side with thin even gaps, the middle one wider, the outer two cropped by the edges of the canvas, above one thin continuous horizontal rounded bar (a rail) running the full width. Solid fills, minimum stroke 1.5 pt, glyph about 16 pt tall, geometric, must be legible at 18 px. No text, no outline, no color.
```

## Entrega

- Icono de la app: PNG 1024 x 1024, sRGB, con transparencia. Después genera el set `.icns` con los tamaños 16, 32, 64, 128, 256, 512 y 1024 px (1x y 2x).
- Icono de menú: `MenuBarIconTemplate.png` (18 px), `@2x` (36 px) y `@3x` (54 px). El sufijo `Template` hace que macOS lo tiña según el tema claro u oscuro.
- Si la herramienta ignora la transparencia o dibuja el squircle por su cuenta, pide solo el motivo (paneles y carril) sobre fondo liso y aplica la máscara de macOS después.
