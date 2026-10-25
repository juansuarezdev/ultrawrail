# Prueba de humo manual

Cubre lo que los tests unitarios no pueden: Accessibility y atajos reales.

1. `scripts/bundle.sh` (idealmente con `SIGN_IDENTITY="Apple Development: ..."`).
2. `open build/Linkr.app`. Debe aparecer el icono en la barra de menús y el aviso de permiso.
3. Pulsa "Abrir Ajustes", activa Linkr en Accesibilidad. En ~1 s el menú pasa a "Activo".
4. Abre TextEdit y crea tres documentos con ⌘N.
   - Esperado: tres columnas del 50 % de ancho; la última visible a la derecha, la primera aparcada a la izquierda con 1 px visible.
5. ⌃⌥H / ⌃⌥L: el foco y la tira se desplazan una columna.
6. ⌃⌥R: el ancho de la columna enfocada cicla 50 → 66 → 75 → 25 → 33 → 50 %.
7. ⌃⌥F: ancho completo; otra vez, vuelve al anterior.
8. ⌃⌥C: la columna enfocada queda centrada.
   - ⌃⌥⇧H / ⌃⌥⇧L (o ⌃⌥⇧←/→): la columna enfocada se intercambia con su vecina y mantiene el foco.
9. ⌃⌥[ : la ventana enfocada se apila en la columna de su izquierda; ⌃⌥J / ⌃⌥K cambian de ventana en la pila; ⌃⌥] la saca a su propia columna.
10. Cierra una ventana: las demás se recolocan. Abre un diálogo (⌘O en TextEdit): flota y no entra en la tira.
11. Bloquea la pantalla y desbloquea: el layout se mantiene.
12. Menú: "Iniciar al arrancar" marca/desmarca; "Salir de Linkr" cierra la app.

Si algo falla, anota el paso y el comportamiento observado.

Pasos adicionales:

13. Abre una segunda app (por ejemplo Safari junto a TextEdit): ⌃⌥H / ⌃⌥L mueven el foco entre columnas de ambas apps. ⌘-Tab hacia una ventana aparcada la trae a la vista.
14. ⌘M sobre una columna: las demás se recolocan. Restáurala desde el Dock: vuelve a la tira.
15. Con tres ventanas de medio ancho, cierra la del medio: no debe quedar la mitad derecha en blanco.

## Animación y previsualización

1. Abre el menú de Linkr. Arriba debe verse la tira dibujada, con el marco de pantalla y la barra de posición debajo, y la línea "Activo · N columnas · M ventanas".
2. Con tres ventanas de TextEdit, pulsa ⌃⌥H / ⌃⌥L: las ventanas se deslizan en ~0,18 s en vez de saltar. No deben quedar a medio camino ni parpadear.
3. Abre el menú y, con él abierto, pulsa ⌃⌥H / ⌃⌥L: el marco y la barra de la previsualización se mueven con suavidad.
4. Cierra el menú, cambia el foco varias veces y ábrelo: la previsualización ya muestra el estado actual, sin animar.
5. Menú > "Velocidad de animación": con "Rápida" el deslizamiento es más corto; con "Desactivada" las ventanas saltan, pero la previsualización sigue animándose.
6. Activa Ajustes del Sistema > Accesibilidad > Pantalla > "Reducir movimiento": con "Respetar Reducir movimiento del sistema" marcado, todo salta. Desmárcalo y vuelve a animarse.
7. Cambia el ancho con ⌃⌥R: la ventana enfocada cambia de ancho al instante (no se anima).
8. Con el menú abierto y otra app enfocada, los atajos ⌃⌥H / ⌃⌥L siguen funcionando y el menú no se cierra al cambiar el foco.
9. El menú abre sin retraso perceptible.
10. Abre el menú, ciérralo y mira la CPU de Linkr en el Monitor de Actividad: debe quedar en reposo (el temporizador de la previsualización se detiene al cerrar el menú).
11. Abre una app pesada (por ejemplo un navegador con varias pestañas) junto a TextEdit y repite el paso 2: si se ven tirones, anótalo; el salto automático por frame lento debe evitar que se quede a medias.

## Plantillas

1. Ctrl+Alt+T abre el panel centrado con tres tarjetas (Mitades, Principal + lateral, Mitad + dos apiladas). Pulsarlo de nuevo, o Esc, lo cierra sin cambiar nada.
2. Elegir cada tarjeta redibuja los huecos y rellena las fichas por orden de columna.
3. Arrastrar una ficha de la lista a un hueco la asigna; sobre un hueco ocupado, intercambia o libera al ocupante.
4. Arrastrar una ficha desde un hueco a la lista la desasigna; con ventanas sin hueco aparece el aviso de columnas extra.
5. Aplicar (botón o Intro) reordena las ventanas (se deslizan las que solo cambian de posición; las que cambian de tamaño o de pila saltan) y mantiene el foco; el preview del menú refleja el cambio.
6. Con más ventanas que huecos, las sobrantes quedan como columnas a la derecha y ninguna desaparece.
7. El panel se ve bien en modo claro y oscuro.

## Leyenda de atajos

1. El menú tiene "Atajos de teclado" con un submenú: "Teclado Windows" (por defecto) y "Teclado Mac", con la elegida marcada, y debajo los 12 atajos (Ctrl+Alt+... o ⌃⌥...).
2. Cambiar de teclado cambia el texto de todas las líneas y se recuerda al reabrir la app.

## Ventanas nuevas

1. Por defecto el modo es Manual (menú, "Ventanas nuevas"). Abre una ventana nueva: las demás no se mueven.
2. Con la ventana nueva enfocada, Ctrl+Alt+A la añade a la derecha de la columna enfocada y la tira se recoloca.
3. En modo Automático, una ventana nueva entra sola. Al pasar de Manual a Automático entran las pendientes.
4. En el panel de plantillas, con muchas ventanas la lista de la derecha tiene scroll con la rueda o el trackpad.

## Ventana de ajustes

1. El menú tiene "Ajustes…" (Cmd+,). Al abrirlo aparece una ventana con pestañas General, Diseño y Atajos, y Linkr aparece en el Dock y en Cmd+Tab. Al cerrarla desaparece del Dock.
2. Abrir Ajustes dos veces reutiliza la misma ventana.
3. En General, cambiar velocidad, ventanas nuevas o teclado se refleja en el menú, y al revés.
4. En Diseño, mover "Hueco entre ventanas" y "Margen exterior" recoloca las ventanas en vivo. Cambiar el ancho de las columnas nuevas solo afecta a ventanas que se añaden después.
5. "Restaurar valores" vuelve a 8 px, 8 px y 50 %.
6. Los ajustes persisten al cerrar y reabrir Linkr.
7. Con 2 columnas de 50 %, cambiar el foco entre ellas no mueve las ventanas (sin desplazamiento leve).

## Limitaciones conocidas

- Las ventanas a pantalla completa no emiten notificación AX: no se detecta que entren o salgan de ese modo.
- Las ventanas de pantallas secundarias u otros Spaces se traen a la tira de la pantalla principal cuando reciben el foco.
- Las apps ocultas (⌘H) dejan huecos en la tira.
- No se comprueban los valores de retorno del registro de notificaciones AX.
