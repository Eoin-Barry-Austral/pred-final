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

## 2. BO por ganancia: elegir los hiperparámetros por el sustituto, no por el máximo medido

- **Dónde:** `z739_final_senior_v3.R`, celdas 91 (control de la BO) y 95 (elección de los
  mejores hiperparámetros). Solo cuando `BO_METRICA=ganancia`.
- **Qué:** hoy el script toma la fila de `BO_log.txt` con la ganancia **medida** más alta
  (`setorder(tb_bayesiana, -y)` y la fila 1). Con un objetivo ruidoso, ese punto puede ser uno
  con suerte. Cambiar a **el punto que el modelo sustituto (kriging con nugget) predice como
  mejor**: `makeMBOControl(final.method = "best.predicted")` y usar `bayesiana_salida$x` en vez
  de la fila 1.
- **Cuidados al implementarlo:**
  - Verificar en qué escala devuelve mlrMBO `bayesiana_salida$x` (con o sin `trafo`): el final
    training hoy aplica `2^x` a los valores de `BO_log.txt`, que están sin transformar.
  - Si la BO ya terminó y se retoma desde `BO_log.txt`, no hay `bayesiana_salida`: guardar el
    punto elegido (por ejemplo en `BO_elegido.txt`) para poder retomarlo.
  - Dejar en el log cuál se eligió y su ganancia medida vs la predicha.
- **Por qué:** el nugget ya hace que la BO **busque** sin perseguir picos de ruido, pero la
  **elección final** sigue siendo el máximo medido. Elegir por el sustituto es coherente con
  tratar la ganancia como ruidosa.
- **Sí afecta el modelo** (cambia los hiperparámetros del final training). Si se aplica después
  de correr la v3, sería una versión nueva (no comparable directamente con la v3 ya corrida).
- Agregado: 2026-10-18.
