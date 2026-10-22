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

## 2026-10-21 11:00 UTC — se para la v4; volvemos a la v2 (AUC)

- **v4, 2 pares:** 150001 429,4 (v2 435,9, −6,5) y 910009 429,4 (v2 436,7, −7,4). También por debajo de la v3. Hipótesis: optimizar la ganancia de un solo mes (202107) ajusta la BO al ruido de ese mes. La BO midió las ganancias más altas de todas las versiones (606–619 M) y el público fue el más bajo.
- Además, 720007 eligió 1.635 árboles: ~40 min por modelo final, ~20 h por semilla.
- **Decisión del usuario:** parar la v4 (z739h-a y z739h-a2 en 0; 333331 quedó en 11/30 y 720007 en 3/30) y buscar mejoras sobre la v2, que vuelve a optimizar AUC. Se pausa el chequeo de cada 2 h.
- **Balance de la búsqueda por ganancia:** v3 (4 meses) empata con la v2 (−0,7; Wilcoxon p = 0,80), y la v4 (1 mes) pierde ~7. La ganancia como métrica de la BO no mejoró a la AUC.

## 2026-10-21 — v5 preparada (exp. 9850, VMs z739i-*)

- **v5 = v2 (BO por AUC) con dos cambios:** semillerío de **30** (`FT_SEMILLERIO`; las 9 primeras semillas son las de la v2 en el mismo orden, y las 21 siguientes las de la v3) y canaritos con **2,0** desvíos (`CN_DESVIOS`). También guarda `kaggle_submissions.csv`, como la v3.
- Mismas 10 semillas del pipeline que la v2: comparación pareada con `comparar_pares.R v2 v5`. Ojo: son dos cambios juntos, así que si cambia el puntaje no se sabe cuál de los dos fue. Se aceptó por el tiempo.
- VMs: `vm/` de la v4 (vigías de CPU, del final training y de la BO); la vigía de la BO ahora cuenta las líneas ` AUC ` además de ` GANANCIA `.
- Tiempo estimado con los logs de la v2: preprocesamiento ~22 min, BO ~2,3–2,8 h, 30 modelos finales a ~11–17 min cada uno ~5,5–8,5 h. **~8,5–11,5 h por semilla**; con 2 VMs, las 10 semillas en ~50 h.

## 2026-10-21 11:20 UTC — v5 lanzada

- Prueba corta (exp. 9990, 3% de clientes): pasaron todos los controles (`canaritos: ratio 0.2 desvios 2`, `semillerio: 30 modelos`, BO por AUC con 34 evaluaciones, modelo final, credencial de Kaggle, lista de envíos guardada, `TERMINADO`, sin errores ni vigía). Se apagó la VM de prueba.
- Lanzadas **z739i-a** (empieza por 150001) y **z739i-a2** (empieza por 910009). Fin estimado: viernes 2026-10-23 por la tarde (UTC).
- El chequeo de cada 2 h se reactivó y ahora sigue la v5 (pares contra la v2).

## 2026-10-21 — ensambles entre versiones (sin subir todavía)

- `ensamble_versiones.R`: ensamble por ranking de corridas de varias versiones (cada corrida pesa igual).
- Armados en `C:\tmp\lab1\ensamble_final\salida`: v2 (10 corridas; idéntico al ens10 de antes) en 9.500 y 10.000; v2+v3 (17) en 9.500 y 10.000; v2+v3+v4 (19) en 10.000.
- Cada corrida comparte ~94–95% de sus 10.000 envíos con el ensamble: las versiones se parecen mucho, así que el ensamble entre versiones mezcla poca diversidad.
- **Puntajes públicos de los ensambles entre versiones** (en `z739_v2/resultados/ensambles_publicos.tsv`): v2 (10) 443,4 en 9.500 y 444,5 en 10.000; v2+v3 (17) **446,2** en 9.500 y 444,1 en 10.000; v2+v3+v4 (19) 444,5 en 10.000. Todos dan +5 a +9 sobre la semilla promedio en el mismo corte (~438–439), pero **por debajo del ens6 de la v2 (450,9)**, que tiene un subconjunto de esas mismas corridas. Con ~95% de envíos compartidos, una diferencia de 7 puntos entre ens6 y ens10 es ruido del 30% público. Para el privado se espera más del ensamble grande que del ens6 o de la mejor semilla suelta (458,7).

## 2026-10-21 — v6 preparada (exp. 9700, VMs z739j-*, sin correr)

