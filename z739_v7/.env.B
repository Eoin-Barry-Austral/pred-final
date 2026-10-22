# PRUEBA CORTA de z739_final_senior_v7.R (no es una corrida real). VM z739k-b.
# v7 = v5 (BO por AUC, semillerio 20, canaritos 2.0, deflacion por IPC) con:
#   * FE genetico (una sola busqueda para todas las semillas, despues de canaritos)
#   * 2020 fuera de todo entrenamiento (sigue en el dataset para lags y tendencias)
# Lo lee vm/lanzar.sh A (VM z739k-a). Formato KEY=valor, sin espacios ni comillas.

GRUPO=B

# experimento nuevo: exp/WF9600_s<semilla>; la genetica en exp/WF9600_ga
EXPERIMENTO=9988

# semillas buenas primero (promedio publico de la v2)
SEMILLAS_PIPELINE=570001
PRUEBA_FRACCION=0.03

FT_SEMILLERIO=20
CN_DESVIOS=2.0
DR_METODO=deflacion
MESES_EXCLUIR=202001,202002,202003,202004,202005,202006,202007,202008,202009,202010,202011,202012

GA_ACTIVA=1
GA_BUSQUEDA=202104,202105
GA_CONTROL=202103,202106
GA_RONDAS=3
GA_POBLACION=20
GA_GENERACIONES=10
GA_UNDERSAMPLING=0.1
GA_N_CONTROL=19
GA_SEMILLA=777
GA_HORAS_MAX=8

KAGGLE_SUBIR=0
KAGGLE_COMPETENCIA=labo-1-ba-2026-analista-sr
KAGGLE_JSON=/home/ds/buckets/b1/kaggle.json

BUCKET_DIR=/home/ds/buckets/b1
DATASET_PATH=/home/ds/buckets/b1/datasets/analistasr_competencia_2026.csv.gz

MAIL_FROM=sin-mail
MAIL_PASS_FILE=/dev/null
MAIL_TO_FILE=/dev/null
