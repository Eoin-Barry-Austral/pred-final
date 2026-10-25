# Ensambles "locos" pensados desde la matriz de confusion (perder un BAJA+2 cuesta
# 39 veces mas que mandarle de mas a alguien). Usa las predicciones de cada corrida.
# uso: Rscript ensamble_locos.R <carpeta base con v2, v7, v3, v11> <carpeta de salida>
suppressWarnings(suppressMessages(library(data.table)))
a <- commandArgs(TRUE); E <- a[1]; O <- a[2]
dir.create(O, showWarnings= FALSE, recursive= TRUE)

lee_version <- function(v) {
  fs <- list.files(file.path(E, v), pattern= "^pred_[0-9]+[.]txt$", full.names= TRUE)
  P <- NULL
  for (f in fs) {
    p <- fread(f, select= c("numero_de_cliente", "prob"))
    col <- paste0(v, "_", sub("^pred_([0-9]+)[.]txt$", "\\1", basename(f)))
    setnames(p, "prob", col)
    P <- if (is.null(P)) p else merge(P, p, by= "numero_de_cliente")
  }
  P
}
V <- lapply(c("v2", "v7", "v3", "v11"), lee_version); names(V) <- c("v2", "v7", "v3", "v11")
P <- Reduce(function(x, y) merge(x, y, by= "numero_de_cliente"), V)
n <- nrow(P)
puesto <- function(x) frank(-x, ties.method= "average")      # 1 = el mas probable
base <- unlist(lapply(V[c("v2", "v7", "v3")], function(x) setdiff(names(x), "numero_de_cliente")))
POS <- as.matrix(P[, lapply(.SD, puesto), .SDcols= base])
m <- rowMeans(POS); s <- apply(POS, 1, sd)
cat("clientes:", n, "- corridas en la base (v2+v7+v3):", length(base), "\n")

graba <- function(orden, nombre, envios) {
  sel <- P$numero_de_cliente[orden[1:envios]]
  out <- data.table(numero_de_cliente= P$numero_de_cliente, Predicted= as.integer(P$numero_de_cliente %in% sel))
  f <- file.path(O, sprintf("KA_loco_%s_%d.csv", nombre, envios))
  fwrite(out, f)
  cat(sprintf("  %-40s envios %d - comparte %.1f%% con C (mismo corte)\n", basename(f), sum(out$Predicted),
              100 * mean(sel %in% P$numero_de_cliente[order(m)][1:envios])))
}

# 1. premiar la duda: puesto promedio corrido hacia arriba segun cuanto discrepan
graba(order(m - s), "1_premiar_duda", 10000)
graba(order(m - s), "1_premiar_duda", 10500)
# 2. castigar la duda: solo entra si todos coinciden
graba(order(m + s), "2_castigar_duda", 10000)
# 3. voto optimista: el mejor puesto entre los ensambles de cada version
pv <- sapply(V, function(x) { cols <- setdiff(names(x), "numero_de_cliente")
  r <- rowMeans(as.matrix(P[, lapply(.SD, puesto), .SDcols= cols])); frank(r, ties.method= "first") })
graba(order(apply(pv, 1, min), m), "3_voto_optimista", 10000)
# 4. rescate de la v11: C en 9.500 + los mejores de la v11 que C deja afuera
c9500 <- order(m)[1:9500]
resto <- setdiff(order(pv[, "v11"]), c9500)
graba(c(c9500, resto), "4_rescate_v11", 10000)
# 5. que la ganancia decida cuantos: P(BAJA+2) > 25.000 / 1.000.000 = 2,5%.
# La prob de la v2 es P(BAJA+1 o BAJA+2) (final training con 100% de los datos);
# BAJA+1 y BAJA+2 son ~mitad y mitad, asi que P(BAJA+2) ~ prob / 2 -> umbral prob > 0,05
pv2 <- rowMeans(as.matrix(P[, setdiff(names(V$v2), "numero_de_cliente"), with= FALSE]))
for (u in c(0.04, 0.05, 0.06)) cat(sprintf("  umbral prob v2 > %.2f -> %d clientes\n", u, sum(pv2 > u)))
N5 <- sum(pv2 > 0.05)
graba(order(m), "5_corte_por_ganancia", N5)
