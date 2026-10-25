# PRUEBA CORTA de la v12 (3% de clientes). VM z739p-b.
# (todo el dataset, semillerio 9, canaritos 2.5, sin pesos) con los hiperparametros
# de la BO de la 570001 de la v2 en todas las semillas (sin BO). VMs z739p-*.
# Lo lee vm/lanzar.sh (VMs z739p-*). Formato KEY=valor, sin espacios ni comillas.

GRUPO=B
EXPERIMENTO=9980
SEMILLAS_PIPELINE=333331
PRUEBA_FRACCION=0.03

FT_SEMILLERIO=9
CN_DESVIOS=2.5
DR_METODO=deflacion
MESES_EXCLUIR=
CK_DESDE_EXP=
GA_ACTIVA=0
POS_PESO=1
BO_LOG_FIJO=/home/ds/buckets/b1/exp/WF9800_s570001/BO_log.txt

KAGGLE_SUBIR=0
KAGGLE_COMPETENCIA=labo-1-ba-2026-analista-sr
KAGGLE_JSON=/home/ds/buckets/b1/kaggle.json

BUCKET_DIR=/home/ds/buckets/b1
DATASET_PATH=/home/ds/buckets/b1/datasets/analistasr_competencia_2026.csv.gz

MAIL_FROM=sin-mail
MAIL_PASS_FILE=/dev/null
MAIL_TO_FILE=/dev/null