Motivo: después de una semana, los cambios de búsqueda y semillas (v3, v4, v5) mueven ±5 puntos y los primeros del público están ~15 arriba. La v6 cambia **lo que ve el modelo**.

- **v6 = v2** (BO por AUC, semillerío de 9, canaritos 2,5) **con variables nuevas** (`FE_NUEVAS=1`), calculadas después de las tendencias y antes del random forest y de los canaritos (que podan las que no sirvan):
    - **ventanas de 3 y 12 meses** solo de `ratioavg`, `min` y `ratiomax`, que son las medidas históricas que más pesan en la de 6 (la pendiente `tend6` y `avg6` pesan ~3%), en **30 variables clave**: las de mayor importancia sumada en los modelos de canaritos de 7 semillas de la v3;
    - **aceleración** (x − 2·lag1 + lag2) de las 30 claves;
    - **recencia**: meses consecutivos en cero y meses en cero de los últimos 6, en 19 variables de actividad (transacciones, tarjetas, sueldo, homebanking, etc.);
    - **sueldo**: `sueldo_total`, `perdio_sueldo` (cobraba el mes anterior y este no) y sueldo contra el mes anterior;
    - **frecuencia del valor exacto** en el mes, en 12 montos clave.
- **Random forest de variables entrenado con 201907–201909** (`FE_RF_MESES`) en vez de 202101–202103: en la v2 sus hojas se arman con etiquetas de meses que después entran al entrenamiento. El efecto esperado es chico (hojas de ≥100 clientes, 3 de 31 meses), pero es lo correcto.
- El bloque nuevo se probó localmente con un dataset inventado (`z739_v6/test_fe_v6.R`): rachas, ceros en 6 meses (NA en los primeros 5), aceleración, sueldo perdido y frecuencias dan lo esperado.
- Tiempo estimado: ~5–5,5 h por semilla (como la v2, con unos minutos más de variables y ~265 columnas antes de los canaritos). Con 2 VMs, las 10 semillas en ~27 h.

## 2026-10-21 19:15 UTC — v5: 910009

- **910009:** v5 **440,4** contra 436,7 en la v2 (**+3,7**); en el centro 9.000–10.500, **446,9 contra 435,6 (+11,2)**. Máximo 449,7 en 9.500.
- Primer par a favor de una versión nueva en el centro. La v3 (también con semillerío de 30) había dado 445,6 en el centro para esta semilla: puede ser el semillerío. Es un solo par.

## 2026-10-21 19:25 UTC — plan A: v5 en una VM, v6 en la otra

- Se paró **z739i-a2** (v5; la 720007 recién empezaba). **z739i-a** sigue con la v5 en orden (150001, 333331, …). La 720007 queda marcada como tomada por z739i-a2, así que la VM 1 la saltea.
- La v6 va con **semillerío de 30** (pedido del usuario: "eso necesito tener sí o sí"). Ahora es v2 + semillerío 30 + variables nuevas + RF en 201907–201909, con canaritos 2,5. Contra la v5 cambia las variables nuevas, el RF y los canaritos (2,5 en vez de 2,0).
- Con una VM y ~10 h por semilla, la v6 llega a ~5–6 semillas para el sábado a la noche.
- **19:22 UTC: la v5 también pasa a semillerío de 20** (usuario). Se actualizó el `.env` en el bucket y se reinició z739i-a. R relee el `.env` al arrancar y retoma desde los 13 modelos grabados de la 150001, así que esa semilla termina con 20 modelos (7 más). La 910009 ya está hecha con 30 (en `prediccion.txt` se pueden promediar solo los primeros 20). La v6 también va con 20.

## 2026-10-21 19:30 UTC — v6 lanzada

- Prueba corta (exp. 9989, 3% de clientes): pasaron todos los controles. `FE v6: 264 columnas nuevas` (30 claves, 19 de actividad, 12 montos), random forest con 201907–201909, BO por AUC, modelo final, Kaggle y `TERMINADO`, sin errores.
- **Buena señal:** en el modelo de canaritos de la prueba, varias variables nuevas quedan arriba: `cpayroll_trx_ceros6` en el puesto **4**, `mpayroll_ratiomax12` en el **5**, `ctarjeta_visa_transacciones_ratioavg12` 12, `mcomisiones_ratiomax12` 16, `mprestamos_personales_frec` 17, `mpayroll_frec` 18. Sueldo y recencia aportan información que el modelo no tenía (con el 3% de clientes, es solo una indicación).
- Lanzada **z739j-a** (v6, semillerío 20, empieza por 150001). La v5 sigue en z739i-a.
- El chequeo de cada 2 h ahora sigue la v5 y la v6.

