# Segunda tanda de ensambles "locos".
# uso: Rscript ensamble_locos2.R <carpeta base (v2, v7, v3, oro)> <carpeta de salida>
suppressWarnings(suppressMessages(library(data.table)))
a <- commandArgs(TRUE); E <- a[1]; O <- a[2]
dir.create(O, showWarnings= FALSE, recursive= TRUE)

lee <- function(dir, prefijo) {
  fs <- list.files(dir, pattern= "^pred_.*[.]txt$", full.names= TRUE)
  P <- NULL
  for (f in fs) {
    p <- fread(f, select= c("numero_de_cliente", "prob"))
    setnames(p, "prob", paste0(prefijo, "_", sub("^pred_(.*)[.]txt$", "\\1", basename(f))))
    P <- if (is.null(P)) p else merge(P, p, by= "numero_de_cliente")
  }
  P
}
P <- Reduce(function(x, y) merge(x, y, by= "numero_de_cliente"),
            list(lee(file.path(E, "v2"), "v2"), lee(file.path(E, "v7"), "v7"), lee(file.path(E, "v3"), "v3")))
puesto <- function(x) frank(-x, ties.method= "average")      # 1 = el mas probable
cols <- setdiff(names(P), "numero_de_cliente")
POS <- as.matrix(P[, lapply(.SD, puesto), .SDcols= cols])
m <- rowMeans(POS)
cat("corridas de C:", ncol(POS), "\n")

graba <- function(ids, nombre) {
  out <- data.table(numero_de_cliente= P$numero_de_cliente, Predicted= as.integer(P$numero_de_cliente %in% ids))
  f <- file.path(O, sprintf("KA_%s_%d.csv", nombre, length(ids)))
  fwrite(out, f)
  cat(sprintf("  %-38s envios %d - comparte %.1f%% con C\n", basename(f), sum(out$Predicted),
              100 * mean(ids %in% P$numero_de_cliente[order(m)][1:length(ids)])))
}
top <- function(score, n) P$numero_de_cliente[order(score)][1:n]   # score: menor = mejor

# 1. democracia de cortes: cada corrida vota por sus 10.000; desempata el puesto promedio
votos <- rowSums(POS <= 10000)
graba(P$numero_de_cliente[order(-votos, m)][1:10000], "democracia")
cat("   clientes con todos los votos:", sum(votos == ncol(POS)), "- con al menos uno:", sum(votos > 0), "\n")
# 2. fusion recíproca de rankings (RRF, k = 60)
rrf <- rowSums(1 / (60 + POS))
graba(P$numero_de_cliente[order(-rrf)][1:10000], "fusion_reciproca")
# 3. v2 manda: la v2 pesa el doble
w <- ifelse(startsWith(cols, "v2_"), 2, 1)
graba(top(as.vector(POS %*% w) / sum(w), 10000), "v2_manda")
# 4. los titulares: las 5 corridas de la v2 con mejor puntaje publico
tit <- paste0("v2_", c(570001, 333331, 210011, 910009, 150001))
mt <- rowMeans(POS[, tit])
graba(top(mt, 9500), "titulares")
graba(top(mt, 10000), "titulares")
# 5. la semilla de oro: la 570001 en todas sus versiones
G <- lee(file.path(E, "oro"), "oro")
G <- G[match(P$numero_de_cliente, G$numero_de_cliente)]
cat("   semilla de oro, corridas:", paste(setdiff(names(G), "numero_de_cliente"), collapse= ", "), "\n")
mg <- rowMeans(as.matrix(G[, lapply(.SD, puesto), .SDcols= setdiff(names(G), "numero_de_cliente")]))
graba(top(mg, 9500), "semilla_de_oro")
graba(top(mg, 10000), "semilla_de_oro")
