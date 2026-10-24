# Linkr: animación y previsualización en el menú

Extiende el MVP descrito en `2026-10-24-linkr-design.md`. Añade (1) animación del desplazamiento de las ventanas reales y (2) una previsualización animada de la tira dentro del menú de la barra de menús.

Sustituye la decisión "salto instantáneo" del MVP para el desplazamiento horizontal. Todo lo demás del MVP sigue vigente.

## Decisiones

| Tema | Decisión |
|------|----------|
| Alcance de la animación | Ventanas reales y previsualización del menú |
| Qué se anima en las ventanas | Solo el desplazamiento horizontal (cambio de foco, abrir, cerrar). Los cambios de ancho y las pilas saltan |
| Duración y curva | Normal 180 ms, Rápida 120 ms, `easeOut` |
| Ajustes | Velocidad (Rápida, Normal, Desactivada) y "Respetar Reducir movimiento del sistema" (activado por defecto). Se guardan en `UserDefaults` y se cambian desde el menú |
| Estilo del preview | Tira con marco de pantalla, más barra de posición debajo |
| Interacción del preview | Solo visual; sin clics |

## Alcance

Dentro:
- `Tween` y curva `easeOut` puros.
- `Animator` que interpola las posiciones de las ventanas reales.
- `StripPreviewView` en el menú, animada mientras el menú está abierto.
- Ajustes de velocidad y de reducir movimiento.

Fuera: animar cambios de ancho y pilas, clics en el preview, animación en pantallas secundarias.

## Animación de las ventanas reales

**Qué se anima.** Una ventana se anima solo si su tamaño no cambia entre el rect actual y el de destino y solo varía su `x`. El resto de ventanas escribe su destino de inmediato. Las ventanas aparcadas fuera de la vista (tanto en origen como en destino) también saltan.

**Piezas:**
- `Tween` y `Easing.easeOut` en `LayoutEngine`: puros. Un `Tween` guarda los rects de origen y destino por ventana y la duración; `frames(at:)` devuelve los rects interpolados para un instante.
- `FrameClock` (protocolo) en `LinkrCore`: `start(_ tick:)`, `stop()`. En la app real lo implementa un `Timer` de 60 Hz en el bucle principal; en los tests, un reloj manual.
- `Animator` en `LinkrCore`, `@MainActor`, usado por el `Controller`. Recibe el `WindowService`, el `FrameClock`, una fuente de tiempo y los ajustes de movimiento.

**Flujo.** `Controller.relayout` calcula los destinos como antes. Para cada ventana cuyo rect cambia:
1. Si no cumple la regla de "se anima", se escribe ya y se registra en `lastApplied`.
2. Si la cumple y la velocidad no es "Desactivada" ni aplica "Reducir movimiento", se entrega al `Animator`.
3. El `Animator` avanza en cada tick, escribe los rects interpolados y, en el último frame, escribe exactamente el destino y lo registra en `lastApplied`.

**Límites:**
- Máximo 4 ventanas animadas a la vez: las 4 más cercanas a la columna enfocada entre las que intersectan el área visible en origen o destino. Las demás saltan.
- Si las escrituras de un tick tardan más de 33 ms, la animación termina: se escribe el destino de todas las ventanas animadas.
- Si llega un nuevo layout durante una animación, se parte de la posición actual de cada ventana (no de la anterior) hacia el nuevo destino.
- "Reducir movimiento": se consulta `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` al iniciar cada animación.

**Errores.** Si una escritura falla durante la animación, se cancela la animación de esa ventana, se intenta escribir su destino y se cuenta un único fallo en la tabla de fallos del `Controller`. Tres fallos seguidos siguen sacando la ventana del modelo, como en el MVP.

## Previsualización en el menú

**Qué dibuja.** Una barra de color por ventana, en la posición de su columna y a escala; un marco que marca la zona visible; las columnas fuera del marco atenuadas; la columna enfocada con borde blanco; una barra fina de posición (pista completa y tramo claro que indica dónde está la pantalla en la tira); y debajo la línea de estado ("Activo · N columnas · M ventanas"). Usa colores del sistema para modo claro y oscuro.

