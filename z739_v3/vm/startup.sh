#!/bin/bash
# Startup script de la VM (corre como root en cada arranque).
# Lo instala vm/lanzar.sh en el template; no se usa a mano.
#
# 1. hace lo mismo que el startup de los templates de la catedra (gcloud config)
# 2. espera a ver el bucket montado (lo monta la imagen labo-family)
# 3. corre el workflow si no termino; retoma solo desde los checkpoints
# 4. al salir R, por lo que sea, espera 30 min y baja el grupo a 0, asi no se
#    recrea. Solo una expropiacion (que no pasa por aca) hace que se recree.
#
# El bucket lo monta gcsfuse para el usuario ds, sin allow_other: root NO lo
# puede leer. Todo acceso al bucket va como ds.

META=http://metadata.google.internal/computeMetadata/v1/instance
meta() { curl -sf -H "Metadata-Flavor: Google" "$META/$1"; }
ds() { sudo -u ds -H "$@"; }

PROYECTO=$(meta attributes/proyecto)
MIG=$(meta attributes/mig)
ZONA=$(meta zone | awk -F/ '{print $NF}')
ds gcloud config set project "$PROYECTO"

B=$(meta attributes/bucket-dir)
DIR="$B/$(meta attributes/wf-dir)"

for i in $(seq 120); do ds test -f "$DIR/.env" && break; sleep 5; done
if ! ds test -f "$DIR/.env"; then
  # sin .env no hay mail: queda en el serial port. Se baja el grupo para no
  # dejar la VM prendida cobrando
  echo "startup: no veo $DIR/.env despues de 10 min: el bucket no esta montado. Bajo el grupo a 0"
  gcloud compute instance-groups managed resize "$MIG" --zone "$ZONA" --project "$PROYECTO" --size 0
  exit 1
fi

set -a; . <(ds cat "$DIR/.env" | tr -d '\r'); set +a

# SEMILLAS_PIPELINE (en el .env, separadas por coma): una corrida completa por
# semilla, en orden, cada una en exp/WF<EXPERIMENTO>_s<semilla>. Vacio = una
# sola corrida en exp/WF<EXPERIMENTO> con la semilla del script.
SEMILLAS=$(echo "${SEMILLAS_PIPELINE:-}" | tr ',' ' ')
[ -z "$SEMILLAS" ] && SEMILLAS="-"
# con dos VMs (vm/lanzar.sh B 2) la segunda recorre la lista al reves, y cada
# semilla la corre la VM que primero crea exp/<corrida>/EN_CURSO (con su MIG
# adentro). La creacion es atomica (if-generation-match=0) y va por gcloud
# storage, no por gcsfuse, que cachea y no ve al instante lo de la otra VM.
[ "$(meta attributes/orden)" = "inverso" ] && SEMILLAS=$(echo $SEMILLAS | tr ' ' '\n' | tac | tr '\n' ' ')
GS="gs://$(meta attributes/bucket)"
tomar() {   # tomar <corrida>: 0 si esta VM corre esa semilla
  local marca="$GS/exp/$1/EN_CURSO" dueno
  dueno=$(ds gcloud storage cat "$marca" 2>/dev/null | tr -d '[:space:]')
  [ "$dueno" = "$MIG" ] && return 0
  [ -n "$dueno" ] && return 1
  echo "$MIG" | ds gcloud storage cp - "$marca" --if-generation-match=0 >/dev/null 2>&1
}

nombre() { if [ "$1" = "-" ]; then echo "WF$EXPERIMENTO"; else echo "WF${EXPERIMENTO}_s$1"; fi; }

mail() {   # mail <corrida> <titulo> <cuerpo>: al hilo "experimento" de esa corrida
  ds test -f "$MAIL_PASS_FILE" && ds test -f "$MAIL_TO_FILE" || return 0
  local para rcpt="" m
  para=$(ds cat "$MAIL_TO_FILE" | grep -v '^#' | sed '/^[[:space:]]*$/d')
  for d in $para; do rcpt="$rcpt --mail-rcpt $d"; done
  m=$(mktemp)
  local raiz="<$(echo $1 | tr A-Z a-z)-$(echo $GRUPO | tr A-Z a-z)-experimento@workflow635>"
  printf "From: %s\nTo: %s\nSubject: Re: [%s grupo %s] experimento\nIn-Reply-To: %s\nReferences: %s\n\n%s\n\n%s\n" \
    "$MAIL_FROM" "$(echo $para | sed 's/ /, /g')" "$1" "$GRUPO" "$raiz" "$raiz" "$2" "$3" > "$m"
  curl -s --max-time 30 --ssl-reqd --url smtps://smtp.gmail.com:465 \
    --mail-from "$MAIL_FROM" $rcpt \
    --user "$MAIL_FROM:$(ds head -1 "$MAIL_PASS_FILE" | tr -d '[:space:]')" -T "$m"
  rm -f "$m"
}

