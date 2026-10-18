# Bitácora

Decisiones y resultados en orden. Fechas y horas en UTC.

## 2026-10-17 — z739 v2: notebook de la cátedra convertida a script (exp. 9800)

Cambios sobre `z739_final_senior.ipynb` (ver [`z739_v2/`](z739_v2/)):

- Tendencias completas en el FE histórico (tendencia, mínimo, máximo, promedio, ratioavg, ratiomax).
- FE random forest: 50 árboles × 32 hojas, `mtry` 0,4.
- Canaritos: `ratio` 0,2 y `desvios` 2,5 (podar menos; bajar `desvios` poda **más**).
- BO: suma `min_data_in_leaf`, `lambda_l1` y `lambda_l2`; 50 iteraciones (82 evaluaciones con los 32 puntos iniciales).
- Semillerío fijo de 9 modelos por corrida; el ensamble grande se hace entre semillas del pipeline, promediando **rankings** (no probabilidades: cada semilla elige hiperparámetros distintos).
- Sin algoritmo genético.
- Para correr sin supervisión: configuración por `.env`, checkpoint después de canaritos, retome de la BO y de los modelos grabados, subida a Kaggle sin resubir.
- Template de 256 GB: ~4.500 columnas antes de canaritos; el pico medido fue ~107 GB.

Errores encontrados y arreglados en el camino:

1. `foto_mes_formato_fecha` (columna Date) quedaba en el dataset porque la notebook solo la borra si existe `cantidad_total_transacciones`, que este dataset no tiene. Con `ratioavg` el FE histórico intentaba dividir una fecha. Se borra después del FE intra-mes.
2. Modo prueba (`PRUEBA_FRACCION`): con 3% de los clientes, 202109 tiene menos clientes que el primer corte; el corte usa `min(envios, filas)`.
3. Canaritos usaba 1 hilo; ahora todos los núcleos. `setDTthreads(0)` para data.table.
4. `lgb.importance` falla con modelos muy grandes (límite de 2^31 bytes de R); respaldo: la cantidad de splits que LightGBM escribe al final del modelo.
5. Credencial de Kaggle: la imagen de la cátedra mueve `kaggle.json` del bucket a Secret Manager y lo borra; el script usa `~/.kaggle/kaggle.json` (o el del bucket si sigue ahí) y anota en el log la cuenta.

## 2026-10-18 — Primeros resultados en Kaggle (v2)

- Cada semilla tarda ~5 h. Columnas después de canaritos: 491–695. AUC de la BO: ~0,939–0,940.
- Puntajes públicos (30% de 202109) en [`z739_v2/resultados/puntajes_publicos.tsv`](z739_v2/resultados/puntajes_publicos.tsv). Promedio de los 9 cortes por semilla: 570001 **444,0**; 910009 436,7; 720007 424,2. **Hay 20 puntos entre semillas de la misma configuración**: el público es muy ruidoso, comparar promedios y no picos.
- Mejor envío: 570001 con 9.500 → **458,664**, 6° del leaderboard público.
- Promedio de las 3 semillas por corte: el máximo está en **9.000–10.000** envíos; 8.000 y 12.000 son claramente peores.
- La semilla 150001 se trabó en el final training (de 20 min a más de 5 h por modelo); se reinició la VM y retomó desde los 6 modelos grabados. Terminó a las 16:09.
- Primer ensamble por ranking (3 semillas) en 9.000 / 9.500 / 10.000.

## Próximo — z739 v3 (exp. 9900)

- La BO optimiza **ganancia** (promedio de los cortes 8.000–12.000) medida en **4 meses** (202104–202107), un solo modelo por evaluación medido en cada mes; training de la BO 201901–202102. Objetivo tratado como ruidoso en la BO (`noisy`, nugget).
- Mismas 10 semillas que la v2 → comparación pareada con **Wilcoxon** (`comparar_v2_v3.R`) sobre el promedio público de los 9 cortes por semilla.
- La v3 guarda la lista completa de envíos con su puntaje (`kaggle_submissions.csv`) para hacer la comparación sin copiar puntajes a mano.