**Piezas:**
- `Layout.stripRects` en `LayoutEngine` (pura): devuelve los rects de cada ventana en coordenadas de tira, sin aparcar, más el ancho total de la tira. La geometría del preview (escala, posición del marco, tramo de la barra) sale de ahí y de `scrollOffset`. La tira se ajusta a un máximo de 256 px de ancho (el menú mide unos 280 px).
- `StripPreviewView` en `LinkrApp`: `NSView` propia, usada como `view` de un `NSMenuItem`. Dibuja con Core Graphics.
- `Controller.onChange`: callback con una instantánea (`Workspace`, área útil, configuración). Se emite cada vez que cambia el modelo y no se emite sin cambio.

**Datos y animación.** `AppDelegate` entrega las instantáneas a la vista. Con el menú cerrado solo guarda la última. Al abrirse (`menuWillOpen`), la vista se pinta ya en el estado actual, sin animar. Mientras el menú está abierto, un `Timer` de 60 Hz en el modo `.common` (el menú corre en un modo de bucle especial) interpola marco, anchos y posiciones hacia el estado nuevo, con la misma curva y duración que los ajustes. Se anima aunque las ventanas reales estén en "Desactivada"; con "Reducir movimiento" activo y aplicable, salta directo. El timer se detiene al cerrarse el menú.

## Ajustes

- Velocidad: Rápida (120 ms), Normal (180 ms, por defecto), Desactivada. Clave `UserDefaults`: `motionSpeed`.
- "Respetar Reducir movimiento del sistema": activado por defecto. Clave: `respectReduceMotion`.
- Ambos aparecen en el menú, debajo de la línea de estado y encima de "Iniciar al arrancar".
- Durante el desarrollo, hasta el paso 4 del orden de construcción, la velocidad por defecto es "Desactivada" para no cambiar el comportamiento ya probado.

## Pruebas

Unitarias (`swift test`, TDD):
- `Tween` y `easeOut`: extremos (t=0 origen, t=1 destino), monotonía, duración 0 devuelve el destino.
- `Layout.stripRects`: coordenadas de tira, pilas y anchos distintos.
- Geometría del preview: escala, marco, tramo de la barra, tira más corta que la pantalla.
- `Animator` con reloj manual y `FakeWindows`: frames intermedios entre origen y destino y último frame igual al destino; una ventana cuyo tamaño cambia salta; máximo 4 animadas; frame lento salta al destino (tiempo inyectado); un layout nuevo retoma desde la posición actual; una escritura fallida cancela solo esa ventana y cuenta un fallo; velocidad "Desactivada" o "Reducir movimiento" escriben de inmediato.
- `Controller`: `onChange` se emite en cada cambio y no sin cambio. Las pruebas existentes siguen pasando; el doble de pruebas usa velocidad "Desactivada" por defecto.

Manuales (se añaden a `docs/smoke-test.md`): fluidez con TextEdit y con una app pesada; ⌃⌥H/L con el menú abierto anima el preview; "Desactivada" y "Reducir movimiento" funcionan; el menú abre sin retraso.

## Orden de construcción

1. Motor: `Tween`, `easeOut`, `stripRects` y geometría del preview, con tests.
2. `Animator` y `FrameClock` en `LinkrCore`, integrados en el `Controller`, con velocidad "Desactivada" por defecto.
3. `Controller.onChange` y `StripPreviewView` en el menú.
4. Ajustes (velocidad, reducir movimiento) con `UserDefaults`, y animación activada por defecto.
5. Documentación y prueba de humo.

## Riesgos

- Escribir 4 ventanas por Accessibility en cada frame puede no llegar a 60 fps con apps lentas; el salto por frame lento lo acota, y el ajuste permite apagarlo.
- Algunas apps pintan mal mientras se mueven; el ajuste "Desactivada" es la salida.
- El `Timer` del preview en el modo `.common` debe detenerse al cerrar el menú para no gastar CPU; se verifica a mano.