## 2026-10-21 22:40 UTC — v5: 150001

- **150001:** v5 432,3 contra 435,9 en la v2 (−3,6); en el centro 437,5 contra 437,8 (−0,3). Pares de la v5: 1 peor de 2; diferencia media +0,1 (9 cortes) y **+5,5 en el centro**.
- La 150001 en todas las versiones: v2 435,9 · v3 431,5 · v4 429,4 · v5 432,3. En el grupo B (202107 real) fue la segunda peor de 9. Puede que el ranking de esa semilla encaje mal con el 30% público, que es fijo, y no que el modelo sea peor en el privado. No se descarta del ensamble por su puntaje público.

## 2026-10-22 01:30 UTC — v6: la BO de la 150001 sale de la banda de la v2

- **Mejor AUC de la BO, v6 150001: 0,94150**, contra 0,93982 en la v2 y 0,93972 en la v5 para la misma semilla (+0,0017). En las 10 semillas de la v2 la mejor AUC estuvo entre 0,9390 y 0,9400; la v3, la v4 y la v5 quedaron dentro de esa banda. Es la primera versión que sale de la banda. Las variables nuevas usan solo el mes actual y los anteriores.
- Hiperparámetros parecidos a la v2 (1.014 árboles y 1.137 hojas, contra 1.006 y 955), pero con `feature_fraction` 0,32 (la v2 usaba 0,07) y más columnas: **cada modelo final tarda ~39 min** (la v5 ~15–20). Con 20 modelos, la 150001 de la v6 sube a Kaggle ~14:00 UTC.
- v5 333331: mejor AUC 0,93977 (v2 0,94003); ~15 min por modelo, Kaggle ~06:20 UTC.

## 2026-10-22 07:10 UTC — v5: 333331

| semilla | v2 | v5 | dif | centro v2 | centro v5 | dif centro |
|---|---|---|---|---|---|---|
| 150001 | 435,9 | 432,3 | −3,6 | 437,8 | 437,5 | −0,3 |
| 333331 | 440,7 | 437,3 | −3,3 | 443,7 | 439,5 | −4,2 |
| 910009 | 436,7 | 440,4 | +3,7 | 435,6 | 446,9 | +11,2 |

- v5 peor que la v2 en **2 de 3** (9 cortes y centro). Diferencia media **−1,1** (9 cortes) y **+2,2** en el centro. Sin p de Wilcoxon todavía (pocos pares).
- La única a favor (910009) es la que se hizo con semillerío de 30; las dos con 20 quedan abajo.
- Estado: v5 600017 en la BO (~45 de 82), termina ~13:30–14:00 UTC. v6 150001 con 10 de 20 modelos finales (~35 min cada uno), sube a Kaggle ~12:45 UTC.

## 2026-10-22 13:30 UTC — v6: 150001 se desploma en Kaggle

- **v6 150001: 411,4** (centro 414,8), contra **435,9 en la v2 (−24,5)** y 432,3 en la v5 (−20,9). Es más de 3 veces el ruido entre semillas. Y eso que tuvo **la mejor AUC de la BO de todas las corridas (0,9415 en 202107)**.
- Las predicciones de 202109 se parecen bastante a las de la v2 (Spearman 0,973), pero comparten solo el **87% de los primeros 10.000** (entre versiones parecidas, ~95%). Unos 1.300 clientes distintos cerca del corte explican la caída.
- En el modelo final de la v6, las 5 variables más importantes son `rf_*`, del **random forest entrenado con 201907–201909** (el cambio de meses del RF). Después vienen variables nuevas (`mprestamos_personales_ratiomax3`, `mcuentas_saldo_min3`, `cdescubierto_preacordado_ratioavg12`, `mprestamos_personales_frec`, `cpayroll_trx_mesesencero`).
- Hipótesis, sin poder separarlas con lo que hay: (1) el RF de 2019 arma hojas que funcionan hasta 202107 (el final training las "corrige" con 31 meses) pero describen peor a 202109; (2) alguna variable nueva se comporta distinto en 202108–202109 (por ejemplo, una variable de actividad mal cargada en esos meses que dispara las rachas en cero). Confirmarlo requiere mirar el dataset de 202109.
- Lección: subir la AUC de validación en 202107 no garantiza nada en 202109. Pasó con las mejoras de la BO por ganancia (v3, v4) y ahora con las variables nuevas.

## 2026-10-22 13:40 UTC — se para la v6; las 2 VMs a la v5, priorizando semillas

