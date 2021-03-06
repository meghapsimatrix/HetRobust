library(plyr)
library(Pusto)
rm(list=ls())
source("SSTP.R")

#-----------------------------
# Data-generating model
#-----------------------------

estimate_model <- function(Y, X, trueB, whichX) {
  
  X <- X[, whichX]
  B <- trueB[whichX]
  
  n <- nrow(X)
  p <- ncol(X)
  
  M <- solve(t(X) %*% X)
  X_M <- X %*% M
  coefs <- colSums(Y * X_M)
  e <- Y - as.vector(X %*% coefs)
  
  H <- X_M %*% t(X)
  h <- diag(H)
  
  values <- list(X = X, Y = Y, B = B, X_M = X_M, H = H, h = h, e = e, coefs = coefs, n = n, p = p, M = M)
  
  return(values)
}

gdm <- function(n = 25, B = c(1, 1, 1, 1, 0, 0), Estruct = "E0", whichX = c(T, T ,T ,T ,T ,F), Edist = "En") {
  
  # Distributions used in generating data
  b1 <- runif(n, 0, 1)
  b2 <- rnorm(n, 0, 1)
  b3 <- rchisq(n, 1)
  b4 <- rnorm(n, 0, 1)
  b5 <- runif(n, 0, 1)
  
  # Four independant variables based on distributions
  x0 <- 1
  x1 <- 1 + b1
  x2 <- 3 * b1 + .6 * b2
  x3 <- 2 * b1 + .6 * b3
  x4 <- .1 * x1 + .9 * x3 - .8 * b4 + 4 * b5
  x2[x2 < -2.5] <- -2.5
  x4[x4 < -2.5] <- -2.5
  
  # One dummy variable created by splitting x2
  xD <- ifelse(x2 > 1.6, 1, 0)
  
  # X matrix
  X <- cbind(x0, x1, x2, x3, x4, xD)
  
  # Three types of homoscedastistic error distributions:
  Edist <- switch(Edist,
                  En = rnorm(n, 0, 1),
                  Ech = (rchisq(n, 5) - 5) / sqrt(10),
                  Et = rt(n, 5))
  
  # Seven types of error structures
  error <- switch(Estruct,
                  E0 = Edist,
                  E1 = sqrt(x1) * Edist,
                  E2 = sqrt(x3 + 1.6) * Edist,
                  E3 = sqrt(x3) * sqrt(x4 + 2.5) * Edist,
                  E4 = sqrt(x1) * sqrt(x2 + 2.5) * sqrt(x3) * Edist,
                  E5 = ifelse(xD == 1, 1.5 * Edist, Edist),
                  E6 = ifelse(xD == 1, 4 * Edist, Edist)
  )
  
  # Generate DV
  Y <- as.vector(X %*% B) + error
  
  values <- estimate_model(Y, X, B, whichX)
  
  return(values)
}

#-----------------------------------
# simulation driver
#-----------------------------------

runSim <- function(iterations, n, B, whichX, Estruct, Edist, HC, tests, seed = NULL) {
  require(plyr)
  require(reshape2)
  
  B <- as.numeric(unlist(strsplit(B, " ")))
  whichX <- as.logical(unlist(strsplit(whichX, " ")))
  HC <- as.character(unlist(strsplit(HC, " ")))
  tests <- as.character(unlist(strsplit(tests, " ")))
  
  if (!is.null(seed)) set.seed(seed)
  
  reps <- rdply(iterations, {
    model <- gdm(n = n, 
                 B = B, 
                 Estruct = Estruct,
                 whichX = whichX,
                 Edist = Edist)
    
    ldply(HC, estimate, tests = tests, model = model)
  })
  
  # performance calculations
  
  if ("saddle" %in% tests) tests <- c(tests[tests != "saddle"], paste0("saddle_V",1:2))
  
  reps <- melt(reps, id.vars = c("HC","coef","criterion"), measure.vars = tests, variable.name = "test")
  ddply(reps, .(HC,coef,criterion,test), summarize, 
        p01 = mean(ifelse(is.na(value), F, value < .01)),
        p05 = mean(ifelse(is.na(value), F, value < .05)),
        p10 = mean(ifelse(is.na(value), F, value < .10)),
        percentNA = mean(is.na(value)))
}

#-----------------------------
# Run Rothenberg Edgeworth Correction
#-----------------------------


testmod <- lapply(c(25, 50, 100, 250, 500), gdm)

pvals <- lapply(testmod, estimate, HC = "HC0", tests = c("Satt","saddle","edgeKC","edgeR"))
pvals[[1]][1:5,4:9]
pvals[[1]][6:10,4:9]

model <- testmod[[5]]
HC <- "HC2"
M <- model$M
X <- model$X
e <- as.vector(model$e)
h <- model$h
n <- model$n
p <- model$p
coefs <- as.vector(model$coefs)
B <- model$B
H <- model$H
X_M <- model$X_M

omega <- switch(HC,
                HC0 = 1,
                HC1 = sqrt((n - p) / n),
                HC2 = sqrt(1 - h),
                HC3 = (1 - h),
                HC4 = (1 - h)^(pmin(h * n / p, 4) / 2),
                HC4m = (1 - h)^((pmin(h * n / p, 1) + pmin(h * n / p, 1.5))/2),
                HC5 = (1 - h)^(pmin(h * n / p, pmax(4, .7 * n * max(h) / p)) / 4)
)

V_b <- colSums((X_M * e / omega)^2)
coefs_to_test <- c(coefs - B, coefs)

tHC <- coefs_to_test / sqrt(V_b)

sapply(1:p, nu_q, X_M = X_M, H = H, h = h)
Satterthwaite(V_b, X_M, omega, e, H, n, p)
(nu <- 6 * V_b^2 / colSums((X_M * e / omega)^4))

# model-based
q_ii <- -h
a_vec <- 0
(b_vec <- colSums((X_M / omega)^2 * q_ii) / colSums(X_M^2) - 1)
t_adj1 <- abs(tHC) / 2 * (2 - (1 + tHC^2) / nu + a_vec * (tHC^2 - 1) + b_vec)
p_edgeR1 <- 2 * (1 - pnorm(t_adj1))
cbind(tHC, t_adj1, p_edgeR1)

# empirical
sigma <- (e/omega)^2
I_H <- diag(nrow=n) - H
q_ii <- colSums(I_H^2 * sigma) - sigma
z_mat <- I_H %*% (sigma * X_M)
(a_vec <- colSums((X_M * z_mat / omega)^2) / V_b^2)
(b_vec <- colSums((X_M / omega)^2 * q_ii) / V_b - 1)
t_adj2 <- abs(tHC) / 2 * (2 - (1 + tHC^2) / nu + a_vec * (tHC^2 - 1) + b_vec)
p_edgeR2 <- 2 * (1 - pnorm(t_adj2))
cbind(tHC, t_adj2, p_edgeR2)
