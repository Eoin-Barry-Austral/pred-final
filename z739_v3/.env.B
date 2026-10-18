# PRUEBA CORTA de z739_final_senior_v3.R (no es una corrida real).
# Se lanza con vm/lanzar.sh B (VM z739g-b) solo para separarla de las corridas reales.
GRUPO=B

EXPERIMENTO=9996
SEMILLAS_PIPELINE=150001

# 3% de los clientes, BO minima (32 iniciales + 2), 1 modelo final
PRUEBA_FRACCION=0.03

BO_METRICA=ganancia
BO_VALIDA=202104,202105,202106,202107

# no sube nada: genera los csv y verifica la credencial
KAGGLE_SUBIR=0
KAGGLE_COMPETENCIA=labo-1-ba-2026-analista-sr
KAGGLE_JSON=/home/ds/buckets/b1/kaggle.json

BUCKET_DIR=/home/ds/buckets/b1
DATASET_PATH=/home/ds/buckets/b1/datasets/analistasr_competencia_2026.csv.gz

MAIL_FROM=sin-mail
MAIL_PASS_FILE=/dev/null
MAIL_TO_FILE=/dev/null
