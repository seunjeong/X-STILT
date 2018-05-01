if(F){
  t=1
  yr=recp.yr-2000
  mon=recp.mon
  day=recp.day
  hr=recp.hr
  dxyp=dxyp
  dzp=0
  lat=tmp.lat
  lon=tmp.lon
  agl=agl
  outname=ident
  nhrs=nhrs
  numpar=npar
  nummodel=nummodel

  metd=c("fnl","awrf")
  metfile=metfile
  metlib=metpath
  conv=F
  doublefiles=T
  overwrite=TRUE
  outpath=trajpath
  varsout=varstrajec
  rundir=rundir
  setup.list=list(DELT=2,VEGHT=0.5)
  siguverr=siguverr
  TLuverr=TLuverr
  zcoruverr=zcoruverr
  horcoruverr=horcoruverr
  emisshrs=1/100
  mn=0
  write.r=TRUE
  ziscale=NULL
  sigzierr=NULL
  TLzierr=NULL
  horcorzierr=NULL

}



Trajecmulti<-function(yr=02,mon=8,day=1,hr=6,mn=0,lat=42.536,lon=-72.172,agl=30,nhrs=-48,
                      dxyp=0.,dzp=0.,
                      numpar=100,metlib="/deas/group/stilt/Metdata/",
                      metd="edas",doublefiles=F,metfile=NULL,conv=F,ziscale=NULL,
                      siguverr=NULL,TLuverr=NULL,zcoruverr=NULL,horcoruverr=NULL,
                      varsout=c("time","index","lat","lon","agl","grdht","foot","temp0","swrad","zi","dens","dmass"),
                      rundir=NULL,nummodel=NULL,outname=NULL,outpath="",overwrite=T,emisshrs=1/100,
                      sourcepath="./",debugTF=TRUE,max.counter=NULL,
                      sigzierr=NULL,TLzierr=NULL,horcorzierr=NULL,zsg.name=NULL,create.X0=FALSE,setup.list=list(),
                      hymodelc.exe=NULL,write.r=TRUE,write.nc=FALSE){
#Function to run HYSPLIT particle dispersion model and to check distribution of particles

#INPUT:
#'yr','mon','day','hr': starting time of STILT run
#'mn': if non-zero, is the offset of particle start time (i.e., receptor time) from STILT start time
#      >0 for a forward run (nhrs>0), <0 for a backward run (nhrs<0)
#'lat','lon',&'agl' can be a VECTOR of the same length--to have multiple starting locations; agl in meters above ground
#'nhrs' is number of hours model would be run--NEGATIVE values mean model is run BACKWARDS
#'numpar' is number of particles emitted over the # of hrs specified in 'emisshrs'
#  for each receptor; for npos>1, the namelist variable is adjusted accordingly
#'metd' is character vector with names (descriptors) of met files to be used; possible entries: "edas","fnl","RAMS" (not yet)
#'doublefiles' should concatenated met files be used? Allows starting times between files
#       concatenation with "cat file1 file2 > file12"
#'metfile' specifies the meteorological input file;if not specified, then let 'getmetfile' automatically determine filename based on time and 'metd'
#'conv' turns on convection (RAMS winds: grell convection scheme, EDAS and FNL: simple excessive redistribution within vertical range with CAPE>0)
#'ziscale' is a vector with which to scale the modelled mixed-layer height
#    each element specifies scaling factor for each model simulation hour (ziscale can be of length that is smaller than abs(nhrs))
#'siguverr' & 'TLuverr' refer to the stddev of magnitude in horizontal wind errors [m/s] and their correlation timescale [min]
#   'zcoruverr' refers to the vertical correlation lengthscale of horizontal winds [m]
#   'horcoruverr' refers to the horizontal correlation lengthscale of horizontal winds [km]
#'varsout' specifies output variables from STILT
#      can be any subset of c("time","sigmaw","TL","lon","lat","agl","grdht","index","cldidx","temp","temp0","sampt","foot","shtf","lhtf","tcld","dmass","dens","rhf","sphu","solw","lcld","zloc","swrad","wbar","zi","totrain","convrain","zconv","pres")
#'nummodel' specifies copy of directory where fortran executable is executed; needs to be different for different runs running parallel on same filesystem
#'rundir' specifies main directory where different copy directories are found (see nummodel)
#'outname' specifies name of the object for output; if not specified, uses default name
#     based on time and position using pos2id() (e.g. "2002x08x16x06x42.54Nx072.17Wx00030")
#'outpath' specifies the directory in which the object will be saved
#'overwrite' if TRUE (default), overwrite existing object with same 'outname' or same default name
#'emisshrs' specifies the hrs over which the particles will be emitted
#'sourcepath' specifies the directory in which r scripts are located (needed for ECMWF level info)
#'sigzierr' & 'TLzierr' refer to the stddev of magnitude in mixed layer height errors [%] and their correlation timescale [min]
#   'horcorzierr' refers to the horizontal correlation lengthscale of mixed layer height errors [km]

#OUTPUT:
#assigns the output of particle dispersion model in MATRIX format to an object called 'outname' (or default name indicating time & position);
#object is saved in database at location depending on outpath
#e.g. for outname="tmp" and outpath="/home/gerbig/modeloutput/" the database will be saved as "/home/gerbig/modeloutput/.RDatatmp"
#and contains the object "tmp" that can be retrieved with getr("tmp",path="/home/gerbig/modeloutput/")
#columns are specified using 'varsout' argument
#returns list of:
#  defaultname; all input data; metd with times when switched;
#-status
#  1: new object assigned, no problem;
#  2: new object assigned, ended early
#  3: object already exists, not overwriten
#  4: no object assigned; failed
#
#
#Note that 'metfile' can be a VECTOR of file names--necessary if the model run time encompasses info from TWO files
#Returns the output of particle dispersion model in a matrix format
#Calls 'getmetfile' to get name of necessary meteorological file
#3/3/2004 by JCL and CHG
#
#  $Id: Trajecmulti.r,v 1.19 2014/08/15 18:44:17 mellis Exp $
#---------------------------------------------------------------------------------------------------

  if(!write.r && !write.nc) stop('Need to have at least one of write.r/write.nc TRUE')
  emissrate<-1;sampintv<-2;TLfrac=0.1; #define some former arguments
  if(is.null(rundir))rundir<-"~/STILT/Exe/" #directory in which hymodelc is run (default)
  if(is.null(nummodel)){
    if(substring(unix("hostname"),1,3)=="nod"){ #on grid.deas, node decides which copy number
      nummodel<-as.numeric(substring(unix("hostname"),6,7))
    }else{
      nummodel<-0
    }}

  npos <- length(lat)
  if((npos!=length(lon)) || (npos!=length(agl)) || (npos!=length(agl)) || (npos!=length(outname))){
    stop("lat, lon, agl, outname have to be the same length!")
  }
  if (length(yr) == 1) yr <- rep(yr,npos)
  if (length(mon) == 1) mon <- rep(mon,npos)
  if (length(day) == 1) day <- rep(day,npos)
  if (length(hr) == 1) hr <- rep(hr,npos)
  if (length(mn) == 1) mn <- rep(mn,npos)
  if (length(nhrs) == 1) nhrs <- rep(nhrs,npos)
  if (length(emisshrs) == 1) emisshrs <- rep(emisshrs,npos)
  if (length(dxyp) == 1) dxyp <- rep(dxyp,npos)
  if (length(dzp) == 1) dzp <- rep(dzp,npos)
  if((npos!=length(yr)) || (npos!=length(mon)) || (npos!=length(day)) || (npos!=length(hr))
     || (npos!=length(mn)) || (npos!=length(nhrs)) || (npos!=length(emisshrs))
     || (npos!=length(dxyp)) || (npos!=length(dzp)) ){
    stop("yr, mon, day, hr, mn, nhrs, emisshrs, dxyp, dzp have to be length 1 or have the same length as lat/lon/agl/outname!")
  }

  status<-4 #assume worst case: nothin writen, nothing found

  # Generate values for setup namelist variables
  # Values from function arguments (for historical reasons)
  # Adjust the total number of particles released at one time for the number of receptors
  setup.list$NUMPAR <- npos*numpar
  # default value for maxpar:
  if (is.null(setup.list$MAXPAR)) setup.list$MAXPAR <- setup.list$NUMPAR+npos
  # if part of the setup.list, make sure maxpar is large enough:
  setup.list$MAXPAR <- max(setup.list$MAXPAR,setup.list$NUMPAR+npos)

  i<-0;if(conv)i<-1
  setup.list$ICONVECT <- i #flag used to switch on convection
  i<-0;if(!is.null(ziscale))i<-1 #'ziscale' is vector of scaling factors used to prescribe mixed-layer height during model run
  setup.list$ZICONTROLTF <- i #flag used to switch on reading of ziscale from file
  i <- 0
  if((is.null(siguverr)|is.null(TLuverr))&(is.null(sigzierr)|is.null(TLzierr))){
    i <- 0
  } else if(!(is.null(siguverr)|is.null(TLuverr))&(is.null(sigzierr)|is.null(TLzierr))){
    i <- 1
  } else if((is.null(siguverr)|is.null(TLuverr))&!(is.null(sigzierr)|is.null(TLzierr))){
    i <- 2
  } else if(!(is.null(siguverr)|is.null(TLuverr))&!(is.null(sigzierr)|is.null(TLzierr))){
    i <- 3
  }
  setup.list$WINDERRTF <- i #flag used for wind/pblh error modeling

  #translate variable names from R to fortran
  r.names<-c("time","sigmaw","TL",  "lon", "lat", "agl", "grdht","index","cldidx","temp","temp0","sampt","foot","shtf","lhtf","tcld","dmass","dens","rhf", "sphu","solw","lcld","zloc","swrad","wbar","zi",  "totrain","convrain","zconv","pres")
  f.names<-c("time","sigw",  "tlgr","long","lati","zagl","zsfc", "indx", "icdx",  "temz","temp", "samt", "foot","shtf","whtf","tcld","dmas", "dens","rhfr","sphu","solw","lcld","zloc","dswf", "wout","mlht","rain",   "crai","zcfx","pres")
  varsout.f<-f.names[match(varsout,r.names)]
  if(sum(is.na(match(varsout,r.names)))>0)stop(paste("wrong names:",varsout[is.na(match(varsout,r.names))]))
  varsout.r <- varsout
  if (npos > 1) {
  # Add ptyp to varsout (internal to Trajecmulti/hymodelc), so PARTICLE.DAT can be split up below:
    varsout <- c(varsout,'ptyp')
    varsout.f <- c(varsout.f,'ptyp')
  }
  n.col<-length(varsout)

  varsouttxt <- paste("'",paste(varsout.f,collapse="','"),"'",sep="")
  setup.list$IVMAX <- length(varsout.f) #number of output variables
  setup.list$VARSIWANT <- varsouttxt #4-letter code for output variables

  #defaults: (see hymodelc.f90 for explanation of all options)

  if (is.null(setup.list$VEGHT)) setup.list$VEGHT <- 0.5 #height (m AGL) below which time is counted as particle seeing the ground
  #     if <1 then interpreted as fraction of zi (mixed layer height as derived from met data)
  if (is.null(setup.list$NDUMP)) setup.list$NDUMP <- 0 #can be set to dump out all the particle/puff points
  # at the end of a simulation to a file called PARDUMP. This file can be read from root directory
  # at start of new simulation to continue previous calculation.
  # Valid NDUMP settings: 0 - no I/O, 1- read and write, 2 - read only, 3 - write only. Default value = 0
  if (is.null(setup.list$OUTFRAC)) setup.list$OUTFRAC <- 0.9 #fraction of particles which are allowed to leave
  # the model area before hysplit stops
  if (is.null(setup.list$NTURB)) setup.list$NTURB <- 0 #flag used to switch off turbulence (=1 means no turbulence)
  if (is.null(setup.list$DELT)) setup.list$DELT <- 0.0 #nonzero value sets integration timestep to fixed step
  if (is.null(setup.list$TRATIO)) setup.list$TRATIO <- 0.75 #fraction of gridcell travelled by particles during a single timestep
  #ensure Courant condition
  if (is.null(setup.list$INITD)) setup.list$INITD <- 0 #3-D particle simulation
  if (is.null(setup.list$KHMAX)) setup.list$KHMAX <- 9999 #max age a particle is allowed to attain
  if (is.null(setup.list$QCYCLE)) setup.list$QCYCLE <- 0 #number of hours between emission cycles
  if (is.null(setup.list$KRND)) setup.list$KRND <- 6 #at this interval in hrs, enhanced puff merging occurs
  if (is.null(setup.list$OUTDT)) setup.list$OUTDT <- 0.0 #interval [min] that will determine how often particle data
  # are written out to PARTICLE.DAT; if outdt=0.0, then data at EVERY timestep is written out
  if (is.null(setup.list$FRMR)) setup.list$FRMR <- 0.0 #fraction of mass permitted to be removed at KRND intervals.
  if (is.null(setup.list$RANDOM)) setup.list$RANDOM <- 0 #flag (1-yes) for using a random number generator that generates
  # diff random number sequence each time model is run
  if (is.null(setup.list$KMIX0)) setup.list$KMIX0 <- 250 #mixing depth (abs(kmix0) is used as the minimum mixing depth,
  # negative values are used to force mixing heights coincident with model levels)
  if (is.null(setup.list$ISOT)) setup.list$ISOT <- -99 #obsolete flag used to set isotropic turbulence option
  # the following defaults (aside from KMIXD) correspond to isot=0:
  if (is.null(setup.list$KBLS)) setup.list$KBLS <- 1 #boundary layer stability derived from heat and momentum fluxes
  if (is.null(setup.list$KBLT)) setup.list$KBLT <- 1 #boundary layer turbulence parameterization: Beljaars/Holtslag and Betchov/Yaglom
  if (is.null(setup.list$KMIXD)) setup.list$KMIXD <- 3 #PBL height computation: compute from bulk Ri profile (but see ziscale)
  if (is.null(setup.list$KZMIX)) setup.list$KZMIX <- 1 #Vertical diffusivity in PBL set to single average value
  if (is.null(setup.list$KDEF)) setup.list$KDEF <- 1 #horizontal turbulence computed from the velocity deformation

  # Note: everything in returninfo will be coerced to character
  returninfo.matrix <- cbind(yr,mon,day,hr,mn,lat,lon,agl,nhrs,emissrate,outname)
  #numpar
  names.returninfo <- "numpar"
  returninfo <- numpar
  for (xname in c('DELT','NDUMP','RANDOM','OUTDT','VEGHT','NTURB','OUTFRAC')) {
    returninfo <- c(returninfo,setup.list[[xname]])
    names.returninfo <- c(names.returninfo,tolower(xname))
  }

  returninfo <- c(returninfo,metlib,metd,doublefiles,metfile,conv,
                  ziscale,siguverr,TLuverr,zcoruverr,horcoruverr,sigzierr,TLzierr,horcorzierr,varsout.r,
                  nummodel,outpath,overwrite,status,' ')

  names.returninfo<-c(names.returninfo,"metlib",paste("metd",1:length(metd),sep=""),"doublemetfiles")
  if(!is.null(metfile))names.returninfo<-c(names.returninfo,paste("metfile",1:length(metfile),sep=""))
  names.returninfo<-c(names.returninfo,"conv")
  if(!is.null(ziscale))names.returninfo<-c(names.returninfo,paste("ziscale",1:length(ziscale),sep=""))
  if(!is.null(siguverr))names.returninfo<-c(names.returninfo,"siguverr")
  if(!is.null(TLuverr))names.returninfo<-c(names.returninfo,"TLuverr")
  if(!is.null(zcoruverr))names.returninfo<-c(names.returninfo,"zcoruverr")
  if(!is.null(horcoruverr))names.returninfo<-c(names.returninfo,"horcoruverr")
  if(!is.null(sigzierr))names.returninfo<-c(names.returninfo,"sigzierr")
  if(!is.null(TLzierr))names.returninfo<-c(names.returninfo,"TLzierr")
  if(!is.null(horcorzierr))names.returninfo<-c(names.returninfo,"horcorzierr")
  names.returninfo<-c(names.returninfo,paste("varsout",1:length(varsout.r),sep=""),"nummodel","outpath","overwrite","status","metoutname")

  names(returninfo)<-names.returninfo
  newnames <- c(dimnames(returninfo.matrix)[[2]], names.returninfo)
  returnvalue <- array("",dim=c(dim(returninfo.matrix)[1],length(newnames)),
                       dimnames=list(NULL,newnames))
  returnvalue[,1:dim(returninfo.matrix)[2]] <- returninfo.matrix

  for (xcolname in names.returninfo) returnvalue[,xcolname] <- returninfo[xcolname]

  mask.rows <- rep(TRUE,npos)
  if(!overwrite){
  #check if there, if so, don't overwrite, just return with status 3
    for (irow in 1:npos) {
      if(existsr(outname,outpath) || file.exists(paste(outpath,'stilt',outname,'.nc',sep=''))) {
        mask.rows[irow] <- FALSE
        returnvalue[irow,"status"]<-3
        cat("Trajec(): found object", outname, " in ", outpath, "; use this.\n")
      } #if(existsr(outname,outpath))
    }
    if (sum(mask.rows) == npos) return(return.value)
  }

  rundir<-paste(rundir,"Copy",nummodel,"/",sep="")
  #cat("Trajec(): directory where STILT is run: ", rundir, "\n")

  # Date computations: Convert all starting times to floating point hours:
  yr4<- ifelse(yr<50,yr+2000,yr+1900)
  ftime <- (julian(m=mon[mask.rows],d=day[mask.rows],y=yr4[mask.rows])*24+hr[mask.rows])+mn[mask.rows]/60.
  # Date computations: Find earliest (latest) date/time for forward (backward) runs:
  if (nhrs[1] < 0) {
    if (any(nhrs > 0)) stop('All nhrs must have the same sign')
    ftime.start <- ceiling(max(ftime)) #backward run: round up to the nearest full hour
  } else {
    if (any(nhrs < 0)) stop('All nhrs must have the same sign')
    ftime.start <- floor(min(ftime)) #forward run: round down to the nearest full hour
  }
  # Save maxpage (maximum particle age in minutes) from original nhrs input:
  maxpage <- 60.*abs(nhrs[mask.rows])
  maxpage.arg <- max(maxpage)
  if (!all(maxpage == maxpage.arg))
    warning('Multiple nhrs not supported in single hymodelc run, will use a single value for maxpage instead')
  # Compute mn as the (signed) difference between STILT start time and release time
  mn[mask.rows] <- round(60.*(ftime[mask.rows]-ftime.start))
  # Accordingly increment nhrs for each receptor
  nhrs[mask.rows] <- sign(nhrs[mask.rows])*ceiling(abs(nhrs[mask.rows]) + abs(mn[mask.rows])/60.)
  nhrs.arg <- sign(nhrs[mask.rows][1])*max(abs(nhrs[mask.rows]))

  # Convert STILT starting time (on the full hour) back to date format
  mdy <- month.day.year(floor(ftime.start/24))
  yr.arg <- mdy$year %% 100; mon.arg <- mdy$month; day.arg <- mdy$day
  hr.arg <- round(ftime.start-24*floor(ftime.start/24))
  cpos <- as.numeric(gregexpr('x',outname[1],fixed=TRUE)[[1]])
  encode.minutes <- length(cpos) > 6
  ident.start.date <- paste(sprintf('%4.4i',mdy$year),sprintf('%2.2i',mon.arg),
                            sprintf('%2.2i',day.arg),sprintf('%2.2i',hr.arg),sep='x')
  if (encode.minutes) ident.start.date <- paste(ident.start.date,'00',sep='x')

  input1<-paste(rundir,"CONTROL",sep="")  #general input file for 'chghymodelc'
  input2<-paste(rundir,"SETUP.CFG",sep="")  #namelist file for 'chghymodelc'
  input3<-paste(rundir,"ZICONTROL",sep="") #file for prescribing mixed-layer heights
  input4<-paste(rundir,"WINDERR",sep="")  #wind error covariance
  input5<-paste(rundir,"ZSG_LEVS.IN",sep="")  #file for prescribing heights in met fields to achieve better match with internal levels
  input6<-paste(rundir,"ZIERR",sep="")  #mixed layer height error covariance
  gatt.files <-        c(input1,   input2,     input3,     input4,   input5,       input6 )
  names(gatt.files) <- c("CONTROL","SETUP.CFG","ZICONTROL","WINDERR","ZSG_LEVS.IN","ZIERR")
  #
  ##First delete any previous files--so not have same run results between runs if run doesn't succeed
  unix(paste("rm -f ",input1,sep=""))
  unix(paste("rm -f ",input2,sep=""))
  unix(paste("rm -f ",input3,sep=""))
  unix(paste("rm -f ",input4,sep=""))
  unix(paste("rm -f ",input5,sep=""))
  unix(paste("rm -f ",input6,sep=""))
  #unix(paste("rm -f ",rundir,"hymodelc.out",sep=""))
  #
  #Write the prescribed heights in met fields for ECMWF fields (hybrid coordinate)
  ecflag<-FALSE;if(!is.null(metfile)){if(length(grep("ec",tolower(metfile)))>0)ecflag<-TRUE}
  if(length(grep("ec",tolower(metd)))>0)ecflag<-TRUE
  if(ecflag){
    metfile1<-getmetfile(yr=yr.arg,mon=mon.arg,day=day.arg,hr=hr.arg,nhrs=nhrs.arg,metd="ECmetF",doublefiles=doublefiles)[1] #get name(s) of met files required to drive model
    if (is.null(zsg.name)) {
      zname<-paste(substring(metfile1,1,nchar(metfile1)-nchar("arl")),"IN",sep="")
    } else {
      zname <- zsg.name
    }
  #print(paste(metlib,zname,sep=""))
    file.copy(from=paste(metlib,zname,sep=""), to=paste(rundir,"ZSG_LEVS.IN",sep=""), overwrite = TRUE) #use correct sigma levels, specific for ECMWF metdata file
  }  #if(ecflag){

  #Write the prescribed scaling factors for mixed-layer heights to 'ZICONTROL'
  if(!is.null(ziscale)){
    cat(paste(length(ziscale),"\n",sep=""),file=input3)
    for(j in 1:length(ziscale))cat(paste(ziscale[j],"\n",sep=""),file=input3,append=T)  #scaling factor for mixed-layer height
  }  #if(!is.null(ziscale)){

  #Write the stddev of magnitude in horizontal wind errors [m/s] and their correlation timescale [min] & length scales to 'WINDERR'
  if(!is.null(siguverr)&!is.null(TLuverr)&!is.null(zcoruverr)&!is.null(horcoruverr)){
    cat(paste(siguverr,"\n",sep=""),file=input4)
    cat(paste(TLuverr,"\n",sep=""),file=input4,append=T)
    cat(paste(zcoruverr,"\n",sep=""),file=input4,append=T)    #vertical correlation lengthscale [m]
    cat(paste(horcoruverr,"\n",sep=""),file=input4,append=T)  #horizontal correlation lengthscale [km]
  }  #if(!is.null(siguverr)&!is.null(TLuverr)&!is.null(zcoruverr)&!is.null(horcoruverr)){

  #Write the stddev of magnitude in mixed layer height errors [%] and their correlation timescale [min] & length scale to 'ZIERR'
  if(!is.null(sigzierr)&!is.null(TLzierr)&!is.null(horcorzierr)){
    cat(paste(sigzierr,"\n",sep=""),file=input6)
    cat(paste(TLzierr,"\n",sep=""),file=input6,append=T)
    cat(paste(horcorzierr,"\n",sep=""),file=input6,append=T)  #horizontal correlation lengthscale [km]
  }  #if(!is.null(sigzierr)&!is.null(TLzierr)&!is.null(horcorzierr)){

  #create batch file to run hymodelc in 'rundir'
  batchname<-paste(rundir,"runhymodelc.bat",sep="")  #name for executable
  cat(paste("cd ",rundir,"\n",sep=""),file=batchname)
  if (is.null(hymodelc.exe)) hymodelc.exe <- "hymodelc"
  if (!debugTF) {
    cat(paste(hymodelc.exe," >! hymodelc.out","\n",sep=""),file=batchname,append=T)
  } else {
    cat(paste(hymodelc.exe," >>! hymodelc.out","\n",sep=""),file=batchname,append=T)
  }

  outdat<-NULL
  #timesofar<-0 #time calculated so far, as absolute value in hours
  #
  if(is.null(metfile)){
    for (i in 1:length(metd)){
      metf<-getmetfile(yr=yr.arg,mon=mon.arg,day=day.arg,hr=hr.arg,nhrs=nhrs.arg,metd=metd[i],doublefiles=doublefiles) #get name(s) of met files required to drive model
      metfile<-c(metfile,metf)
    }
  }
  cat("Trajec(): metfile that will be used: ", metfile, "\n")
  returnvalue[mask.rows,'metoutname'] <- paste(metfile,collapse='x')

  #check if metfiles available
  for(mm in metfile){  #loop over the number of meteorological files
  #  if(! my.file.exists(paste(metlib,mm,sep=""))){
    if(! is.element(mm,list.files(metlib))){
      stop(paste("Trajec(): Metfile ",metlib,mm," not found",sep=""))
    }
  }

  if(length(grep('wrf|d[0-9][0-9]',metd)) > 0) {
  #Write the prescribed heights in met fields for AWRF
    if (is.null(zsg.name)) {
      zname<-"ZSG_LEVS.IN.AWRF"
    } else {
      zname <- zsg.name
    }
    print(paste("Using ",sourcepath,zname,sep=""))
    file.copy(from=paste(sourcepath,zname,sep=""), to=paste(rundir,"ZSG_LEVS.IN",sep=""), overwrite = TRUE)
  }

  #generate emit variables for netCDF file
  emitdat <- list()
  for(i in (1:npos)[mask.rows]) {
    emitdat[['emithrs']] <- c(emitdat[['emithrs']],emisshrs[i])
    emitdat[['emitdx']] <- c(emitdat[['emitdx']],dxyp[i])
    emitdat[['emitdy']] <- c(emitdat[['emitdy']],dxyp[i])
    emitdat[['emitdz']] <- c(emitdat[['emitdz']],dzp[i])
  }
  emitdat <- as.data.frame(emitdat)

  #
  #Generate 'CONTROL' file
  cat(paste(yr.arg,' ',mon.arg,' ',day.arg,' ',hr.arg,'\n',sep=""),file=input1)  #starting time
  cat(paste(sum(mask.rows),'\n',sep=""),file=input1,append=T)  #print out number of starting locations
  jtyp <- 0
  for(i in (1:npos)[mask.rows]) {
  #print out each starting location, along with QRTM/AREA (=0) and ptyp, dxyp, dzp
    jtyp <- jtyp+1
    cat(paste(lat[i],' ',lon[i],' ',agl[i],' 0.0 0.0 ',jtyp,' ',dxyp[i],' ',dzp[i],'\n',sep=""),file=input1,append=T)
  }
  cat(paste(round(nhrs.arg),' ',round(maxpage.arg),'\n',0,'\n','25000.0','\n',sep=""),file=input1,append=T)
  #numb of hrs model will be run and maximum particle age, vertical motion calc method (0 = vertical velocity from data), top of model domain (m AGL)

  cat(paste(length(metfile),'\n',sep=""),file=input1,append=T)  #number of met data files
  for (i in 1:length(metfile)){
    cat(paste(metlib,'\n',metfile[i],'\n',sep=""),file=input1,append=T)  #met directory, met filename
  }

  #numb of pollutants, pollutant name, mass units emitted per hour, hours of emission
  cat(paste(sum(mask.rows),'\n',sep=""),file=input1,append=T)  #print out number of starting locations
  jtyp <- 0
  for(i in (1:npos)[mask.rows]) {
  #print out separate pollutant info for each starting location: starting tim (mn) and emisshrs
    jtyp <- jtyp+1
    cat(paste(sprintf('t%03i',jtyp),'\n',emissrate,'\n',emisshrs[i],'\n',sep=""),file=input1,append=T)
    cat(paste('00 00 00 00 ',mn[i],'\n',sep=""),file=input1,append=T)  #starting time of emissions--all 0's mean simulation starting time
  }
  #   all default values for concentration grid definition
  cat(paste('1','\n','0.0 0.0','\n','0.5 0.5','\n','30.0 30.0','\n','./','\n','cdump','\n','1','\n',sep=""),file=input1,append=T)
  cat(paste(100,'\n','00 00 00 00 00','\n','00 00 00 00 00','\n',sep=""),file=input1,append=T)
  cat(paste('00 ',sampintv,' 00','\n',sep=""),file=input1,append=T)   #'sampintv' is time interval(hrs) between which concentration grid  output would be written to file
  #   all default values for deposition definitions (needs to be repeated npos times)
  cat(paste(sum(mask.rows),'\n',sep=""),file=input1,append=T)  #print out number of starting locations
  for(i in (1:npos)[mask.rows]) {
    cat(paste('0.0 0.0 0.0','\n','0.0 0.0 0.0 0.0 0.0','\n','0.0 0.0 0.0','\n','0.0','\n','0.0','\n',sep=""),file=input1,append=T)
  }
  #
  #

  #Generate 'Setup.cfg' file
  cat(paste(" &SETUP","\n",sep=""),file=input2)
  for (xname in names(setup.list))
    cat(paste(xname,"=",setup.list[[xname]],",\n",sep=""),file=input2,append=T)
  cat(paste(" /","\n",sep=""),file=input2,append=T)

  #remove old PARTICLE.DAT
  unix(paste("rm -f ",rundir,"PARTICLE.DAT",sep=""))
  unix(paste("rm -f ",rundir,"core",sep=""))
  #debug:
  if (debugTF) {
    for (tmp.file in paste(rundir,c("CONTROL","SETUP.CFG"),sep="")) {
      cat(tmp.file,":\n")
      unix(paste("cat",tmp.file,sep=" "),intern=F)
    }
  }
  #Call the executable 'chghymodelc'
  unix.shell(paste("sync",sep=""),shell="/bin/csh")   #sync before to make sure files are writen before read

  # Issue with deallocate "uverr" in hymodelc.f90, line 4066, not an error, try suppress the warning, DW, 11/09/2017
  #unix.shell(paste("source ",rundir,"runhymodelc.bat",sep=""),shell="/bin/csh")   #output in 'PARTICLE.DAT' in same directory
  try(unix.shell(paste("source ",rundir,"runhymodelc.bat",sep=""),shell="/bin/csh"),silent=TRUE)
  unix.shell(paste("sync",sep=""),shell="/bin/csh")   #sync after to make sure files are writen before read

  #doesn't crash when PARTICLE.DAT isn't there
  dat <- NULL
  if(! file.exists(paste(rundir, "PARTICLE.DAT",sep='')) ){
    print("Trajec(): PARTICLE.DAT not found");
  } else {
    #doesn't read the data when core was dumped; necessary since PARDUMP file will not be updated
    if(length(unix.shell(paste("if (-e ",rundir,"core) echo 'core dumped'; endif",sep=""),shell="/bin/csh"))>0) {
      print("Trajec(): core was dumped, don't use")
    } else {
      #doesn't crash when PARTICLE.DAT is empty or has only one line (checking if larger than 500 b)
      if(as.numeric(unix(paste("cat ", rundir,"PARTICLE.DAT | wc -l",sep=""))) < 2){
        print("Trajec(): PARTICLE.DAT too short");
      } else {
        #DMM Modification to cover downstream to solve ******* in EDAS40 output of PARTICLE.DAT; This is a cluge!
        if(length(grep("edas40",tolower(metd)))>0) {
          datb<-scan(paste(rundir,"PARTICLE.DAT",sep=""),what=character(),skip=npos,quiet=T) #now read it
          datb[which(substring(datb,1,2)=="**")]<-NA
          datbb<-as.numeric(datb)
          dat<-matrix(datbb,byrow=T,ncol=n.col)
        } else {
          dat<-matrix(scan(paste(rundir,"PARTICLE.DAT",sep=""),skip=npos,quiet=T),byrow=T,ncol=n.col) #now read it
        }  #if(metdat=="edas40")
      }
    }
    if (!is.null(dat)) {
      outdat<-rbind(outdat,dat)
      dimnames(outdat)<-list(NULL,varsout)
    }
  } #of if can't read Particle.dat or else...

  if (is.null(outdat)) return(returnvalue)

  jtyp <- 0
  for (ipos in 1:npos) {
    if (mask.rows[ipos]) {
      this.outdat <- NULL
      if (npos > 1) {
  # extract all rows for this pollutant, drop ptyp column
        jtyp <- jtyp+1
        if (sum(outdat[,'ptyp'] == jtyp) > 0)
          this.outdat <- outdat[outdat[,'ptyp'] == jtyp,-dim(outdat)[2],drop=FALSE]
      } else {
        this.outdat <- outdat
      }
      if (!is.null(this.outdat)) {
        returnvalue[ipos,"status"]<-1 #perfect, all times done
        # Combine stilt start time with other info for receptor:
        ident.start <- paste(ident.start.date,
                             substring(outname[ipos],nchar(ident.start.date)+1),sep='')
        if (write.r)
          assignr(outname[ipos],this.outdat,outpath,printTF=T)
        if (write.nc)
          make.stilt.nc4(ident=outname[ipos],part=TRUE,partdat=this.outdat,targetdir=outpath,appendnc=FALSE,
                         global.att.files=gatt.files,ident.start=ident.start,emit=TRUE,emitdat=emitdat[ipos,])
        unix(paste("rm -f ",input5,sep=""))
        if (create.X0) {
          min.time <- min(abs(this.outdat[,'time']))
          first.rows <- (1:dim(this.outdat)[1])[abs(this.outdat[,'time']) == min.time]
          outdat0 <- this.outdat[first.rows,,drop=FALSE]
          outname0 <- paste(outname[ipos],'X0',sep='')
          if (write.r)
            assignr(outname0,outdat0,outpath,printTF=T)
          if (write.nc)
            make.stilt.nc4(ident=outname0,part=TRUE,partdat=outdat0,targetdir=outpath,appendnc=FALSE,ident.start=ident.start)
        }
      }
    }
  }
  return(returnvalue)
}
