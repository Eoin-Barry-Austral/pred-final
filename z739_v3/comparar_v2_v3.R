# Compara v2 (exp 9800, BO por AUC) contra v3 (exp 9900, BO por ganancia en 4 meses)
# con los puntajes publicos de Kaggle, semilla por semilla (diseño pareado).
# uso: Rscript comparar_v2_v3.R <kaggle_submissions.csv> [exp_v2] [exp_v3]
#   el csv es el que guarda la v3 en exp/WF9900_s<semilla>/kaggle_submissions.csv
suppressWarnings(suppressMessages(library(data.table)))
a <- commandArgs(TRUE)
exp_v2 <- if (length(a) >= 2) a[2] else "9800"
exp_v3 <- if (length(a) >= 3) a[3] else "9900"

k <- fread(a[1])
setnames(k, tolower(gsub("[^A-Za-z]", "", names(k))))   # publicScore -> publicscore, etc.
k <- k[grepl("envios=", description)]
k[, envios := as.integer(sub(".*envios=([0-9]+).*", "\\1", description))]
k[, semilla := sub(".*semilla=([0-9]+).*", "\\1", description)]
k[, exp := sub(".*exp=([0-9]+).*", "\\1", description)]
k[, publico := as.numeric(publicscore)]
k <- k[exp %in% c(exp_v2, exp_v3) & !is.na(publico)]
# si un mismo archivo se subio dos veces, el ultimo
k <- k[order(date)][, .SD[.N], by= .(exp, semilla, envios)]

# por semilla: promedio de los 9 cortes
S <- k[, .(cortes= .N, promedio= mean(publico)), by= .(exp, semilla)]
W <- dcast(S, semilla ~ exp, value.var= "promedio")
setnames(W, c(exp_v2, exp_v3), c("v2", "v3"))
W <- W[!is.na(v2) & !is.na(v3)]
W[, dif := v3 - v2]
cat("\nPromedio publico de los 9 cortes, por semilla (pares completos):\n")
print(W[order(-dif)], digits= 5)

if (nrow(W) >= 5) {
  t <- wilcox.test(W$v3, W$v2, paired= TRUE, conf.int= TRUE, exact= TRUE)
  cat(sprintf("\nWilcoxon pareado (n = %d): p = %.4f\n", nrow(W), t$p.value))
  cat(sprintf("Diferencia tipica v3 - v2 (Hodges-Lehmann): %+.2f puntos, IC 95%% [%+.2f, %+.2f]\n",
              t$estimate, t$conf.int[1], t$conf.int[2]))
  cat(sprintf("v3 gana en %d de %d semillas; media de la diferencia %+.2f\n",
              sum(W$dif > 0), nrow(W), mean(W$dif)))
} else cat("\nPocos pares completos todavia (", nrow(W), ") para el test\n")

cat("\nPromedio por corte (todas las semillas de cada version):\n")
print(dcast(k, envios ~ exp, value.var= "publico", fun.aggregate= mean), digits= 5)
