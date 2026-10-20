# Cambios pendientes

Lista de cambios acordados que se implementan **al final del análisis**, todos juntos.
Cada uno con el motivo y dónde va. Al implementarlo, pasarlo a la bitácora y borrarlo de acá.

> Los puntos **1** (vigía del final training trabado) y **2** (elegir los hiperparámetros por
> el sustituto, `best.predicted`) se implementaron el 2026-10-18 en la v3, antes de lanzarla.
> Ver BITACORA.md.

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

> El punto **4** (early stopping en la BO) se implementó el 2026-10-19 en la v4, con la
> ganancia árbol por árbol como métrica y el factor 1,15 para el final training. Ver BITACORA.md.

## 5. Revisar el factor 1,15 de iteraciones del final training (v4)

- **Dónde:** `.env.A` de la v4 (`FT_FACTOR_ITER`).
- **Cómo decidirlo:** con las primeras semillas de la v4, mirar en el log la línea
  "BO early stopping: … ganancia promedio vs la mejor iteración" y las columnas `g_085`,
  `g_115`, `g_130` de `BO_log.txt`. Si x1,15 queda prácticamente igual que la mejor iteración,
  el factor no importa; si cae claramente, bajarlo; si sube, subirlo.
- **Sí afecta el modelo** (cambia la cantidad de árboles del final training).
- Agregado: 2026-10-19.

## 6. Idea para una versión futura: normalizar la ganancia por mes en la BO

- **Dónde:** `ganancia_meses()` del script (v3; sirve para cualquier BO con varios meses de validación).
- **Qué:** en vez de promediar la ganancia en millones de cada mes, promediar la ganancia
  **relativa** de cada mes, por ejemplo dividida por la ganancia máxima posible del mes
  (todos los BAJA+2 × 975.000), así cada mes pesa igual.
- **Por qué:** en las 4 semillas de la v3 y en todas sus evaluaciones, 202105 fue el peor mes
  (~240 M) y 202107 el mejor (~580 M). No es que el modelo ande peor: 202105 tiene 854 BAJA+2
  (0,52%) contra 1.304 (0,79%) de 202107. Al promediar en millones, los meses con más bajas
  dominan el objetivo de la BO.
- **Sí afecta el modelo** (cambia qué hiperparámetros elige la BO). No aplica a la v4 (valida un solo mes).
- Agregado: 2026-10-19.

> El punto **7** (vigia tambien para la BO: 60 min sin una evaluacion nueva) se implemento el 2026-10-19 en la v4. Ver BITACORA.md.
