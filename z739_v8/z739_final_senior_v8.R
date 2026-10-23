
# ======================================================================
# 9 WorkFlow Analista Senior

# ======================================================================
# 9.5 Objetivo

# ======================================================================
# 9.7  Workflow

# ======================================================================
# Inicializacion

# --- celda 8 ---
format(Sys.time(), "%a %b %d %X %Y")

# --- celda 9 ---
# limpio la memoria
rm(list=ls(all.names=TRUE)) # remove all objects
gc(full=TRUE, verbose=FALSE) # garbage collection

# --- celda 10 ---
# z739_final_senior_v8.R
# v8 = v7 con la genetica medida en los datasets de varias semillas del pipeline
#   (GA_SEMILLAS_DATOS, de GA_DATOS_EXP): cada formula se mide en todas y se
#   promedia, asi la ganadora no depende de una sola semilla. Y CK_DESDE_EXP:
#   reusa el dataset despues de canaritos de otro experimento con el mismo
#   preprocesamiento (la v7), sin rehacerlo.
# v7 = v5 (BO por AUC, semillerio FT_SEMILLERIO, canaritos CN_DESVIOS) con:
#   * MESES_EXCLUIR: meses que no entran a ningun entrenamiento (BO, final y
#     genetica); siguen en el dataset para los lags y las tendencias
#   * GA_ACTIVA=1: FE genetico, una sola busqueda para todas las semillas
#     (ver el bloque "v7: FE GENETICO")
#   * DR_METODO: metodo del Data Drifting (por defecto deflacion por IPC); se
#     corrigen los nombres de las funciones del dolar, que fallaban
#   y guarda la lista de envios de Kaggle (kaggle_submissions.csv), como la v3.
# Version script de la notebook z739_final_senior_v2.ipynb (grupo A: predice 202109 y sube a Kaggle)
#   uso: Rscript z739_final_senior_v8.R <archivo .env> <semilla del pipeline>
# Cambios respecto de la notebook (solo lo necesario para correr sin supervision):
#   * configuracion (rutas, experimento, Kaggle) desde el .env; la semilla del pipeline por argumento
#   * carpeta exp/WF<EXPERIMENTO>_s<semilla>; al final graba TERMINADO
#   * checkpoint despues de canaritos y retoma de la BO y de los modelos ya grabados
#   * lgb.importance con respaldo si el modelo es demasiado grande (limite de 2^31 bytes de R)
#   * Kaggle: prepara kaggle.json, no resube lo ya subido, no falla si Kaggle no responde
dir.create(Sys.getenv("R_LIBS_USER"), recursive= TRUE, showWarnings= FALSE)
.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
options(repos= c(CRAN= "https://cloud.r-project.org"))

require("data.table")
setDTthreads(0)   # data.table con todos los nucleos (por defecto usa la mitad)

if( !require("R.utils")) install.packages("R.utils")
require("R.utils")

if( !require("fst")) install.packages("fst")
require("fst")

marca <- function(...) cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "|", ..., "\n")

# ======================================================================
# Parametros

# --- celda 12 ---
args <- commandArgs(trailingOnly= TRUE)
archivo_env <- if (length(args) >= 1) args[1] else ".env"
if (!file.exists(archivo_env)) stop("No existe el archivo de configuracion ", archivo_env)
readRenviron(archivo_env)

PARAM <- list()
PARAM$semilla_primigenia <- if (length(args) >= 2) as.numeric(args[2]) else 102191
PARAM$experimento <- as.integer(Sys.getenv("EXPERIMENTO"))
PARAM$dataset <- basename(Sys.getenv("DATASET_PATH"))
# PRUEBA_FRACCION > 0 (solo para probar el pipeline): esa fraccion de los
# clientes, una BO minima y 1 modelo final. 0 o vacio = corrida normal
PRUEBA <- as.numeric(Sys.getenv("PRUEBA_FRACCION", "0"))
if (is.na(PRUEBA)) PRUEBA <- 0
if (PRUEBA > 0) marca("MODO PRUEBA:", PRUEBA, "de los clientes, BO minima, 1 modelo final")
marca("inicio: experimento", PARAM$experimento, "semilla del pipeline", PARAM$semilla_primigenia)

# ======================================================================
# Carpeta del Experimento

# --- celda 14 ---
# carpeta de trabajo: exp/WF<experimento>_s<semilla> (la misma que espera vm/startup.sh)
experimento_folder <- paste0("WF", PARAM$experimento, "_s", format(PARAM$semilla_primigenia, scientific= FALSE))
carpeta <- file.path(Sys.getenv("BUCKET_DIR"), "exp", experimento_folder)
dir.create(carpeta, recursive= TRUE, showWarnings= FALSE)
setwd(carpeta)
dir.create("checkpoints", showWarnings= FALSE)
CK <- "checkpoints/dataset_canaritos.fst"
CK_GA <- "checkpoints/ga_base.fst"
# v8: si esta semilla ya tiene el dataset despues de canaritos en otro experimento
# con el mismo preprocesamiento (CK_DESDE_EXP, la v7), se lee de ahi y no se
# rehace (~20 min). Solo se lee: nunca se escribe en la carpeta del otro experimento
carpeta_ck_otro <- function(exp) file.path(Sys.getenv("BUCKET_DIR"), "exp",
  paste0("WF", exp, "_s", format(PARAM$semilla_primigenia, scientific= FALSE)), "checkpoints")
if (!file.exists(CK) && Sys.getenv("CK_DESDE_EXP", "") != "") {
  otro <- carpeta_ck_otro(Sys.getenv("CK_DESDE_EXP"))
  if (file.exists(file.path(otro, "dataset_canaritos.fst")) && file.exists(file.path(otro, "ga_base.fst"))) {
    CK <- file.path(otro, "dataset_canaritos.fst")
    CK_GA <- file.path(otro, "ga_base.fst")
    marca("v8: uso el checkpoint de canaritos del experimento", Sys.getenv("CK_DESDE_EXP"))
  }
}

# v7: meses fuera de todo entrenamiento (por ejemplo 202001-202012)
MESES_EXCLUIR <- {
  v <- Sys.getenv("MESES_EXCLUIR", "")
  if (v == "") integer(0) else as.integer(strsplit(v, ",")[[1]])
}
if (length(MESES_EXCLUIR)) marca("meses fuera del entrenamiento:", paste(MESES_EXCLUIR, collapse= ","))

# v7: genetica. Las variables base se guardan ANTES de canaritos (que puede
# borrar alguna) en su propio checkpoint, para poder retomar
GA_ACTIVA <- Sys.getenv("GA_ACTIVA", "0") == "1"
GA_CLAVES <- c("ctrx_quarter_normalizado", "mprestamos_personales", "mcaja_ahorro",
  "mpayroll_sobre_edad", "mcuentas_saldo", "mcomisiones", "mpasivos_margen",
  "mtarjeta_visa_consumo", "cproductos", "mactivos_margen", "ctarjeta_visa_transacciones",
  "mcuenta_corriente", "mrentabilidad_annual", "cpayroll_trx", "mrentabilidad",
  "cdescubierto_preacordado", "vm_status01", "mcomisiones_mantenimiento",
  "mcuenta_debitos_automaticos", "mpayroll", "mcaja_ahorro_dolares", "mautoservicio",
  "mtarjeta_master_consumo", "ccaja_ahorro", "vm_msaldototal", "ccallcenter_transacciones",
  "ctarjeta_debito_transacciones", "ctrx_quarter", "vm_mpagominimo", "Visa_cconsumos")

# ======================================================================
# 9.7.1   Preprocesamiento del dataset

# ======================================================================
# 9.7.1.1  DT incorporar dataset

