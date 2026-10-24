# Ensamble por RANKING de las semillas del pipeline (exp 9800, predice 202109)
# uso: Rscript ensamble_ranking.R <carpeta con pred_<semilla>.txt> <carpeta de salida> <cortes separados por coma>
# Cada semilla aporta el ranking de sus clientes (no la probabilidad: cada semilla
# eligio hiperparametros distintos y sus probabilidades estan en escalas distintas).
suppressWarnings(suppressMessages(library(data.table)))
a <- commandArgs(TRUE)
entrada <- a[1]; salida <- a[2]
cortes <- as.integer(strsplit(a[3], ",")[[1]])
dir.create(salida, showWarnings= FALSE, recursive= TRUE)

archivos <- list.files(entrada, pattern= "^pred_[0-9]+[.]txt$", full.names= TRUE)
semillas <- sub("^pred_([0-9]+)[.]txt$", "\\1", basename(archivos))
cat("semillas:", semillas, "\n")

P <- NULL
for (i in seq_along(archivos)) {
  p <- fread(archivos[i], select= c("numero_de_cliente", "prob"))
  p[, (paste0("r_", semillas[i])) := frank(prob, ties.method= "average")]   # mayor prob = mayor ranking
  p[, prob := NULL]
  P <- if (is.null(P)) p else merge(P, p, by= "numero_de_cliente")
}
cat("clientes:", nrow(P), "\n")
P[, rank_prom := rowMeans(.SD), .SDcols= patterns("^r_")]
setorder(P, -rank_prom)

# control: cuanto se parecen los envios del ensamble a los de cada semilla
for (s in semillas) {
  top_s <- P[order(-get(paste0("r_", s)))][1:9500, numero_de_cliente]
  cat(sprintf("  semilla %s: comparte %.1f%% de los 9500 enviados con el ensamble\n", s,
              100 * mean(top_s %in% P[1:9500, numero_de_cliente])))
}

etiqueta <- paste0("ens", length(semillas))
for (envios in cortes) {
  P[, Predicted := 0L]
  P[1:envios, Predicted := 1L]
  f <- file.path(salida, sprintf("KA9800_%s_%d.csv", etiqueta, envios))
  fwrite(P[, list(numero_de_cliente, Predicted)], f, sep= ",")
  cat("grabado", f, "- enviados:", sum(P$Predicted), "\n")
}
fwrite(P[, c("numero_de_cliente", "rank_prom"), with= FALSE], file.path(salida, paste0("ranking_", etiqueta, ".txt")), sep= "\t")
