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

## 2026-10-20 — v3: 5 pares

| semilla | v2 | v3 | dif. (9 cortes) | dif. centro 9.000–10.500 |
|---|---|---|---|---|
| 150001 | 435,9 | 431,5 | −4,4 | −6,8 |
| 333331 | 440,7 | 433,6 | −7,1 | −10,6 |
| 600017 | 425,4 | 428,5 | +3,1 | +3,0 |
| 720007 | 424,2 | 429,1 | +4,9 | +1,3 |
| 910009 | 436,7 | 437,5 | +0,8 | +9,9 |

- **Regla: 2 peores de 5** (hacen falta 4 para pasar a la v4). Diferencia media −0,5 (9 cortes) y −0,6 (centro): por ahora la v3 empata con la v2.
- La v3 tiene **menos dispersión entre semillas** (428,5–437,5, contra 424,2–440,7 en la v2): mejora las semillas flojas de la v2 y empeora las buenas. Consistente con el semillerío de 30 y con modelos más regularizados.
- Tiempos: 720007 tardó 12 h (con la BO trabada y el reinicio), 600017 solo 5 h 08 min. En curso desde las 07:28 UTC: 570001 (z739g-a2) y 850009 (z739g-a), los dos en el final training.

## 2026-10-20 — v4: canaritos con 2,0 desvíos

- `PARAM$CN$desvios` pasa a leerse del `.env` (`CN_DESVIOS`, por defecto 2,5); la v4 usa **2,0** (`.env.A` y `.env.B`). El log lo registra en la línea `canaritos: ratio 0.2 desvios 2`, que la prueba corta de la v4 controla.
- Efecto medido con `impo_1.txt` de las 7 semillas de la v3: con 2,0, 4 semillas quedan casi igual (488–633 columnas) y 3 pierden ~85–115 columnas (13–18%; 150001 692→578, 720007 630→517, 910009 673→588). Las que se van rankean por debajo de casi todos los canaritos. Con 1,5 o 1,0 el recorte sería del 10–35%.
- Contra: la v4 suma un tercer cambio respecto de la v3 (validación en 202107, early stopping, canaritos). Se aceptó porque el efecto es chico y el objetivo es el puntaje del domingo.

## 2026-10-20 15:40 UTC — v3: 570001

- **570001:** v3 442,7 contra 444,0 en la v2 (−1,3; centro −2,9). **Regla: 3 peores de 6**; diferencia media −0,7 (9 cortes).
- El pico se corrió: la v2 tuvo su máximo en 9.500 (458,664) y la v3 en **10.000 (457,498)** y 10.500 (455,664). 9.000 y 9.500 dieron el mismo puntaje (443,748).

## 2026-10-20 19:40 UTC — v3: 850009 → regla cumplida (4 peores de 7)

- **850009:** v3 434,7 contra 435,3 en la v2 (−0,6; centro −3,3). **4 peores de 7: se cumple la regla de pasar a la v4.**
- Balance de la v3 en 7 pares: diferencia media −0,7 (9 cortes) y −1,3 (centro). En la práctica, un empate: optimizar ganancia en 4 meses con datos hasta 202102 no mejoró a la v2 en el público.
- La tabla de la v2 no tenía los cortes de 850009 y 999953: se completaron desde la lista de envíos de Kaggle que guarda la v3 (`kaggle_submissions.csv`).

## 2026-10-20 19:28 UTC — cambio automático a la v4 (exp. 9950)

- El chequeo de cada 2 h detectó 4 peores de 7, **paró la v3** y corrió la prueba corta de la v4 (exp. 9995, 3% de clientes). Pasaron todos los controles, incluido `canaritos: ratio 0.2 desvios 2`, y lanzó **z739h-a** (empieza por 150001) y **z739h-a2** (empieza por 910009).
- La v3 quedó con **7 de 10 semillas** terminadas: 450007 se cortó al final de la BO y 999953 recién empezaba. Los checkpoints quedan en el bucket por si se quieren terminar después.
- Ojo con la prueba corta: con el 3% de clientes, 202107 tiene 4.925 clientes, menos que el corte más chico (8.000). Todos los cortes envían a todos, la ganancia es la misma en cada árbol, y por eso dio `best_iter` 1 y "final training con 1 arboles". Es un artefacto de la prueba, no un error. Hay que confirmar con las primeras evaluaciones reales de la BO que `best_iter` varía y la ganancia es positiva.

## 2026-10-20 20:20 UTC — comparación v4 contra v2

- `comparar_pares.R` ahora compara dos versiones cualesquiera (`Rscript comparar_pares.R v2 v4`). Solo usa semillas con los 9 cortes en las dos versiones y suma Wilcoxon pareado desde 5 pares. v2 vs v3 (7 pares): p = 0,80.
- `agregar_puntajes.R` carga en `z739_vN/resultados/puntajes_publicos.tsv` los envíos de un experimento, desde el `kaggle_submissions.csv` que guarda cada semilla.
- El chequeo de cada 2 h ahora sigue la v4: carga sus puntajes, compara contra la v2 (y la v3 como dato), actualiza esta bitácora y hace commit. Ya no tiene acciones sobre las VMs.

## 2026-10-21 05:10 UTC — v4: 150001 y 910009

| semilla | v2 | v4 | dif | dif centro |
|---|---|---|---|---|
| 150001 | 435,9 | 429,4 | −6,5 | −5,3 |
| 910009 | 436,7 | 429,4 | −7,4 | −8,8 |

- **2 peores de 2** (9 cortes y centro 9.000–10.500). Diferencia media −7,0 (9 cortes) y −7,0 (centro). Todavía no hay Wilcoxon (hace falta 5 pares).
- Contra la v3 (dato): 2 peores de 2, diferencia media −5,1 (centro −8,6).
- Tiempos: cada semilla tardó ~8 h (canaritos ~20 min, BO ~4 h, final training ~4 h). En curso: 333331 (z739h-a) y 720007 (z739h-a2), las dos en la BO.