for SEM in $SEMILLAS; do
  CORRIDA=$(nombre "$SEM")
  FIN="$B/exp/$CORRIDA/TERMINADO"
  ds test -f "$FIN" && continue
  tomar "$CORRIDA" || { echo "startup: $CORRIDA la corre otra VM"; continue; }
  echo "$CORRIDA" > /home/ds/wf635_corrida_actual    # para el mail del shutdown
  ARG=""; [ "$SEM" != "-" ] && ARG="$SEM"

  # gcsfuse sube un archivo recien al cerrarlo: R escribe el log en el disco
  # local y una copia va al bucket cada minuto (log_<corrida>.txt)
  # Vigia: si R (con sus hijos) pasa 30 min casi sin usar CPU, esta colgado:
  # lo mata y sale con 99, y la misma semilla se reintenta desde el checkpoint.
  # R corre en su propia sesion (setsid) para sumar la CPU de todos sus procesos.
  # v3: tambien si el final training pasa 90 min sin un 'modelo final listo'
  # (R sigue usando CPU pero no avanza: paso con la semilla 150001 de la v2). Al
  # reintentar saltea la BO y los modelos ya grabados. Solo mira las lineas que
  # escribio ESTE intento (LINEA0), no las de intentos anteriores.
  for INTENTO in 1 2 3; do
    ds bash -lc "
      export PATH=\$HOME/.local/bin:\$PATH
      LOCAL=\$HOME/log_$CORRIDA.txt
      COLGADO=\$HOME/colgado_$CORRIDA
      rm -f \$COLGADO
      cd '$DIR' || exit 2
      [ -f log_$CORRIDA.txt ] && [ ! -f \$LOCAL ] && cp log_$CORRIDA.txt \$LOCAL
      ( while sleep 60; do cp \$LOCAL log_$CORRIDA.txt; done ) &
      COPIA=\$!
      LINEA0=\$(cat \$LOCAL 2>/dev/null | wc -l)
      setsid Rscript workflow.R .env $ARG >> \$LOCAL 2>&1 &
      R_PID=\$!
      cpu() { ps -s \$R_PID -o times= | awk '{s += \$1} END {print s + 0}'; }
      ( ANT=\$(cpu); QUIETO=0
        while sleep 300; do
          AHORA=\$(cpu)
          if [ \$((AHORA - ANT)) -lt 3 ]; then QUIETO=\$((QUIETO + 5)); else QUIETO=0; fi
          ANT=\$AHORA
          if [ \$QUIETO -ge 30 ]; then
            echo \"\$(date -u '+%F %T') | VIGIA: R lleva 30 min sin usar CPU, lo mato y reintento la semilla\" >> \$LOCAL
            touch \$COLGADO
            pkill -TERM -s \$R_PID; sleep 30; pkill -KILL -s \$R_PID
            break
          fi
          ETAPA=\$(tail -n +\$((LINEA0 + 1)) \$LOCAL | grep ' | ' | tail -1)
          case \"\$ETAPA\" in
            *'| final training'*|*'| modelo final listo'*)
              T=\$(date -u -d \"\${ETAPA:0:19}\" +%s 2>/dev/null || echo 0)
              if [ \"\$T\" -gt 0 ] && [ \$(( \$(date -u +%s) - T )) -ge 5400 ]; then
                echo \"\$(date -u '+%F %T') | VIGIA: final training sin avances hace 90 min, lo mato y reintento la semilla\" >> \$LOCAL
                touch \$COLGADO
                pkill -TERM -s \$R_PID; sleep 30; pkill -KILL -s \$R_PID
                break
              fi;;
          esac
        done ) &
      VIGIA=\$!
      wait \$R_PID
      RC=\$?
      kill \$COPIA \$VIGIA 2>/dev/null
      cp \$LOCAL log_$CORRIDA.txt
      [ -f \$COLGADO ] && exit 99
      exit \$RC"
    RC=$?
    [ "$RC" = "99" ] || break
    mail "$CORRIDA" "R colgado (intento $INTENTO)" \
      "R paso 30 min sin usar CPU o el final training 90 min sin avances. Lo mate y reintento la semilla desde el checkpoint. Ver $DIR/log_$CORRIDA.txt."
  done
  if ! ds test -f "$FIN"; then
    # rc 1 = error que R ya aviso por mail. Otro rc = R murio sin poder avisar
    # (por ejemplo, sin memoria). En los dos casos sigue con la proxima semilla.
    [ "$RC" != "1" ] && mail "$CORRIDA" "R termino sin terminar (codigo $RC)" \
      "Rscript salio con codigo $RC y sin TERMINADO. Probable falta de memoria. Ver $DIR/log_$CORRIDA.txt. Sigue con la proxima semilla."
  fi
done

if [ "$(meta attributes/apagar-al-terminar)" = "1" ]; then
  sleep 1800
  gcloud compute instance-groups managed resize "$MIG" --zone "$ZONA" --project "$PROYECTO" --size 0
fi
