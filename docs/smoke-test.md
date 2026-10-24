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
9. ⌃⌥[ : la ventana enfocada se apila en la columna de su izquierda; ⌃⌥J / ⌃⌥K cambian de ventana en la pila; ⌃⌥] la saca a su propia columna.
10. Cierra una ventana: las demás se recolocan. Abre un diálogo (⌘O en TextEdit): flota y no entra en la tira.
11. Bloquea la pantalla y desbloquea: el layout se mantiene.
12. Menú: "Iniciar al arrancar" marca/desmarca; "Salir de Linkr" cierra la app.

Si algo falla, anota el paso y el comportamiento observado.
