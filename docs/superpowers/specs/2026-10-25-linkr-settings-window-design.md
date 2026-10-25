# Linkr: ventana de ajustes (fase 1)

Primera de cuatro fases. Añade una ventana de ajustes de app normal, con pestañas. Las fases siguientes, cada una con su spec y plan, añaden apps excluidas, plantillas propias y atajos personalizables.

## Decisiones

| Tema | Decisión |
|------|----------|
| Apertura | Menú "Ajustes…" (Cmd+,) |
| Dock | Linkr es `.accessory`. Al abrir la ventana pasa a `.regular` (Dock y Cmd+Tab); al cerrarla vuelve a `.accessory` |
| Tecnología | SwiftUI (`TabView`, `Form`) dentro de un `NSWindow` con `NSHostingView`; macOS 13 |
| Pestañas | General, Diseño, Atajos |
| Menú | Conserva sus ajustes. Menú y ventana comparten un único modelo, así que un cambio en uno se refleja en el otro |

## Pestañas

- **General:** velocidad de animación (Rápida, Normal, Desactivada), respetar Reducir movimiento, ventanas nuevas (Manual, Automático), tipo de teclado de la leyenda (Windows, Mac) e iniciar al arrancar.
- **Diseño:** hueco entre ventanas (0 a 40 px, por defecto 8), margen exterior (0 a 60 px, por defecto 8), ancho por defecto de las columnas nuevas (25, 33, 50, 66 o 75 %, por defecto 50) y botón "Restaurar valores" (solo esta pestaña).
- **Atajos:** la leyenda actual (`ShortcutLegend`) en solo lectura, con el selector de teclado.

## Cambios de código

- `Controller.config` pasa a ser `public var`. Al cambiarlo con otro valor se hace `relayout(force: true)`, con la animación habitual.
- `Workspace.newColumnWidth` (por defecto `WidthPreset.defaultWidth`) lo usan `addWindow`, la acción de sacar de la pila y las columnas sobrantes de `apply(template)`. `Controller.newColumnWidth` lo expone. Solo afecta a columnas nuevas; las existentes no cambian.
- `LayoutSettingsStore` (`UserDefaults`: `gap`, `outerGap`, `newColumnWidth`).
- `SettingsModel` (`ObservableObject`, `@MainActor`): una propiedad publicada por ajuste, que persiste en los almacenes existentes y avisa con `onChange`. `AppDelegate` lo lee para dibujar el menú y, ante un cambio, lo empuja al `Controller` y reconstruye el menú.
- `SettingsWindowController`: crea y reutiliza la ventana y gestiona la política de activación.

## Pruebas

- Unitarias: `newColumnWidth` en `addWindow`, sacar de la pila y sobrantes de plantilla; cambiar `config` recoloca las ventanas; cambiar `newColumnWidth` no toca las columnas existentes.
- Manuales (`docs/smoke-test.md`): abrir con Cmd+, y desde el menú, Dock mientras está abierta, cambios en vivo en ambos sentidos con el menú, los tres ajustes de Diseño, restaurar valores, reabrir tras cerrar.

## Riesgos

- Si la ventana se cierra con la política `.regular`, hay que volver a `.accessory`; se hace en `windowWillClose`.
- Cambiar el espaciado con muchas ventanas escribe todas a la vez; se acota con la animación habitual (máximo 4 animadas).
