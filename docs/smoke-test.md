# Prueba de humo manual

Cubre lo que los tests unitarios no pueden: Accessibility y atajos reales.

1. `scripts/bundle.sh` (idealmente con `SIGN_IDENTITY="Apple Development: ..."`).
2. `open build/Ultrawrail.app`. Debe aparecer el icono en la barra de menús y el aviso de permiso.
3. Pulsa "Abrir Ajustes", activa Ultrawrail en Accesibilidad. En ~1 s el menú pasa a "Activo".
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
12. Menú: "Iniciar al arrancar" marca/desmarca; "Salir de Ultrawrail" cierra la app.

Si algo falla, anota el paso y el comportamiento observado.

Pasos adicionales:

13. Abre una segunda app (por ejemplo Safari junto a TextEdit): ⌃⌥H / ⌃⌥L mueven el foco entre columnas de ambas apps. ⌘-Tab hacia una ventana aparcada la trae a la vista.
14. ⌘M sobre una columna: las demás se recolocan. Restáurala desde el Dock: vuelve a la tira.
15. Con tres ventanas de medio ancho, cierra la del medio: no debe quedar la mitad derecha en blanco.

## Animación y previsualización

1. Abre el menú de Ultrawrail. Arriba debe verse la tira dibujada, con el marco de pantalla y la barra de posición debajo, y la línea "Activo · N columnas · M ventanas".
2. Con tres ventanas de TextEdit, pulsa ⌃⌥H / ⌃⌥L: las ventanas se deslizan en ~0,18 s en vez de saltar. No deben quedar a medio camino ni parpadear.
3. Abre el menú y, con él abierto, pulsa ⌃⌥H / ⌃⌥L: el marco y la barra de la previsualización se mueven con suavidad.
4. Cierra el menú, cambia el foco varias veces y ábrelo: la previsualización ya muestra el estado actual, sin animar.
5. Menú > "Velocidad de animación": con "Rápida" el deslizamiento es más corto; con "Desactivada" las ventanas saltan, pero la previsualización sigue animándose.
6. Activa Ajustes del Sistema > Accesibilidad > Pantalla > "Reducir movimiento": con "Respetar Reducir movimiento del sistema" marcado, todo salta. Desmárcalo y vuelve a animarse.
7. Cambia el ancho con ⌃⌥R: la ventana enfocada cambia de ancho al instante (no se anima).
8. Con el menú abierto y otra app enfocada, los atajos ⌃⌥H / ⌃⌥L siguen funcionando y el menú no se cierra al cambiar el foco.
9. El menú abre sin retraso perceptible.
10. Abre el menú, ciérralo y mira la CPU de Ultrawrail en el Monitor de Actividad: debe quedar en reposo (el temporizador de la previsualización se detiene al cerrar el menú).
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

1. El menú tiene "Ajustes…" (Cmd+,). Al abrirlo aparece una ventana con pestañas General, Diseño y Atajos, y Ultrawrail aparece en el Dock y en Cmd+Tab. Al cerrarla desaparece del Dock.
2. Abrir Ajustes dos veces reutiliza la misma ventana.
3. En General, cambiar velocidad, ventanas nuevas o teclado se refleja en el menú, y al revés.
4. En Diseño, mover "Hueco entre ventanas" y "Margen exterior" recoloca las ventanas en vivo. Cambiar el ancho de las columnas nuevas solo afecta a ventanas que se añaden después.
5. "Restaurar valores" vuelve a 8 px, 8 px y 50 %.
6. Los ajustes persisten al cerrar y reabrir Ultrawrail.
7. Con 2 columnas de 50 %, cambiar el foco entre ellas no mueve las ventanas (sin desplazamiento leve).

## Editor de plantillas

1. Ajustes tiene la pestaña Plantillas: lista con las 6 de serie (3 con la etiqueta UW) y "Mis plantillas".
2. Las de serie son de solo lectura; "Duplicar" crea una copia editable y la selecciona.
3. Arrastrar un divisor reparte el ancho entre las dos columnas contiguas, con imán a 25, 33, 50, 66 y 75 %, y nunca baja del 15 %.
4. "+ Columna" parte la más ancha; "−" fusiona con la vecina; "− n huecos +" cambia entre 1 y 3 huecos.
5. El selector 16:9, 21:9, 32:9 cambia la proporción del lienzo; por defecto la del monitor.
6. Las plantillas propias salen en Ctrl+Alt+T tras las de serie; con muchas, las tarjetas se desplazan con la rueda.
7. Cerrar y reabrir Ultrawrail conserva las plantillas propias; "Borrar" las quita.

## Ultrawide

1. "Seguimiento del foco: Centrado" mantiene la columna con foco en el centro de la pantalla, salvo en los extremos.
2. "Ancho máximo de columna" recorta las columnas a N px; en 0 muestra "sin límite".
3. "Centrar el grupo si cabe en pantalla" coloca 2 columnas de 25 % en el centro de la pantalla.
4. "Restaurar valores" desactiva las tres opciones.
5. Las tres opciones persisten al cerrar y reabrir Ultrawrail.

## Páginas

1. Win+Alt+→ en una página con ventanas crea la página 2 y esconde las ventanas de la 1.
2. Win+Alt+← vuelve y recoloca las ventanas.
3. Win+Alt+Shift+→ lleva la ventana con foco a la página siguiente y la sigue.
4. Las ventanas nuevas entran en la página activa.
5. Cerrar la última ventana de una página intermedia no rompe el cambio.
6. El menú muestra "Página N de M".
7. El registro Carbon de ⌘⌥←/→ NO falla aunque otra app use ese atajo en sus menús: Ultrawrail se lo quita en silencio a Brave/Chrome (cambio de pestaña), VS Code (cambio de editor) e iTerm (navegación entre paneles). Comprueba que en esas apps el atajo cambia de página y no de pestaña/editor/panel.

## Zonas

1. Con 2 zonas la pantalla se divide en dos mitades; las ventanas nuevas entran en la zona con foco.
2. Ctrl+Alt+Win+→ pasa el foco a la zona siguiente.
3. Con Shift mueve la ventana a esa zona.
4. Cada zona cambia de página por separado con Win+Alt+←/→.
5. Bajar de 3 a 1 zona junta todas las ventanas en la zona restante.
6. Ctrl+Alt+Win+flechas pueden chocar con atajos de otras apps y macOS no avisa.
7. La configuración persiste al reiniciar.
8. En una zona vacía el teclado sigue en la ventana anterior; abre o mueve una ventana a esa zona.

## Apps excluidas

1. Añadir una app en ejecución (Ajustes > Apps) la saca de la tira y sus ventanas dejan de moverse.
2. Quitarla de la lista la vuelve a incorporar.
3. Las ventanas nuevas de una app excluida no entran.
4. La lista persiste al reiniciar.

## Limitaciones conocidas

- Las ventanas a pantalla completa no emiten notificación AX: no se detecta que entren o salgan de ese modo.
- Las ventanas de pantallas secundarias u otros Spaces se traen a la tira de la pantalla principal cuando reciben el foco.
- Las apps ocultas (⌘H) dejan huecos en la tira.
- No se comprueban los valores de retorno del registro de notificaciones AX.
- Las ventanas aparcadas pueden verse en una segunda pantalla situada a la derecha de la principal.
- Si Ultrawrail se cierra de forma inesperada estando en la página 2, las ventanas de las demás páginas siguen aparcadas hasta volver a abrirlo.
- Al pasar el foco a una zona vacía, el teclado sigue en la ventana de la zona anterior y hacer clic en ella no avisa del cambio; abre o mueve una ventana a esa zona.
