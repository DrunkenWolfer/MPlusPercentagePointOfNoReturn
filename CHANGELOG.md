# Changelog

## 2026-05-04

- La detección de mazmorra ya no depende solo de `C_ChallengeMode.GetActiveChallengeMapID()`; si no hay piedra activa todavía, intenta resolver la mazmorra actual por el nombre localizado del cliente.
- Se añadió soporte para "Fuerzas enemigas" al detector del porcentaje actual de trash.
- Se limitó el fallback por nombre para evitar mostrar listas fuera de instancias de grupo.
- Se añadió la opción persistente `Debug` en el menú del addon. Con Debug desactivado, las listas solo se muestran en Mítica con piedra; con Debug activado, pueden mostrarse en cualquier dificultad de mazmorra.
- El desplegable de `Instances` selecciona automáticamente la instancia actual al abrir opciones si esa mazmorra existe en la lista M+, para editar notas más rápido.