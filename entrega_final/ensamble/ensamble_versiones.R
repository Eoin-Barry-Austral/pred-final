# Ensamble por RANKING de corridas de varias versiones (todas predicen 202109).
# uso: Rscript ensamble_versiones.R <nombre> <carpeta de salida> <cortes> <carpeta1> [carpeta2 ...]
#   cada carpeta tiene pred_<semilla>.txt (prediccion.txt de cada corrida, columna prob)
#   ej.: Rscript ensamble_versiones.R v2v3 salida 9500,10000 pred/v2 pred/v3
# Cada corrida pesa lo mismo y aporta el ranking de sus clientes (no la probabilidad).
suppressWarnings(suppressMessages(library(data.table)))
a <- commandArgs(TRUE)
nombre <- a[1]; salida <- a[2]
cortes <- as.integer(strsplit(a[3], ",")[[1]])
carpetas <- a[-(1:3)]
dir.create(salida, showWarnings= FALSE, recursive= TRUE)

P <- NULL
for (d in carpetas) {
  v <- basename(d)
  for (f in list.files(d, pattern= "^pred_[0-9]+[.]txt$", full.names= TRUE)) {
    col <- paste0("r_", v, "_", sub("^pred_([0-9]+)[.]txt$", "\\1", basename(f)))
    p <- fread(f, select= c("numero_de_cliente", "prob"))
    p[, (col) := frank(prob, ties.method= "average")]
    p[, prob := NULL]
    P <- if (is.null(P)) p else merge(P, p, by= "numero_de_cliente")
  }
}
cols <- grep("^r_", names(P), value= TRUE)
cat(nombre, ":", length(cols), "corridas,", nrow(P), "clientes\n")
P[, rank_prom := rowMeans(.SD), .SDcols= cols]
setorder(P, -rank_prom)

# cuanto comparte cada version con el ensamble en los primeros 10.000
top_ens <- P[1:10000, numero_de_cliente]
for (v in unique(sub("^r_([^_]+)_.*", "\\1", cols))) {
  cv <- grep(paste0("^r_", v, "_"), cols, value= TRUE)
  comp <- sapply(cv, function(cc) mean(P[order(-get(cc))][1:10000, numero_de_cliente] %in% top_ens))
  cat(sprintf("  %s: cada corrida comparte en promedio %.1f%% de sus 10.000 con el ensamble\n", v, 100 * mean(comp)))
}

for (envios in cortes) {
  P[, Predicted := 0L]
  P[1:envios, Predicted := 1L]
  f <- file.path(salida, sprintf("KA_ens_%s_%d_%d.csv", nombre, length(cols), envios))
  fwrite(P[, list(numero_de_cliente, Predicted)], f, sep= ",")
  cat("grabado", f, "\n")
}
fwrite(P[, list(numero_de_cliente, rank_prom)], file.path(salida, sprintf("ranking_%s.txt", nombre)), sep= "\t")