- **Se paró la v6** (z739j-a en 0) después de la 150001 (411,4). **z739i-a2 vuelve a la v5**, así que quedan las 2 VMs en la v5 (semillerío 20).
- **Prioridad por semillas buenas en el pasado** (pedido del usuario): se reordenó `SEMILLAS_PIPELINE` en el `.env` del bucket para que la VM 2 (que recorre la lista al revés) arranque por **570001** (v2 444,0) y **210011** (439,6). La VM 1 leyó la lista al arrancar y sigue con su orden: después de la 600017 toma la **850009** (435,3). Las flojas de la v2 (450007, 999953, 720007) quedan para el final.
- Quedan 6 semillas de la v5 y ~7 h por semilla: con 2 VMs terminarían el viernes; el orden asegura que las mejores entren aunque algo se demore.

## 2026-10-22 15:45 UTC — v7 preparada: genética + sin 2020 (exp. 9600, VM z739k-a)

Pedido del usuario: probar la genética con los cambios propuestos, en una sola VM, sin 2020 en el entrenamiento y con las semillas buenas primero. La otra VM sigue con la v5 (570001).

- **v7 = v5** (BO por AUC, semillerío 20, canaritos 2,0, **deflación por IPC**) con:
    - **2020 fuera de todo entrenamiento** (`MESES_EXCLUIR`): BO (17 meses), final training (19 meses) y fitness de la genética. 2020 sigue en el dataset para los lags y las tendencias de 2021.
    - **Genética** (`GA_ACTIVA=1`), **una sola búsqueda para todas las semillas** (la corre la primera semilla y graba en `exp/WF9600_ga/`). Va **después de canaritos**: el fitness usa ~600 columnas (rápido) y las ganadoras no pueden ser borradas. Fitness: **mejora de AUC (BAJA+2) promedio en 202104 y 202105**, con LightGBM chico (100 árboles) y 10% de CONTINUA. Fórmulas de 2 o 3 de las **30 variables clave** con + − × ÷. Control en **202103 y 202106**, otra semilla, contra 19 fórmulas al azar: queda si mejora y supera al percentil 90 del azar. 3 rondas de 20×10, con un tope de 8 h. Cada ganadora entra con lag1, lag2, delta1 y delta2.
    - `DR_METODO` configurable; se corrigió el nombre de las funciones del dólar (`drift_dolarblue` → `drift_dolar_blue`), que hacía fallar esa opción. El usuario eligió quedarse con el IPC: entre 201901 y 202107 el IPC sube ×2,6 y el dólar blue ×4,6.
- Orden de semillas: 570001, 210011, 333331, 910009, 850009, 150001, 600017, 450007, 999953, 720007.
- Se paró z739i-a (v5; la 850009 estaba en el random forest) para hacer lugar.

## 2026-10-22 14:25 UTC — v7 lanzada (VM z739k-a)

- **Prueba corta 1** (exp. 9988, 3% de clientes): todo el flujo sin errores. 2020 fuera (BO con 17 meses, final con 19), genética con 4 muestras y 1 ronda, la ganadora no pasó el control y siguió sin variables genéticas.
- **Prueba corta 2** (exp. 9987, 2 semillas, `GA_FORZAR=1` solo para la prueba): la ganadora entra al dataset (gen_01 con lag1, lag2, delta1 y delta2), y la **segunda semilla reusa las fórmulas sin volver a buscar** ("ya estaba terminada, uso sus ganadoras"). `gen_01` aparece entre las variables importantes del modelo final. Se sacó `GA_FORZAR` de los `.env`.
- **Tiempos estimados** (con los de la v5 escalados por las filas sin 2020: BO ×0,59 y final ×0,61): preprocesamiento ~25 min, BO ~1,6–1,8 h, 20 modelos finales ~2,5–3,5 h y Kaggle ~15 min: **~5 h por semilla** (4,5–6,5). La primera suma la genética (2–5 h, tope de 8): **~8–11 h**.

## 2026-10-22 15:10 UTC — v5/v7: v5 600017

v5 (exp 9850) contra v2, por semilla (media de los 9 cortes y centro 9.000–10.500):

| semilla | v2 | v5 | centro v2 | centro v5 | dif | dif centro |
|---|---|---|---|---|---|---|
| 150001 | 435.9 | 432.3 | 437.8 | 437.5 | -3.6 | -0.3 |
| 333331 | 440.7 | 437.3 | 443.7 | 439.5 | -3.3 | -4.2 |
| 600017 | 425.4 | 426.5 | 428.3 | 430.8 | +1.0 | +2.5 |
| 910009 | 436.7 | 440.4 | 435.6 | 446.9 | +3.7 | +11.2 |

