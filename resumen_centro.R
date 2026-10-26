# Resumen del "centro" (cortes 9.000 a 10.500) por version, desde las tablas del repo.
# uso (desde la raiz del repo): Rscript resumen_centro.R
suppressWarnings(suppressMessages(library(data.table)))
centro <- c(9000, 9500, 10000, 10500)
vs <- c("v2", "v3", "v4", "v5", "v6", "v7", "v7ga", "v8", "v9", "v10", "v11", "v12", "v13", "v14")
T <- rbindlist(lapply(vs, function(v) {
  f <- sprintf("z739_%s/resultados/puntajes_publicos.tsv", v)
  if (!file.exists(f)) return(NULL)
  x <- fread(f, colClasses= c(semilla= "integer", envios= "integer", publico= "numeric"))
  x[, version := v]
}))
T <- T[, if (.N == 9) .SD, by= .(version, semilla)]
r <- T[envios %in% centro, .(centro= mean(publico)), by= .(version, semilla)]
cat("Promedio del centro por version (cada semilla pesa igual):\n")
print(r[, .(semillas= .N, centro_medio= round(mean(centro), 1), mejor_semilla= round(max(centro), 1)), by= version][order(-centro_medio)])
cat("\nCentro por semilla y version:\n")
print(dcast(r[, .(version, semilla, centro= round(centro, 1))], semilla ~ version, value.var= "centro"))
cat("\nMejores envios sueltos en el centro:\n")
print(head(T[envios %in% centro][order(-publico), .(version, semilla, envios, publico)], 8))
