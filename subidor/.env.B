# Subidor de envios pendientes a Kaggle (subir_pendientes.R). VM z739u-b.
# Sube los csv sin marca .subido, en el orden de SUBIR_LISTA, hasta MAX_ENVIOS.
GRUPO=B
EXPERIMENTO=8800
SEMILLAS_PIPELINE=
SUBIR_LISTA=8950:*,9000:600017
MAX_ENVIOS=99
SUBIR_SECO=0
KAGGLE_COMPETENCIA=labo-1-ba-2026-analista-sr
KAGGLE_JSON=/home/ds/buckets/b1/kaggle.json
BUCKET_DIR=/home/ds/buckets/b1
DATASET_PATH=/home/ds/buckets/b1/datasets/analistasr_competencia_2026.csv.gz
MAIL_FROM=sin-mail
MAIL_PASS_FILE=/dev/null
MAIL_TO_FILE=/dev/null
