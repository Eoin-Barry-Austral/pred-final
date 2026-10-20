# Carga en la tabla de puntajes de una version los envios de un experimento,
# desde la lista de Kaggle que guarda cada semilla (kaggle_submissions.csv).
# uso: Rscript agregar_puntajes.R <tabla.tsv> <experimento> <kaggle_submissions.csv> [...]
#   ej.: Rscript agregar_puntajes.R z739_v4/resultados/puntajes_publicos.tsv 9950 ks.csv
# Solo agrega semillas con sus 9 cortes puntuados; reemplaza las que ya estaban.
suppressWarnings(suppressMessages(library(data.table)))
a <- commandArgs(TRUE)
tsv <- a[1]; exp <- a[2]
t <- if (file.exists(tsv)) fread(tsv, colClasses= c(semilla= "integer", envios= "integer", publico= "numeric")) else data.table(semilla= integer(), envios= integer(), publico= numeric())
patron <- sprintf("^KA%s_s([0-9]+)_([0-9]+)[.]csv$", exp)
for (f in a[-(1:2)]) {
  k <- fread(f)
  k <- k[grepl(patron, fileName) & !is.na(publicScore)]
  k[, semilla := as.integer(sub(patron, "\\1", fileName))]
  k[, envios := as.integer(sub(patron, "\\2", fileName))]
  k <- unique(k[, .(semilla, envios, publico= publicScore)], by= c("semilla", "envios"))
  k <- k[, if (.N == 9) .SD, by= semilla]
  t <- rbind(t[!semilla %in% k$semilla], k)
}
setorder(t, semilla, envios)
dir.create(dirname(tsv), recursive= TRUE, showWarnings= FALSE)
fwrite(t, tsv, sep= "\t")
print(t[, .(cortes= .N, media= round(mean(publico), 1)), by= semilla])
