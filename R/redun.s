# $Id$
redun <- function(formula, data, subset,
                  r2=.9, type=c('ordinary','adjusted'),
                  nk=3, tlinear=TRUE, pr=FALSE, ...)
{
  acall   <- match.call()
  type    <- match.arg(type)

  if(!inherits(formula,'formula'))
    stop('formula must be a formula')

  a <- as.character(formula)
  if(length(a)==2 && a[1]=='~' && a[2]=='.')
    {
      if(length(list(...))) data <- dataframeReduce(data, ...)
      nam <- names(data)
      linear <- character(0)
    }
  else
    {
      nam <- var.inner(formula)

      m <- match.call(expand = FALSE)
      Terms <- terms(formula, specials='I')
      m$formula <- formula
      m$r2 <- m$type <- m$nk <- m$tlinear <- m$pr <- m$... <- NULL
      m$na.action <- na.delete

      m[[1]] <- as.name("model.frame")
      linear <- nam[attr(Terms,'specials')$I]
      data <- eval(m, sys.parent())
    }
  p <- length(data)
  n <- nrow(data)
  if(pr) cat(n, 'observations used in analysis\n')

  cat.levels <- vector('list',p)
  names(cat.levels) <- nam
  vtype <- rep('s', p); names(vtype) <- nam

  na <- rep(FALSE, n)
  for(i in 1:p)
    {
      xi  <- data[[i]]
      nai <- is.na(xi)
      na[nai] <- TRUE
      ni  <- nam[i]

      iscat <- FALSE
      if(is.character(xi))
        {
          xi <- as.factor(xi)
          lev <- levels(xi)
          iscat <- TRUE
        }
      else if(is.category(xi))
        {
          lev <- levels(xi)
          iscat <- TRUE
        }
      if(iscat)
        {
          data[[i]] <- as.integer(xi)
          cat.levels[[ni]] <- lev
          vtype[ni] <- 'c'
        }
      else
        {
          u <- unique(xi[!nai])
          if(length(u) == 1) stop(paste(ni,'is constant'))
          else
            if(nk==0 || length(u) == 2 || ni %in% linear)
              vtype[ni] <- 'l'
        }
  }

  xdf <- ifelse(vtype=='l', 1, nk-1)
  j <- vtype=='c'
  if(any(j)) for(i in which(j)) xdf[i] <- length(cat.levels[[i]]) - 1
  names(xdf) <- nam

  n <- sum(!na)
  orig.df <- sum(xdf)
  X <- matrix(NA, nrow=n, ncol=orig.df)
  st <- en <- integer(p)
  start <- 1
  for(i in 1:p)
    {
      xi <- data[[i]]
      xi <- if(is.matrix(xi)) xi[,!na,drop=FALSE] else xi[!na]
      x <- aregTran(xi, vtype[i], nk)
      st[i] <- start
      nc    <- ncol(x)
      xdf[i]<- nc
      end   <- start + nc - 1
      en[i] <- end
      if(end > orig.df) stop('program logic error')
      X[,start:end] <- x
      start <- end + 1
    }

  nc <- ncol(X)
  if(nc < orig.df) X <- X[, 1:nc, drop=FALSE]
  
  In <- 1:p; Out <- integer(0)

  fcan <- function(ix, iy, X, st, en, vtype, tlinear, type)
    {
      ## Get all subscripts for variables in the right hand side
      k <- rep(FALSE, ncol(X))
      for(i in ix) k[st[i]:en[i]] <- TRUE
      ytype <- if(tlinear && vtype[iy]=='s')'l' else vtype[iy]
      Y <- if(ytype=='l') X[,st[iy],drop=FALSE] else
       X[,st[iy]:en[iy],drop=FALSE]
      f <- cancor(X[,k,drop=FALSE], Y)
      r2 <- f$cor[1]^2
      if(type=='ordinary') return(r2)
      dof <- sum(k) + ifelse(ytype=='l', 0, ncol(Y))
      n <- nrow(y)
      max(0, 1 - (1 - r2)*(n-1)/dof)
    }

  r2r <- numeric(0)
  r2l <- list()
  for(i in 1:p) {
    if(pr) cat('Step',i,'of a maximum of', p, '\r')
    ## For each variable currently on the right hand side ("In")
    ## find out how well it can be predicted from all the other "In" variables
    if(length(In) < 2) break
    Rsq <- In*0
    l <- 0
    for(j in In)
      {
        l <- l + 1
        k <- setdiff(In, j)
        Rsq[l] <- fcan(k, j, X, st, en, vtype, tlinear, type)
        if(is.na(Rsq[l]))stop('w')
      }
    if(max(Rsq) < r2) break
    removed   <- In[which.max(Rsq)]
    r2removed <- max(Rsq)
    ## Check that all variables already removed can be predicted
    ## adequately if new variable 'removed' is removed
    k <- setdiff(In, removed)
    r2later <- NULL
    if(length(Out))
      {
        r2later <- Out*0
        names(r2later) <- nam[Out]
        l <- 0
        for(j in Out)
          {
            l <- l+1
            r2later[l] <- fcan(k, j, X, st, en, vtype, tlinear, type)
          }
        if(min(r2later) < r2) break
      }
    Out <- c(Out, removed)
    In  <- setdiff(In, Out)
    r2r <- c(r2r, r2removed)
    if(length(r2later)) r2l[[i]] <- r2later
  }
  if(length(r2r)) names(r2r) <- nam[Out]
  if(length(r2l)) names(r2l) <- nam[Out]
  if(pr) cat('\n')
  
  structure(list(call=acall, formula=formula,
                 In=nam[In], Out=nam[Out],
                 rsquared=r2r, r2later=r2l,
                 n=n, p=p, m=sum(na),
                 vtype=vtype, tlinear=tlinear, nk=nk, df=xdf,
                 cat.levels=cat.levels,
                 r2=r2, type=type),
            class='redun')
}

print.redun <- function(object, digits=3, long=TRUE, ...)
{
  cat("\nRedundancy Analysis\n\n")
  dput(object$call)
  cat("\n")
  cat('n:',object$n,'\tp:',object$p, '\tnk:',object$nk,'\n')
  cat('\nNumber of NAs:\t', object$m, '\n')
  if(object$tlinear)
    cat('\nTransformation of target variables forced to be linear\n')
  cat('\nR-squared cutoff:', object$r2, '\tType:', object$type,'\n')
  cat('\nRendundant variables:\n\n')
  print(object$Out, quote=FALSE)
  cat('\nPredicted from variables:\n\n')
  print(object$In,  quote=FALSE)
  cat('\n')
  w <- object$r2later
  vardel <- names(object$rsquared)
  if(!long)
    {
      print(data.frame('Variable Deleted'=vardel,
                       'R^2'=round(object$rsquared,digits),
                       row.names=NULL, check.names=FALSE))
      return(invisible())
    }
  later  <- rep('', length(vardel))
  i <- 0
  for(v in vardel)
    {
      i <- i + 1
      for(z in w)
        {
          if(length(z) && any(names(z)==v))
            later[i] <- paste(later[i], round(z[v], digits), sep=' ')
        }
    }
  print(data.frame('Variable Deleted'=vardel,
                   'R^2'=round(object$rsquared,digits),
                   'R^2 after later deletions'=later,
                   row.names=NULL,
                   check.names=FALSE))
  invisible()
}

