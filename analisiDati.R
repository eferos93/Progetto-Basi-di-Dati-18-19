install.packages("odbc")
install.packages("RMariaDB")
library(RMariaDB)
con <- dbConnect(
  drv = RMariaDB::MariaDB(), 
  username = "root",
  password = "root", 
  host = "localhost", 
  dbname = "ospedale",
  port = 3307
)

tabPazienti <- dbGetQuery(con, "SELECT reparto, paziente FROM occupa_attualmente ORDER BY reparto")
tabMedici <- dbGetQuery(con, "SELECT reparto, medico FROM afferisce ORDER BY reparto")



barplot(table(tabPazienti$reparto),
        main="Numero pazienti per reparto",
        xlab="Reparti",ylab="Numero pazienti",
        ylim = c(0,16),
        cex.names = 0.7
)

barplot(table(tabMedici$reparto),
        main="Numero medici per reparto",
        xlab="Reparti",ylab="Numero pazienti",
        ylim = c(0,16),
        cex.names = 0.7
)

letti <- dbGetQuery(con, "SELECT SUM(letti_disponibili) AS n_letti_disponibili, SUM(letti_occupati) AS n_letti_occupati FROM reparto")
temp <- dbGetQuery(con, "SELECT COUNT(*) AS totale_letti FROM letto")
m <- data.matrix(letti)
names <- c("letti disponibili", "letti occupati")
numTotLetti <- temp$totale_letti

pie(m, labels = names, main="Grafico a torta letti")


