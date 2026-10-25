# Prompt de logo e icono: Ultrawrail

Prompt listo para pegar en una herramienta de diseño o de generación de imágenes. Sustituye `[VARIANTE]` por A, B o C (ver abajo).

---

## Prompt principal

Diseña el icono de aplicación de **Ultrawrail**, un gestor de ventanas nativo para macOS que vive en la barra de menús. Ultrawrail organiza las ventanas en **columnas sobre una tira horizontal que se desplaza** (scrolling window manager, al estilo de niri o PaperWM) y está pensado también para monitores ultrawide: la tira se extiende más allá de los bordes de la pantalla y el foco la desliza.

### Concepto visual

- Una **tira horizontal de 3 a 4 paneles verticales** (columnas) de distinto ancho, alineados lado a lado con huecos finos y regulares entre ellos.
- **Sensación de desplazamiento:** los paneles de los extremos quedan cortados por el borde del icono, como si la tira continuara fuera del encuadre. Un panel central, algo más ancho, es el "enfocado" y destaca en color.
- **Carril ("rail"):** bajo los paneles corre un **carril** fino y continuo, una barra horizontal redondeada que atraviesa todo el icono de lado a lado y por la que los paneles se deslizan. El nombre es *pane* (panel de ventana) + *rail* (carril): el icono debe leerse como "paneles sobre un riel", sin parecer una vía de tren literal ni una barra de desplazamiento.
- Composición horizontal, centrada, con un ligero desplazamiento hacia la derecha para sugerir movimiento.

### Estilo

- macOS Big Sur o posterior: base en **squircle** (superelipse continua, no rectángulo con esquinas redondeadas simples) sobre una cuadrícula de 1024 px con el margen estándar de icono de macOS.
- Profundidad sutil: una sombra suave bajo los paneles, un brillo fino en el borde superior y un degradado muy ligero. Nada de relieves exagerados ni biselados.
- Formas geométricas limpias, esquinas redondeadas coherentes, trazo uniforme.

### Paleta propuesta

| Rol | Modo claro | Modo oscuro |
|-----|------------|-------------|
| Fondo del squircle (degradado) | `#F4F7FB` a `#DCE4F0` | `#1B2233` a `#0E131F` |
| Paneles secundarios | `#B8C4D9` | `#3A4663` |
| Panel enfocado | `#2F6BFF` a `#5B8CFF` | `#4D83FF` a `#7AA2FF` |
| Carril | `#00C2A8` | `#2EE6C8` |
| Brillo de borde | `#FFFFFF` al 70 % | `#FFFFFF` al 18 % |
| Sombra | `#0B1B3A` al 20 % | `#000000` al 45 % |

Acento principal: azul `#2F6BFF`. Acento del carril: turquesa `#00C2A8`.

### Tres direcciones (elige una con [VARIANTE])

**A. Minimalista.** Fondo plano claro u oscuro del squircle, tres paneles planos (dos grises, uno azul) sobre un único carril turquesa. Sin degradados salvo una sombra muy tenue. Máxima claridad.

**B. Gradiente.** Fondo con degradado diagonal profundo (azul a violeta azulado: `#1F3FD6` a `#6B4BFF` en oscuro, `#7FA6FF` a `#C9B8FF` en claro). Paneles de vidrio esmerilado semitransparente con borde de luz fino; el panel enfocado más luminoso. Profundidad suave tipo Big Sur.

**C. Glifo monocromo.** Un solo color (blanco sobre azul `#2F6BFF`, o azul sobre blanco) con los paneles y el carril como una única silueta de glifo, sin degradados ni sombras. Pensado para sobrevivir a cualquier tamaño y servir de base al icono de la barra de menús.

### Restricciones

- Debe leerse con claridad a **16 px**: pocas formas, contraste alto, sin detalles finos que desaparezcan.
- **Sin texto, sin letras ni la palabra "Ultrawrail"** dentro del icono.
- **Sin marcas, logos ni elementos reconocibles de terceros** (no Apple, no niri, no PaperWM, no iconos de otros gestores de ventanas).
- **Fondo transparente** fuera del squircle (canal alfa limpio, sin cuadro blanco ni sombra recortada).
- Sin fotografías, sin personas, sin mascotas.

### Versión para la barra de menús

Genera además un glifo **template image monocromo** para la barra de menús de macOS:

- Un solo color: **negro puro sobre fondo transparente** (macOS lo tiñe según el tema claro u oscuro).
- Lienzo de **18 pt** (18x18 @1x, 36x36 @2x, 54x54 @3x), con el glifo ocupando unos 16 pt.
- Silueta simple: tres columnas verticales de distinto ancho, la central algo más ancha, sobre una línea de carril horizontal inferior. Los paneles de los extremos cortados por el borde para sugerir la tira.
- Trazo o relleno de al menos 1,5 pt, sin degradados, sin transparencias parciales, sin sombras.
- Nombre de archivo sugerido: `MenuBarIconTemplate` (el sufijo "Template" marca el modo plantilla).

### Entrega

- **Icono de app:** PNG de **1024 x 1024 px**, sRGB, con canal alfa, squircle ya aplicado o cuadrado completo según la herramienta (indícalo).
- **Set completo `.icns` / AppIconSet** (`AppIcon.appiconset`) con los tamaños de macOS: 16, 32, 64, 128, 256, 512 y 1024 px, en 1x y 2x:
  `16@1x, 16@2x(32), 32@1x, 32@2x(64), 128@1x, 128@2x(256), 256@1x, 256@2x(512), 512@1x, 512@2x(1024)`.
- **Menú:** `MenuBarIconTemplate.png` (18 px), `@2x` (36 px) y `@3x` (54 px), negro sobre transparente.
- Entrega también las versiones en modo claro y oscuro del icono principal si la herramienta lo permite.

### Evitar

- Texto, monogramas o la letra "L" dibujada.
- Vías de tren literales, cadenas, candados o eslabones, y barras de desplazamiento tipo scrollbar.
- Capturas de ventanas reales, semáforos de macOS (rojo, amarillo, verde) o barras de título.
- Degradados chillones, neones, brillos de cristal estilo 2008, sombras duras.
- Demasiados paneles (más de 4) o detalles que se pierdan a 16 px.
- Parecido con iconos de Apple (Mission Control, Stage Manager) u otros gestores de ventanas.
- Fondo blanco opaco o sombra exterior recortada en el PNG.
