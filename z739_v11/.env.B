# PRUEBA CORTA de la v11 (base v10; usa el dataset de la prueba de la v7, exp 9987). VM z739o-b.
# v11 = v10 (2020 fuera, sin genetica, semillerio 20, canaritos 2.0) con POS_PESO=3:
#   cada positivo (BAJA+1 y BAJA+2) pesa 3 en la BO y el final training.
# Reusa los datasets despues de canaritos de la v7.
# Lo lee vm/lanzar.sh A (VM z739o-a). Formato KEY=valor, sin espacios ni comillas.

GRUPO=B
EXPERIMENTO=9982
SEMILLAS_PIPELINE=570001
PRUEBA_FRACCION=0.03

FT_SEMILLERIO=20
CN_DESVIOS=2.0
DR_METODO=deflacion
MESES_EXCLUIR=202001,202002,202003,202004,202005,202006,202007,202008,202009,202010,202011,202012
CK_DESDE_EXP=9987
GA_ACTIVA=0
POS_PESO=3

KAGGLE_SUBIR=0
KAGGLE_COMPETENCIA=labo-1-ba-2026-analista-sr
KAGGLE_JSON=/home/ds/buckets/b1/kaggle.json

BUCKET_DIR=/home/ds/buckets/b1
DATASET_PATH=/home/ds/buckets/b1/datasets/analistasr_competencia_2026.csv.gz

MAIL_FROM=sin-mail
MAIL_PASS_FILE=/dev/null
MAIL_TO_FILE=/dev/null
