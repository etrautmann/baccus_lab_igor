#pragma rtGlobals=1		// Use modern global access method.

function Sort_OA(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR onlineAnalysis=$recDF+"onlineAnalysis"
	NVAR runTime=$recDF+"runTime"
	NVAR length=$recDF+"length"
	
	if(!onlineAnalysis)
		return 0
	endif
	
	variable timeAvailable=length-.1-runTime
	variable timer
	variable totTime=0
	
	wave threshVals=$OA_DF+"threshVals"
	
	if(dimsize(threshVals,0)>0)
	
	NVAR startWhere=$OA_DF+"startWhere"
	
		variable i
		for(i=startWhere;i<dimsize(threshVals,0);i+=1)
			timer=startMSTimer
			wave wv=$recDF+"wv"+num2str(threshvals[i][0])
			wave width=$OA_DF+"width"+num2str(threshvals[i][0])
			findlevels /q/EDGE=2 wv,threshvals[i][1]
			wave w_findlevels
			duplicate /o w_findlevels widths
			findlevels /q/EDGE=1 wv,threshvals[i][1]
			if(numpnts(widths)>numpnts(w_findlevels))
				deletepoints 0,1,widths
			elseif(numpnts(widths)<numpnts(w_findlevels))
				deletepoints numpnts(w_findlevels)-1,1,w_findlevels
			endif
			widths-=w_findlevels
			concatenate /NP=0 "widths;",width
			
			totTime+=StopMSTimer(timer)/1e6
			if(totTime>timeAvailable)
				startWhere=i+1
				onlineAnalysis=0
				print totTime
				return 0
			endif
		endfor
		startWhere=0
	endif
	
	onlineAnalysis=0
	
	return 0
end


function Sort_OA_init(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR running=$recDF+"running"
	
	wave w_selected=$OA_DF+"w_selected"
	
	if(numpnts(w_selected)>0)
	
		SetDataFolder OA_DF
		
		variable /g startWhere=0
		
		duplicate /o w_selected selectedChans
		selectedChans=selectnumber(w_selected,NaN,p)
		sort selectedChans,selectedChans
		wavestats /q selectedChans
		deletepoints v_npnts,v_numNaNs,selectedChans
		
		make /o/n=(numpnts(selectedChans),2) threshVals
		
		setDataFolder root:
		
		wave threshVals=$OA_DF+"threshVals"
		threshVals[][0]=selectedChans[p]
		
		variable i
		for(i=0;i<dimsize(threshVals,0);i+=1)
			wave wv=$recDF+"wv"+num2str(threshVals[i][0])
			wavestats /q wv
			threshVals[i][1]=v_sdev*3+v_avg
			make /o/n=0 $OA_DF+"width"+num2str(threshVals[i][0])
		endfor
	endif

	CtrlNamedBackground OA_init, stop
	CtrlNamedBackground OA_init, kill
	
	if(running)
		CtrlNamedBackground OnAnalysis,start
	endif
end


function Sort_OA_finish(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR running=$recDF+"running"
	
	if(!running)
	
		wave threshVals=$OA_DF+"threshVals"
		
		if(dimsize(threshVals,0)>0)
			make /o/n=(dimsize(threshVals,0),2) $OA_DF+"widthRanges"
			wave widthRanges=$OA_DF+"widthRanges"
			widthRanges[][0]=threshVals[p][0]
			widthRanges[][1]=inf
			
			variable v_FitError
			variable i,j
			for(i=0;i<dimsize(widthRanges,0);i+=1)
				wave width=$OA_DF+"width"+num2str(widthRanges[i][0])
				if(numpnts(width)>100)
					make /o/n=100 hist
					histogram /b=1 width hist
					 v_FitError=0
					 make /o/n=7 w_coef
					 wavestats /q hist
					 w_coef = {0,100,10,v_maxLoc,v_maxLoc,deltax(hist),deltax(hist)}
					 FuncFit/q/w=0/NTHR=0 TwoGauss W_coef  hist /D=hist
					 if(v_FitError==0)
					 	duplicate /o hist dif
					 	differentiate hist /d=dif
					 	findlevels /q/EDGE=2 dif,0
					 	wave w_findlevels
					 	if(v_levelsfound>1)
					 		wavestats /q/r=(w_findlevels[0],w_findlevels[1]) hist
					 		widthRanges[i][1]=v_minLoc
					 	endif
					 endif
				 endif
				 killwaves /z width
			endfor
			
			make /o/n=(dimsize(widthRanges,0),2) $OA_DF+"numForRF"
			wave numForRF=$OA_DF+"numForRF"
			numForRF[][1]=NaN

			for(i=0;i<dimsize(widthRanges,0);i+=1)
				numForRF[i][0]=j
				j+=1
				if(widthRanges[i][1]<inf)
					numForRF[i][1]=j
					j+=1
				endif
			endfor
		endif
		
		killwaves /z hist,fit_hist,dif
	endif

	CtrlNamedBackground OA_finish, stop
	CtrlNamedBackground OA_finish, kill
end

Function TwoGauss(w,x) : FitFunc
	Wave w
	Variable x

	//CurveFitDialog/ These comments were created by the Curve Fitting dialog. Altering them will
	//CurveFitDialog/ make the function less convenient to work with in the Curve Fitting dialog.
	//CurveFitDialog/ Equation:
	//CurveFitDialog/ f(x) = y0+A1*exp(-(x-mn1)^2/2/sd1^2)+A2*exp(-(x-mn2)^2/2/sd2^2)
	//CurveFitDialog/ End of Equation
	//CurveFitDialog/ Independent Variables 1
	//CurveFitDialog/ x
	//CurveFitDialog/ Coefficients 7
	//CurveFitDialog/ w[0] = y0
	//CurveFitDialog/ w[1] = A1
	//CurveFitDialog/ w[2] = A2
	//CurveFitDialog/ w[3] = mn1
	//CurveFitDialog/ w[4] = mn2
	//CurveFitDialog/ w[5] = sd1
	//CurveFitDialog/ w[6] = sd2

	return w[0]+w[1]*exp(-(x-w[3])^2/2/w[5]^2)+w[2]*exp(-(x-w[4])^2/2/w[6]^2)
End