# Convierte z739_final_senior_v2.ipynb en un script R para correr sin supervision
# uso: Rscript nb2script.R <notebook> <script de salida>
a <- commandArgs(TRUE)
j <- jsonlite::fromJSON(a[1], simplifyVector= FALSE)
celda <- function(i) paste(unlist(j$cells[[i]]$source), collapse= "")

# cada celda de codigo: "keep" tal cual, NULL = se saca, o un texto que la reemplaza.
# marcas[[i]] = una linea de log antes de la celda
reemplazos <- list()
marcas <- list()
esperado <- list()   # para verificar que la celda es la que creo

# --- encabezado: paquetes en la libreria del usuario (la VM es nueva) -------
esperado[["10"]] <- 'require("data.table")'
reemplazos[["10"]] <- r"---(
# z739_final_senior_v2.R
# Version script de la notebook z739_final_senior_v2.ipynb (grupo A: predice 202109 y sube a Kaggle)
#   uso: Rscript z739_final_senior_v2.R <archivo .env> <semilla del pipeline>
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

if( !require("R.utils")) install.packages("R.utils")
require("R.utils")

if( !require("fst")) install.packages("fst")
require("fst")

marca <- function(...) cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "|", ..., "\n")
)---"

esperado[["12"]] <- "PARAM <- list()"
reemplazos[["12"]] <- r"---(
args <- commandArgs(trailingOnly= TRUE)
archivo_env <- if (length(args) >= 1) args[1] else ".env"
if (!file.exists(archivo_env)) stop("No existe el archivo de configuracion ", archivo_env)
readRenviron(archivo_env)

PARAM <- list()
PARAM$semilla_primigenia <- if (length(args) >= 2) as.numeric(args[2]) else 102191
PARAM$experimento <- as.integer(Sys.getenv("EXPERIMENTO"))
PARAM$dataset <- basename(Sys.getenv("DATASET_PATH"))
marca("inicio: experimento", PARAM$experimento, "semilla del pipeline", PARAM$semilla_primigenia)
)---"

esperado[["14"]] <- "# carpeta de trabajo"
reemplazos[["14"]] <- r"---(
# carpeta de trabajo: exp/WF<experimento>_s<semilla> (la misma que espera vm/startup.sh)
experimento_folder <- paste0("WF", PARAM$experimento, "_s", format(PARAM$semilla_primigenia, scientific= FALSE))
carpeta <- file.path(Sys.getenv("BUCKET_DIR"), "exp", experimento_folder)
dir.create(carpeta, recursive= TRUE, showWarnings= FALSE)
setwd(carpeta)
dir.create("checkpoints", showWarnings= FALSE)
CK <- "checkpoints/dataset_canaritos.fst"
)---"

# --- todo el preprocesamiento queda dentro de un if: si hay checkpoint, se saltea
esperado[["17"]] <- "# lectura del dataset"
reemplazos[["17"]] <- r"---(
if (file.exists(CK)) {
  marca("retomo desde el checkpoint", CK)
  dataset <- read_fst(CK, as.data.table= TRUE)
} else {

marca("lectura del dataset")
dataset <- fread(Sys.getenv("DATASET_PATH"))
)---"

esperado[["20"]] <- 'if( !require("mice"))'
reemplazos[["20"]] <- NULL   # MICE no se usa (metodo MachineLearning) y tarda en instalarse

marcas[["26"]] <- "Catastrophe Analysis"
marcas[["39"]] <- "Data Drifting"
esperado[["40"]] <- "colnames(dataset)"; reemplazos[["40"]] <- NULL
marcas[["45"]] <- "FE intra-mes"
esperado[["46"]] <- "# visualizo las columas"; reemplazos[["46"]] <- NULL
marcas[["52"]] <- "FE historico: lags y deltas"
marcas[["54"]] <- "FE historico: tendencias, minimo, maximo, promedio, ratioavg, ratiomax"
esperado[["56"]] <- "ncol(dataset)"; reemplazos[["56"]] <- NULL
marcas[["61"]] <- "FE random forest"
esperado[["62"]] <- "ncol(dataset)"; reemplazos[["62"]] <- NULL
marcas[["69"]] <- "canaritos"

esperado[["71"]] <- "# verifico"
reemplazos[["71"]] <- r"---(
marca("grabo el checkpoint despues de canaritos:", ncol(dataset), "columnas")
write_fst(dataset, CK)

}   # fin del preprocesamiento (o del retome desde el checkpoint)
marca("dataset listo:", nrow(dataset), "filas x", ncol(dataset), "columnas")
)---"

marcas[["75"]] <- "training strategy"

esperado[["93"]] <- "# inicio la optimizacion bayesiana"
reemplazos[["93"]] <- r"---(
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
)---"

esperado[["95"]] <- "# almaceno los resultados"
reemplazos[["95"]] <- r"---(
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
)---"

