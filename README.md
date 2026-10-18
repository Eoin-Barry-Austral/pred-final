# pred-final — Labo 1 2026 Analista Sr (churn BAJA+2)

Workflow en R para predecir qué clientes se dan de baja (BAJA+2) en **202109** y
maximizar la ganancia en la competencia de Kaggle **Labo 1 BA 2026 Analista Sr**.
Ganancia: +975.000 por cada BAJA+2 enviado, −25.000 por cualquier otro.

Parte de la notebook de la cátedra `z739_final_senior.ipynb`, convertida a script
para correr sin supervisión en VMs Spot de GCP (8 vCPU, 256 GB). El diario de
decisiones y resultados está en [BITACORA.md](BITACORA.md).

## Carpetas

| Carpeta | Qué es | Estado |
|---|---|---|
| [`z739_v2/`](z739_v2/) | La notebook con más feature engineering (tendencias completas, random forest 50×32), canaritos que podan menos y BO de 8 hiperparámetros por AUC. Experimento **9800**, 10 semillas del pipeline | Corriendo |
| [`z739_v3/`](z739_v3/) | v2 + la BO optimiza **ganancia** medida en 4 meses (202104–202107). Experimento **9900**, las mismas 10 semillas para comparar de a pares (Wilcoxon) | Lista, sin correr |

## Cómo se corre

Desde la carpeta de la versión, en Git Bash, con `gcloud` logueado:

```bash
bash vm/lanzar.sh A        # VM 1: recorre SEMILLAS_PIPELINE en orden
bash vm/lanzar.sh A 2      # VM 2: la recorre al revés (cada semilla la corre una sola VM)
bash vm/parar.sh A         # parar la VM 1 (A 2 para la otra)
bash vm/lanzar.sh B        # prueba corta: 3% de los clientes, sin subir a Kaggle
```

- `vm/vm.env`: proyecto, bucket, template de la VM y script que corre.
- `.env.A`: la corrida real (experimento, semillas, Kaggle, métrica de la BO). `.env.B`: la prueba corta.
- Cada semilla deja su salida en `gs://<bucket>/exp/WF<EXPERIMENTO>_s<semilla>/` (`prediccion.txt`, los 9 CSV de Kaggle, `BO_log.txt`, `impo.txt`) y graba `TERMINADO` al final. El log queda en `gs://<bucket>/<prefijo>/A/log_WF<EXPERIMENTO>_s<semilla>.txt`.
- Si GCP expropia la VM, se recrea y retoma desde el checkpoint, la BO y los modelos ya grabados. Si R se cuelga 30 min, se reinicia.
- `ensamble_ranking.R` arma el ensamble entre semillas promediando rankings.
- `z739_v2/nb2script.R` es el conversor de la notebook al script.

## Qué NO está en el repo

El dataset, la credencial de Kaggle, los checkpoints, los modelos y las predicciones
por cliente: quedan en el bucket de GCP. La imagen de la cátedra guarda el
`kaggle.json` del bucket en Secret Manager (`kaggle-cred`) y lo borra del bucket.
