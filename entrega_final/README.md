# Entrega final — Labo 1 BA 2026 Analista Sr

**Archivo entregado:** [`ensamble/KA_ens_C_v2v7v3_25_9500.csv`](ensamble/KA_ens_C_v2v7v3_25_9500.csv)
(puntaje público 450.3). Predice BAJA+2 en **202109** y marca como positivos a los **9.500** clientes de mayor puntaje.

Es un **ensamble por ranking de 25 corridas** de tres versiones del workflow de la cátedra
(`z739_final_senior.ipynb`). Las tres versiones parten de la misma notebook y cambian pocos parámetros:

| Versión | Script | Config | Qué cambia respecto de la notebook | Corridas usadas (semilla del pipeline) |
|---|---|---|---|---|
| **v2** | [`scripts/z739_final_senior_v2.R`](scripts/z739_final_senior_v2.R) (= [`notebook/z739_final_senior_v2.ipynb`](notebook/z739_final_senior_v2.ipynb)) | [`config/v2.env`](config/v2.env) | Feature engineering completo (tendencias, random forest 50×32), canaritos, BO de 8 hiperparámetros por AUC | 10: 150001, 210011, 333331, 450007, 570001, 600017, 720007, 850009, 910009, 999953 (exp. 9800) |
| **v3** | [`scripts/z739_final_senior_v3.R`](scripts/z739_final_senior_v3.R) | [`config/v3.env`](config/v3.env) | v2, pero la BO optimiza **ganancia** medida en 202104–202107 | 7: 150001, 333331, 570001, 600017, 720007, 850009, 910009 (exp. 9900) |
| **v7** | [`scripts/z739_final_senior_v7.R`](scripts/z739_final_senior_v7.R) | [`config/v7.env`](config/v7.env), [`config/v7_9601.env`](config/v7_9601.env) | v2 + semillerío 20, canaritos 2.0, deflación por IPC, 2020 fuera del entrenamiento y 2 variables de FE genético ([`config/genetica_rondas_v7.txt`](config/genetica_rondas_v7.txt)) | 8: 150001, 210011, 333331, 720007, 850009, 910009, 999953 (exp. 9600) y 570001 (exp. 9601) |

La notebook original de la cátedra se convirtió a script R para correr sin supervisión
en VMs de GCP (8 vCPU, 256 GB). Cada script, para una semilla, hace todo el workflow
(feature engineering → canaritos → BO → modelo final con semillerío) y escribe `prediccion.txt`
con la probabilidad de cada cliente de 202109.

## Cómo replicar

### Paso 1 — las 25 corridas

Cada corrida es `Rscript z739_final_senior_vN.R <config>` con el dataset
`analistasr_competencia_2026.csv.gz` en `DATASET_PATH`. La semilla se elige con
`SEMILLAS_PIPELINE` en la config (el script corre una semilla por vez). En GCP:

```bash
# desde una carpeta con el script, la config copiada como .env.A y la carpeta vm/
bash vm/lanzar.sh A      # crea la VM con el template de la cátedra y corre las semillas
bash vm/parar.sh A
```

`vm/vm.env` tiene el proyecto, el bucket, el template y el script a correr.
La salida de cada corrida queda en `exp/WF<experimento>_s<semilla>/prediccion.txt`.

**v7 y la genética:** para obtener exactamente las mismas variables, antes de correr la v7
copiar `config/genetica_rondas_v7.txt` como `exp/WF9600_ga/genetica_rondas.txt` (y como
`exp/WF9601_ga/genetica_rondas.txt` para la 570001), junto con un archivo vacío
`GENETICA_TERMINADA` en cada carpeta. Así el script usa las 2 fórmulas aceptadas
(rondas 1 y 2) en vez de volver a buscarlas.

### Paso 2 — el ensamble

Las 25 predicciones ya calculadas están en [`predicciones/`](predicciones/)
(solo `numero_de_cliente` y `prob`, comprimidas). Para rehacer el archivo entregado:

```bash
cd predicciones && gunzip -k */*.gz && cd ..
Rscript ensamble/ensamble_versiones.R C_v2v7v3 salida 9500 predicciones/v2 predicciones/v7 predicciones/v3
# genera salida/KA_ens_C_v2v7v3_25_9500.csv
```

[`ensamble/ensamble_versiones.R`](ensamble/ensamble_versiones.R): cada corrida convierte su
probabilidad en ranking (`frank`), se promedian los 25 rankings con el mismo peso y se marcan
con 1 los 9.500 clientes de mayor ranking promedio.

Verificado: rehaciendo el ensamble desde estas predicciones se obtiene un archivo
idéntico byte a byte al entregado (md5 `97249f3be2350f9c549fdc2d3cd79c0e`).

## Más detalle

El diario completo de decisiones, pruebas y resultados de todas las versiones (v2 a v16)
está en [`../BITACORA.md`](../BITACORA.md); cada versión tiene su carpeta `z739_vN/` en la raíz del repo.
