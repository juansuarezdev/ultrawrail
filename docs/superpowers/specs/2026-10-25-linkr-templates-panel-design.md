# Linkr: panel de plantillas con arrastrar y soltar

Extiende el MVP, la animación y el preview. Añade un panel flotante, abierto con **Ctrl + Alt + T**, para reorganizar la tira con plantillas prediseñadas y asignar ventanas a huecos arrastrándolas.

## Decisiones

| Tema | Decisión |
|------|----------|
| Qué es una plantilla | Una lista de columnas (ancho y número de huecos). Aplicarla reconstruye la tira; sigue habiendo scroll horizontal |
| Plantillas de serie | Mitades 50/50; Principal + lateral (66 / 33, 1 hueco cada una); Mitad + dos apiladas (50 / 50 con 2 huecos: 3 ventanas visibles) |
| Qué se arrastra | Fichas de ventana (icono y app) a los huecos del panel. No se arrastran las ventanas reales |
| Atajo | Ctrl + Alt + T (abre y cierra); Esc cancela; Intro aplica |
| Sobrantes | Las ventanas sin hueco pasan a columnas extra a la derecha, con ancho por defecto. Ninguna se pierde |
| Fuera de alcance | Plantillas propias o guardadas, plantillas por pantalla, arrastrar ventanas reales |

## Modelo (LayoutEngine, puro)

- `TemplateColumn(width, slots)` y `Template(id, name, columns)` con `slotCount` y `Template.all`.
- `Template.defaultAssignment(for:)`: las primeras `slotCount` ventanas, por su orden, en los huecos en orden de columna; el resto queda sin asignar.
- `Workspace.apply(_ template:, assignment:)`: reconstruye las columnas. Una columna cuyos huecos quedan todos vacíos se descarta. Las ventanas no asignadas (o con id repetido o desconocido) pasan a columnas extra al final. Conserva la ventana enfocada y reinicia `scrollOffset`.
- `Workspace.apply(_ template:, assignment:, viewport:, config:)` (en `Workspace+Perform`): lo anterior más `reveal` y `removeOverscroll`.

## Estado del panel (LinkrCore, puro)

`TemplateBoard`: plantilla elegida, ventanas abiertas y asignación por hueco.
- `select(_:)` rellena los huecos con `defaultAssignment`.
- `drop(_ id, onSlot:)`: si el hueco está ocupado, el ocupante pasa al hueco de origen de la ficha (intercambio) o a "sin asignar" si venía de la lista.
- `unassign(_:)` vacía el hueco de esa ventana.
- `unassigned`: ventanas sin hueco, para la lista y el aviso de sobrantes.

## Controller y servicios

- `Command.showTemplates`: el `Controller` no lo aplica al modelo; llama a `onShowTemplates`.
- `Controller.applyTemplate(_:assignment:)`: aplica con viewport, relayout con la animación habitual y enfoca la ventana enfocada.
- `Controller.managedWindows`: ventanas del modelo en orden de columna.
- `WindowService.describe(_:) -> WindowDescription?` con `appName` y `pid`. `AXWindowService` lo saca de la entrada; `FakeWindows` lo simula.

## Panel (LinkrApp)

`NSPanel` flotante y centrado (unos 560x420 px), colores de sistema. Una sola vista (`TemplateBoardView`) dibuja las tarjetas de plantilla arriba, los huecos a la izquierda y la lista de fichas a la derecha. Clic en una tarjeta la elige; arrastrar una ficha a un hueco la asigna; arrastrarla a la lista la desasigna. Botones Cancelar (Esc) y Aplicar (Intro). Debajo de los huecos, un aviso "N ventanas irán a columnas extra" si hay sobrantes. El panel se abre en la pantalla principal y activa Linkr mientras está abierto.

## Pruebas

- Unitarias: `Template`/`defaultAssignment`; `Workspace.apply(template)` (columnas, anchos, huecos vacíos, sobrantes, id repetido o desconocido, foco conservado); `TemplateBoard` (select, drop con intercambio, drop desde lista, unassign, sobrantes); `Controller.applyTemplate` (frames finales, animación) y que `.showTemplates` llama a `onShowTemplates` sin tocar el modelo.
- Manuales (`docs/smoke-test.md`): abrir con Ctrl + Alt + T, elegir cada plantilla, arrastrar, intercambiar, aplicar y cancelar, sobrantes, modo claro y oscuro.

## Riesgos

- El arrastre usa AppKit y solo se verifica a mano.
- Ctrl + Alt + T puede estar ocupado por otra app: el menú ya lista los atajos que no se registran.
