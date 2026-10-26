# PRUEBA CORTA de la v16 (3% de clientes). VM z739t-b.
# Todo el dataset, semillerio 9, canaritos 2.5, sin pesos. Hiperparametros UNIFORMES en todas las semillas:
# la mediana de la mejor fila de la BO de la v2 de las 10 semillas, con el minimo por hoja x 0.75 (exp/v16_hp).
# Lo lee vm/lanzar.sh (VMs z739t-*). Formato KEY=valor, sin espacios ni comillas.

GRUPO=B
EXPERIMENTO=9975
SEMILLAS_PIPELINE=570001
PRUEBA_FRACCION=0.03

FT_SEMILLERIO=9
CN_DESVIOS=2.5
DR_METODO=deflacion
MESES_EXCLUIR=
CK_DESDE_EXP=
GA_ACTIVA=0
POS_PESO=1
BO_LOG_FIJO=/home/ds/buckets/b1/exp/v16_hp/BO_log.txt
FT_UNDERSAMPLING=0.15

KAGGLE_SUBIR=0
KAGGLE_COMPETENCIA=labo-1-ba-2026-analista-sr
KAGGLE_JSON=/home/ds/buckets/b1/kaggle.json

BUCKET_DIR=/home/ds/buckets/b1
DATASET_PATH=/home/ds/buckets/b1/datasets/analistasr_competencia_2026.csv.gz

MAIL_FROM=sin-mail
MAIL_PASS_FILE=/dev/null
MAIL_TO_FILE=/dev/null
