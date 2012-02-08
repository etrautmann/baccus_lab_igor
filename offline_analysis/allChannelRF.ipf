#pragma rtGlobals=1		// Use modern global access method.

Override CONSTANT BOX_PIX=16,STIM_SIZE=500,FT=0.0333461

function allChannelRF_OA(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR onlineAnalysis=$recDF+"onlineAnalysis"

	if(!onlineAnalysis)
		return 0
	endif
	
	wave stim=$OA_DF+"stim"
	wave threshVals=$OA_DF+"threshVals"
	wave widthRanges=$OA_DF+"widthRanges"
	wave numForRF=$OA_DF+"numForRF"
	
	if(!WaveExists(stim))
		onlineAnalysis=0
		return 0
	endif
	
	if(dimsize(threshVals,0)==0)
		onlineAnalysis=0
		return 0
	endif
	
	wave whichRF=$OA_DF+"whichRF"
	wave timeSpikes=$OA_DF+"timeSpikes"
	wave numSpikes=$OA_DF+"numSpikes"
	
	NVAR cnt=$recDF+"cnt"
	NVAR length=$recDF+"length"
	NVAR runTime=$recDF+"runTime"
	
	variable timeAvailable=length-.2-runTime
	variable tickStart=ticks/60.15
	variable totTime
	
	NVAR RFlength=$OA_DF+"RFlength"
	NVAR whichOne=$OA_DF+"whichOne"
	NVAR mn=$OA_DF+"mn"
	NVAR getTimes=$OA_DF+"getTimes"
	NVAR doRFs=$OA_DF+"doRFs"
	NVAR updateDisplay=$OA_DF+"updateDisplay"
	NVAR updateYet=$OA_DF+"updateYet"
	
	variable thresh
	variable start
	
	variable i
		
//--------Spike extraction--------//

	if(getTimes)
		for(i=whichOne;i<dimsize(threshVals,0);i+=1)
			wave wv=$recDF+"wv"+num2str(threshVals[i][0])
			thresh=threshVals[i][1]
			
			if(cnt==1)
				start=RFlength
			else
				start=0
			endif
				
			findlevels /q/EDGE=1/r=(start,length) wv,thresh
			wave w_findlevels
			duplicate /o w_findlevels tms
			
			findlevels /q/EDGE=2/r=(start,length) wv,thresh
			if(numpnts(w_findlevels)>numpnts(tms))
				deletepoints 0,1,w_findlevels
			elseif(numpnts(w_findlevels)<numpnts(tms))
				deletepoints numpnts(w_findlevels)-1,1,tms
			endif
			w_findlevels-=tms
			tms+=(cnt-1)*length
			
			duplicate /o tms,numRF
			
			if(widthRanges[i][1]<inf)
				numRF=selectnumber(w_findlevels[p]<=widthRanges[i][1],numForRF[i][1],numForRF[i][0])
			else
				numRF=numForRF[i][0]
			endif
			
			concatenate /NP=0 "numRF;",whichRF
			concatenate /NP=0 "tms;",timeSpikes
			
			totTime=ticks/60.15-tickStart
			if(totTime>timeAvailable)
				if(i<dimsize(threshVals,0)-1)
					whichOne=i+1
				else
					whichOne=0
					getTimes=0
					doRFs=1
				endif
				onlineAnalysis=0
				return 0				
			endif
		endfor
		getTimes=0
		doRFs=1
		whichOne=0
	endif
	
//--------RF calculation--------//
	
	if(doRFs)
		variable spCnt
		
		for(i=whichOne;i<numpnts(timeSpikes);i+=1)
			wave RF=$OA_DF+"RF"+num2str(whichRF[i])
			spCnt=numSpikes[whichRF[i]]
			if(spCnt==0)
				RF=((stim[p][q](timeSpikes[i]-z))-mn)/mn
			else
				RF=(RF*spCnt+((stim[p][q](timeSpikes[i]-z))-mn)/mn)/(spCnt+1)
			endif
			numSpikes[whichRF[i]]+=1
			totTime=ticks/60.15-tickStart
			if(totTime>timeAvailable)
				if(i<numpnts(timeSpikes)-1)
					whichOne=i+1
				else
					whichOne=0
					getTimes=1
					doRFs=0
					make /o/n=0 $OA_DF+"timeSpikes",$OA_DF+"whichRF"
				endif
				onlineAnalysis=0
				return 0
			endif
		endfor
		doRFs=0
		whichOne=0
		make /o/n=0 $OA_DF+"timeSpikes",$OA_DF+"whichRF"
		if(mod(updateYet,5)==4)
			getTimes=0
			updateDisplay=1
		else
			getTimes=1
		endif
		updateYet+=1
	endif
	
//--------Display update--------//
		
	if(updateDisplay)
		
		for(i=whichOne;i<numpnts(numSpikes);i+=1)
			wave RF=$OA_DF+"RF"+num2str(i)
			wave rfTime=$OA_DF+"rfTime"+num2str(i)
			wave rfSpace=$OA_DF+"rfSpace"+num2str(i)
			wavestats /q RF
			if(abs(v_min)>v_max)
				rfTime=RF[v_minRowLoc][v_minColLoc][p]
				rfSpace=RF[p][q](v_minLayerLoc)
			else
				rfTime=RF[v_maxRowLoc][v_maxColLoc][p]
				rfSpace=RF[p][q](v_maxLayerLoc)
			endif
			totTime=ticks/60.15-tickStart
			if(totTime>timeAvailable)
				if(i<numpnts(numSpikes)-1)
					whichOne=i+1
				else
					whichOne=0
					getTimes=1
					updateDisplay=0
				endif
				onlineAnalysis=0
				return 0
			endif
		endfor
		getTimes=1
		updateDisplay=1
		whichOne=0
	endif
	
	onlineAnalysis=0
	
	return 0
end

function allChannelRF_OA_init(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR running=$recDF+"running"
	
	wave numForRF=$OA_DF+"numForRF"
	
	if(dimsize(numForRF,0)>0)
		wavestats /q numForRF
		variable numRF=v_npnts
	
		SetDataFolder OA_DF
			
		doWindow allRF
		if(V_flag)
			KillWindow allRF
		endif
			
		KillWaves /z stim
		
		variable numBoxes=ceil(STIM_SIZE/BOX_PIX)
		GBLoadWave /Q/O/N=stim/T={72,72}/W=1
		rename stim0 stim
		variable frames=numpnts(stim)/numBoxes^2
		redimension /n=(numBoxes,numBoxes,frames) stim
		setscale /p z,0,FT,stim
		
		variable /g RFlength=.3
		variable /g RFdelta=.02
		variable /g whichOne=0
		variable /g mn
		variable /g getTimes=1
		variable /g doRFs=0
		variable /g updateDisplay=0
		variable /g updateYet=0
		
		wavestats /q stim
		
		mn=v_avg
		
		string list=WaveList("RF*",";","")
		variable i
		for(i=0;i<ItemsInList(list);i+=1)
			wave hold=$StringFromList(i,list)
			killwaves /z hold
		endfor
		
		make /o/n=(numRF) numSpikes=0
		make /o/n=0 timeSpikes,whichRF
		
		for(i=0;i<numpnts(numSpikes);i+=1)
			make /o/n=(dimsize(stim,0),dimsize(stim,1),RFlength/RFdelta+1) RF=0
			make /o/n=(dimsize(RF,2)) rfTime=0
			make /o/n=(dimsize(RF,0),dimsize(RF,1)) rfSpace=0
			setscale /p z,0,RFdelta,RF
			setscale /p x,0,RFdelta,rfTime
			duplicate /o RF $"RF"+num2str(i)
			duplicate /o rfTime $"rfTime"+num2str(i)
			duplicate /o rfSpace $"rfSpace"+num2str(i)
		endfor
		
		killWaves /z rfTime,RF,rfSpace
		
		SetDataFolder root:
		
		displayAllRF()
		
		SetDataFolder root:
	endif
	
	CtrlNamedBackground OA_init, stop
	CtrlNamedBackground OA_init, kill
	
	if(running)
		CtrlNamedBackground OnAnalysis,start
	endif
end

function allChannelRF_OA_finish(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR running=$recDF+"running"
	
	if(running)
		return 0
	endif
	
	wave numForRF=$OA_DF+"numForRF"
	if(dimsize(numForRF,0)>0)
		
		wave runOrNot=$OA_DF+"rfTime0"
		if(abs(sum(runOrNot))>0)
			wave numSpikes=$OA_DF+"numSpikes"
			
			variable xsize=1024
			variable ysize=768
			variable stimSize=ceil(STIM_SIZE/BOX_PIX)*BOX_PIX
			
			variable xOffset=floor((xsize/2-stimSize/2)/BOX_PIX)*BOX_PIX
			variable yOffset=floor((ysize/2-stimSize/2)/BOX_PIX)*BOX_PIX
			variable boxes=min(ceil(160/BOX_PIX)+(!mod(ceil(160/BOX_PIX),2)),11)
			
			variable xCenter,yCenter,radius
			
			SetDataFolder OA_DF
			
			make /o/n=(numpnts(numSpikes),7) cellData
						
			SetDataFolder root:
			
			wave cellData=$OA_DF+"cellData"
			
			variable v_FitError=0
			
			variable i
			
			for(i=0;i<numpnts(numSpikes);i+=1)
				wave RF=$OA_DF+"RF"+num2str(i)
				wavestats /q rf
				rf-=v_avg
				
				threshRF(RF)
				wave rf_thr
				make /o/n=(boxes,boxes) focus
				wavestats /q  rf_thr
				setscale /p x,v_maxRowLoc-floor(boxes/2),1,focus
				setscale /p y,v_maxColLoc-floor(boxes/2),1,focus
				focus=rf_thr(x)(y)
				v_FitError=0
				CurveFit/NTHR=1/TBOX=0/w=0/q/N=1 Gauss2D  focus /D
				wave w_coef
				if(v_FitError==0)
					if(w_coef[3]<w_coef[5])
						w_coef[3]=w_coef[5]+1e-6
					endif
					w_coef[6]=pi
					Make/O/T/N=2 T_Constraints
					T_Constraints[0] = {"K6 >=0","K3>=K5"}
					FuncFitMD/NTHR=0/w=0/q betterGauss2D W_coef  focus /D /C=T_Constraints
				endif 
				killwaves /z focus,fit_focus
								
				if(v_FitError==0)
					cellData[i][]=w_coef[q]
				else
					cellData[i][]=NaN
				endif
			endfor
			
			if(numpnts(numSpikes)==1)
				xCenter=(cellData[0][2]+.5)*BOX_PIX+xOffset
				yCenter=(cellData[0][4]+.5)*BOX_PIX+yOffset
				radius=max(cellData[0][3],cellData[0][5])*BOX_PIX
				NewPanel /k=1/N=Cellis/W=(100,100,250,170)
				titleBox tb1 frame=0,fsize=14,pos={10,0},title="xCenter = "+num2str(xCenter)
				titleBox tb2 frame=0,fsize=14,pos={10,20},title="yCenter = "+num2str(yCenter)
				titleBox tb3 frame=0,fsize=14,pos={10,40},title="radius = "+num2str(radius)
			else
				doWindow spatialRF
				if(V_flag)
					KillWindow spatialRF
				endif
				
				SetDataFolder OA_DF
				
				string listx=WaveList("RFx*",";","")
				string listy=WaveList("RFy*",";","")
				SetDataFolder root:
				
				for(i=0;i<itemsInList(listx);i+=1)
					wave thisRF=$StringFromList(i,listx)
					killwaves /z thisRF
				endfor
				
				for(i=0;i<itemsInList(listy);i+=1)
					wave thisRF=$StringFromList(i,listy)
					killwaves /z thisRF
				endfor
				
				display /K=1 /N=spatialRF 
				duplicate /o cellData Parameters
				rescaleParameters(xOffset,yOffset)
				for(i=0;i<numpnts(numSpikes);i+=1)
					if(abs(Parameters[i][3])<30 && abs(Parameters[i][5])<30)
						makeRF(i)
						wave xRF=$"RFx_"+num2str(i)
						wave yRF=$"RFy_"+num2str(i)
						appendtograph yRF vs xRF
					endif
				endfor
				modifygraph rgb=(0,0,0),lsize=2
				ModifyGraph btLen=1.5
				ModifyGraph mirror=3
				ModifyGraph grid=1,gridRGB=(0,0,0)
				ModifyGraph width={Plan,1,bottom,left}
				
			endif
		endif
	endif
	
	CtrlNamedBackground OA_finish, stop
	CtrlNamedBackground OA_finish, kill
end

Function betterGauss2D(w,x,y) : FitFunc
	Wave w
	Variable x
	Variable y

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ variable A=cos(theta)^2/2/sigX^2+sin(theta)^2/2/sigY
	//CurveFitDialog/ variable B=-sin(2*theta)/4/sigX^2+sin(2*theta)/4/sigY^2
	//CurveFitDialog/ variable C=sin(theta)^2/2/sigX^2+cos(theta)^2/2/sigY
	//CurveFitDialog/ 
	//CurveFitDialog/ f(x,y) = z0+A0*exp(-(A*(x-x0)^2+2*B*(x-x0)*(y-y0)+C*(y-y0)^2))
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 2
	//CurveFitDialog/ x
	//CurveFitDialog/ y
	//CurveFitDialog/ Coefficients 7
	//CurveFitDialog/ w[0] = z0
	//CurveFitDialog/ w[1] = A0
	//CurveFitDialog/ w[2] = x0
	//CurveFitDialog/ w[3] = sigX
	//CurveFitDialog/ w[4] = y0
	//CurveFitDialog/ w[5] = sigY
	//CurveFitDialog/ w[6] = theta

	variable A=cos(w[6])^2/2/w[3]^2+sin(w[6])^2/2/w[5]
	variable B=sin(2*w[6])/4/w[3]^2-sin(2*w[6])/4/w[5]^2
	variable C=sin(w[6])^2/2/w[3]^2+cos(w[6])^2/2/w[5]
	
	return w[0]+w[1]*exp(-(A*(x-w[2])^2+2*B*(x-w[2])*(y-w[4])+C*(y-w[4])^2))
End

function displayAllRF()
	display /K=1/N=allRF
	
	SetDataFolder OA_DF
	
	string list=WaveList("rfTime*",";","")
	
	SetDataFolder root:
	
	variable maxVert=10
	
	variable numVert=min(ItemsInList(list),maxVert)
	variable numHoriz=ceil(ItemsInList(list)/numVert)
	
	variable spacingVert=1/numVert
	variable spacingHoriz=1/numHoriz
	
	variable whereHoriz,whereVert
	
	string lAxisTime,lAxisSpace,bAxisTime,bAxisSpace
	
	variable i
	for(i=0;i<ItemsInList(list);i+=1)
		whereVert=1-mod(i,numVert)*spacingVert
		whereHoriz=floor(i/numVert)*spacingHoriz
	
		lAxisTime="l"+num2str(mod(i,maxVert))+"t"
		lAxisSpace="l"+num2str(mod(i,maxVert))+"s"
		bAxisTime="b"+num2str(floor(i/maxVert))+"t"
		bAxisSpace="b"+num2str(floor(i/maxVert))+"s"
		wave rfTime=$OA_DF+"rfTime"+num2str(i)
		wave rfSpace=$OA_DF+"rfSpace"+num2str(i)
		appendtograph /l=$lAxisTime /b=$bAxisTime rfTime
		appendimage /l=$lAxisSpace /b=$bAxisSpace rfSpace
		modifygraph axisenab($lAxisTime)={max(0,whereVert-spacingVert),whereVert}
		modifygraph axisenab($lAxisSpace)={max(0,whereVert-spacingVert),whereVert}
		modifygraph axisenab($bAxisTime)={whereHoriz,whereHoriz+spacingHoriz*.66}
		modifygraph axisenab($bAxisSpace)={whereHoriz+spacingHoriz*.66,whereHoriz+spacingHoriz}
	endfor
	
	modifygraph freepos={0,kwfraction}
	modifygraph rgb=(0,0,0)
	ModifyGraph tick=3,nticks=0,standoff=0,axRGB=(65535,65535,65535)
	ModifyGraph tlblRGB=(65535,65535,65535),alblRGB=(65535,65535,65535)
	ModifyGraph width={Aspect,3*numHoriz/numVert}
end

override function threshrf (rfin)
	wave rfin
	variable thr=0
	
	variable tstart=.025
	variable tend=.3
	
	make /o/n=(dimsize (rfin,0)*dimsize(rfin,1)) rfmags,rfx,rfy
	variable px,py,pix
	make /o/n=(dimsize(rfin,2)) onepixtimesq // For one pixel p, holds p(t)^2, used to
	                                                                         // compute the rms value of that pixel over time
	setscale /p x,dimoffset(rfin,2),dimdelta(rfin,2),onepixtimesq
	for (px=0;px<dimsize(rfin,0);px+=1)        //Loop over x coord
		for (py=0;py<dimsize(rfin,1);py+=1) //Loop over y coord
			onepixtimesq=rfin[px][py][p]^2
			wavestats /q/r=(tstart,tend) onepixtimesq 
			rfmags[pix]=sqrt(v_avg) //rms value of one pix
			rfx[pix]=px
			rfy[pix]=py
			pix+=1
		endfor
	endfor
	sort /r rfmags,rfmags,rfx,rfy //sort the pixels with the greatest rms values
	wavestats /q  rfmags
	rfx=selectnumber( rfmags[p]>v_sdev*thr,nan,rfx) //get pixels greater than the thr in std devs
	rfy=selectnumber( rfmags[p]>v_sdev*thr,nan,rfy) //get pixels greater than the thr in std devs
	rfmags=selectnumber( rfmags[p]>v_sdev*thr,nan,rfmags)
	wavestats /q rfmags
	deletepoints v_npnts,numpnts(rfmags),rfmags,rfx,rfy 
	make /o/n=(dimsize(rfin,0),dimsize(rfin,1)) rf_thr //thresholded spatial receptive field
	rf_thr=0
	for (pix=0;pix<v_npnts;pix+=1)
		rf_thr[rfx[pix]][rfy[pix]]=rfmags[pix]
	endfor
end

function makeRF(which)
	variable which
	variable cor,A0,z0,x0,sigX,y0,sigY
	wave Parameters,ms
	z0=Parameters[which][0]
	A0=Parameters[which][1]
	x0=Parameters[which][2]
	sigX=Parameters[which][3]
	y0=Parameters[which][4]
	sigY=Parameters[which][5]
	cor=Parameters[which][6]
	make /o/n=(1000) RFx,RFy
	setscale /i x,0,2*pi,RFx,RFy
	RFx=x0+sigX*cos(x)*cos(cor)-sigY*sin(x)*sin(cor)
	RFy=y0+sigX*cos(x)*sin(cor)+sigY*sin(x)*cos(cor)
	duplicate /o RFx $"RFx_"+num2str(which)
	duplicate /o RFy $"RFy_"+num2str(which)
end

function check(which)
	variable which
	variable cor,A0,z0
	wave Parameters
	z0=Parameters[which][0]
	A0=Parameters[which][1]
	cor=Parameters[which][6]
	return  z0+A0*exp(-1/2/(1-cor^2)*(1-cor))
end

function makeMS()
	make /o/n=(77) ms
	ms[0,25]={0,0.005,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1,1.1,1.2,1.3,1.4,1.5,1.6,1.8,2,2.2,2.4,2.6,2.8,3,3.2}
	ms[26,51]={3.6,4,4.5,5,6,7,9,10,15,20,30,40,50,-50,-40,-30,-20,-15,-10,-9,-7,-6,-5,-4.5,-4,-3.6}
	ms[52,70]={-3.2,-3,-2.8,-2.6,-2.4,-2.2,-2,-1.8,-1.6,-1.5,-1.4,-1.3,-1.2,-1.1,-1,-0.9,-0.8,-0.7,-0.6}
	ms[71,76]={-0.5,-0.4,-0.3,-0.2,-0.1,-0.005}
end

function rescaleParameters(xOffset,yOffset)
	variable xOffset,yOffset
	wave Parameters
	
	Parameters[][2]+=.5
	Parameters[][4]+=.5
	Parameters[][2]*=BOX_PIX
	Parameters[][4]*=BOX_PIX
	Parameters[][2]+=xOffset
	Parameters[][4]+=yOffset
	
	Parameters[][3]*=BOX_PIX
	Parameters[][5]*=BOX_PIX
end