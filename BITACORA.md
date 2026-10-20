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
- **Ensamble por ranking de 6 semillas** (150001, 333331, 450007, 570001, 720007, 910009): **450,914** en 9.500 y **447,831** en 10.000, contra 440,9 y 439,7 de promedio de las semillas en esos cortes (**+8 a +10 puntos**). En 9.500 supera a 5 de las 6 semillas. Detalle en z739_v2/resultados/ensambles_publicos.tsv.

## Próximo — z739 v3 (exp. 9900)

- La BO optimiza **ganancia** (promedio de los cortes 8.000–12.000) medida en **4 meses** (202104–202107), un solo modelo por evaluación medido en cada mes; training de la BO 201901–202102. Objetivo tratado como ruidoso en la BO (`noisy`, nugget).
- Mismas 10 semillas que la v2 → comparación pareada con **Wilcoxon** (`comparar_v2_v3.R`) sobre el promedio público de los 9 cortes por semilla.
- La v3 guarda la lista completa de envíos con su puntaje (`kaggle_submissions.csv`) para hacer la comparación sin copiar puntajes a mano.
- **Semillerío de 30** en la v3 (`FT_SEMILLERIO`, 2026-10-18): dentro de una semilla, dos promedios de 4 y 5 modelos comparten solo 94,7% de los 9.500 enviados, así que el semillerío de 9 deja ruido. Las 9 primeras semillas del semillerío son las de la v2, en el mismo orden: `prob_1..prob_9` de `prediccion.txt` permiten reconstruir la v3 con 9 modelos para aislar el efecto de la BO. Costo: el final training pasa de ~1–3 h a ~3,5–10 h por semilla.
- **Antes de lanzarla** (2026-10-18) se sumaron dos cambios de la lista de pendientes:
    1. **Vigía del final training** (`vm/startup.sh`): si el final training pasa 90 min sin un `modelo final listo`, reinicia R; al reintentar saltea la BO y los modelos ya grabados. Solo mira las líneas del intento actual, para que un intento anterior trabado no dispare reinicios. Probado localmente con 6 logs simulados.
    2. **Elección por el sustituto** (`final.method = "best.predicted"`): con BO por ganancia, los hiperparámetros finales son los de la evaluación que el kriging con nugget predice como mejor, no la de mayor ganancia medida (que puede ser un pico de suerte). La fila elegida queda marcada (`elegido`) en `BO_log.txt` para retomar. A verificar en la prueba corta: el log tiene que decir *BO: elegido por el sustituto*.

## 2026-10-19 — v3: primer par y preparación de la v4

- **v3, semilla 150001:** promedio público de los 9 cortes **431,5** contra **435,9** en la v2 (−4,5), peor en 8 de 9 cortes y unos −8 en 9.000–10.000. Un solo par: no concluye, pero es mala señal.
- **Regla de decisión (acordada):** se compara cada semilla de la v3 con la misma semilla de la v2 (promedio público de los 9 cortes). **Cuando 4 semillas de la v3 resulten peores que su par de la v2 (conteo acumulado), se para la v3 y se lanza la v4.** Al 2026-10-19 15:15 UTC: 1 peor de 1.
- La BO de la v3 eligió modelos mucho más chicos y regularizados que la v2 (150001: 554 árboles, 294 hojas, lr 0,05, `min_data_in_leaf` 295, `lambda_l1` 19,7; la v2 eligió 1.590 árboles y 4.076 hojas). Hipótesis: entrenar la BO hasta 202102 (datos viejos) le cuesta en 202109.
- **v4 (exp. 9950, preparada, sin correr):** validación de la BO **hacia adelante** (`BO_ESQUEMA=adelante`, `BO_VALIDA=202105,202107`): para cada mes de validación un modelo entrenado de 201901 a ese mes menos 2 (202105 ← 201901–202103; 202107 ← 201901–202105). Datos recientes como el final training, sin ver datos posteriores al mes que valida. Se descartó entrenar hasta 202107 sacando 202104–202105, porque el modelo vería datos posteriores a los meses que valida (interpolar en vez de predecir 2 meses adelante). Costo: 2 modelos por evaluación (BO ~2×, ~12–14 h por semilla con semillerío de 30).
- **v4 simplificada (2026-10-19):** en vez de validar hacia adelante en 2 meses (2 modelos por evaluación), la BO **entrena 201901–202105 y valida solo en 202107**: la misma ventana que la v2, pero optimizando ganancia (con nugget, best.predicted y semillerío de 30, como la v3). Un modelo por evaluación: mismo costo que la v3 (~9–11 h por semilla), lo que deja margen para una v5. Contra: un solo mes de validación es más ruidoso que los 4 de la v3. El esquema "adelante" queda en el script (`BO_ESQUEMA=adelante`) pero no se usa.
- **v4 con early stopping (2026-10-19):** la BO deja de buscar `num_iterations` (7 hiperparámetros, 28 puntos iniciales + 50 = 78 evaluaciones). Cada evaluación entrena hasta 2.048 árboles y corta si la **ganancia en 202107** (la meseta de los cortes 8.000–12.000, calculada árbol por árbol) no mejora en **200 árboles**. El final training usa la mejor iteración de la evaluación elegida **× 1,15** (regla práctica: el final training tiene ~4 veces más filas; cerca del óptimo la curva suele ser plana). Cada evaluación registra la ganancia en 0,85×, 1,15× y 1,3× de su mejor iteración (`g_085`, `g_115`, `g_130` en `BO_log.txt`) para revisar el factor con datos; 1,15× y 1,3× solo existen si caen dentro de las 200 iteraciones posteriores al mejor punto. Configurable: `BO_EARLY_STOPPING`, `BO_TOPE_ITERACIONES`, `FT_FACTOR_ITER`.
- **Cambio automático a la v4 (autorizado por el usuario, 2026-10-19):** el chequeo de cada 2 h cuenta los pares v3 vs v2 con `kaggle_submissions.csv`. Cuando haya 4 semillas de la v3 peores que su par de la v2, para la v3, corre la prueba corta de la v4 (exp. 9995) y, solo si pasan todos los controles (BO por ganancia en 202107 con early stopping, `best_iter` en el log y en `BO_log.txt`, árboles del final training, credencial de Kaggle, `TERMINADO`, sin errores), lanza las 2 VMs de la v4. Si un control falla, deja la v3 parada y no lanza nada.
- **Vigia de la BO en la v4 (2026-10-19):** `vm/startup.sh` reinicia R si la BO pasa 60 min sin una evaluacion nueva (linea GANANCIA del intento actual); al reintentar mlrMBO retoma desde HT.RDATA. Motivo: la semilla 720007 de la v3 tardo 1 h 43 min en la evaluacion 58 (2.022 hojas) usando CPU; se reinicio la VM a mano a las 23:30 UTC y la evaluacion siguiente (1.450 hojas) tardo ~5 min. Probado localmente con 3 escenarios simulados (evaluaciones normales, una de 50 min, BO trabada).
