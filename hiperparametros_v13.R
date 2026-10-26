# Hiperparametros de la v13, escritos a la vista: parte de la mejor fila de la BO de
# la v2 de cada semilla y los ajusta para entrenar con 4 veces menos filas (5% de los
# CONTINUA, contra 20% en la BO de la v2):
#   minimo de clientes por hoja / 4, hojas por arbol / 2, learning rate / 2, arboles x 2
# En el BO_log, arboles, hojas y learning rate estan en log2 (el script hace 2^x).
# uso: Rscript hiperparametros_v13.R <carpeta con BO_log_<semilla>.txt de la v2> <carpeta de salida>
suppressWarnings(suppressMessages(library(data.table)))
a <- commandArgs(TRUE); D <- a[1]; O <- a[2]
dir.create(O, showWarnings= FALSE, recursive= TRUE)
res <- list()
for (f in list.files(D, pattern= "^BO_log_[0-9]+[.]txt$", full.names= TRUE)) {
  s <- sub("^BO_log_([0-9]+)[.]txt$", "\\1", basename(f))
  b <- fread(f)
  setorder(b, -y, -num_iterations)
  x <- b[1]
  n <- copy(x)
  n[, num_iterations := num_iterations + 1]                # arboles x 2
  n[, num_leaves := num_leaves - 1]                        # hojas / 2
  n[, learning_rate := learning_rate - 1]                  # learning rate / 2
  n[, min_data_in_leaf := round(min_data_in_leaf / 4)]     # minimo por hoja / 4
  fwrite(n, file.path(O, sprintf("BO_log_%s.txt", s)), sep= "\t")
  res[[s]] <- data.table(semilla= s,
    arboles= sprintf("%d -> %d", round(2^x$num_iterations), round(2^n$num_iterations)),
    hojas= sprintf("%d -> %d", round(2^x$num_leaves), round(2^n$num_leaves)),
    learning_rate= sprintf("%.4f -> %.4f", 2^x$learning_rate, 2^n$learning_rate),
    min_por_hoja= sprintf("%d -> %d", round(x$min_data_in_leaf), round(n$min_data_in_leaf)))
}
print(rbindlist(res))
