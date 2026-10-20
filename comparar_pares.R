# Pares por semilla entre dos versiones, desde las tablas de puntajes publicos del repo.
# uso (desde la raiz del repo): Rscript comparar_pares.R [base] [nueva]
#   por defecto v2 contra v3; ej.: Rscript comparar_pares.R v2 v4
suppressWarnings(suppressMessages(library(data.table)))
args <- commandArgs(TRUE)
va <- if (length(args) >= 1) args[1] else "v2"
vb <- if (length(args) >= 2) args[2] else "v3"
cc <- c(semilla= "integer", envios= "integer", publico= "numeric")
a <- fread(sprintf("z739_%s/resultados/puntajes_publicos.tsv", va), colClasses= cc)
b <- fread(sprintf("z739_%s/resultados/puntajes_publicos.tsv", vb), colClasses= cc)
m <- merge(a, b, by= c("semilla", "envios"), suffixes= c("_a", "_b"))
m <- m[, if (.N == 9) .SD, by= semilla]   # solo semillas con los 9 cortes en las dos versiones
if (nrow(m) == 0) { cat("todavia no hay semillas con los 9 cortes en", va, "y", vb, "\n"); quit(save= "no") }
centro <- c(9000, 9500, 10000, 10500)
r <- m[, .(a= mean(publico_a), b= mean(publico_b),
           centro_a= mean(publico_a[envios %in% centro]), centro_b= mean(publico_b[envios %in% centro])),
       by= semilla]
r[, `:=`(dif= b - a, dif_centro= centro_b - centro_a)]
setnames(r, c("a", "b", "centro_a", "centro_b"), c(va, vb, paste0("centro_", va), paste0("centro_", vb)))
print(r[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 1) else x)])
cat(sprintf("\n%s peor que su par de la %s (9 cortes): %d de %d   |   en el centro (9.000-10.500): %d de %d\n",
            vb, va, sum(r$dif < 0), nrow(r), sum(r$dif_centro < 0), nrow(r)))
cat(sprintf("diferencia media: %+.1f (9 cortes), %+.1f (centro)\n", mean(r$dif), mean(r$dif_centro)))
if (nrow(r) >= 5) {
  w <- suppressWarnings(wilcox.test(r$dif, exact= FALSE))
  cat(sprintf("Wilcoxon pareado (9 cortes): p = %.3f\n", w$p.value))
}
