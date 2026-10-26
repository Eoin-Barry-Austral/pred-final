# Hiperparametros uniformes para todas las semillas: la mediana de la mejor fila de
# la BO de la v2 de cada semilla (en la escala del BO_log: arboles, hojas, learning
# rate, min_sum_hessian y lambdas en log2).
# uso: Rscript hiperparametros_uniformes.R <carpeta con BO_log_<semilla>.txt> <archivo de salida>
suppressWarnings(suppressMessages(library(data.table)))
a <- commandArgs(TRUE)
fs <- list.files(a[1], pattern= "^BO_log_[0-9]+[.]txt$", full.names= TRUE)
b <- rbindlist(lapply(fs, function(f) { x <- fread(f); setorder(x, -y, -num_iterations); x[1] }), fill= TRUE)
cols <- c("num_iterations", "num_leaves", "learning_rate", "feature_fraction",
          "min_sum_hessian_in_leaf", "min_data_in_leaf", "lambda_l1", "lambda_l2")
med <- b[, lapply(.SD, median), .SDcols= cols]
med[, min_data_in_leaf := round(min_data_in_leaf)]
med[, y := 1]
fwrite(med, a[2], sep= "\t")
cat(sprintf("semillas: %d\n", nrow(b)))
cat(sprintf("arboles %d | hojas %d | learning_rate %.4f | feature_fraction %.3f | min_sum_hessian %.4f | min_data_in_leaf %d | lambda_l1 %.4f | lambda_l2 %.4f\n",
  round(2^med$num_iterations), round(2^med$num_leaves), 2^med$learning_rate, med$feature_fraction,
  2^med$min_sum_hessian_in_leaf, med$min_data_in_leaf, 2^med$lambda_l1, 2^med$lambda_l2))
cat("rango entre semillas:\n")
print(b[, .(arboles= range(round(2^num_iterations)), hojas= range(round(2^num_leaves)),
            lr= round(range(2^learning_rate), 4), min_data= range(round(min_data_in_leaf)))])