esperado[["102"]] <- "param_final"
reemplazos[["102"]] <- "print(param_final)"

esperado[["105"]] <- 'if(!require("primes"))'; reemplazos[["105"]] <- NULL
esperado[["106"]] <- "primos <- generate_primes"
reemplazos[["106"]] <- r"---(
# semillerio FIJO: las mismas 9 semillas en todas las corridas;
# el ensamble grande es entre semillas del pipeline
PARAM$FT$semillas <- c(100213, 100313, 100613, 100913, 101113, 570991, 669287, 832421, 882599)
PARAM$FT$semillerio <- length(PARAM$FT$semillas)
cat( PARAM$FT$semillas, "\n")
)---"

esperado[["107"]] <- "primero <- TRUE"
reemplazos[["107"]] <- r"---(
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
)---"

marcas[["108"]] <- "final training"
marcas[["111"]] <- "scoring de 202109"
esperado[["115"]] <- "# veo que hay en tb_prediccion"; reemplazos[["115"]] <- NULL

esperado[["119"]] <- "# genero archivos con los"
reemplazos[["119"]] <- r"---(
# genero archivos con los  "envios" mejores y los subo a Kaggle
marca("Kaggle")
PARAM$kaggle$competencia <- Sys.getenv("KAGGLE_COMPETENCIA", "labo-1-ba-2026-analista-sr")
PARAM$kaggle$cortes <- seq(8000, 12000, by = 500)

kaggle_ok <- FALSE
if (Sys.getenv("KAGGLE_SUBIR", "1") == "1") {
  dir.create("~/.kaggle", showWarnings= FALSE)
  if (!file.exists("~/.kaggle/kaggle.json") && file.exists(Sys.getenv("KAGGLE_JSON"))) {
    file.copy(Sys.getenv("KAGGLE_JSON"), "~/.kaggle/kaggle.json")
    Sys.chmod("~/.kaggle/kaggle.json", "600")
  }
  kaggle_bin <- unname(Sys.which("kaggle"))
  if (!nzchar(kaggle_bin)) {
    system2("python3", c("-m", "pip", "install", "--user", "--quiet", "--break-system-packages", "kaggle"))
    kaggle_bin <- path.expand("~/.local/bin/kaggle")
  }
  kaggle_ok <- file.exists("~/.kaggle/kaggle.json") && file.exists(kaggle_bin)
  marca("Kaggle", if (kaggle_ok) "listo" else "NO disponible: los csv quedan en ./kaggle para subir a mano")
}

# ordeno por probabilidad descendente
setorder(tb_prediccion, -prob)
dir.create("kaggle", showWarnings= FALSE)

for (envios in PARAM$kaggle$cortes) {

  tb_prediccion[, Predicted := 0L] # seteo inicial a 0
  tb_prediccion[1:envios, Predicted := 1L] # marco los primeros

  archivo_kaggle <- paste0("./kaggle/KA", PARAM$experimento, "_s",
    format(PARAM$semilla_primigenia, scientific= FALSE), "_", envios, ".csv")
  marca_subido <- paste0(archivo_kaggle, ".subido")

  fwrite(tb_prediccion[, list(numero_de_cliente, Predicted)], file= archivo_kaggle, sep= ",")
  if (!kaggle_ok || file.exists(marca_subido)) next

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
)---"

esperado[["121"]] <- "format(Sys.time()"
reemplazos[["121"]] <- r"---(
writeLines(format(Sys.time()), "TERMINADO")
marca("TERMINADO")
)---"

# --- armado -----------------------------------------------------------------
quitar <- c("20", "40", "46", "56", "62", "105", "115")
salida <- character(0)
for (i in seq_along(j$cells)) {
  c <- j$cells[[i]]
  k <- as.character(i)
  if (c$cell_type == "markdown") {
    # los titulos de la notebook quedan como comentarios de seccion
    t <- trimws(unlist(strsplit(celda(i), "\n"))[1])
    if (startsWith(t, "#")) salida <- c(salida, "", paste0("# ", strrep("=", 70)), paste0("# ", sub("^#+ *", "", t)))
    next
  }
  src <- celda(i)
  if (!is.null(esperado[[k]]) && !startsWith(trimws(src), esperado[[k]]))
    stop("la celda ", i, " no empieza como esperaba: ", substr(src, 1, 60))
  if (k %in% quitar) {
    salida <- c(salida, "", paste0("# --- celda ", i, " de la notebook: se saca (solo mostraba datos o instalaba algo que no se usa) ---"))
    next
  }
  salida <- c(salida, "", paste0("# --- celda ", i, " ---"))
  if (!is.null(marcas[[k]])) salida <- c(salida, paste0('marca("', marcas[[k]], '")'))
  salida <- c(salida, if (k %in% names(reemplazos)) trimws(reemplazos[[k]]) else src)
}
writeLines(salida, a[2])
invisible(parse(a[2]))
cat("script ok:", length(salida), "lineas\n")
