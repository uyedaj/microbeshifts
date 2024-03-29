## Cyanofunctions
## Cleaning and preparing the data
## This function should likely receive some attention from Carrine!
clean.data <- function(){
  ## Read in character matrix and cell diameter data
  cyanodat <- read.table("../data/charactermatrix.txt")
  celldiam <- read.table("../data/celldiameter.msq")
  rownames(celldiam) <- celldiam[,1]
  celldiam <- celldiam[,-1]
  rownames(cyanodat) <- cyanodat[,1]
  cyanodat <- cyanodat[,-1]
  ## Read in the characters and states metadata
  states <- readLines("../data/charactersandstates.txt")
  ## Clean the text so that they can be used as column names
  states[grep(".", states)]
  heads <- strsplit(states[grep(".", states)], "\\. ", perl=TRUE)
  colnames(cyanodat) <- sapply(gsub("-", "", gsub(" ", "_", as.data.frame(do.call(rbind, heads[sapply(heads, length)==2]))[,2])), function(x) substr(x, 1, nchar(x)-2))
  cyanodat$celldiam_min <- celldiam[,1]
  cyanodat$celldiam_mean <- celldiam[,2]
  cyanodat$celldiam_max <- celldiam[,3]
  cyanodat[cyanodat=="?"] <- NA
  ## Determine what set of traits will be kept
  whichcol <- c('Thermophilic', 'Nonfreshwater_habitat', 'Akinetes', 'Heterocysts', 'Nitrogen_fixation', 'Morphology',
              'Habit', 'Freeliving', 'Mats', 'Epi/Endolithic',  'Epiphytic', 'Periphytic', 'Motility', 'Hormogonia', 
              'Gas_vesicles', 'False_Branching', 'True_Branching', 'Fission_in_multiple_planes', 'Uniseriate_trichome', 
              'Multiseriate_trichomes', 'Baeocytes', 'Extracellular_sheath', 'Mucilage', 'celldiam_mean')
  dat <- cyanodat
  ## Decisions on how to group ambiguous or multistate characters
  dat$Morphology[cyanodat$Morphology=="0&2"] <- 0
  dat$Motility[cyanodat$Motility=="2"] <- 1
  dat$Multiseriate_trichomes[cyanodat$Multiseriate_trichomes!=0] <- 1
  dat$Mucilage[cyanodat$Mucilage!=0] <- 1
  dat$Habit[cyanodat$Habit=="0&1"] <- 0
  dat <- dat[,whichcol]
  dat$Pelagic <- as.numeric(dat$Nonfreshwater_habitat==1 & dat$Habit==0)
  dat$celldiam_mean <- as.numeric(as.numeric(as.character(cyanodat$celldiam_mean))>=3.5)
  return(dat)
}

## 
make.bisse.fns <- function(tree, dat){
  ## set branch lengths to by
  tree$edge.length <- tree$edge.length/1000
  
  ## Combine tree 
  tdcy <- make.treedata(tree, dat, name_column=0)
  rownames(tdcy$dat) <- tdcy$phy$tip.label
  colnames(tdcy$dat) <- gsub("/", "_", colnames(tdcy$dat), fixed=TRUE)
  nc <- ncol(tdcy$dat)
  tdcyList <- lapply(1:nc, function(x) select(tdcy, x))
  tdcyList <- lapply(1:nc, function(x) filter_(tdcyList[[x]], paste("!is.na(",names(tdcyList[[x]]$dat),")", sep="")))
  
  ## Set global birth-death parameters
  bd.lik <- make.bd(tdcy$phy)
  bd.est <- find.mle(bd.lik, x.init=c(5,0))
  lambda <<- bd.est$par[1]
  mu <<- bd.est$par[2]
  
  ## Make the functions
  bisse.fns <- lapply(1:nc, function(x) make.bisse.t(tdcyList[[x]]$phy, setNames(tdcyList[[x]]$dat[[1]], attributes(tdcyList[[x]])$tip.label), functions=c(rep("constant.t",4), rep("stepf.t", 2)))) 
  notime.fns <- lapply(1:nc, function(x) make.bisse(tdcyList[[x]]$phy, setNames(tdcyList[[x]]$dat[[1]], attributes(tdcyList[[x]])$tip.label)))
  ARD.notime.fns <- lapply(notime.fns, function(x) constrain(x, lambda0~lambda, lambda1~lambda, mu0~mu, mu1~mu))
  ARD.R2.fns <- lapply(bisse.fns, function(x) constrain2(x, lambda0~lambda, lambda1~lambda, mu0~mu, mu1~mu, q10.y1~r1*q10.y0, q01.y1~r2*q01.y0, q01.tc ~ q10.tc, extra=c('r1', 'r2')))
  
  fns <- list(bisse=bisse.fns, notime=notime.fns, ARD.notime=ARD.notime.fns, ARD.R2=ARD.R2.fns, tdList=tdcyList)
  return(fns)
  
}

