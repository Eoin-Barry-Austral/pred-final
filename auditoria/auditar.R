# Auditoria: lo que cada corrida dice en su log que uso, contra lo que tenia que usar.
# Se mira solo el ULTIMO intento de cada log (desde la ultima linea "inicio:"), salvo
# el conteo de modelos finales, que suma semillas unicas de todos los intentos.
suppressMessages(library(data.table))
d <- "C:/tmp/lab1/auditoria"
esperado <- list(
  "9800" = list(version= "v2", bo= "AUC", ft= 9,  desv= "2.5 (fijo en el script)", excl= FALSE, ga= FALSE),
  "9900" = list(version= "v3", bo= "ganancia 4 meses", ft= 30, desv= "2.5 (fijo)", excl= FALSE, ga= FALSE),
  "9950" = list(version= "v4", bo= "ganancia 202107 + ES", ft= 30, desv= "2", excl= FALSE, ga= FALSE),
  "9850" = list(version= "v5", bo= "AUC", ft= 20, desv= "2", excl= FALSE, ga= FALSE),
  "9700" = list(version= "v6", bo= "AUC", ft= 20, desv= "2.5", excl= FALSE, ga= FALSE),
  "9600" = list(version= "v7", bo= "AUC", ft= 20, desv= "2", excl= TRUE,  ga= TRUE))
r <- list()
for (f in list.files(d, pattern= "^log_WF[0-9]+_s[0-9]+[.]txt$", full.names= TRUE)) {
  exp <- sub(".*log_WF([0-9]+)_s.*", "\\1", f); sem <- sub(".*_s([0-9]+)[.]txt$", "\\1", f)
  x <- readLines(f, warn= FALSE)
  ini <- tail(grep("\\| inicio:", x), 1); if (!length(ini)) ini <- 1
  u <- x[ini:length(x)]
  g <- function(p) { l <- grep(p, u, value= TRUE); if (length(l)) sub(".*\\| ", "", tail(l, 1)) else "" }
  modelos <- length(unique(sub(".*semilla ([0-9]+).*", "\\1", grep("modelo final listo", x, value= TRUE))))
  r[[f]] <- data.table(version= esperado[[exp]]$version, semilla= sem,
    terminado= any(grepl("\\| TERMINADO", u)),
    intentos= length(grep("\\| inicio:", x)),
    canaritos= sub("canaritos: ratio 0.2 desvios ", "", g("canaritos: ratio")),
    bo= g("BO por ganancia|optimizacion bayesiana:|BO con early"),
    meses_bo= g("BO: entrena con"),
    semillerio= g("semillerio:"),
    modelos= modelos,
    genetica= g("genetica: (agregadas|ninguna)"),
    columnas= sub(".*: ", "", g("checkpoint despues de canaritos|dataset listo")),
    esperado_ft= esperado[[exp]]$ft, esperado_canaritos= esperado[[exp]]$desv,
    esperado_ga= esperado[[exp]]$ga)
}
R <- rbindlist(r)
setorder(R, version, semilla)
options(width= 250)
print(R[, .(version, semilla, terminado, intentos, canaritos, esp_can= esperado_canaritos, semillerio, modelos, esp_ft= esperado_ft,
            meses_bo= substr(meses_bo, 1, 40), genetica= substr(genetica, 1, 45))])
