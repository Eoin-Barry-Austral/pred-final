# Pares v2 vs v3 por semilla, desde las tablas de puntajes publicos del repo.
# uso (desde la raiz del repo): Rscript comparar_pares.R
suppressWarnings(suppressMessages(library(data.table)))
a <- fread("z739_v2/resultados/puntajes_publicos.tsv")
b <- fread("z739_v3/resultados/puntajes_publicos.tsv")
m <- merge(a, b, by= c("semilla", "envios"), suffixes= c("_v2", "_v3"))
centro <- c(9000, 9500, 10000, 10500)
r <- m[, .(v2= mean(publico_v2), v3= mean(publico_v3),
           centro_v2= mean(publico_v2[envios %in% centro]), centro_v3= mean(publico_v3[envios %in% centro])),
       by= semilla]
r[, `:=`(dif= v3 - v2, dif_centro= centro_v3 - centro_v2)]
print(r[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 1) else x)])
cat(sprintf("\nv3 peor que su par de la v2 (9 cortes): %d de %d   |   en el centro (9.000-10.500): %d de %d\n",
            sum(r$dif < 0), nrow(r), sum(r$dif_centro < 0), nrow(r)))
cat(sprintf("diferencia media: %+.1f (9 cortes), %+.1f (centro)\n", mean(r$dif), mean(r$dif_centro)))
