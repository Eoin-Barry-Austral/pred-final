# Cambios pendientes

Lista de cambios acordados que se implementan **al final del análisis**, todos juntos.
Cada uno con el motivo y dónde va. Al implementarlo, pasarlo a la bitácora y borrarlo de acá.

## 1. Vigía: reiniciar R si el final training se traba

- **Dónde:** `vm/startup.sh` (z739_v3; aplica también a cualquier versión que se relance).
- **Qué:** además de la regla actual (R 30 min sin usar CPU), si durante el final training pasan
  **más de 90 min sin una línea `modelo final listo`** en el log, matar R y relanzar la semilla.
  Al relanzar retoma desde el checkpoint, saltea la BO (`BO_log.txt`) y los modelos ya grabados:
  solo se pierde el modelo a medio hacer.
- **Por qué:** el 2026-10-18 la semilla 150001 pasó de ~20 min a más de 4 h por modelo a partir
  del 6.º, sin errores y usando CPU, así que el vigía actual no lo detecta. Se resolvió
  reiniciando la VM a mano. Con semillerío de 30 hay más oportunidades de que se repita.
- **No afecta el modelo** (no cambia la comparación v2 vs v3).
- Agregado: 2026-10-18.
