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

## 4. Idea para v4/v5: early stopping en la BO

- **No es para la v3** (la v3 existe para dejar de elegir por AUC).
- **Qué:** `early_stopping_rounds = 200` en la BO, con un set de validación; la cantidad de
  árboles la decide el early stopping y `num_iterations` deja de ser hiperparámetro (8 → 7).
- **A favor:** la BO es mucho más rápida (corta temprano las combinaciones malas) y explora
  mejor con una dimensión menos; el tiempo ahorrado paga más iteraciones o más semillas.
- **En contra:** necesita una métrica árbol por árbol en validación, que en la práctica es la
  AUC (la ganancia por árbol es lenta y ruidosa, y el ruido puede cortar antes de tiempo); y el
  final training no tiene mes de validación, así que hay que llevarle la iteración de corte de la
  BO ajustada a ojo (+10–20%) porque entrena con más datos.
- Agregado: 2026-10-18.
