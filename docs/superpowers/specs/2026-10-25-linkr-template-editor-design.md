# Linkr: editor de plantillas propias (fase 1 del paquete ultrawide y páginas)

Primera de cuatro fases (editor de plantillas, ultrawide, páginas, zonas). Prototipo aprobado: artifact "Linkr Plantillas y Páginas", tablero "Ajustes: Plantillas y Páginas".

## Decisiones

| Tema | Decisión |
|------|----------|
| Dónde | Pestaña "Plantillas" en la ventana de Ajustes |
| Editor | Lienzo de pantalla en miniatura con divisores arrastrables, "+ Columna", "−" por columna y "− n huecos +" por columna |
| Restricción | Una plantilla suma siempre el 100 % de la pantalla; 1 a 5 columnas; 1 a 3 huecos por columna; ancho mínimo 15 % |
| Imanes | 25, 33, 50, 66 y 75 % (tolerancia 2,5 puntos), al arrastrar un divisor |
| De serie | Mitades, Principal + lateral, Mitad + dos apiladas (las actuales) y tres para ultrawide: Centro 25·50·25, Cuatro columnas, Dos zonas 16:9. Son de solo lectura; se duplican para editar |
| Guardado | Automático, en `UserDefaults` como JSON (`customTemplates`). Se ignoran entradas inválidas al leer |
| Panel Ctrl+Alt+T | Muestra de serie y propias; la fila de tarjetas se desplaza horizontalmente cuando no caben |
| Proporción del lienzo | Selector 16:9, 21:9, 32:9; por defecto la del monitor principal |

## Modelo (LayoutEngine, puro)

- `Template` y `TemplateColumn` pasan a `Codable`.
- `Template.ultrawide` (3 plantillas) y `Template.builtIn` (`all` + `ultrawide`). `Template.all` no cambia.
- `TemplateDraft`: `init(columns:)` normaliza (suma exacta 1, 3 decimales, límites), `addColumn()` (parte la más ancha), `removeColumn(at:)` (la fusiona con su vecina), `setSlots(_:at:)`, `moveDivider(_:to:)` (imanes, mínimo 15 %).

## Núcleo y app

- `TemplateCodec` (LinkrCore): codifica y decodifica `[Template]`; al decodificar descarta las inválidas y normaliza con `TemplateDraft`.
- `TemplateLibrary.all(custom:)`: `Template.builtIn` más las propias cuyo id no choque con uno de serie.
- `SettingsModel.customTemplates` (publicado, persistido) con `newTemplate`, `duplicate`, `update`, `delete`, y `allTemplates`.
- El panel de plantillas recibe `templates: () -> [Template]`.
- `TemplatesTab` (SwiftUI) con lista y editor.

## Pruebas

- `TemplateDraft`: suma 100 % tras cada operación, imanes, mínimo, añadir y quitar columnas, límites de huecos. `TemplateCodec`: ida y vuelta, descarte de inválidas, normalización. `TemplateLibrary`: colisión de ids.
- A mano: arrastrar divisores, duplicar y borrar, que las propias salgan en Ctrl+Alt+T, scroll de tarjetas, persistencia al reiniciar.