v5 peor que la v2: 2 de 4 (9 cortes) y 2 de 4 (centro). Diferencia media: -0.5 (9 cortes), +2.3 (centro). Sin p de Wilcoxon todavía (pocas semillas). La v7 todavía no tiene semillas terminadas (sigue la genética en la 570001).

## 2026-10-22 16:00 UTC — v7: cambio de criterio de la genética (decidido con el control a la vista)

- Ronda 1: `(mprestamos_personales - ctrx_quarter) - mrentabilidad_annual`. Mejora de AUC de +0,00109 en la búsqueda y **+0,00143 en el control** (202103 y 202106, otra semilla). Pero quedó 6.ª de 20 contra las fórmulas al azar (percentil 90 del azar: +0,00183). Descartada con el criterio original.
- Lectura: la ganancia de agregar fórmulas está **repartida**. Casi cualquier combinación de las 30 claves suma algo (los árboles no arman bien diferencias ni ratios) y ninguna se destaca, así que la genética no encuentra nada mejor que el azar.
- **Decisión del usuario:** el control original contesta "¿la genética le gana al azar?", pero para la competencia importa "¿agregarla es mejor que nada?". **Nuevo criterio: queda toda ganadora con mejora positiva en el control.** Se aplica al terminar la genética, marcando `aceptada=TRUE` en `exp/WF9600_ga/genetica_rondas.txt` (el original queda en `z739v7/ga_rondas/`).
- Consecuencia: la **570001 de la v7 queda sin genética** (mide solo el efecto de sacar 2020) y **las siguientes semillas** (210011 en adelante) usan las fórmulas aceptadas. Riesgo: la v6 también mejoraba la AUC y se desplomó en Kaggle, pero acá son 5 columnas por fórmula, contra 264.

## 2026-10-22 17:33 UTC — v7: genética terminada (2 de 3 fórmulas entran)

| Ronda | Fórmula | Mejora AUC búsqueda | Mejora AUC control | p90 azar | Puesto | Entra |
|---|---|---|---|---|---|---|
| 1 | `(mprestamos_personales - ctrx_quarter) - mrentabilidad_annual` | +0,00109 | **+0,00143** | +0,00183 | 6/20 | **sí** |
| 2 | `(mprestamos_personales * ccaja_ahorro) * cproductos` | +0,00130 | **+0,00062** | +0,00113 | 7/20 | **sí** |
| 3 | `(mcomisiones + mrentabilidad) - vm_mpagominimo` | +0,00087 | −0,00005 | +0,00150 | 16/20 | no |

- ~2,8 h en total (~26 s por medición). Ninguna le gana al azar (la ganancia está repartida). Con el criterio de "mejora positiva en el control" quedan las rondas 1 y 2: `gen_01` y `gen_02`, cada una con lag1, lag2, delta1 y delta2, para la 210011 y las semillas siguientes. La ronda 3 no se desinfló en el control: se perdió.
- Archivos: `z739_v7/resultados/genetica_rondas_original.txt` (lo que decidió el script) y `genetica_rondas_aceptadas.txt` (lo que usan las semillas).

## 2026-10-22 21:00 UTC — 570001: v2 vs v5 vs v7 (sin 2020)

| Corte | v2 | v5 | v7 (sin 2020, sin genética) |
|---|---|---|---|
| 8.000 | 428,0 | 414,0 | 431,7 |
| 9.000 | 455,3 | 420,2 | 426,6 |
| 9.500 | 458,7 | 424,1 | 439,4 |
| 10.000 | 452,7 | 449,5 | 448,1 |
| 10.500 | 445,7 | 445,6 | 448,3 |
| 12.000 | 427,0 | 429,9 | 434,0 |
| **Promedio 9 cortes** | **444,0** | **431,2** | **437,0** |
| Centro 9.000–10.500 | 453,1 | 434,9 | 440,6 |

- **Sacar 2020: v7 contra v5 en la misma semilla, +5,8 (centro +5,7).** Un solo par: es la primera medición del efecto, no una conclusión.
- La 570001 (la mejor de la v2) cae en la v5 (−12,8) y en la v7 (−7,0). En parte es regresión a la media (en la v3 dio 442,7).
- **v5 con 5 pares: diferencia media −3,0 (centro −1,8), Wilcoxon p = 0,59.** No le gana a la v2.
