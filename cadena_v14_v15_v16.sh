#!/bin/bash
# Cadena: espera que termine una version (10 semillas con TERMINADO, o sus VMs
# apagadas), la para, corre la prueba corta de la siguiente y, si pasa los
# controles, la lanza en 2 VMs. v14 -> v15 -> v16.
SDK="/c/Users/eoinb/AppData/Local/Google/Cloud SDK/google-cloud-sdk"; export PATH="$SDK/bin:$PATH" CLOUDSDK_PYTHON="$SDK/platform/bundledpython/python.exe"
G=gs://eoin_barry_austral_bukito2026

esperar_fin() {   # esperar_fin <experimento> <prefijo VM> <carpeta local>
  local exp=$1 pre=$2 dir=$3 n vms
  for i in $(seq 900); do
    n=$(gcloud storage ls "$G/exp/" 2>/dev/null | grep -c "WF${exp}_s")
    n=$(for d in $(gcloud storage ls "$G/exp/" 2>/dev/null | grep "WF${exp}_s"); do gcloud storage ls "${d}TERMINADO" >/dev/null 2>&1 && echo 1; done | wc -l)
    vms=$(gcloud compute instances list --filter="name~$pre-a" --format="value(name)" | wc -l)
    [ "$n" -ge 10 ] && break
    [ "$vms" = 0 ] && break
    sleep 120
  done
  date -u; echo "exp $exp: $n semillas con TERMINADO, VMs $pre-a prendidas: $vms"
  cd "$dir" && bash vm/parar.sh A 2>&1 | tail -1; bash vm/parar.sh A 2 2>&1 | tail -1
  for i in $(seq 30); do vms=$(gcloud compute instances list --filter="name~$pre" --format="value(name)" | wc -l); [ "$vms" = 0 ] && break; sleep 15; done
}

probar_y_lanzar() {   # probar_y_lanzar <version> <prefijo VM> <exp prueba> <undersampling> <min_data> <carpeta>
  local v=$1 pre=$2 tst=$3 und=$4 md=$5 dir=$6 L OK
  cd "$dir" && bash vm/lanzar.sh B 2>&1 | tail -1
  local F="$G/$pre/B/log_WF${tst}_s570001.txt"
  for i in $(seq 40); do L=$(gcloud storage cat "$F" 2>/dev/null); echo "$L" | grep -qE "TERMINADO|Execution halted" && break; sleep 30; done
  echo "--- prueba v$v"; echo "$L" | grep -E "hiperparametros fijos|undersampling de CONTINUA|TERMINADO|halted|Error" | cut -c1-200
  OK=1
  echo "$L" | grep -q "| TERMINADO" || OK=0
  echo "$L" | grep -qE "Execution halted|Error in" && OK=0
  echo "$L" | grep -q "hiperparametros fijos de /home/ds/buckets/b1/exp/v${v}_hp/BO_log.txt" || OK=0
  echo "$L" | grep -q "final training: undersampling de CONTINUA $und " || OK=0
  echo "$L" | grep -q "credencial de Kaggle OK" || OK=0
  echo "$L" | grep -q "$md" || OK=0
  echo "controles v$v OK=$OK"
  bash vm/parar.sh B 2>&1 | tail -1
  for i in $(seq 30); do N=$(gcloud compute instances list --filter="name~$pre-b" --format="value(name)" | wc -l); [ "$N" = 0 ] && break; sleep 15; done
  if [ "$OK" = 1 ]; then bash vm/lanzar.sh A 2>&1 | tail -1; bash vm/lanzar.sh A 2 2>&1 | tail -1; echo "V$v LANZADA $(date -u)"; return 0
  else echo "V$v NO LANZADA: fallo algun control"; echo "$L" | tail -30; return 1; fi
}

esperar_fin 9000 z739r /c/tmp/lab1/z739v14
probar_y_lanzar 15 z739s 9976 0.125 1393 /c/tmp/lab1/z739v15 || exit 1
esperar_fin 8950 z739s /c/tmp/lab1/z739v15
probar_y_lanzar 16 z739t 9975 0.15 1672 /c/tmp/lab1/z739v16 || exit 1
date -u; gcloud compute instances list --filter="name~z739" --format="value(name,status)"
