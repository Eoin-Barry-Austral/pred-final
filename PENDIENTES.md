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

## 3. Revisar la cantidad de iteraciones de la BO por ganancia

- **Dónde:** `z739_final_senior_v3.R`, celda 86 (`PARAM$hipeparametertuning$num_interations`).
- **Qué:** hoy son 50 iteraciones + 32 puntos iniciales (4 por dimensión × 8) = 82
  evaluaciones. Ese 50 fue una regla práctica al pasar de 5 a 8 hiperparámetros (la notebook
  tenía 30), no se ajustó para una métrica ruidosa.
- **Cómo decidirlo (después de correr la v3):** mirar en `BO_log.txt` de cada semilla en qué
  evaluación apareció la mejor ganancia y si las últimas ~20 siguen encontrando mejoras. Si la
  mejor suele aparecer al final, subir (por ejemplo a 80 → 112 evaluaciones, +1 a 1,5 h por
  semilla). Si se estabiliza antes, dejarlo.
- **Por qué:** con ganancia ruidosa y nugget, cada evaluación aporta menos información y el
  nugget se estima con los mismos puntos; 82 evaluaciones (~10 por dimensión) alcanza para la
  AUC pero puede quedar corto acá.
- **Sí afecta el modelo** (cambia la búsqueda). Aplicarlo después de la v3 es una versión nueva.
- Agregado: 2026-10-18.
