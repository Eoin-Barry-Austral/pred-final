# PRUEBA CORTA de la v10 (usa el dataset de la prueba de la v7, exp 9987). VM z739n-b.
# v10 = v7 SIN genetica: 2020 fuera de todo entrenamiento, nada mas (BO con 17 meses,
# final con 19). Semillerio 20, canaritos 2.0, deflacion por IPC. Es la receta de la
# 570001 de la v7 (exp 9600), que corrio sin genetica: esa semilla no se repite.
# Reusa los datasets despues de canaritos de la v7.
# Lo lee vm/lanzar.sh A (VM z739n-a). Formato KEY=valor, sin espacios ni comillas.

GRUPO=B
EXPERIMENTO=9983
SEMILLAS_PIPELINE=570001
PRUEBA_FRACCION=0.03

FT_SEMILLERIO=20
CN_DESVIOS=2.0
DR_METODO=deflacion
MESES_EXCLUIR=202001,202002,202003,202004,202005,202006,202007,202008,202009,202010,202011,202012
CK_DESDE_EXP=9987
GA_ACTIVA=0

KAGGLE_SUBIR=0
KAGGLE_COMPETENCIA=labo-1-ba-2026-analista-sr
KAGGLE_JSON=/home/ds/buckets/b1/kaggle.json

BUCKET_DIR=/home/ds/buckets/b1
DATASET_PATH=/home/ds/buckets/b1/datasets/analistasr_competencia_2026.csv.gz

MAIL_FROM=sin-mail
MAIL_PASS_FILE=/dev/null
MAIL_TO_FILE=/dev/null
