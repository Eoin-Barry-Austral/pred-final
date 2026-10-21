# prueba local del bloque "FE v6" con un dataset inventado
suppressMessages(library(data.table))
lineas <- readLines("z739_v6/z739_final_senior_v6.R", warn= FALSE)
ini <- grep('^if \\(Sys.getenv\\("FE_NUEVAS"', lineas)
fin <- grep("columnas nuevas -", lineas) + 2
bloque <- lineas[ini:fin]
stopifnot(tail(bloque, 1) == "}")

marca <- function(...) cat("MARCA |", ..., "\n")
llamadas <- list()
TendenciaYmuchomas <- function(dataset, cols, ventana, ...) {   # la real esta en C; aca solo registro
  llamadas[[length(llamadas) + 1]] <<- list(ventana= ventana, n= length(cols), args= list(...))
  for (c in cols) dataset[, paste0(c, "_min", ventana) := 0]
}

set.seed(1)
cl <- rep(1:4, each= 8); mes <- rep(c(202101:202108), 4)
dataset <- data.table(numero_de_cliente= cl, foto_mes= mes,
  mpayroll= c(100,100,100,0,0,0,100,0,  0,0,0,0,0,0,0,0,  50,50,50,50,50,50,50,50,  NA,10,0,0,10,0,0,0),
  mpayroll2= 0,
  ctrx_quarter= c(5,4,0,0,0,3,0,0,  0,0,0,0,0,0,0,0,  9,9,9,9,9,9,9,9,  1,0,0,NA,0,0,1,0),
  mcaja_ahorro= c(rep(c(10, 20), 16)))
dataset[, ctrx_quarter_lag1 := shift(ctrx_quarter), by= numero_de_cliente]
dataset[, ctrx_quarter_lag2 := shift(ctrx_quarter, 2), by= numero_de_cliente]
setorder(dataset, -foto_mes)   # desordenado a proposito

Sys.setenv(FE_NUEVAS= "1")
eval(parse(text= bloque))

print(dataset[, .(numero_de_cliente, foto_mes, mpayroll, sueldo_total, perdio_sueldo, sueldo_vs_lag1,
                  sueldo_total_mesesencero, sueldo_total_ceros6, ctrx_quarter, ctrx_quarter_mesesencero,
                  ctrx_quarter_ceros6, ctrx_quarter_acel, mcaja_ahorro_frec)])
str(llamadas)

# controles
stopifnot(dataset[numero_de_cliente == 1, perdio_sueldo] %in% c(NA, 0L, 1L))
stopifnot(identical(dataset[numero_de_cliente == 1, perdio_sueldo], c(0L, 0L, 0L, 1L, 0L, 0L, 0L, 1L)))
stopifnot(identical(dataset[numero_de_cliente == 1, ctrx_quarter_mesesencero], c(0L, 0L, 1L, 2L, 3L, 0L, 1L, 2L)))
stopifnot(identical(dataset[numero_de_cliente == 2, ctrx_quarter_mesesencero], 1:8))
stopifnot(dataset[numero_de_cliente == 4 & foto_mes == 202104, ctrx_quarter_mesesencero] == 0L)  # NA corta la racha
stopifnot(all(is.na(dataset[numero_de_cliente == 1, ctrx_quarter_ceros6][1:5])))
stopifnot(dataset[numero_de_cliente == 1 & foto_mes == 202106, ctrx_quarter_ceros6] == 3)
stopifnot(dataset[numero_de_cliente == 2 & foto_mes == 202108, ctrx_quarter_ceros6] == 6)
stopifnot(all(dataset$mcaja_ahorro_frec == 4L))
stopifnot(dataset[numero_de_cliente == 1 & foto_mes == 202103, ctrx_quarter_acel] == 0 - 2 * 4 + 5)
cat("\nTODOS LOS CONTROLES OK\n")