fullProfiles <- function(n, fns, res=NULL){
  
}

fitFns <- function(n, fns, tds, res=NULL){
  nc <- length(fns)
  for(j in 1:n) {
    fits <- foreach(i=1:nc) %dopar% {
      find.mle(fns[[i]], x.init=start.gen(fns[[i]], tds[[i]]), method="optim", lower=lower.gen(fns[[i]], tds[[i]]), upper=upper.gen(fns[[i]], tds[[i]]) )
    }
    ## Create a summary table
    parests <- do.call(rbind, lapply(fits, function(x) as.data.frame(matrix(c(x$par, x$lnLik, x$message), nrow=1))))
    colnames(parests) <- c(argnames(fns[[1]]), "lnL", "message")
    ## Save only the best-fitting indpendent runs
    if(is.null(res)){
      res <- parests
    } else {
      replace <- which(defactor(parests$lnL) > defactor(res$lnL))
      if(length(replace) > 0){
        res[-ncol(res)] <- apply(res[-ncol(res)], 2, defactor)
        parests[-ncol(parests)] <- apply(parests[-ncol(parests)], 2, defactor)
        res[replace, ] <- parests[replace, ]
        #cyFit.best[-ncol(cyFit.best)] <- apply(cyFit.best[-ncol(cyFit.best)], 2, defactor)
        #parests[-ncol(parests)] <- apply(parests[-ncol(parests)], 2, defactor)
        #cyFit.best[replace, ] <- parests[replace, ]
      }
      print(replace)
      
    }
  }
  return(res)
}

profiles <- function(n, fns, tds, starts, res=NULL, seq=seq(0.1, 3.7, 0.2)){
  ## Start only over seq1, add seq2 if it looks productive
  nc <- length(fns)
  if(is.null(res)){
      res <- list()
      seqFns <- lapply(fns, function(x) lapply(seq, function(y) {ft <<- y; constrain2(x, q10.tc~ft, extra=c("r1", "r2"))}))
      for(i in 1:nc){
        tmpfns <- seqFns[[i]]
        cl <- makeCluster(8)
        clusterEvalQ(cl,c(require(geiger), require(diversitree), require(optimx), source("./shiftfunctions.R"), source("./cyanofunctions.R")))
        # Use function clusterExport() to send dataframes or other objects to each core
        clusterExport(cl, varlist=c("tmpfns", "seq", "starts", "tds", "lambda", "mu", "i"))
        registerDoParallel(cl)
        tmp <-  (j=1:length(seq)) %dopar% {
          fn <<- tmpfns[[j]]
          ft <<- seq[j]
          #fn <- constrain2(fn, q10.tc~ft, extra=c("r1", "r2"))
          startx <- runif(4, 0.5, 2)*c(1, 1, starts[i, 1], starts[i, 2])
          return(list(fn,startx))
          #optimx(c(0.1,0.1,0.1,0.1), fn, lower=c(0,0,0,0), control=list(maximize=TRUE, all.methods=TRUE))
          #find.mle(fn, x.init=startx, method="subplex")
        }
        res[[i]] <- tmp
        rm(tmp)     
        gc()
      }
  } else {
    for(i in 1:nc){
      tmp <- foreach(j=1:length(seq)) %dopar% {
        fn <- fns[[i]]
        ft <<- seq[j]
        fn <- constrain2(fn, q10.tc~ft, extra=c("r1", "r2"))
        if(j==1){
          startx <- runif(4, 0.5, 2)*c(1, 1, starts[i, 1], starts[i, 2])
        } else {
          startx <- runif(4, 0.5, 2)*c(1, 1, starts[i, 1], starts[i, 2]) #c(tmp[[j-1]]$par)
        }
        find.mle(fn, x.init=startx, method="subplex")
      }
      replace <- which(sapply(tmp, function(x) x$lnLik) > sapply(res[[i]], function(x) x$lnLik))
      if(length(replace)>0){
        res[[i]][replace] <- tmp[replace]
      }
    }
  }
  res
}