# Ultrawrail: diseño del MVP

Gestor de ventanas de scroll horizontal para macOS, escrito en Swift nativo. Las ventanas se colocan en columnas sobre una tira que se extiende más allá de los bordes de la pantalla; el foco desplaza la tira.

El diseño parte de la descripción pública de este tipo de gestores (niri, PaperWM). No se reutiliza código ni se analiza ningún binario de terceros.

## Decisiones

| Tema | Decisión |
|------|----------|
| Lenguaje | Swift 6, nativo |
| Mover ventanas | Accessibility API (`AXUIElement`). Las ventanas fuera de la vista se aparcan en una franja de 1 px en el borde de la pantalla |
| Permisos | Solo Accessibility |
| Build | Swift Package (SwiftPM) con una librería y un ejecutable. Un script empaqueta el `.app` (`Info.plist` con `LSUIElement`) y lo firma |
| Movimiento | Salto instantáneo. Sin animación en el MVP |
| Plataforma | macOS 13+, Apple silicon |

## Alcance del MVP

Dentro:
- Una tira horizontal de columnas en la pantalla principal.
- Nuevas ventanas abren a la derecha de la enfocada, con ancho por defecto.
- Anchos preestablecidos (25, 33, 50, 66, 75 %), ancho completo y centrado.
- Huecos configurables entre ventanas y respecto a los bordes.
- Apilar varias ventanas en una columna.
- Atajos globales Ctrl+Opt con teclas Vim o flechas.
- App de barra de menús, con pantalla de permisos en el primer arranque.
- Lanzamiento al inicio de sesión.
- Diálogos y ventanas de tamaño fijo quedan flotando.

Fuera (versiones posteriores): animación, gestos de trackpad, indicador de tira, columnas fijadas, reglas por app, Spaces y varias pantallas independientes, restauración de sesión, actualizaciones automáticas, licencias.

## Arquitectura

```
Package.swift
Sources/
  LayoutEngine/     librería pura, sin AppKit ni Accessibility
  UltrawrailCore/        protocolos WindowService/HotkeyService y Controller
  UltrawrailApp/         ejecutable: Accessibility, atajos, barra de menús
Tests/
  LayoutEngineTests/
  UltrawrailCoreTests/   Controller con WindowService falso
scripts/
  bundle.sh         genera y firma el .app
```

- **LayoutEngine.** Modelo `Workspace`: columnas ordenadas, cada una con ventanas apiladas y un ancho; índice de foco y `scrollOffset`. Funciones puras: dado el modelo, el tamaño de pantalla y los huecos, devuelve el `CGRect` de cada ventana y calcula el desplazamiento necesario para que la columna enfocada quede visible. No depende de macOS.
- **WindowService.** Capa fina sobre Accessibility, detrás de un protocolo. Lista ventanas, lee y escribe posición y tamaño, y emite eventos (ventana abierta, cerrada, enfocada). Es la única parte que toca `AXUIElement`.
- **HotkeyService.** Registra atajos globales y los traduce a `Command` (`focusLeft`, `focusRight`, `cycleWidth`, etc.), detrás de un protocolo.
- **Controller.** Une los tres: recibe comandos y eventos, actualiza el `Workspace`, pide el layout y lo aplica por WindowService.
- **MenuBarUI.** Icono de barra de menús, estado, ajustes y pantalla de permisos.

Los límites con el sistema (Accessibility y atajos) quedan tras protocolos; la lógica de layout se prueba sin ventanas reales.

## Flujo de datos

El `Workspace` es la fuente de verdad. No se lee de vuelta de las ventanas reales salvo en eventos puntuales.

**Comando** (por ejemplo, Ctrl+Opt+→):
1. HotkeyService emite `Command.focusRight`.
2. Controller aplica el comando al `Workspace` (foco +1, `scrollOffset` recalculado).
3. LayoutEngine devuelve `[WindowID: CGRect]`.
4. WindowService escribe las posiciones que cambiaron y enfoca la ventana destino.

**Evento del sistema** (ventana abierta, cerrada o enfocada):
1. WindowService traduce la notificación AX a un evento (`windowOpened`, `windowClosed`, `windowFocused`).
2. Controller decide si la ventana se gestiona. Las que no (diálogos, tamaño fijo, sin botón de cierre) flotan.
3. Si se gestiona, entra en una columna nueva a la derecha de la enfocada y se rehace el layout.
4. Si el usuario enfoca una ventana con el ratón, el modelo actualiza foco y scroll sin mover el resto.

**Reglas:**
- Una escritura por ventana y por cambio: se compara con el último rect aplicado y se omite si no cambió.
- El modelo manda: una ventana gestionada que el usuario mueva a mano se recoloca en el siguiente layout.
- Un solo hilo (`@MainActor`). Los eventos entran por una cola y se procesan en orden.

## Manejo de errores

- **Sin permiso de Accessibility.** Se comprueba con `AXIsProcessTrusted()` al arrancar. Si falta, se muestra una pantalla con instrucciones, se abre la sección correcta de Ajustes del Sistema y se reintenta cada segundo hasta que se conceda. Hasta entonces la app no hace nada más.
- **Fallo de una escritura AX.** Se registra y se omite esa ventana; el resto del layout continúa. Tras varios fallos seguidos, la ventana pasa a flotante y sale del modelo.
- **Tamaño mínimo mayor que la columna.** La ventana conserva su mínimo; no se recalcula el resto.
- **Ventana desaparecida sin aviso.** Cada layout valida el `AXUIElement`; si no es válido, se elimina del modelo.
- **Reposo, bloqueo o cambio de pantallas.** Se rehace el layout completo desde el modelo (`NSApplication.didChangeScreenParametersNotification` y notificaciones de despertar).
- **Conflicto de atajos.** Si el registro falla, se avisa en el menú y no se interfiere con otras apps.

## Pruebas

- **LayoutEngine (grueso).** Pruebas unitarias con `swift test`: rects y scroll, ciclo de anchos, pilas, huecos, foco al abrir y cerrar, bordes de la tira. Se escribe cada prueba antes que el código (TDD).
- **Controller.** Pruebas con un `WindowService` falso que registra las llamadas; verifican el flujo de comandos y eventos.
- **WindowService y HotkeyService.** No tienen pruebas unitarias porque dependen del sistema. Se verifican a mano con un guion de humo: abrir tres ventanas de TextEdit y comprobar colocación, foco y cambio de ancho.
- **Orden de construcción.** LayoutEngine con sus pruebas, después Controller, por último la integración real con Accessibility.

## Riesgos

- macOS no permite colocar ventanas totalmente fuera de la pantalla; la franja de 1 px es un compromiso. Si resulta visible o molesta, se reevalúa.
- Algunas apps (Electron, ventanas de tamaño fijo) responden mal a los cambios de tamaño por AX; se gestionan como flotantes.
- Las llamadas AX son lentas (~1-5 ms por ventana). La política de una escritura por cambio mitiga el coste.
