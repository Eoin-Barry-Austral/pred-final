# Sube a Kaggle los csv de corridas anteriores que todavia no se subieron (sin la
# marca .subido), en el orden de SUBIR_LISTA, hasta MAX_ENVIOS o hasta 3 fallas
# seguidas (por ejemplo, el limite diario de Kaggle). Graba la marca .subido de
# cada uno que entra, igual que el workflow. Al final guarda la lista de envios.
#   SUBIR_LISTA = exp:semilla,... ("*" = todas las semillas de ese experimento)
#   MAX_ENVIOS  = tope de envios de esta corrida
#   SUBIR_SECO  = 1: no sube nada, solo lista lo pendiente y prueba la credencial
# uso: Rscript subir_pendientes.R <archivo .env>
args <- commandArgs(trailingOnly= TRUE)
readRenviron(if (length(args) >= 1) args[1] else ".env")
marca <- function(...) cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "|", ..., "\n")
# espera "ocupada": la vigia de vm/startup.sh mata a R si pasa 30 min sin usar CPU
esperar <- function(seg) { t0 <- Sys.time(); while (as.numeric(difftime(Sys.time(), t0, units= "secs")) < seg) invisible(sum(runif(1e5))) }
B <- Sys.getenv("BUCKET_DIR")
comp <- Sys.getenv("KAGGLE_COMPETENCIA", "labo-1-ba-2026-analista-sr")
max_envios <- as.integer(Sys.getenv("MAX_ENVIOS", "99"))
seco <- Sys.getenv("SUBIR_SECO", "0") == "1"
carpeta <- file.path(B, "exp", paste0("WF", Sys.getenv("EXPERIMENTO")))
dir.create(carpeta, recursive= TRUE, showWarnings= FALSE)
marca("subidor: experimento", Sys.getenv("EXPERIMENTO"), "- tope", max_envios, if (seco) "- MODO SECO" else "")

# credencial (igual que el workflow: ~/.kaggle/kaggle.json lo arma la imagen)
dir.create("~/.kaggle", showWarnings= FALSE)
kaggle_json <- path.expand("~/.kaggle/kaggle.json")
if (file.exists(Sys.getenv("KAGGLE_JSON"))) { file.copy(Sys.getenv("KAGGLE_JSON"), kaggle_json, overwrite= TRUE); Sys.chmod(kaggle_json, "600") }
kaggle_bin <- unname(Sys.which("kaggle"))
if (!nzchar(kaggle_bin)) {
  system2("python3", c("-m", "pip", "install", "--user", "--quiet", "--break-system-packages", "kaggle"))
  kaggle_bin <- path.expand("~/.local/bin/kaggle")
}
if (!(file.exists(kaggle_json) && file.exists(kaggle_bin))) stop("subidor: Kaggle no disponible")
marca("Kaggle: cuenta", sub('.*"username" *: *"([^"]+)".*', "\\1", paste(readLines(kaggle_json, warn= FALSE), collapse= "")))
prueba <- suppressWarnings(system(paste(shQuote(kaggle_bin), "competitions submissions -c", comp), intern= TRUE))
marca("Kaggle: credencial", if (is.null(attr(prueba, "status"))) "OK" else "FALLA")

# pendientes, en orden
pend <- character(0)
for (item in strsplit(Sys.getenv("SUBIR_LISTA"), ",")[[1]]) {
  p <- strsplit(item, ":")[[1]]; ex <- p[1]; se <- p[2]
  dirs <- if (se == "*") sort(Sys.glob(file.path(B, "exp", paste0("WF", ex, "_s*")))) else file.path(B, "exp", paste0("WF", ex, "_s", se))
  for (d in dirs) {
    cs <- sort(Sys.glob(file.path(d, "kaggle", "KA*.csv")))
    cs <- cs[!file.exists(paste0(cs, ".subido"))]
    pend <- c(pend, cs)
  }
}
marca("subidor:", length(pend), "archivos pendientes en el orden pedido")
cat(basename(pend), sep= "\n")

subidos <- 0; fallas <- 0
if (!seco) for (f in pend) {
  if (subidos >= max_envios) { marca("subidor: tope de", max_envios, "alcanzado"); break }
  m <- regmatches(basename(f), regexec("^KA([0-9]+)_s([0-9]+)_([0-9]+)[.]csv$", basename(f)))[[1]]
  desc <- if (length(m) == 4) sprintf("envios=%s semilla=%s exp=%s", m[4], m[3], m[2]) else basename(f)
  esperar(30)
  salida <- suppressWarnings(system(paste(shQuote(kaggle_bin), "competitions submit -c", comp,
                                          "-f", shQuote(f), "-m", shQuote(desc)), intern= TRUE))
  ok <- is.null(attr(salida, "status")) && any(grepl("Successfully submitted", salida, fixed= TRUE))
  if (ok) {
    writeLines(c(format(Sys.time()), salida), paste0(f, ".subido"))
    subidos <- subidos + 1; fallas <- 0
    marca("subido", subidos, ":", basename(f))
  } else {
    fallas <- fallas + 1
    marca("FALLO", basename(f), ":", paste(salida, collapse= " | "))
    if (fallas >= 3) { marca("subidor: 3 fallas seguidas, corto (probable limite diario)"); break }
  }
}
marca("subidor: subidos", subidos, "de", length(pend), "pendientes")

# lista de envios con puntaje, para cargar en el repo
if (!seco) esperar(180)
lista <- suppressWarnings(system(paste(shQuote(kaggle_bin), "competitions submissions -c", comp, "--csv --page-size 200"), intern= TRUE))
if (is.null(attr(lista, "status")) && length(lista) > 1) writeLines(lista, file.path(carpeta, "kaggle_submissions.csv"))
writeLines(format(Sys.time()), file.path(carpeta, "TERMINADO"))
marca("TERMINADO")