# --- celda 17 ---
if (file.exists(CK)) {
  marca("retomo desde el checkpoint", CK)
  dataset <- read_fst(CK, as.data.table= TRUE)
} else {

marca("lectura del dataset")
dataset <- fread(Sys.getenv("DATASET_PATH"))
if (PRUEBA > 0) {
  set.seed(1)
  ids <- unique(dataset$numero_de_cliente)
  dataset <- dataset[numero_de_cliente %in% sample(ids, ceiling(length(ids) * PRUEBA))]
  marca("MODO PRUEBA: quedan", nrow(dataset), "filas")
}

# ======================================================================
# 9.7.1.2  CA  Catastrophe Analysis

# --- celda 20 de la notebook: se saca (solo mostraba datos o instalaba algo que no se usa) ---

# --- celda 21 ---
# Escrito por alumnos de  Universidad Austral  Rosario

Corregir_MICE <- function(pcampo, pmeses) {

  meth <- rep("", ncol(dataset))
  names(meth) <- colnames(dataset)
  meth[names(meth) == pcampo] <- "sample"

  # llamada a mice  !
  imputacion <- mice(dataset,
    method = meth,
    maxit = 5,
    m = 1,
    seed = 7)

  tbl <- mice::complete(dataset)

  dataset[, paste0(pcampo) := ifelse(foto_mes %in% pmeses, tbl[, get(pcampo)], get(pcampo))]

}


# --- celda 22 ---
Corregir_interpolar <- function(pcampo, pmeses) {

  tbl <- dataset[, list(
    "v1" = shift(get(pcampo), 1, type = "lag"),
    "v2" = shift(get(pcampo), 1, type = "lead")
  ),
  by = eval(PARAM$dataset_metadata$entity_id)
  ]

  tbl[, paste0(PARAM$dataset_metadata$entity_id) := NULL]
  tbl[, promedio := rowMeans(tbl, na.rm = TRUE)]

  dataset[
    ,
    paste0(pcampo) := ifelse(!(foto_mes %in% pmeses),
      get(pcampo),
      tbl$promedio
    )
  ]
}

# --- celda 23 ---
AsignarNA_campomeses <- function(pcampo, pmeses) {

  if( pcampo %in% colnames( dataset ) ) {

    dataset[ foto_mes %in% pmeses, paste0(pcampo) := NA ]
  }
}

# --- celda 24 ---

Corregir_atributo <- function(pcampo, pmeses, pmetodo)
{
  # si el campo no existe en el dataset, Afuera !
  if( !(pcampo %in% colnames( dataset )) )
    return( 1 )

  # llamo a la funcion especializada que corresponde
  switch( pmetodo,
    "MachineLearning"     = AsignarNA_campomeses(pcampo, pmeses),
    "EstadisticaClasica"  = Corregir_interpolar(pcampo, pmeses),
    "MICE"                = Corregir_MICE(pcampo, pmeses),
  )

  return( 0 )
}

# --- celda 25 ---

Corregir_Rotas <- function(dataset, pmetodo) {
  gc(verbose= FALSE)
  cat( "inicio Corregir_Rotas()\n")
  # acomodo los errores del dataset

  Corregir_atributo("active_quarter", c(202006), pmetodo) # 1
  Corregir_atributo("internet", c(202006), pmetodo) # 2

  Corregir_atributo("mrentabilidad", c(201905, 201910, 202006), pmetodo) # 3
  Corregir_atributo("mrentabilidad_annual", c(201905, 201910, 202006), pmetodo) # 4

  Corregir_atributo("mcomisiones", c(201905, 201910, 202006), pmetodo) # 5

  Corregir_atributo("mactivos_margen", c(201905, 201910, 202006), pmetodo) # 6
  Corregir_atributo("mpasivos_margen", c(201905, 201910, 202006), pmetodo) # 7

  Corregir_atributo("mcuentas_saldo", c(202006), pmetodo) # 8

  Corregir_atributo("ctarjeta_debito_transacciones", c(202006), pmetodo) # 9

  Corregir_atributo("mautoservicio", c(202006), pmetodo) # 10

  Corregir_atributo("ctarjeta_visa_transacciones", c(202006), pmetodo) # 11
  Corregir_atributo("mtarjeta_visa_consumo", c(202006), pmetodo) # 12

  Corregir_atributo("ctarjeta_master_transacciones", c(202006), pmetodo) # 13
  Corregir_atributo("mtarjeta_master_consumo", c(202006), pmetodo) # 14

  Corregir_atributo("ctarjeta_visa_debitos_automaticos", c(201904), pmetodo) # 15
  Corregir_atributo("mttarjeta_visa_debitos_automaticos", c(201904), pmetodo) # 16

  Corregir_atributo("ccajeros_propios_descuentos",
    c(201910, 202002, 202006, 202009, 202010, 202102), pmetodo) # 17

  Corregir_atributo("mcajeros_propios_descuentos",
    c(201910, 202002, 202006, 202009, 202010, 202102), pmetodo) # 18

  Corregir_atributo("ctarjeta_visa_descuentos",
    c(201910, 202002, 202006, 202009, 202010, 202102), pmetodo) # 19

  Corregir_atributo("mtarjeta_visa_descuentos",
    c(201910, 202002, 202006, 202009, 202010, 202102), pmetodo) # 20

  Corregir_atributo("ctarjeta_master_descuentos",
    c(201910, 202002, 202006, 202009, 202010, 202102), pmetodo) # 21

  Corregir_atributo("mtarjeta_master_descuentos",
    c(201910, 202002, 202006, 202009, 202010, 202102), pmetodo) # 22

  Corregir_atributo("ccomisiones_otras", c(201905, 201910, 202006), pmetodo) # 23
  Corregir_atributo("mcomisiones_otras", c(201905, 201910, 202006), pmetodo) # 24

  Corregir_atributo("cextraccion_autoservicio", c(202006), pmetodo) # 25
  Corregir_atributo("mextraccion_autoservicio", c(202006), pmetodo) # 26

  Corregir_atributo("ccheques_depositados", c(202006), pmetodo) # 27
  Corregir_atributo("mcheques_depositados", c(202006), pmetodo) # 28
  Corregir_atributo("ccheques_emitidos", c(202006), pmetodo) # 29
  Corregir_atributo("mcheques_emitidos", c(202006), pmetodo) # 30
  Corregir_atributo("ccheques_depositados_rechazados", c(202006), pmetodo) # 31
  Corregir_atributo("mcheques_depositados_rechazados", c(202006), pmetodo) # 32
  Corregir_atributo("ccheques_emitidos_rechazados", c(202006), pmetodo) # 33
  Corregir_atributo("mcheques_emitidos_rechazados", c(202006), pmetodo) # 34

  Corregir_atributo("tcallcenter", c(202006), pmetodo) # 35
  Corregir_atributo("ccallcenter_transacciones", c(202006), pmetodo) # 36

  Corregir_atributo("thomebanking", c(202006), pmetodo) # 37
  Corregir_atributo("chomebanking_transacciones", c(201910, 202006), pmetodo) # 38

  Corregir_atributo("ccajas_transacciones", c(202006), pmetodo) # 39
  Corregir_atributo("ccajas_consultas", c(202006), pmetodo) # 40

  Corregir_atributo("ccajas_depositos", c(202006, 202105), pmetodo) # 41

  Corregir_atributo("ccajas_extracciones", c(202006), pmetodo) # 41
  Corregir_atributo("ccajas_otras", c(202006), pmetodo) # 43

  Corregir_atributo("catm_trx", c(202006), pmetodo) # 44
  Corregir_atributo("matm", c(202006), pmetodo) # 45
  Corregir_atributo("catm_trx_other", c(202006), pmetodo) # 46
  Corregir_atributo("matm_other", c(202006), pmetodo) # 47

  cat( "fin Corregir_rotas()\n")
}


# --- celda 26 ---
marca("Catastrophe Analysis")
# resuelvo el Catastrophe Analysis

setorder( dataset, numero_de_cliente, foto_mes )

PARAM$CA$metodo= "MachineLearning"

if( PARAM$CA$metodo %in% c("MachineLearning", "EstadisticaClasica", "MICE") )
  Corregir_Rotas(dataset, PARAM$CA$metodo)

# ======================================================================
# 9.7.1.3  DR  Data Drifting

# --- celda 28 ---
# meses que me interesan para el ajuste de variables monetarias
vfoto_mes <- c(
  201901, 201902, 201903, 201904, 201905, 201906,
  201907, 201908, 201909, 201910, 201911, 201912,
  202001, 202002, 202003, 202004, 202005, 202006,
  202007, 202008, 202009, 202010, 202011, 202012,
  202101, 202102, 202103, 202104, 202105, 202106,
  202107, 202108, 202109
)


# --- celda 29 ---
# los valores que siguen fueron calculados por alumnos

# momento 1.0  31-dic-2020 a las 23:59
vIPC <- c(
  1.9903030878, 1.9174403544, 1.8296186587,
  1.7728862972, 1.7212488323, 1.6776304408,
  1.6431248196, 1.5814483345, 1.4947526791,
  1.4484037589, 1.3913580777, 1.3404220402,
  1.3154288912, 1.2921698342, 1.2472681797,
  1.2300475145, 1.2118694724, 1.1881073259,
  1.1693969743, 1.1375456949, 1.1065619600,
  1.0681100000, 1.0370000000, 1.0000000000,
  0.9680542110, 0.9344152616, 0.8882274350,
  0.8532444140, 0.8251880213, 0.8003763543,
  0.7763107219, 0.7566381305, 0.7289384687
)

vdolar_blue <- c(
   39.045455,  38.402500,  41.639474,
   44.274737,  46.095455,  45.063333,
   43.983333,  54.842857,  61.059524,
   65.545455,  66.750000,  72.368421,
   77.477273,  78.191667,  82.434211,
  101.087500, 126.236842, 125.857143,
  130.782609, 133.400000, 137.954545,
  170.619048, 160.400000, 153.052632,
  157.900000, 149.780952, 143.615385,
  146.250000, 153.550000, 162.000000,
  178.478261, 180.878788, 184.357143
)

vdolar_oficial <- c(
   38.430000,  39.428000,  42.542105,
   44.354211,  46.088636,  44.955000,
   43.751429,  54.650476,  58.790000,
   61.403182,  63.012632,  63.011579,
   62.983636,  63.580556,  65.200000,
   67.872000,  70.047895,  72.520952,
   75.324286,  77.488500,  79.430909,
   83.134762,  85.484737,  88.181667,
   91.474000,  93.997778,  96.635909,
   98.526000,  99.613158, 100.619048,
  101.619048, 102.569048, 103.781818
)

vUVA <- c(
  2.001408838932958,  1.950325472789153,  1.89323032351521,
  1.8247220405493787, 1.746027787673673,  1.6871348409529485,
  1.6361678865622313, 1.5927529755859773, 1.5549162794128493,
  1.4949100586391746, 1.4197729500774545, 1.3678188186372326,
  1.3136508617223726, 1.2690535173062818, 1.2381595983200178,
  1.211656735577568,  1.1770808941405335, 1.1570338657445522,
  1.1388769475653255, 1.1156993751209352, 1.093638313080772,
  1.0657171590878205, 1.0362173587708712, 1.0,
  0.9669867858358365, 0.9323750098728378, 0.8958202912590305,
  0.8631993702994263, 0.8253893405524657, 0.7928918905364516,
  0.7666323845128089, 0.7428976357662823, 0.721615762047849
)


# --- celda 30 ---
tb_indices <- as.data.table( list(
  "IPC" = vIPC,
  "dolar_blue" = vdolar_blue,
  "dolar_oficial" = vdolar_oficial,
  "UVA" = vUVA
  )
)

tb_indices[[ 'foto_mes' ]] <- vfoto_mes

tb_indices

# --- celda 31 ---
drift_UVA <- function(campos_monetarios) {
  cat( "inicio drift_UVA()\n")

  dataset[tb_indices,
    on = c("foto_mes"),
    (campos_monetarios) := .SD * i.UVA,
    .SDcols = campos_monetarios
  ]

  cat( "fin drift_UVA()\n")
}


# --- celda 32 ---
drift_dolar_oficial <- function(campos_monetarios) {
  cat( "inicio drift_dolar_oficial()\n")

  dataset[tb_indices,
    on = c("foto_mes"),
    (campos_monetarios) := .SD / i.dolar_oficial,
    .SDcols = campos_monetarios
  ]

  cat( "fin drift_dolar_oficial()\n")
}


# --- celda 33 ---
drift_dolar_blue <- function(campos_monetarios) {
  cat( "inicio drift_dolar_blue()\n")

  dataset[tb_indices,
    on = c("foto_mes"),
    (campos_monetarios) := .SD / i.dolar_blue,
    .SDcols = campos_monetarios
  ]

  cat( "fin drift_dolar_blue()\n")
}


# --- celda 34 ---
drift_deflacion <- function(campos_monetarios) {
  cat( "inicio drift_deflacion()\n")

  dataset[tb_indices,
    on = c("foto_mes"),
    (campos_monetarios) := .SD * i.IPC,
    .SDcols = campos_monetarios
  ]

  cat( "fin drift_deflacion()\n")
}


# --- celda 35 ---
drift_rank_simple <- function(campos_drift) {

  cat( "inicio drift_rank_simple()\n")
  for (campo in campos_drift)
  {
    cat(campo, " ")
    dataset[, paste0(campo, "_rank") :=
      (frank(get(campo), ties.method = "random") - 1) / (.N - 1), by = list(foto_mes)]
    dataset[, (campo) := NULL]
  }
  cat( "fin drift_rank_simple()\n")
}


# --- celda 36 ---
# El cero se transforma en cero
# los positivos se rankean por su lado
# los negativos se rankean por su lado

drift_rank_cero_fijo <- function(campos_drift) {

  cat( "inicio drift_rank_cero_fijo()\n")
  for (campo in campos_drift)
  {
    cat(campo, " ")
    dataset[get(campo) == 0, paste0(campo, "_rank") := 0]
    dataset[get(campo) > 0, paste0(campo, "_rank") :=
      frank(get(campo), ties.method = "random") / .N, by = list(foto_mes)]

    dataset[get(campo) < 0, paste0(campo, "_rank") :=
      -frank(-get(campo), ties.method = "random") / .N, by = list(foto_mes)]
    dataset[, (campo) := NULL]
  }
  cat("\n")
  cat( "fin drift_rank_cero_fijo()\n")
}


# --- celda 37 ---
# funcion provista por alumnos amantes de la Estadistica Clasica

drift_estandarizar <- function(campos_drift) {

  cat( "inicio drift_estandarizar()\n")
  for (campo in campos_drift)
  {
    cat(campo, " ")
    dataset[, paste0(campo, "_normal") :=
      (get(campo) -mean(get(campo), na.rm=TRUE)) / sd(get(campo), na.rm=TRUE),
      by = list(foto_mes)]

    dataset[, (campo) := NULL]
  }
  cat( "fin drift_estandarizar()\n")
}



# --- celda 38 ---
# por como armé los nombres de campos,
#  estos son los campos que expresan variables monetarias
campos_monetarios <- colnames(dataset)
campos_monetarios <- campos_monetarios[campos_monetarios %like%
  "^(m|Visa_m|Master_m|vm_m)"]

campos_monetarios

# --- celda 39 ---
marca("Data Drifting")
# ejecuto el Data Drifting
setorder( dataset, numero_de_cliente, foto_mes )


PARAM$DR$metodo <- Sys.getenv("DR_METODO", "deflacion")   # v7: configurable
marca("Data Drifting: metodo", PARAM$DR$metodo)

switch(PARAM$DR$metodo,
  "ninguno"        = cat("No hay correccion del data drifting"),
  "rank_simple"    = drift_rank_simple(campos_monetarios),
  "rank_cero_fijo" = drift_rank_cero_fijo(campos_monetarios),
  "deflacion"      = drift_deflacion(campos_monetarios),
  "dolar_blue"     = drift_dolar_blue(campos_monetarios),
  "dolar_oficial"  = drift_dolar_oficial(campos_monetarios),
  "UVA"            = drift_UVA(campos_monetarios),
  "estandarizar"   = drift_estandarizar(campos_monetarios)
)


# --- celda 40 de la notebook: se saca (solo mostraba datos o instalaba algo que no se usa) ---

# ======================================================================
# 9.7.1.3  FE_intra_manual Feature Engineering intra-mes

# --- celda 42 ---
if( !require("lubridate")) install.packages("lubridate", repos = "http://cran.us.r-project.org")
require("lubridate")

# --- celda 43 ---
# esta funcion atributos presentes existe debido a que las modalidades poseen datasets con distinta cantidad de campos
atributos_presentes <- function( patributos )
{
  atributos <- unique( patributos )
  comun <- intersect( atributos, colnames(dataset) )

  return(  length( atributos ) == length( comun ) )
}

# --- celda 44 ---
# Esta es la parte que los alumnos deben desplegar todo su ingenio
# Agregar aqui sus PROPIAS VARIABLES manuales

AgregarVariables_IntraMes <- function(dataset) {
  cat( "inicio AgregarVariables_IntraMes()\n")
  gc(verbose= FALSE)
  # INICIO de la seccion donde se deben hacer cambios con variables nuevas

  # el mes 1,2, ..12
  if( atributos_presentes( c("foto_mes") ))
    dataset[, kmes := foto_mes %% 100]

  # creo un ctr_quarter que tenga en cuenta cuando
  # los clientes hace 3 menos meses que estan
  # ya que seria injusto considerar las transacciones medidas en menor tiempo
  if( atributos_presentes( c("ctrx_quarter") ))
    dataset[, ctrx_quarter_normalizado := as.numeric(ctrx_quarter) ]

  if( atributos_presentes( c("ctrx_quarter", "cliente_antiguedad") ))
    dataset[cliente_antiguedad == 1, ctrx_quarter_normalizado := ctrx_quarter * 5]

  if( atributos_presentes( c("ctrx_quarter", "cliente_antiguedad") ))
    dataset[cliente_antiguedad == 2, ctrx_quarter_normalizado := ctrx_quarter * 2]

  if( atributos_presentes( c("ctrx_quarter", "cliente_antiguedad") ))
    dataset[
      cliente_antiguedad == 3,
      ctrx_quarter_normalizado := ctrx_quarter * 1.2
    ]

   if(atributos_presentes(c("foto_mes")))
    dataset[,foto_mes_formato_fecha := as.Date(paste(substr(dataset$foto_mes,1,4),substr(dataset$foto_mes,5,6),"01",sep='-'))]

  #dataset$foto_mes_formato_fecha <<- as.Date(paste(substr(dataset$foto_mes,1,4),substr(dataset$foto_mes,5,6),"01",sep='-'))

  if(atributos_presentes(c("cantidad_total_transacciones"))){
   auxiliarmenos1 <- dataset[,list(numero_de_cliente,foto_mes_formato_fecha, cantidad_total_transacciones)]
   auxiliarmenos2 <- dataset[,list(numero_de_cliente,foto_mes_formato_fecha,cantidad_total_transacciones)]
   # auxiliarmenos1$foto_mes_formato_fecha <- as.Date(auxiliarmenos1$foto_mes_formato_fecha)
   # auxiliarmenos2$foto_mes_formato_fecha <- as.Date(auxiliarmenos2$foto_mes_formato_fecha)
   auxiliarmenos1$foto_mes_formato_fecha <- auxiliarmenos1$foto_mes_formato_fecha  %m-%  months(1)
   auxiliarmenos2$foto_mes_formato_fecha <- auxiliarmenos2$foto_mes_formato_fecha %m-% months(2)
   auxiliarmenos1$codigo <- paste(auxiliarmenos1$numero_de_cliente,auxiliarmenos1$foto_mes_formato_fecha,sep='-')
   auxiliarmenos2$codigo <- paste(auxiliarmenos2$numero_de_cliente,auxiliarmenos2$foto_mes_formato_fecha,sep='-')

   dataset[, codigo := paste(numero_de_cliente, foto_mes_formato_fecha, sep='-') ]

   dataset[ auxiliarmenos1,
            on = "codigo",
            transaccionesmenos1 := i.cantidad_total_transacciones ]

   dataset[ auxiliarmenos2,
            on = "codigo",
            transaccionesmenos2 := i.cantidad_total_transacciones ]

   dataset[, cantidad_total_transacciones_quarter := rowSums(cbind(cantidad_total_transacciones +
    transaccionesmenos1 + transaccionesmenos2),na.rm=T) ]

   dataset[, codigo := NULL ]
   dataset[, transaccionesmenos1 := NULL ]
   dataset[, transaccionesmenos2 := NULL ]
   dataset[, foto_mes_formato_fecha := NULL ]
   rm(auxiliarmenos1)
   rm(auxiliarmenos2)
  }

  # foto_mes_formato_fecha se crea siempre pero arriba solo se borra si existe
  # cantidad_total_transacciones (no esta en este dataset). Si queda, es una
  # columna Date: el FE historico la lagea y ratioavg/ratiomax fallan al dividir
  if( "foto_mes_formato_fecha" %in% colnames(dataset) )
    dataset[, foto_mes_formato_fecha := NULL ]

  if( atributos_presentes( c("cantidad_total_transacciones_quarter") ))
    dataset[, cantidad_total_transacciones_quarter_normalizado := cantidad_total_transacciones_quarter]

  if( atributos_presentes( c("cantidad_total_transacciones_quarter", "cliente_antiguedad") ))
    dataset[cliente_antiguedad == 1, cantidad_total_transacciones_quarter_normalizado := cantidad_total_transacciones_quarter * 5]

  if( atributos_presentes( c("cantidad_total_transacciones_quarter", "cliente_antiguedad") ))
    dataset[cliente_antiguedad == 2, cantidad_total_transacciones_quarter_normalizado := cantidad_total_transacciones_quarter * 2]

  if( atributos_presentes( c("cantidad_total_transacciones_quarter", "cliente_antiguedad") ))
    dataset[cliente_antiguedad == 3, cantidad_total_transacciones_quarter_normalizado := cantidad_total_transacciones_quarter * 1.2]

  # variable extraida de una tesis de maestria de Irlanda
  if( atributos_presentes( c("mpayroll", "cliente_edad") ))
    dataset[, mpayroll_sobre_edad := mpayroll / cliente_edad]

  # se crean los nuevos campos para MasterCard  y Visa,
  #  teniendo en cuenta los NA's
  # varias formas de combinar Visa_status y Master_status
  if( atributos_presentes( c("Master_status", "Visa_status") ))
  {
    dataset[, vm_status01 := pmax(Master_status, Visa_status, na.rm = TRUE)]
    dataset[, vm_status02 := Master_status + Visa_status]

    dataset[, vm_status03 := pmax(
      ifelse(is.na(Master_status), 10, Master_status),
      ifelse(is.na(Visa_status), 10, Visa_status)
    )]

    dataset[, vm_status04 := ifelse(is.na(Master_status), 10, Master_status)
      + ifelse(is.na(Visa_status), 10, Visa_status)]

    dataset[, vm_status05 := ifelse(is.na(Master_status), 10, Master_status)
      + 100 * ifelse(is.na(Visa_status), 10, Visa_status)]

    dataset[, vm_status06 := ifelse(is.na(Visa_status),
      ifelse(is.na(Master_status), 10, Master_status),
      Visa_status
    )]

    dataset[, mv_status07 := ifelse(is.na(Master_status),
      ifelse(is.na(Visa_status), 10, Visa_status),
      Master_status
    )]
  }


  # combino MasterCard y Visa
  if( atributos_presentes( c("Master_mfinanciacion_limite", "Visa_mfinanciacion_limite") ))
    dataset[, vm_mfinanciacion_limite := rowSums(cbind(Master_mfinanciacion_limite, Visa_mfinanciacion_limite), na.rm = TRUE)]

  if( atributos_presentes( c("Master_Fvencimiento", "Visa_Fvencimiento") ))
    dataset[, vm_Fvencimiento := pmin(Master_Fvencimiento, Visa_Fvencimiento, na.rm = TRUE)]

  if( atributos_presentes( c("Master_Finiciomora", "Visa_Finiciomora") ))
    dataset[, vm_Finiciomora := pmin(Master_Finiciomora, Visa_Finiciomora, na.rm = TRUE)]

  if( atributos_presentes( c("Master_msaldototal", "Visa_msaldototal") ))
    dataset[, vm_msaldototal := rowSums(cbind(Master_msaldototal, Visa_msaldototal), na.rm = TRUE)]

  if( atributos_presentes( c("Master_msaldopesos", "Visa_msaldopesos") ))
    dataset[, vm_msaldopesos := rowSums(cbind(Master_msaldopesos, Visa_msaldopesos), na.rm = TRUE)]

  if( atributos_presentes( c("Master_msaldodolares", "Visa_msaldodolares") ))
    dataset[, vm_msaldodolares := rowSums(cbind(Master_msaldodolares, Visa_msaldodolares), na.rm = TRUE)]

  if( atributos_presentes( c("Master_mconsumospesos", "Visa_mconsumospesos") ))
    dataset[, vm_mconsumospesos := rowSums(cbind(Master_mconsumospesos, Visa_mconsumospesos), na.rm = TRUE)]

  if( atributos_presentes( c("Master_mconsumosdolares", "Visa_mconsumosdolares") ))
    dataset[, vm_mconsumosdolares := rowSums(cbind(Master_mconsumosdolares, Visa_mconsumosdolares), na.rm = TRUE)]

  if( atributos_presentes( c("Master_mlimitecompra", "Visa_mlimitecompra") ))
    dataset[, vm_mlimitecompra := rowSums(cbind(Master_mlimitecompra, Visa_mlimitecompra), na.rm = TRUE)]

  if( atributos_presentes( c("Master_madelantopesos", "Visa_madelantopesos") ))
    dataset[, vm_madelantopesos := rowSums(cbind(Master_madelantopesos, Visa_madelantopesos), na.rm = TRUE)]

  if( atributos_presentes( c("Master_madelantodolares", "Visa_madelantodolares") ))
    dataset[, vm_madelantodolares := rowSums(cbind(Master_madelantodolares, Visa_madelantodolares), na.rm = TRUE)]

  if( atributos_presentes( c("Master_fultimo_cierre", "Visa_fultimo_cierre") ))
    dataset[, vm_fultimo_cierre := pmax(Master_fultimo_cierre, Visa_fultimo_cierre, na.rm = TRUE)]

  if( atributos_presentes( c("Master_mpagado", "Visa_mpagado") ))
    dataset[, vm_mpagado := rowSums(cbind(Master_mpagado, Visa_mpagado), na.rm = TRUE)]

  if( atributos_presentes( c("Master_mpagospesos", "Visa_mpagospesos") ))
    dataset[, vm_mpagospesos := rowSums(cbind(Master_mpagospesos, Visa_mpagospesos), na.rm = TRUE)]

  if( atributos_presentes( c("Master_mpagosdolares", "Visa_mpagosdolares") ))
    dataset[, vm_mpagosdolares := rowSums(cbind(Master_mpagosdolares, Visa_mpagosdolares), na.rm = TRUE)]

  if( atributos_presentes( c("Master_fechaalta", "Visa_fechaalta") ))
    dataset[, vm_fechaalta := pmax(Master_fechaalta, Visa_fechaalta, na.rm = TRUE)]

  if( atributos_presentes( c("Master_mconsumototal", "Visa_mconsumototal") ))
    dataset[, vm_mconsumototal := rowSums(cbind(Master_mconsumototal, Visa_mconsumototal), na.rm = TRUE)]

  if( atributos_presentes( c("Master_cconsumos", "Visa_cconsumos") ))
    dataset[, vm_cconsumos := rowSums(cbind(Master_cconsumos, Visa_cconsumos), na.rm = TRUE)]

  if( atributos_presentes( c("Master_cadelantosefectivo", "Visa_cadelantosefectivo") ))
    dataset[, vm_cadelantosefectivo := rowSums(cbind(Master_cadelantosefectivo, Visa_cadelantosefectivo), na.rm = TRUE)]

  if( atributos_presentes( c("Master_mpagominimo", "Visa_mpagominimo") ))
    dataset[, vm_mpagominimo := rowSums(cbind(Master_mpagominimo, Visa_mpagominimo), na.rm = TRUE)]

  # a partir de aqui juego con la suma de Mastercard y Visa
  if( atributos_presentes( c("Master_mlimitecompra", "vm_mlimitecompra") ))
    dataset[, vmr_Master_mlimitecompra := Master_mlimitecompra / vm_mlimitecompra]

  if( atributos_presentes( c("Visa_mlimitecompra", "vm_mlimitecompra") ))
    dataset[, vmr_Visa_mlimitecompra := Visa_mlimitecompra / vm_mlimitecompra]

  if( atributos_presentes( c("vm_msaldototal", "vm_mlimitecompra") ))
    dataset[, vmr_msaldototal := vm_msaldototal / vm_mlimitecompra]

  if( atributos_presentes( c("vm_msaldopesos", "vm_mlimitecompra") ))
    dataset[, vmr_msaldopesos := vm_msaldopesos / vm_mlimitecompra]

  if( atributos_presentes( c("vm_msaldopesos", "vm_msaldototal") ))
    dataset[, vmr_msaldopesos2 := vm_msaldopesos / vm_msaldototal]

  if( atributos_presentes( c("vm_msaldodolares", "vm_mlimitecompra") ))
    dataset[, vmr_msaldodolares := vm_msaldodolares / vm_mlimitecompra]

  if( atributos_presentes( c("vm_msaldodolares", "vm_msaldototal") ))
    dataset[, vmr_msaldodolares2 := vm_msaldodolares / vm_msaldototal]

  if( atributos_presentes( c("vm_mconsumospesos", "vm_mlimitecompra") ))
    dataset[, vmr_mconsumospesos := vm_mconsumospesos / vm_mlimitecompra]

  if( atributos_presentes( c("vm_mconsumosdolares", "vm_mlimitecompra") ))
    dataset[, vmr_mconsumosdolares := vm_mconsumosdolares / vm_mlimitecompra]

  if( atributos_presentes( c("vm_madelantopesos", "vm_mlimitecompra") ))
    dataset[, vmr_madelantopesos := vm_madelantopesos / vm_mlimitecompra]

  if( atributos_presentes( c("vm_madelantodolares", "vm_mlimitecompra") ))
    dataset[, vmr_madelantodolares := vm_madelantodolares / vm_mlimitecompra]

  if( atributos_presentes( c("vm_mpagado", "vm_mlimitecompra") ))
    dataset[, vmr_mpagado := vm_mpagado / vm_mlimitecompra]

  if( atributos_presentes( c("vm_mpagospesos", "vm_mlimitecompra") ))
    dataset[, vmr_mpagospesos := vm_mpagospesos / vm_mlimitecompra]

  if( atributos_presentes( c("vm_mpagosdolares", "vm_mlimitecompra") ))
    dataset[, vmr_mpagosdolares := vm_mpagosdolares / vm_mlimitecompra]

  if( atributos_presentes( c("vm_mconsumototal", "vm_mlimitecompra") ))
    dataset[, vmr_mconsumototal := vm_mconsumototal / vm_mlimitecompra]

  if( atributos_presentes( c("vm_mpagominimo", "vm_mlimitecompra") ))
    dataset[, vmr_mpagominimo := vm_mpagominimo / vm_mlimitecompra]

  # Aqui debe usted agregar sus propias nuevas variables

  # valvula de seguridad para evitar valores infinitos
  # paso los infinitos a NULOS
  infinitos <- lapply(
    names(dataset),
    function(.name) dataset[, sum(is.infinite(get(.name)))]
  )

  infinitos_qty <- sum(unlist(infinitos))
  if (infinitos_qty > 0) {
    cat(
      "ATENCION, hay", infinitos_qty,
      "valores infinitos en tu dataset. Seran pasados a NA\n"
    )
    dataset[mapply(is.infinite, dataset)] <<- NA
  }


  # valvula de seguridad para evitar valores NaN  que es 0/0
  # paso los NaN a 0 , decision polemica si las hay
  # se invita a asignar un valor razonable segun la semantica del campo creado
  nans <- lapply(
    names(dataset),
    function(.name) dataset[, sum(is.nan(get(.name)))]
  )

  nans_qty <- sum(unlist(nans))
  if (nans_qty > 0) {
    cat(
      "ATENCION, hay", nans_qty,
      "valores NaN 0/0 en tu dataset. Seran pasados arbitrariamente a 0\n"
    )

    cat("Si no te gusta la decision, modifica a gusto el programa!\n\n")
    dataset[mapply(is.nan, dataset)] <<- 0
  }

  cat( "fin AgregarVariables_IntraMes()\n")
}


# --- celda 45 ---
marca("FE intra-mes")
# agrego las variables intra mes

AgregarVariables_IntraMes(dataset)

# --- celda 46 de la notebook: se saca (solo mostraba datos o instalaba algo que no se usa) ---

# ======================================================================
# 9.7.1.4  FEhist Feature Engineering historico

# --- celda 49 ---
if( !require("Rcpp")) install.packages("Rcpp", repos = "http://cran.us.r-project.org")
require("Rcpp")

# --- celda 50 ---
# se calculan para los 6 meses previos el minimo, maximo y
#  tendencia calculada con cuadrados minimos
# la formula de calculo de la tendencia puede verse en
#  https://stats.libretexts.org/Bookshelves/Introductory_Statistics/Book%3A_Introductory_Statistics_(Shafer_and_Zhang)/10%3A_Correlation_and_Regression/10.04%3A_The_Least_Squares_Regression_Line
# para la maxíma velocidad esta funcion esta escrita en lenguaje C,
# y no en la porqueria de R o Python

cppFunction("NumericVector fhistC(NumericVector pcolumna, IntegerVector pdesde )
{
  /* Aqui se cargan los valores para la regresion */
  double  x[100] ;
  double  y[100] ;

  int n = pcolumna.size();
  NumericVector out( 5*n );

  for(int i = 0; i < n; i++)
  {
    //lag
    if( pdesde[i]-1 < i )  out[ i + 4*n ]  =  pcolumna[i-1] ;
    else                   out[ i + 4*n ]  =  NA_REAL ;


    int  libre    = 0 ;
    int  xvalor   = 1 ;

    for( int j= pdesde[i]-1;  j<=i; j++ )
    {
       double a = pcolumna[j] ;

       if( !R_IsNA( a ) )
       {
          y[ libre ]= a ;
          x[ libre ]= xvalor ;
          libre++ ;
       }

       xvalor++ ;
    }

    /* Si hay al menos dos valores */
    if( libre > 1 )
    {
      double  xsum  = x[0] ;
      double  ysum  = y[0] ;
      double  xysum = xsum * ysum ;
      double  xxsum = xsum * xsum ;
      double  vmin  = y[0] ;
      double  vmax  = y[0] ;

      for( int h=1; h<libre; h++)
      {
        xsum  += x[h] ;
        ysum  += y[h] ;
        xysum += x[h]*y[h] ;
        xxsum += x[h]*x[h] ;

        if( y[h] < vmin )  vmin = y[h] ;
        if( y[h] > vmax )  vmax = y[h] ;
      }

      out[ i ]  =  (libre*xysum - xsum*ysum)/(libre*xxsum -xsum*xsum) ;
      out[ i + n ]    =  vmin ;
      out[ i + 2*n ]  =  vmax ;
      out[ i + 3*n ]  =  ysum / libre ;
    }
    else
    {
      out[ i       ]  =  NA_REAL ;
      out[ i + n   ]  =  NA_REAL ;
      out[ i + 2*n ]  =  NA_REAL ;
      out[ i + 3*n ]  =  NA_REAL ;
    }
  }

  return  out;
}")


# --- celda 51 ---
# calcula la tendencia de las variables cols de los ultimos 6 meses
# la tendencia es la pendiente de la recta que ajusta por cuadrados minimos
# La funcionalidad de ratioavg es autoria de  Daiana Sparta,  UAustral  2021

TendenciaYmuchomas <- function(
    dataset, cols, ventana = 6, tendencia = TRUE,
    minimo = TRUE, maximo = TRUE, promedio = TRUE,
    ratioavg = FALSE, ratiomax = FALSE) {
  gc(verbose= FALSE)
  # Esta es la cantidad de meses que utilizo para la historia
  ventana_regresion <- ventana

  last <- nrow(dataset)

  # creo el vector_desde que indica cada ventana
  # de esta forma se acelera el procesamiento ya que lo hago una sola vez
  vector_ids <- dataset[ , numero_de_cliente ]

  vector_desde <- seq(
    -ventana_regresion + 2,
    nrow(dataset) - ventana_regresion + 1
  )

  vector_desde[1:ventana_regresion] <- 1

  for (i in 2:last) {
    if (vector_ids[i - 1] != vector_ids[i]) {
      vector_desde[i] <- i
    }
  }
  for (i in 2:last) {
    if (vector_desde[i] < vector_desde[i - 1]) {
      vector_desde[i] <- vector_desde[i - 1]
    }
  }

  for (campo in cols) {
    nueva_col <- fhistC(dataset[, get(campo)], vector_desde)

    if (tendencia) {
      dataset[, paste0(campo, "_tend", ventana) :=
        nueva_col[(0 * last + 1):(1 * last)]]
    }

    if (minimo) {
      dataset[, paste0(campo, "_min", ventana) :=
        nueva_col[(1 * last + 1):(2 * last)]]
    }

    if (maximo) {
      dataset[, paste0(campo, "_max", ventana) :=
        nueva_col[(2 * last + 1):(3 * last)]]
    }

    if (promedio) {
      dataset[, paste0(campo, "_avg", ventana) :=
        nueva_col[(3 * last + 1):(4 * last)]]
    }

    if (ratioavg) {
      dataset[, paste0(campo, "_ratioavg", ventana) :=
        get(campo) / nueva_col[(3 * last + 1):(4 * last)]]
    }

    if (ratiomax) {
      dataset[, paste0(campo, "_ratiomax", ventana) :=
        get(campo) / nueva_col[(2 * last + 1):(3 * last)]]
    }
  }
}


# --- celda 52 ---
marca("FE historico: lags y deltas")
# Feature Engineering Historico

setorder(dataset, numero_de_cliente, foto_mes)

# todo es lagueable, menos la primary key y la clase
cols_lagueables <- copy( setdiff(
    colnames(dataset),
    c("numero_de_cliente", "foto_mes", "clase_ternaria")
) )

# https://rdrr.io/cran/data.table/man/shift.html

# lags de orden 1
dataset[,
    paste0(cols_lagueables, "_lag1") := shift(.SD, 1, NA, "lag"),
    by = numero_de_cliente,
    .SDcols = cols_lagueables
]

# lags de orden 2
dataset[,
    paste0(cols_lagueables, "_lag2") := shift(.SD, 2, NA, "lag"),
    by = numero_de_cliente,
    .SDcols = cols_lagueables
]

# agrego los delta lags
for (vcol in cols_lagueables)
{
    dataset[, paste0(vcol, "_delta1") := get(vcol) - get(paste0(vcol, "_lag1"))]
    dataset[, paste0(vcol, "_delta2") := get(vcol) - get(paste0(vcol, "_lag2"))]
}


# --- celda 53 ---
# parametros de Feature Engineering Historico de Tendencias
PARAM$FE_hist$Tendencias$run <- TRUE
PARAM$FE_hist$Tendencias$ventana <- 6
PARAM$FE_hist$Tendencias$tendencia <- TRUE
PARAM$FE_hist$Tendencias$minimo <- TRUE
PARAM$FE_hist$Tendencias$maximo <- TRUE
PARAM$FE_hist$Tendencias$promedio <- TRUE
PARAM$FE_hist$Tendencias$ratioavg <- TRUE
PARAM$FE_hist$Tendencias$ratiomax <- TRUE


# --- celda 54 ---
marca("FE historico: tendencias, minimo, maximo, promedio, ratioavg, ratiomax")
cols_lagueables <- intersect(cols_lagueables, colnames(dataset))
setorder(dataset, numero_de_cliente, foto_mes)

if( PARAM$FE_hist$Tendencias$run) {
    TendenciaYmuchomas(dataset,
    cols = cols_lagueables,
    ventana = PARAM$FE_hist$Tendencias$ventana, # 6 meses de historia
    tendencia = PARAM$FE_hist$Tendencias$tendencia,
    minimo = PARAM$FE_hist$Tendencias$minimo,
    maximo = PARAM$FE_hist$Tendencias$maximo,
    promedio = PARAM$FE_hist$Tendencias$promedio,
    ratioavg = PARAM$FE_hist$Tendencias$ratioavg,
    ratiomax = PARAM$FE_hist$Tendencias$ratiomax
  )
}



# --- celda 56 de la notebook: se saca (solo mostraba datos o instalaba algo que no se usa) ---

# ======================================================================
# 9.7.1.5  FE_rf Feature Engineering de nuevas variables a partir de hojas de Random Forest

# --- celda 58 ---
if( !require("lightgbm")) install.packages("lightgbm")
require("lightgbm")

# --- celda 59 ---
AgregaVarRandomForest <- function() {

  cat( "inicio AgregaVarRandomForest()\n")
  gc(verbose= FALSE)
  dataset[, clase01 := 0L ]
  dataset[ clase_ternaria %in% PARAM$FE_rf$train$clase01_valor1,
      clase01 := 1L ]

  campos_buenos <- setdiff(
    colnames(dataset),
    c( "clase_ternaria", "clase01")
  )

  dataset[, entrenamiento :=
    as.integer( foto_mes %in% PARAM$FE_rf$train$training )]

  dtrain <- lgb.Dataset(
    data = data.matrix(dataset[entrenamiento == TRUE, campos_buenos, with = FALSE]),
    label = dataset[entrenamiento == TRUE, clase01],
    free_raw_data = FALSE
  )

  modelo <- lgb.train(
     data = dtrain,
     param = PARAM$FE_rf$lgb_param,
     verbose = -100
  )

  cat( "Fin construccion RandomForest\n" )
  # grabo el modelo, achivo .model
  lgb.save(modelo, file="modelo.model" )

  qarbolitos <- copy(PARAM$FE_rf$lgb_param$num_iterations)

  periodos <- dataset[ , unique( foto_mes ) ]

  for( periodo in  periodos )
  {
    cat( "periodo = ", periodo, "\n" )
    datamatrix <- data.matrix(dataset[ foto_mes== periodo, campos_buenos, with = FALSE])

    cat( "Inicio prediccion\n" )
    prediccion <- predict(
        modelo,
        datamatrix,
        type = "leaf"
    )
    cat( "Fin prediccion\n" )

    for( arbolito in 1:qarbolitos )
    {
       cat( arbolito, " " )
       hojas_arbol <- unique(prediccion[ , arbolito])

       for (pos in 1:length(hojas_arbol)) {
         # el numero de nodo de la hoja, estan salteados
         nodo_id <- hojas_arbol[pos]
         dataset[ foto_mes== periodo, paste0(
            "rf_", sprintf("%03d", arbolito),
             "_", sprintf("%03d", nodo_id)
          ) :=  as.integer( nodo_id == prediccion[ , arbolito]) ]

       }

       rm( hojas_arbol )
    }
    cat( "\n" )

    rm( prediccion )
    rm( datamatrix )
    gc(verbose= FALSE)
  }

  gc(verbose= FALSE)

  # borro clase01 , no debe ensuciar el dataset
  dataset[ , clase01 := NULL ]

}


# --- celda 60 ---
# Parametros de Feature Engineering  a partir de hojas de Random Forest

# Estos CUATRO parametros son los que se deben modificar
PARAM$FE_rf$arbolitos= 50
PARAM$FE_rf$hojas_por_arbol= 32
PARAM$FE_rf$datos_por_hoja= 100
PARAM$FE_rf$mtry_ratio= 0.4

# Estos son quasi fijos
PARAM$FE_rf$train$clase01_valor1 <- c( "BAJA+2", "BAJA+1")
PARAM$FE_rf$train$training <- c( 202101, 202102, 202103)

# Estos TAMBIEN son quasi fijos
PARAM$FE_rf$lgb_param <-list(
    # parametros que se pueden cambiar
    num_iterations = PARAM$FE_rf$arbolitos,
    num_leaves  = PARAM$FE_rf$hojas_por_arbol,
    min_data_in_leaf = PARAM$FE_rf$datos_por_hoja,
    feature_fraction_bynode  = PARAM$FE_rf$mtry_ratio,

    # para que LightGBM emule Random Forest
    boosting = "rf",
    bagging_fraction = ( 1.0 - 1.0/exp(1.0) ),
    bagging_freq = 1.0,
    feature_fraction = 1.0,

    # genericos de LightGBM
    max_bin = 31L,
    objective = "binary",
    first_metric_only = TRUE,
    boost_from_average = TRUE,
    feature_pre_filter = FALSE,
    force_row_wise = TRUE,
    verbosity = -100,
    max_depth = -1L,
    min_gain_to_split = 0.0,
    min_sum_hessian_in_leaf = 0.001,
    lambda_l1 = 0.0,
    lambda_l2 = 0.0,

    pos_bagging_fraction = 1.0,
    neg_bagging_fraction = 1.0,
    is_unbalance = FALSE,
    scale_pos_weight = 1.0,

    drop_rate = 0.1,
    max_drop = 50,
    skip_drop = 0.5,

    extra_trees = FALSE
  )

# --- celda 61 ---
marca("FE random forest")
# Feature Engineering agregando variables de Random Forest
AgregaVarRandomForest()

# --- celda 62 de la notebook: se saca (solo mostraba datos o instalaba algo que no se usa) ---

# ======================================================================
# 9.7.1.6  FEhist Reduccion dimensionalidad con canaritos

# --- celda 66 ---
VPOS_CORTE <- c()

fganancia_lgbm_meseta <- function(probs, datos) {
  vlabels <- get_field(datos, "label")
  vpesos <- get_field(datos, "weight")

  tbl <- as.data.table(list(
    "prob" = probs,
    "gan" = ifelse(vlabels == 1 & vpesos > 1, PARAM$CN$train$gan1, PARAM$CN$train$gan0)
  ))

  setorder(tbl, -prob)
  tbl[, posicion := .I]
  tbl[, gan_acum := cumsum(gan)]
  setorder(tbl, -gan_acum) # voy por la meseta

  gan <- mean(tbl[1:500, gan_acum]) # meseta de tamaño 500

  pos_meseta <- tbl[1:500, median(posicion)]
  VPOS_CORTE <<- c(VPOS_CORTE, pos_meseta)

  return(list(
    "name" = "ganancia",
    "value" = gan,
    "higher_better" = TRUE
  ))
}


# --- celda 67 ---
# Elimina del dataset las variables que estan por debajo
#  de la capa geologica de canaritos
# se llama varias veces, luego de agregar muchas variables nuevas,
#  para ir reduciendo la cantidad de variables
# y así hacer lugar a nuevas variables importantes

GVEZ <- 1

campitos <- c( "numero_de_cliente", "foto_mes", "clase_ternaria" )

CanaritosAsesinos <- function(
  canaritos_ratio,
  canaritos_desvios,
  canaritos_semilla) {

  cat( "inicio CanaritosAsesinos()\n")
  gc(verbose= FALSE)
  dataset[, clase01 := 0L ]
  dataset[ clase_ternaria %in% PARAM$CN$train$clase01_valor1,
      clase01 := 1L ]

  set.seed(canaritos_semilla, kind = "L'Ecuyer-CMRG")
  for (i in 1:(ncol(dataset) * canaritos_ratio)) {
    dataset[, paste0("canarito", i) := runif(nrow(dataset))]
  }

  campos_buenos <- setdiff(
    colnames(dataset),
    c( campitos, "clase01")
  )

  azar <- runif(nrow(dataset))

  dataset[, entrenamiento :=
    as.integer( foto_mes %in% PARAM$CN$train$training &
      (clase01 == 1 | azar < PARAM$CN$train$undersampling))]

  dtrain <- lgb.Dataset(
    data = data.matrix(dataset[entrenamiento == TRUE, campos_buenos, with = FALSE]),
    label = dataset[entrenamiento == TRUE, clase01],
    weight = dataset[
      entrenamiento == TRUE,
      ifelse(clase_ternaria %in% PARAM$CN$train$positivos, 1.0000001, 1.0)
    ],
    free_raw_data = FALSE
  )

  dvalid <- lgb.Dataset(
    data = data.matrix(dataset[foto_mes %in% PARAM$CN$train$validation, campos_buenos, with = FALSE]),
    label = dataset[foto_mes %in% PARAM$CN$train$validation, clase01],
    weight = dataset[
      foto_mes %in% PARAM$CN$train$validation,
      ifelse( clase_ternaria %in% PARAM$CN$train$positivos, 1.0000001, 1.0)
    ],
    free_raw_data = FALSE
  )


  param <- list(
    objective = "binary",
    metric = "custom",
    first_metric_only = TRUE,
    boost_from_average = TRUE,
    feature_pre_filter = FALSE,
    verbosity = -100,
    seed = canaritos_semilla,
    max_depth = -1, # -1 significa no limitar,  por ahora lo dejo fijo
    min_gain_to_split = 0.0, # por ahora, lo dejo fijo
    lambda_l1 = 0.0, # por ahora, lo dejo fijo
    lambda_l2 = 0.0, # por ahora, lo dejo fijo
    max_bin = 31, # por ahora, lo dejo fijo
    num_iterations = 9999, # un numero grande, lo limita early_stopping_rounds
    force_row_wise = TRUE, # para que los alumnos no se atemoricen con  warning
    learning_rate = 0.065,
    feature_fraction = 1.0, # lo seteo en 1
    min_data_in_leaf = 260,
    num_leaves = 60,
    early_stopping_rounds = 200,
    num_threads = parallel::detectCores()   # la notebook usaba 1: con ~4.500 columnas era el cuello de botella
  )

  set.seed(canaritos_semilla, kind = "L'Ecuyer-CMRG")
  modelo <- lgb.train(
    data = dtrain,
    valids = list(valid = dvalid),
    eval = fganancia_lgbm_meseta,
    param = param,
    verbose = -100
  )

  tb_importancia <- lgb.importance(model = modelo)
  tb_importancia[, pos := .I]

  fwrite(tb_importancia,
    file = paste0("impo_", GVEZ, ".txt"),
    sep = "\t"
  )

  GVEZ <<- GVEZ + 1

  umbral <- tb_importancia[
    Feature %like% "canarito",
    median(pos) + canaritos_desvios * sd(pos)
  ] # Atencion corto en la mediana mas desvios!!

  col_utiles <- tb_importancia[
    pos < umbral & !(Feature %like% "canarito"),
    Feature
  ]

  col_utiles <- unique(c(
    col_utiles,
    c(campitos, "mes")
  ))

  col_inutiles <- setdiff(colnames(dataset), col_utiles)

  dataset[, (col_inutiles) := NULL]

  cat( "fin CanaritosAsesinos()\n")

  return( tb_importancia )
}


# --- celda 68 ---
# Estos DOS parametros son los que se deben modificar
PARAM$CN$ratio <- 0.2
PARAM$CN$desvios <- as.numeric(Sys.getenv("CN_DESVIOS", "2.5"))   # v5: 2.0 desde el .env


# Parametros quasi fijos
# Parametros de un LightGBM que se genera para estimar la column importance
PARAM$CN$train$clase01_valor1 <- c( "BAJA+2", "BAJA+1")
PARAM$CN$train$positivos <- c( "BAJA+2")
PARAM$CN$train$training <- c( 202101, 202102, 202103)
PARAM$CN$train$validation <- c( 202105 )
PARAM$CN$train$undersampling <- 0.1
PARAM$CN$train$gan1 <- 0.975
PARAM$CN$train$gan0 <- -0.025

# --- celda 69 ---
if (GA_ACTIVA) {
  setorder(dataset, numero_de_cliente, foto_mes)
  write_fst(dataset[, intersect(c("numero_de_cliente", "foto_mes", GA_CLAVES), colnames(dataset)), with= FALSE], CK_GA)
  marca("genetica: variables base guardadas antes de canaritos")
}

marca("canaritos: ratio", PARAM$CN$ratio, "desvios", PARAM$CN$desvios)
# la llamada a Canaritos Asesinos
tb_importancia <- CanaritosAsesinos(
  canaritos_ratio = PARAM$CN$ratio,
  canaritos_desvios = PARAM$CN$desvios,
  canaritos_semilla = PARAM$semilla_primigenia
)


# --- celda 70 ---
# grabo la importancia, ver el archivo directamente en la carpeta

fwrite( tb_importancia,
  file="canaritos.txt",
  sep="\t"
)

# --- celda 71 ---
marca("grabo el checkpoint despues de canaritos:", ncol(dataset), "columnas")
write_fst(dataset, CK)

}   # fin del preprocesamiento (o del retome desde el checkpoint)
marca("dataset listo:", nrow(dataset), "filas x", ncol(dataset), "columnas")

# ======================================================================
# v7: FE GENETICO (GA_ACTIVA=1)
# Una sola busqueda para todas las semillas del experimento: la primera semilla
# que llega la corre y graba todo en <BUCKET_DIR>/exp/WF<EXPERIMENTO>_ga/; las
# siguientes solo leen las formulas que quedaron. Diferencias con el grupo B:
#   * fitness: mejora de AUC (BAJA+2) promedio en GA_BUSQUEDA (2 meses), no la
#     ganancia de un mes; LightGBM chico con GA_UNDERSAMPLING de los CONTINUA,
#     entrenado con los meses hasta dos antes de cada mes, sin MESES_EXCLUIR
#   * las formulas combinan 2 o 3 de las 30 variables clave del mes (deflactadas)
#   * control: la ganadora contra GA_N_CONTROL formulas al azar en GA_CONTROL,
#     con otra semilla de LightGBM; queda si mejora y supera al percentil 90
#     de las al azar
#   * corre despues de canaritos: las ganadoras (con lag1, lag2, delta1, delta2)
#     entran al dataset y canaritos no las puede borrar
# Retoma: genetica_log.txt es tambien el cache (misma semilla = mismo camino)
if (GA_ACTIVA) {
  if (!require("lightgbm")) install.packages("lightgbm")   # al retomar del checkpoint no se cargo antes
  require("lightgbm")
  if (!require("gramEvol")) install.packages("gramEvol")
  require("gramEvol")
  setorder(dataset, numero_de_cliente, foto_mes)
  ga_base <- read_fst(CK_GA, as.data.table= TRUE)
  if (nrow(ga_base) != nrow(dataset) ||
      !identical(ga_base$numero_de_cliente, dataset$numero_de_cliente) ||
      !identical(ga_base$foto_mes, dataset$foto_mes))
    stop("genetica: ga_base no coincide fila a fila con el dataset")

  GA_DIR <- file.path(Sys.getenv("BUCKET_DIR"), "exp", paste0("WF", PARAM$experimento, "_ga"))
  dir.create(GA_DIR, showWarnings= FALSE, recursive= TRUE)
  ARCH_GA_LOG    <- file.path(GA_DIR, "genetica_log.txt")
  ARCH_GA_RONDAS <- file.path(GA_DIR, "genetica_rondas.txt")
  ARCH_GA_CTRL   <- file.path(GA_DIR, "genetica_control.txt")
  ARCH_GA_FIN    <- file.path(GA_DIR, "GENETICA_TERMINADA")

  meses_env <- function(v, defecto) as.integer(strsplit(Sys.getenv(v, defecto), ",")[[1]])
  GAP <- list(
    busqueda      = meses_env("GA_BUSQUEDA", "202104,202105"),
    control       = meses_env("GA_CONTROL", "202103,202106"),
    rondas        = as.integer(Sys.getenv("GA_RONDAS", "3")),
    poblacion     = as.integer(Sys.getenv("GA_POBLACION", "20")),
    generaciones  = as.integer(Sys.getenv("GA_GENERACIONES", "10")),
    undersampling = as.numeric(Sys.getenv("GA_UNDERSAMPLING", "0.1")),
    n_control     = as.integer(Sys.getenv("GA_N_CONTROL", "19")),
    semilla       = as.integer(Sys.getenv("GA_SEMILLA", "777")),
    horas_max     = as.numeric(Sys.getenv("GA_HORAS_MAX", "8"))
  )
  if (PRUEBA > 0) { GAP$rondas <- 1L; GAP$poblacion <- 6L; GAP$generaciones <- 2L; GAP$n_control <- 4L }
  if (length(intersect(c(GAP$busqueda, GAP$control), c(202107, 202108, 202109))))
    stop("la genetica no puede medir en 202107 (validacion de la BO) ni despues")

  ga_lgb <- list(objective= "binary", num_iterations= 100, learning_rate= 0.1,
    num_leaves= 60, min_data_in_leaf= if (PRUEBA > 0) 20 else 260,
    feature_fraction= 0.5, bagging_fraction= 0.8, bagging_freq= 1, max_bin= 31,
    force_row_wise= TRUE, deterministic= TRUE, verbosity= -100,
    num_threads= parallel::detectCores())

  ga_vars <- setdiff(names(ga_base), c("numero_de_cliente", "foto_mes"))
  campos_ga <- setdiff(names(dataset)[sapply(dataset, is.numeric)], c("numero_de_cliente", "clase01", "azar"))
  MESES_DS <- sort(unique(dataset$foto_mes))
  ga_ventana <- function(mes) setdiff(head(MESES_DS[MESES_DS <= mes], -2), MESES_EXCLUIR)

  ga_eval <- function(formula) {
    v <- tryCatch(eval(parse(text= formula)[[1]], envir= ga_base), error= function(e) NULL)
    if (is.null(v) || length(v) != nrow(ga_base)) return(NULL)
    v <- as.numeric(v)
    v[is.infinite(v)] <- NA
    v[is.nan(v)] <- 0
    if (length(unique(v[!is.na(v)])) < 2) return(NULL)
    v
  }
  # la formula con lag1, lag2, delta1 y delta2 (por cliente), para todas las filas
  ga_columnas <- function(formula) {
    v <- ga_eval(formula)
    if (is.null(v)) return(NULL)
    id <- ga_base$numero_de_cliente
    m1 <- id == shift(id, 1); m2 <- id == shift(id, 2)
    l1 <- shift(v, 1); l1[is.na(m1) | !m1] <- NA
    l2 <- shift(v, 2); l2[is.na(m2) | !m2] <- NA
    cbind(gen= v, gen_lag1= l1, gen_lag2= l2, gen_delta1= v - l1, gen_delta2= v - l2)
  }

  ga_auc <- function(p, y) {
    r <- frank(p); n1 <- sum(y); n0 <- length(y) - n1
    (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
  }

  # v8: la muestra sale de cualquier dataset ds con las mismas filas que ga_base
  # (el de esta semilla o el de otra semilla del pipeline, despues de canaritos)
  ga_muestra <- function(mes, ds= dataset, etiqueta= "") {
    campos <- setdiff(names(ds)[sapply(ds, is.numeric)], c("numero_de_cliente", "clase01", "azar"))
    set.seed(GAP$semilla + mes, kind = "L'Ecuyer-CMRG")
    azar <- runif(nrow(ds))
    pos <- ds$clase_ternaria %in% c("BAJA+1", "BAJA+2")
    s <- new.env()
    s$mes <- mes
    s$tr <- which(ds$foto_mes %in% ga_ventana(mes) & (pos | azar < GAP$undersampling))
    s$va <- which(ds$foto_mes == mes)
    s$Xtr <- data.matrix(ds[s$tr, campos, with= FALSE])
    s$Xva <- data.matrix(ds[s$va, campos, with= FALSE])
    s$ytr <- as.integer(pos[s$tr])
    s$yva <- as.integer(ds$clase_ternaria[s$va] == "BAJA+2")
    marca("genetica: muestra", etiqueta, "de", mes, "- entrena", paste(range(ga_ventana(mes)), collapse= "-"),
          "sin", length(intersect(MESES_EXCLUIR, MESES_DS)), "meses excluidos,", length(s$tr),
          "filas,", length(campos), "columnas; valida con", length(s$va))
    s
  }
  # v8: GA_SEMILLAS_DATOS = semillas del pipeline cuyos datasets (de GA_DATOS_EXP)
  # se usan para medir: cada formula se mide en todas y se promedia
  ga_muestras <- function(meses) {
    sems <- Sys.getenv("GA_SEMILLAS_DATOS", "")
    if (sems == "") return(lapply(meses, ga_muestra))
    res <- list()
    for (sm in strsplit(sems, ",")[[1]]) {
      arch <- file.path(Sys.getenv("BUCKET_DIR"), "exp", paste0("WF", Sys.getenv("GA_DATOS_EXP"), "_s", sm),
                        "checkpoints", "dataset_canaritos.fst")
      ds <- read_fst(arch, as.data.table= TRUE)
      setorder(ds, numero_de_cliente, foto_mes)
      if (nrow(ds) != nrow(ga_base) || !identical(ds$numero_de_cliente, ga_base$numero_de_cliente) ||
          !identical(ds$foto_mes, ga_base$foto_mes))
        stop("genetica: el dataset de la semilla ", sm, " no coincide fila a fila con ga_base")
      res <- c(res, lapply(meses, ga_muestra, ds= ds, etiqueta= paste0("s", sm)))
      rm(ds); gc(full= TRUE, verbose= FALSE)
    }
    res
  }

  # AUC de un modelo con las columnas extra (ganadoras previas + candidata)
  ga_auc_muestra <- function(s, extra, semilla) {
    Xtr <- s$Xtr; Xva <- s$Xva
    if (!is.null(extra)) { Xtr <- cbind(Xtr, extra[s$tr, , drop= FALSE]); Xva <- cbind(Xva, extra[s$va, , drop= FALSE]) }
    p <- ga_lgb; p$seed <- semilla
    m <- lgb.train(data= lgb.Dataset(Xtr, label= s$ytr, free_raw_data= TRUE), params= p, verbose= -100)
    ga_auc(predict(m, Xva), s$yva)
  }
  ga_auc_prom <- function(muestras, extra, semilla) mean(sapply(muestras, ga_auc_muestra, extra= extra, semilla= semilla))

  # log y cache: una fila por medicion (ronda, tipo, formula, valor, segundos)
  GA <- new.env()
  GA$cache <- list()
  if (file.exists(ARCH_GA_LOG)) {
    l <- fread(ARCH_GA_LOG, sep= "\t")
    for (i in seq_len(nrow(l))) GA$cache[[paste(l$ronda[i], l$tipo[i], l$formula[i])]] <- l$valor[i]
    marca("genetica: ya hay", nrow(l), "mediciones en el log")
  }
  ga_medir <- function(ronda, tipo, formula, fn) {
    clave <- paste(ronda, tipo, formula)
    if (!is.null(GA$cache[[clave]])) return(GA$cache[[clave]])
    rng <- if (exists(".Random.seed", envir= globalenv())) get(".Random.seed", envir= globalenv())
    t0 <- Sys.time()
    valor <- fn()
    if (!is.null(rng)) assign(".Random.seed", rng, envir= globalenv())
    fwrite(data.table(ronda= ronda, tipo= tipo, formula= formula, valor= valor,
      segundos= round(as.numeric(difftime(Sys.time(), t0, units= "secs")), 1),
      fecha= format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      ARCH_GA_LOG, sep= "\t", append= file.exists(ARCH_GA_LOG))
    GA$cache[[clave]] <- valor
    valor
  }
  ga_horas <- function() if (file.exists(ARCH_GA_LOG)) sum(fread(ARCH_GA_LOG, sep= "\t")$segundos, na.rm= TRUE) / 3600 else 0

  ga_formulas_azar <- function(n, semilla) {
    rng <- if (exists(".Random.seed", envir= globalenv())) get(".Random.seed", envir= globalenv())
    set.seed(semilla, kind = "L'Ecuyer-CMRG")
    ops <- c(" + ", " - ", " * ", " / ")
    f <- character(0); intentos <- 0
    while (length(f) < n && intentos < 100 * n) {
      intentos <- intentos + 1
      v <- sample(ga_vars, 3, replace= TRUE); o <- sample(ops, 2, replace= TRUE)
      cand <- if (runif(1) < 0.5) paste0(v[1], o[1], v[2]) else paste0("(", v[1], o[1], v[2], ")", o[2], v[3])
      if (!(cand %in% f) && !is.null(ga_eval(cand))) f <- c(f, cand)
    }
    if (!is.null(rng)) assign(".Random.seed", rng, envir= globalenv())
    f
  }

  ga_rondas <- function() if (file.exists(ARCH_GA_RONDAS)) fread(ARCH_GA_RONDAS, sep= "\t") else data.table()
  GA$extra <- NULL   # columnas de las ganadoras aceptadas (todas las filas)
  ga_sumar_ganadora <- function(nombre, formula) {
    cols <- ga_columnas(formula)
    colnames(cols) <- sub("^gen", nombre, colnames(cols))
    GA$extra <- cbind(GA$extra, cols)
  }

  if (!file.exists(ARCH_GA_FIN)) {
    marca("genetica: busqueda en", paste(GAP$busqueda, collapse= ","), "- control en",
          paste(GAP$control, collapse= ","), "-", length(ga_vars), "variables base,",
          GAP$rondas, "rondas de", GAP$poblacion, "x", GAP$generaciones)
    GA$busqueda <- ga_muestras(GAP$busqueda)
    GA$control  <- ga_muestras(GAP$control)
    gramatica <- CreateGrammar(list(
      expr = gsrule("<var><op><var>", "(<var><op><var>)<op><var>"),
      op   = gsrule(" + ", " - ", " * ", " / "),
      var  = do.call(gsrule, as.list(ga_vars))
    ))
    t_sesion <- Sys.time(); horas0 <- ga_horas()
    horas_usadas <- function() horas0 + as.numeric(difftime(Sys.time(), t_sesion, units= "hours"))

    for (r in seq_len(GAP$rondas)) {
      hechas <- ga_rondas()
      if (nrow(hechas) && r %in% hechas$ronda) {
        fila <- hechas[ronda == r]
        marca("genetica: ronda", r, "ya hecha:", fila$formula, if (fila$aceptada) "(queda)" else "(descartada)")
        if (fila$aceptada) ga_sumar_ganadora(fila$nombre, fila$formula)
        next
      }
      if (horas_usadas() >= GAP$horas_max) { marca("genetica: tope de horas, no se abren mas rondas"); break }

      base_b <- ga_medir(r, "BASE", "-", function() ga_auc_prom(GA$busqueda, GA$extra, GAP$semilla))
      costo <- function(expr) {
        formula <- as.character(expr)
        if (horas_usadas() >= GAP$horas_max)
          stop(structure(class= c("ga_tope", "error", "condition"), list(message= "tope de horas", call= NULL)))
        mejora <- ga_medir(r, "GA", formula, function() {
          cols <- ga_columnas(formula)
          if (is.null(cols)) return(-1)
          ga_auc_prom(GA$busqueda, cbind(GA$extra, cols), GAP$semilla) - base_b
        })
        -mejora
      }
      monitor <- function(res) marca("genetica ronda", r, "generacion",
        tryCatch(res$population$currentIteration, error= function(e) NA),
        "mejor mejora de AUC", round(-min(res$best$cost), 5))

      set.seed(GAP$semilla + r, kind = "L'Ecuyer-CMRG")
      corto <- FALSE
      ge <- tryCatch(
        GrammaticalEvolution(gramatica, costo, optimizer= "ga", popSize= GAP$poblacion,
          iterations= GAP$generaciones, monitorFunc= monitor, disable.warnings= TRUE),
        ga_tope= function(e) { corto <<- TRUE; NULL })
      l <- fread(ARCH_GA_LOG, sep= "\t")[ronda == r & tipo == "GA"]
      if (!nrow(l)) { marca("genetica: la ronda", r, "no llego a medir formulas"); break }
      mejor <- if (corto || is.null(ge)) l[which.max(valor), formula] else as.character(ge$best$expressions)
      mejora_b <- l[formula == mejor, valor][1]

      # control: otra semilla de LightGBM, otros meses, contra formulas al azar
      sem_c <- GAP$semilla + 1
      base_c <- ga_medir(r, "CONTROL_BASE", "-", function() ga_auc_prom(GA$control, GA$extra, sem_c))
      medir_c <- function(tipo, f) ga_medir(r, tipo, f, function() {
        cols <- ga_columnas(f)
        if (is.null(cols)) return(NA_real_)
        ga_auc_prom(GA$control, cbind(GA$extra, cols), sem_c) - base_c
      })
      m_ga <- medir_c("CONTROL_GA", mejor)
      azar <- ga_formulas_azar(GAP$n_control, GAP$semilla + 2000 * r)
      m_azar <- sapply(azar, function(f) medir_c("CONTROL_AZAR", f))
      fwrite(data.table(ronda= r, tipo= c("GA", rep("AZAR", length(azar))), formula= c(mejor, azar),
                        mejora= c(m_ga, m_azar)),
             ARCH_GA_CTRL, sep= "\t", append= file.exists(ARCH_GA_CTRL))
      p90 <- quantile(m_azar, 0.9, na.rm= TRUE)
      # v8: GA_CRITERIO=positiva -> queda si mejora en el control (aunque no le gane al azar)
      pasa <- if (Sys.getenv("GA_CRITERIO", "azar") == "positiva") isTRUE(!is.na(m_ga) && m_ga > 0) else isTRUE(!is.na(m_ga) && m_ga > 0 && m_ga > p90)
      pasa <- pasa || Sys.getenv("GA_FORZAR", "0") == "1"   # FORZAR: solo para probar
      puesto <- 1L + sum(m_azar >= m_ga, na.rm= TRUE)
      fila <- data.table(ronda= r, nombre= sprintf("gen_%02d", r), formula= mejor, mejora_busqueda= mejora_b,
        mejora_control= m_ga, p90_azar= p90, puesto_control= puesto, de= length(azar) + 1L,
        aceptada= pasa, evaluaciones= nrow(l), corto= corto)
      fwrite(fila, ARCH_GA_RONDAS, sep= "\t", append= file.exists(ARCH_GA_RONDAS))
      marca("genetica: ronda", r, "-", mejor, "- mejora de AUC busqueda", round(mejora_b, 5),
            "control", round(m_ga, 5), "(p90 de las al azar", round(p90, 5), ", puesto", puesto, "de", length(azar) + 1, ")",
            if (pasa) "-> QUEDA" else "-> descartada")
      if (pasa) ga_sumar_ganadora(fila$nombre, mejor)
    }
    rm(list= intersect(c("busqueda", "control"), ls(GA)), envir= GA)
    writeLines(format(Sys.time()), ARCH_GA_FIN)
    marca("genetica: terminada en", round(ga_horas(), 2), "horas de entrenamiento")
  } else {
    marca("genetica: ya estaba terminada, uso sus ganadoras")
    hechas <- ga_rondas()
    for (i in seq_len(nrow(hechas))) if (hechas$aceptada[i]) ga_sumar_ganadora(hechas$nombre[i], hechas$formula[i])
  }

  if (!is.null(GA$extra)) {
    for (j in colnames(GA$extra)) set(dataset, j= j, value= GA$extra[, j])
    marca("genetica: agregadas", ncol(GA$extra), "columnas:", paste(colnames(GA$extra), collapse= ", "))
  } else {
    marca("genetica: ninguna formula paso el control; sigue sin variables geneticas")
  }
  rm(ga_base); GA$extra <- NULL; gc(full= TRUE, verbose= FALSE)
}

# ======================================================================
# 9.7.2 Modelado

# ======================================================================
# 9.7.2.1 Training Strategy

# --- celda 75 ---
marca("training strategy")
PARAM$trainingstrategy$validate <- c(202107)

PARAM$trainingstrategy$training <- c(
  201901, 201902, 201903, 201904, 201905, 201906,
  201907, 201908, 201909, 201910, 201911, 201912,
  202001, 202002, 202003, 202004, 202005, 202006,
  202007, 202008, 202009, 202010, 202011, 202012,
  202101, 202102, 202103, 202104, 202105
)
PARAM$trainingstrategy$training <- setdiff(PARAM$trainingstrategy$training, MESES_EXCLUIR)   # v7
marca("BO: entrena con", length(PARAM$trainingstrategy$training), "meses:", paste(range(PARAM$trainingstrategy$training), collapse= "-"))

PARAM$trainingstrategy$training_pct <- 0.2


PARAM$trainingstrategy$positivos <- c( "BAJA+1", "BAJA+2")

# --- celda 76 ---
# seteo la clase01   1={BAJA+1, BAJA+2}   0={CONTINUA}
dataset[, clase01 := ifelse( clase_ternaria %in% PARAM$trainingstrategy$positivos, 1, 0 )]

# --- celda 77 ---
# los campos en los que se entrena
campos_buenos <- copy( setdiff(
    colnames(dataset), c("clase_ternaria","clase01","azar"))
)

# --- celda 78 ---
# preparo para que se puede hacer undersampling de los CONTINUA
#  solamente por un tema de VELOCIDAD
set.seed(PARAM$semilla_primigenia, kind = "L'Ecuyer-CMRG")
dataset[, azar:=runif(nrow(dataset))]

# undersampling de los CONTINUA
dataset[, fold_train :=  foto_mes %in%  PARAM$trainingstrategy$training &
    (clase_ternaria %in% c("BAJA+1", "BAJA+2") |
     azar < PARAM$trainingstrategy$training_pct ) ]


if( !require("lightgbm")) install.packages("lightgbm")
require("lightgbm")

dtrain <- lgb.Dataset(
  data= data.matrix(dataset[fold_train == TRUE, campos_buenos, with = FALSE]),
  label= dataset[fold_train == TRUE, clase01],
  free_raw_data= TRUE
)

# --- celda 79 ---
# datos de validation
dvalidate <- lgb.Dataset(
  data= data.matrix(dataset[foto_mes %in% PARAM$trainingstrategy$validate, campos_buenos, with = FALSE]),
  label= dataset[foto_mes %in% PARAM$trainingstrategy$validate, clase01],
  free_raw_data= TRUE
)

nrow(dvalidate)

# ======================================================================
# 9.7.2.2. Hyperparameter Tuning

# --- celda 84 ---
# paquetes necesarios para la Bayesian Optimization
if(!require("DiceKriging")) install.packages("DiceKriging")
require("DiceKriging")

if(!require("mlrMBO")) install.packages("mlrMBO")
require("mlrMBO")

# --- celda 86 ---
# 40 es el minimo razonable,  un buen analista Sr aumentara este valor
PARAM$hipeparametertuning$num_interations <- 50
if (PRUEBA > 0) PARAM$hipeparametertuning$num_interations <- 2

# parametros fijos del LightGBM
PARAM$lgbm$param_fijos <- list(
  objective= "binary",
  metric= "auc",
  first_metric_only= TRUE,
  boost_from_average= TRUE,
  feature_pre_filter= FALSE,
  verbosity= -100,
  force_row_wise= TRUE, # para evitar warning
  seed= PARAM$semilla_primigenia,
  extra_trees= FALSE,

  num_leaves= 128,
  max_depth= -1L, # -1 significa no limitar,  por ahora lo dejo fijo
  min_gain_to_split= 0.0, # min_gain_to_split >= 0.0
  # min_data_in_leaf, lambda_l1, lambda_l2: los optimiza la Bayesian Optimization
  min_sum_hessian_in_leaf= 0.001, #  min_sum_hessian_in_leaf >= 0.0

  bagging_fraction= 1.0, # 0.0 < bagging_fraction <= 1.0
  pos_bagging_fraction= 1.0, # 0.0 < pos_bagging_fraction <= 1.0
  neg_bagging_fraction= 1.0, # 0.0 < neg_bagging_fraction <= 1.0
  is_unbalance= FALSE, #
  scale_pos_weight= 1.0, # scale_pos_weight > 0.0

  drop_rate= 0.1, # 0.0 < neg_bagging_fraction <= 1.0
  max_drop= 50, # <=0 means no limit
  skip_drop= 0.5, # 0.0 <= skip_drop <= 1.0

  max_bin= 31,
  early_stopping_rounds= 0
)



# --- celda 87 ---

PARAM$hipeparametertuning$hs <- makeParamSet(
  makeNumericParam("num_iterations", lower= 2.0, upper= 10.0, trafo= function(x) round(2^x) ),
  makeNumericParam("num_leaves", lower= 2.0, upper= 11.0, trafo= function(x) round(2^x) ),
  makeNumericParam("learning_rate", lower= -7.0, upper= -0.1, trafo= function(x) 2^x ),
  makeNumericParam("feature_fraction", lower= 0.05, upper= 0.90),
  makeNumericParam("min_sum_hessian_in_leaf", lower= -10.0, upper= 10.0, trafo= function(x) 2^x),
  makeIntegerParam("min_data_in_leaf", lower= 1L, upper= 8000L),
  makeNumericParam("lambda_l1", lower= -10.0, upper= 7.0, trafo= function(x) 2^x),
  makeNumericParam("lambda_l2", lower= -10.0, upper= 7.0, trafo= function(x) 2^x)
)

# --- celda 89 ---
# En  x llegan los parmaetros de la bayesiana
#  devuelve la AUC en validate del modelo entrenado
#  en el parametro x llegan los hiperparámetros que se estan optimizando

EstimarGanancia_AUC_lightgbm <- function(x) {

  # x pisa (o agrega) a param_fijos
  param_completo <- modifyList(PARAM$lgbm$param_fijos, x)

  # entreno LightGBM
  modelo_train <- lgb.train(
    data= dtrain,
    valids= list(valid = dvalidate),
    eval= "auc",
    param= param_completo,
    verbose= -100
  )

  # recupero la AUC en validation
  AUC <- modelo_train$record_evals$valid$auc$eval[[x$num_iterations]]


  message(format(Sys.time(), "%a %b %d %X %Y  "),
    toString(x),
    " AUC ", AUC
  )

  # hago espacio en la memoria
  rm(modelo_train)
  gc(full= TRUE, verbose= FALSE)

  return(AUC)
}

# --- celda 91 ---
configureMlr(show.learner.output = FALSE)

# configuro la busqueda bayesiana,  los hiperparametros que se van a optimizar
# por favor, no desesperarse por lo complejo
obj.fun <- makeSingleObjectiveFunction(
    fn= EstimarGanancia_AUC_lightgbm, # la funcion que voy a maximizar
    minimize= FALSE, # estoy Maximizando AUC
    noisy= FALSE,
    par.set= PARAM$hipeparametertuning$hs,
    has.simple.signature= FALSE # paso los parametros en una lista
)

# cada 600 segundos guardo el resultado intermedio
ctrl <- makeMBOControl(
    save.on.disk.at.time= 600,
    save.file.path= "HT.RDATA"
)

# indico la cantidad de iteraciones que va a tener la Bayesian Optimization
ctrl <- setMBOControlTermination(
    ctrl,
    iters= PARAM$hipeparametertuning$num_interations  # cantidad de iteraciones inteligentes
)

# defino el método estandar para la creacion de los puntos iniciales
#   los "No Inteligentes"
ctrl <- setMBOControlInfill(ctrl, crit = makeMBOInfillCritEI())

# mas configuraciones
surr.km <- makeLearner(
    "regr.km",
    predict.type= "se",
    covtype= "matern3_2",
    control= list(trace = TRUE)
)

# --- celda 93 ---
# inicio la optimizacion bayesiana
marca("optimizacion bayesiana:", PARAM$hipeparametertuning$num_interations, "iteraciones inteligentes")
if (file.exists("BO_log.txt")) {
  marca("la BO ya habia terminado: leo BO_log.txt")
  tb_bayesiana <- fread("BO_log.txt")
} else {
  if (!file.exists("HT.RDATA")) {
    bayesiana_salida <- mbo(obj.fun, learner= surr.km, control= ctrl)
  } else {
    bayesiana_salida <- mboContinue("HT.RDATA") # retomo en caso que ya exista
  }
  tb_bayesiana <- as.data.table(bayesiana_salida$opt.path)
}

# --- celda 95 ---
# almaceno los resultados de la Bayesian Optimization
# y capturo los mejores hiperparametros encontrados

# ordeno en forma descendente por AUC = y
setorder(tb_bayesiana, -y, -num_iterations)

# grabo para eventualmente poder utilizarlos en OTRA corrida
fwrite( tb_bayesiana,
  file="BO_log.txt",
  sep="\t"
)

# los mejores hiperparámetros son los que quedaron en el registro 1 de la tabla
PARAM$out$lgbm$mejores_hiperparametros <- tb_bayesiana[
  1, # el primero es el de mejor AUC
  setdiff(colnames(tb_bayesiana),
    c("y","dob","eol","error.message","exec.time","ei","error.model",
      "train.time","prop.type","propose.time","se","mean","iter")),
  with= FALSE
]

print(PARAM$out$lgbm$mejores_hiperparametros)
marca("mejor AUC de la BO:", tb_bayesiana[1, y], "de", nrow(tb_bayesiana), "evaluaciones")

# ======================================================================
# 9.7.3 Produccion

# ======================================================================
# Final Training

# ======================================================================
# Final Training Dataset

# --- celda 99 ---
PARAM$trainingstrategy$final_train <- c(
  201901, 201902, 201903, 201904, 201905, 201906,
  201907, 201908, 201909, 201910, 201911, 201912,
  202001, 202002, 202003, 202004, 202005, 202006,
  202007, 202008, 202009, 202010, 202011, 202012,
  202101, 202102, 202103, 202104, 202105, 202106,
  202107
)
PARAM$trainingstrategy$final_train <- setdiff(PARAM$trainingstrategy$final_train, MESES_EXCLUIR)   # v7
marca("final training: entrena con", length(PARAM$trainingstrategy$final_train), "meses")

dataset[, fold_final_train := foto_mes %in% PARAM$trainingstrategy$final_train ]

# creo el dfinal_train en formato  LightGBM
dfinal_train <- lgb.Dataset(
  data= data.matrix(dataset[fold_final_train == TRUE, campos_buenos, with= FALSE]),
  label= dataset[fold_final_train == TRUE, clase01],
  free_raw_data= TRUE
)

nrow( dfinal_train) # verifico el tamaño

# ======================================================================
# Final Training Hyperparameters

# --- celda 101 ---
# uno los parametros fijos y los mejores encontrados de los variables
fijos <- copy(PARAM$lgbm$param_fijos)

# quito lo que optimice en la Bayesian Optimization
fijos$num_iterations <- NULL
fijos$early_stopping_rounds <- NULL

# agrego a los hiperparametros fijos los que encontre con la Bayesian Optimization
param_final <- copy(fijos)

x <- PARAM$out$lgbm$mejores_hiperparametros
param_final$num_iterations <- round( 2^x$num_iterations )
param_final$num_leaves <- round( 2^x$num_leaves )
param_final$learning_rate <- 2^x$learning_rate
param_final$feature_fraction <- x$feature_fraction
param_final$min_sum_hessian_in_leaf <- 2^x$min_sum_hessian_in_leaf
param_final$min_data_in_leaf <- round( x$min_data_in_leaf )
param_final$lambda_l1 <- 2^x$lambda_l1
param_final$lambda_l2 <- 2^x$lambda_l2



# --- celda 102 ---
print(param_final)

# ======================================================================
# Training

# --- celda 104 ---
# poner este valor en 5 o en 1  si se está muy ajustado de tiempo

# v5: semillerio de 30 (FT_SEMILLERIO en el .env, de 1 a 30)
PARAM$FT$semillerio <- as.integer(Sys.getenv("FT_SEMILLERIO", "9"))

# --- celda 105 de la notebook: se saca (solo mostraba datos o instalaba algo que no se usa) ---

# --- celda 106 ---
# semillerio FIJO: las mismas semillas en todas las corridas. Las 9 primeras son
# las de la v2 (en el mismo orden): prob_1..prob_9 de prediccion.txt son modelos
# comparables con la v2. Las 21 siguientes son las mismas de la v3
PARAM$FT$semillas <- c(100213, 100313, 100613, 100913, 101113, 570991, 669287, 832421, 882599,
                       287821, 291491, 365297, 695269, 956713, 553667, 118273, 859093, 691121,
                       502631, 527809, 405413, 168227, 157669, 509797, 925271, 146383, 118603,
                       397297, 963499, 977507)
PARAM$FT$semillas <- head(PARAM$FT$semillas, PARAM$FT$semillerio)
PARAM$FT$semillerio <- length(PARAM$FT$semillas)
marca("semillerio:", PARAM$FT$semillerio, "modelos")
if (PRUEBA > 0) { PARAM$FT$semillas <- PARAM$FT$semillas[1]; PARAM$FT$semillerio <- 1 }
cat( PARAM$FT$semillas, "\n")

# --- celda 107 ---
primero <- TRUE

crear_modelo_final <- function( sem ) {

  nombre_arch <- paste0( "./modelos/modelo_", sem, ".txt")
  if( !file.exists(nombre_arch) )
  {
    param_final$seed <- sem

    set.seed(sem, kind = "L'Ecuyer-CMRG")
    final_model <- lgb.train(
      data= dfinal_train,
      param= param_final,
      verbose= -100
    )

    lgb.save(final_model, nombre_arch) # grabo el modelo"

    # grabo la primer importancia de variables
    #  Natalia : da lo mismo cual se guarda
    if( primero)
    {
      primero <<- FALSE
      # lgb.importance pasa el modelo a JSON en un solo string de R: con modelos
      # muy grandes supera los 2^31 bytes y R corta. Respaldo: la cantidad de
      # splits por variable que LightGBM escribe al final del modelo grabado
      tb_importancia <- tryCatch(as.data.table(lgb.importance(final_model)),
        error= function(e) {
          marca("importancia: lgb.importance fallo (", conditionMessage(e), "); uso los splits del modelo grabado")
          l <- system2("awk", c("'/^feature_importances:/{f=1;next} f&&!NF{exit} f'", shQuote(nombre_arch)), stdout= TRUE)
          l <- l[grepl("=", l, fixed= TRUE)]
          data.table(Feature= sub("=[^=]*$", "", l), Frequency= as.numeric(sub("^.*=", "", l)))
        })
      archivo_importancia <- "impo.txt"

      fwrite( tb_importancia,
        file= archivo_importancia,
        sep= "\t"
      )
    }

    rm(final_model)
    gc(full = TRUE, verbose=FALSE)
  }
  marca("modelo final listo, semilla", sem)
}

# --- celda 108 ---
marca("final training")
gc(full = TRUE, verbose=FALSE)
dir.create("modelos", showWarnings =FALSE)

primero <- TRUE
for( sem in PARAM$FT$semillas)  crear_modelo_final(sem)

# ======================================================================
# Scoring

# --- celda 111 ---
marca("scoring de 202109")
PARAM$trainingstrategy$future <- c(202109)

dfuture <- dataset[ foto_mes %in% PARAM$trainingstrategy$future ]

# --- celda 112 ---
# aplico final_model   a dfuture

tb_prediccion <- dfuture[, list(numero_de_cliente)]
tb_prediccion[, prob := 0]

datos_matrix <- data.matrix(dfuture[, campos_buenos, with= FALSE])

# --- celda 113 ---
agregar_a_ensemble <- function( sem ) {

  nombre_arch <- paste0( "./modelos/modelo_", sem, ".txt")
  final_model <- lgb.load(nombre_arch)

  prediccion <- predict(
    final_model,
    datos_matrix
  )

  tb_prediccion[, paste0("prob_", isem) := prediccion]
  tb_prediccion[, prob := prob + prediccion]

  rm(final_model)
  rm(prediccion)
  gc(full = TRUE, verbose=FALSE)
}

# --- celda 114 ---
for( isem in seq(length(PARAM$FT$semillas)) )
{
  sem <- PARAM$FT$semillas[ isem ]
  agregar_a_ensemble( sem )
  gc(full = TRUE, verbose=FALSE)
}

rm( datos_matrix)
gc(full = TRUE, verbose=FALSE)

tb_prediccion[, prob := prob /length(PARAM$FT$semillas) ]

# --- celda 115 de la notebook: se saca (solo mostraba datos o instalaba algo que no se usa) ---

# --- celda 116 ---
# grabo las probabilidad del modelo
#  me va a ser util para hacer Ensembles de modelos
fwrite(tb_prediccion,
  file= "prediccion.txt",
  sep= "\t"
)

# ======================================================================
# Kaggle Competition Submit

# --- celda 119 ---
# genero archivos con los  "envios" mejores y los subo a Kaggle
marca("Kaggle")
PARAM$kaggle$competencia <- Sys.getenv("KAGGLE_COMPETENCIA", "labo-1-ba-2026-analista-sr")
PARAM$kaggle$cortes <- seq(8000, 12000, by = 500)

kaggle_ok <- FALSE
kaggle_subir <- Sys.getenv("KAGGLE_SUBIR", "1") == "1"
if (kaggle_subir || PRUEBA > 0) {
  # La imagen de la catedra (kaggle_startup.sh) toma el kaggle.json del bucket,
  # lo guarda en Secret Manager (secreto kaggle-cred), lo BORRA del bucket y arma
  # ~/.kaggle/kaggle.json con el. Si el archivo sigue en el bucket (KAGGLE_JSON),
  # se usa ese, pisando el de la VM
  dir.create("~/.kaggle", showWarnings= FALSE)
  kaggle_json <- path.expand("~/.kaggle/kaggle.json")
  if (file.exists(Sys.getenv("KAGGLE_JSON"))) {
    file.copy(Sys.getenv("KAGGLE_JSON"), kaggle_json, overwrite= TRUE)
    Sys.chmod(kaggle_json, "600")
  }
  kaggle_bin <- unname(Sys.which("kaggle"))
  if (!nzchar(kaggle_bin)) {
    system2("python3", c("-m", "pip", "install", "--user", "--quiet", "--break-system-packages", "kaggle"))
    kaggle_bin <- path.expand("~/.local/bin/kaggle")
  }
  kaggle_ok <- file.exists(kaggle_json) && file.exists(kaggle_bin)
  marca("Kaggle", if (kaggle_ok) "listo" else "NO disponible: los csv quedan en ./kaggle para subir a mano")
  if (kaggle_ok) {
    # solo el nombre de usuario, nunca la clave
    kaggle_usuario <- sub('.*"username" *: *"([^"]+)".*', "\\1", paste(readLines(kaggle_json, warn= FALSE), collapse= ""))
    marca("Kaggle: cuenta", kaggle_usuario)
  }
  if (PRUEBA > 0 && kaggle_ok) {
    # modo prueba: no sube nada, solo verifica que la credencial funcione
    # (lista los envios ya hechos a la competencia)
    prueba_k <- suppressWarnings(system(paste(shQuote(kaggle_bin), "competitions submissions -c",
      PARAM$kaggle$competencia), intern= TRUE))
    marca("MODO PRUEBA: credencial de Kaggle", if (is.null(attr(prueba_k, "status"))) "OK" else "FALLA")
    cat(head(prueba_k, 5), sep= "\n")
  }
}

# ordeno por probabilidad descendente
setorder(tb_prediccion, -prob)
dir.create("kaggle", showWarnings= FALSE)

for (envios in PARAM$kaggle$cortes) {

  tb_prediccion[, Predicted := 0L] # seteo inicial a 0
  tb_prediccion[1:min(envios, .N), Predicted := 1L] # marco los primeros (min: en modo prueba hay menos clientes que envios)

  archivo_kaggle <- paste0("./kaggle/KA", PARAM$experimento, "_s",
    format(PARAM$semilla_primigenia, scientific= FALSE), "_", envios, ".csv")
  marca_subido <- paste0(archivo_kaggle, ".subido")

  fwrite(tb_prediccion[, list(numero_de_cliente, Predicted)], file= archivo_kaggle, sep= ",")
  if (!kaggle_ok || !kaggle_subir || file.exists(marca_subido)) next

  linea <- paste(shQuote(kaggle_bin), "competitions submit",
    "-c", PARAM$kaggle$competencia,
    "-f", archivo_kaggle,
    paste0("-m 'envios=", envios, " semilla=", format(PARAM$semilla_primigenia, scientific= FALSE),
           " exp=", PARAM$experimento, "'"))

  Sys.sleep(30)
  salida <- suppressWarnings(system(linea, intern= TRUE)) # el submit a Kaggle
  cat(salida, sep= "\n")
  if (is.null(attr(salida, "status"))) writeLines(c(format(Sys.time()), salida), marca_subido)
}

# v5 (como la v3): guarda la lista de TODOS los envios de la cuenta a la competencia,
# con su puntaje publico, para comparar versiones sin copiar puntajes a mano. Espera
# unos minutos a que Kaggle puntue los ultimos. Si falla, solo lo anota en el log
if (kaggle_ok) {
  if (kaggle_subir) Sys.sleep(180)
  base_k <- paste(shQuote(kaggle_bin), "competitions submissions -c", PARAM$kaggle$competencia, "--csv")
  lista_k <- suppressWarnings(system(paste(base_k, "--page-size 200"), intern= TRUE))
  if (!is.null(attr(lista_k, "status")))   # version del CLI sin --page-size
    lista_k <- suppressWarnings(system(base_k, intern= TRUE))
  if (is.null(attr(lista_k, "status")) && length(lista_k) > 1) {
    writeLines(lista_k, "kaggle_submissions.csv")
    marca("Kaggle: lista de envios guardada en kaggle_submissions.csv:", length(lista_k) - 1, "envios")
  } else {
    marca("Kaggle: no se pudo bajar la lista de envios (no afecta la corrida)")
  }
}

# --- celda 120 ---
# grabo los parametros
if( !require("yaml")) install.packages("yaml")
require("yaml")

write_yaml( PARAM, file="PARAM.yml")

# --- celda 121 ---
writeLines(format(Sys.time()), "TERMINADO")
marca("TERMINADO")
