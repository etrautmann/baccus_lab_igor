#pragma rtGlobals=1		// Use modern global access method.

// To perform an online analysis copy this template into your own procedure window and include the appropriate
//		actions and functions. Make sure to load your procedure before displaying the RecordMEA display.
//
// You must have three functions:
//		1) A main function that performs your online analysis. It must have an '_OA' at the end of its name
//		2) An initialization function that has the same name as your main function with '_init' appended to the end
//		3) A finalization function that has the same name as your main function with '_finish' appended to the end
//
// If you have loaded a procedure with a function ending with '_OA', then there will be a drop-down menu containing
//		all functions ending with '_OA.' Select your desired function from the drop-down menu.
//
// When you check the "Analyze"  checkbox the initialization procedure will run, and if you are already recording the
//		main function will start as well. If you have not started recording then the main function will begin with the recording.
//
// After you are done with the analysis, when you uncheck the analyze button the finalization procedure will run.
//
// VERY IMPORTANT: make sure your analysis does not take longer than the time left over after saving and recording.

// Will be working on waves titled "wvN" where N is the channel number starting from 0
// These waves are stored in the Recording data folder, which can be accessed using
//		the string constant recDF, i.e. wave wv0 = $recDF+"wv0"
// If you are recording from all 64 channels:
//		wv0 = phototdiode
//		wv1 = voltage
//		wv2 = current
//		wv3 = not in use
//		wv4 - wv63 = MEA channels
// Otherwise waves are namesd in order from 0 - # of channels being recorded


//CONSTANT numChans=64, delta=0.0001
//StrCONSTANT WiringType="NRSE",recDF="root:Recording:"
//StrCONSTANT OA_DF="root:OA:"
//StrCONSTANT room="d213"

// note for CombinedAnalysis Loop experiments: 
// the online analysis check boxes should still be used, as it initializes the globals 
// appropriately for each analysis

// subroutine of function Record()
// when recording session starts, 
// initializes all output functions required for the chosen online analysis,
// which must have been initialized before this function
Function OnlineAnalysis_init()

	DFREF home = GetDataFolderDFR()
	SetDataFolder root:OA
	
	SVAR/z RoutineName
	if ( SVAR_exists(RoutineName)==0 )
		print "No online analysis function initialized."
		SetDataFolder home
		return 0
	endif
	NVAR reps=$recDF+"reps"
	variable/g DO_refnum = 0
	variable/g Timing_refnum = 0
	variable/g SaveTimingFlag = 1			// set this to save RunTimeBenchmark file
	variable/g HighPassFilter = 1			// set to filter data with SmoothXOP;
										// functionality not consistently added to all online analysis routines!
	
	StrSwitch ( RoutineName )
		case "OnlineSpikeCount" :
			DigitalOut_start()				// initialize port output
			DigitalOut_write(0,0)			// make sure all lines are low

			make/o/n=(reps, 3) DigitalOut_log = -1			// log what's been written to the digital output lines
			setdimlabel 1, 0, NumSpikes, DigitalOut_log
			setdimlabel 1, 1, DO_counter, DigitalOut_log
			setdimlabel 1, 2, cnt, DigitalOut_log
			break
		case "TrackObjSimple" :
			DigitalOut_start()				// initialize port output
			DigitalOut_write(0,0)			// make sure all lines are low

			make/o/n=(reps, 3) DigitalOut_log = -1			// log what's been written to the digital output lines
			setdimlabel 1, 0, MasterCntr, DigitalOut_log
			setdimlabel 1, 1, LocalCntr, DigitalOut_log
			setdimlabel 1, 2, Shift, DigitalOut_log
			break
		case "TrackObj1" :
			DigitalOut_start()				// initialize port output
			DigitalOut_write(0,0)			// make sure all lines are low

			make/o/n=(reps, 3) DigitalOut_log = -1			// log what's been written to the digital output lines
			setdimlabel 1, 0, MasterCntr, DigitalOut_log
			setdimlabel 1, 1, LocalCntr, DigitalOut_log
			setdimlabel 1, 2, Shift, DigitalOut_log
			break
		default :
			break
	EndSwitch

	SVAR saveName=$recDF+"saveName"
	open/F=".bin"/p=path1/M="Save digital output log as:" DO_refnum as SaveName+"_DOlog.bin"
	make/o/n=(1,dimsize(DigitalOut_log,1)) DO_2write			// shorter buffer needed to write this
	
	variable Threshold_refnum 		// save threshold info!!
	open/F=".txt"/p=path1/M="Save threshold info as:" Threshold_refnum as SaveName+"_thresh.txt"
	fprintf Threshold_refnum, "File information for experiment started %s, %s.\n", date(), time()
	NVAR/z OnlineSpikeCountCh = root:OA:OnlineSpikeCountCh
	if ( NVAR_exists(OnlineSpikeCountCh) )
		fprintf Threshold_refnum, "Spikes played back from ch %d\n", OnlineSpikeCountCh
	endif
	
	fprintf Threshold_refnum, "ChThreshold:\n\n"
	Wave ChThreshold = root:OA:ChThreshold
	variable i
	for ( i=0 ; i<dimsize(ChThreshold,0) ; i+=1 )
		fprintf Threshold_refnum, "%d\t%.6f\n", i, ChThreshold[i]
	endfor
	close Threshold_refnum
	
	if ( SaveTimingFlag )
		wave timing = root:RunTimeBenchmark
		make/o/n=(1, dimsize(timing,1)) RTB_temp
		open/F=".bin"/p=path1/M="Save loop execution time as:" Timing_refnum as SaveName+"_timing.bin"
	endif
	
	SetDataFolder home
end

// to be included in the loop of WriteToWaveAndFile
// switches behavior on the SVAR RoutineName
Function OnlineAnalysis_MainLoop()

	DFREF home = GetDataFolderDFR()
	SetDataFolder root:OA
	
	SVAR/z RoutineName
	if ( SVAR_exists(RoutineName)==0 )
		SetDataFolder home
		return 0
	endif
	
	NVAR cnt=$recDF+"cnt"
	NVAR DO_counter, DO_refnum
	Wave DigitalOut_log, ChThreshold, DO_2write
	
	StrSwitch ( RoutineName )
		case "OnlineSpikeCount" :
			Wave NumSpikes
			NVAR OnlineSpikeCountCh 
	
	//		for ( i=0 ; i<NumChans ; i+=1 )
	//			if ( ChThreshold[i] != 0 )			// if threshold has been set
	//				wave w = $recDF+"wv"+num2str(i)
	//				FindLevels/EDGE=1/Q w, ChThreshold[i]/0.00030518
	//				NumSpikes[i] = V_levelsFound
	////				print V_levelsFound, i
	//			endif
	//		endfor
			
	//		DO_counter = mod(cnt,8)
			DigitalOut_write(Numspikes[OnlineSpikeCountCh], DO_counter)
			
			// log output
			DigitalOut_log[cnt-1][0] = Numspikes[OnlineSpikeCountCh][0]
			DigitalOut_log[cnt-1][1] = DO_counter
			DigitalOut_log[cnt-1][2] = cnt
			
			// save digitalOut_log on the fly, so that it doesn't get wiped by a crash		
			DO_2write = DigitalOut_log[cnt-1+p][q]			// copy to shorter buffer
			FBinWrite/B=2/f=4 DO_refnum, DO_2write
			break
		case "TrackObjSimple" :
			Wave NumSpikes, COM
			NVAR Shift, Velocity
	
			DigitalOut_write(Shift, DO_counter)
			
			// log output
			DigitalOut_log[cnt-1][0] = cnt
			DigitalOut_log[cnt-1][1] = DO_counter
			DigitalOut_log[cnt-1][2] = Shift
	
			DO_2write = DigitalOut_log[cnt-1+p][q]			// copy to shorter buffer
			FBinWrite/B=2/f=4 DO_refnum, DO_2write
			
			break
		case "TrackObj1" :
			Wave NumSpikes2D, COM_wave
			NVAR Shift, Velocity
	
			DigitalOut_write(Shift, DO_counter)
			
			// log output
			DigitalOut_log[cnt-1][0] = cnt
			DigitalOut_log[cnt-1][1] = DO_counter
			DigitalOut_log[cnt-1][2] = Shift
	
			DO_2write = DigitalOut_log[cnt-1+p][q]			// copy to shorter buffer
			FBinWrite/B=2/f=4 DO_refnum, DO_2write
			
			break
		case "Development" :			// scratch for an earlier version: shouldn't work any more
			SetDataFolder recDF
			NVAR DO_Value 			// digital value to write to port
			NVAR DO_Start			// when flag is set, write digital lines
			NVAR DO_End 			// when flag is set, end digital output (reset to 0)
			SetDataFolder root:
		
			If ( DO_End )
				DO_end = 0
				DigitalOut_write(0,0)				// blank it
			endif
			if ( DO_Start )
				DO_start = 0
				controlinfo DigitalOut0
				variable v0 = V_value
				controlinfo DigitalOut1
				variable v1 = V_value
				controlinfo DigitalOut2
		
				DigitalOut_write(v0+v1*2^8+V_value*2^16,0)		// write the proper value
		//		DigitalOut_write(DO_Value)		// write the proper value
				DO_End = 1
			endif
		default :
			break
	EndSwitch

	NVAR SaveTimingFlag, Timing_refnum
	if ( SaveTimingFlag )
		wave RTB_temp
		wave RunTimeBenchmark = root:RunTimeBenchmark
		RTB_temp = RunTimeBenchmark[cnt-2][q]
		FbinWrite/b=2/f=4 Timing_refnum, RTB_temp
	endif
	
	SetDataFolder home
End

// called in the doStop() function, for a clean exit
Function OnlineAnalysis_stop()

	DFREF home = GetDataFolderDFR()
	SetDataFolder root:OA:

	SVAR/z RoutineName
	if ( SVAR_exists(RoutineName)==0 )
		SetDataFolder home
		return 0
	endif

	DigitalOut_stop()

	NVAR DO_refnum
	Close DO_refnum

	NVAR SaveTimingFlag, Timing_refnum
	if ( SaveTimingFlag )
		close Timing_refnum
	endif


	// save the digital_outputlog to file as igor binary
	Wave DigitalOut_log
	NVAR cnt=$recDF+"cnt"
	redimension/n=(cnt+5,-1) DigitalOut_log			// remove excess points
	SVAR saveName=$recDF+"saveName"
	Save/p=path1/c DigitalOut_log as (saveName+"_DOlog.ibw")

	SetDataFolder home
End

// Online analysis for spike-thresholding specified channels
// after acquiring a certain length of data, peruse offline with SetChanThresholds to set thresholds
// any thresholds set to 0 will be skipped by this routine
// for the OnlineSpikeCount experiments, use same function to determine which channel to output
function OnlineSpikeCount_OA(s)
	STRUCT WMBackgroundStruct &s

	NVAR onlineAnalysis=$recDF+"onlineAnalysis"
	if(!onlineAnalysis)
		return 0
	endif
	
	DFREF home = GetDataFolderDFR()
	NewDataFolder/o/s root:OA
	
	NVAR OA_timer
	OA_timer = startMStimer

	Wave NumSpikes, ChThreshold
	NumSpikes = 0			// start from 0
	NVAR OnlineSpikeCountCh, DO_counter
	
	variable i
	for ( i=0 ; i<NumChans ; i+=1 )
		if ( ChThreshold[i] != 0 )			// if threshold has been set
			wave w = $recDF+"wv"+num2str(i)
			FindLevels/EDGE=1/Q w, ChThreshold[i]
			NumSpikes[i] = V_levelsFound
//			NumSpikes[i] = (gnoise(1)-1)*3		// for off-line testing
		endif
	endfor
	DO_counter = (mod(DO_counter+1, 8))		// do this here, to make sure that loop is being hit every single time
	OA_timer = stopMStimer(OA_timer)/10^6
	

	onlineAnalysis=0
	SetDataFolder home
	return 0
end


// This initialization procedure is started when you check the analyze box. It will run once and then kill itself.
function OnlineSpikeCount_OA_init(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR running=$recDF+"running"
	
	DFREF home = GetDataFolderDFR()
	NewDataFolder/o/s root:OA
	
	string/g RoutineName = "OnlineSpikeCount"

	make/o/n=(numChans) NumSpikes=0			// how many spikes found on each channel
	wave/z ChThreshold = $"root:Thresholds:ChThreshold"
	if ( WaveExists(ChThreshold)==0 )
		print "Cannot find ChThreshold wave: creating it, but thresholds will need to be set."
		make/o/n=(numChans) ChThreshold
	else
		duplicate/o ChThreshold, $"root:OA:ChThreshold"		// copy to this DF
		wave ChThreshold = $"root:OA:ChThreshold"			// and redirect wave
	endif
	if ( abs(chThreshold[4]) < 10 )			// probably hasn't been rescaled
		chThreshold /= 0.00030518
	endif

	variable/g OnlineSpikeCountCh							// output the spikes on which channel?
	NVAR OnlineSpikeCountCh_set = root:Thresholds:OnlineSpikeCountCh
	OnlineSpikeCountCh = OnlineSpikeCountCh_set					// copy value
	variable/g DO_counter=0								// "timestamp" for stimulus computer
	variable/g OA_timer

	CtrlNamedBackground OA_init, stop
	CtrlNamedBackground OA_init, kill
	
	if(running)
		CtrlNamedBackground OnAnalysis,start
	endif
	SetDataFolder home
end


// This finalization procedure is started when you uncheck the analyze box. It will run once and then kill itself.
function OnlineSpikeCount_OA_finish(s)
	STRUCT WMBackgroundStruct &s
	
	DFREF home = GetDataFolderDFR()
	SetDataFolder root:OA:

	KillStrings/z RoutineName

	CtrlNamedBackground OA_finish, stop
	CtrlNamedBackground OA_finish, kill
	SetDataFolder home
end


////////////////  Track a 1D moving bar
// threshold all channels with a set threshold (defined with SetChanThresholds offline)
// calculate center-of-mass of neural excitation for all spikes in most recent block of data
// output a value to the digital lines that shifts the stimulus appropriately
function TrackObjSimple_OA(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR onlineAnalysis=$recDF+"onlineAnalysis"
	NVAR runTime=$recDF+"runTime"
	NVAR cnt = $recDF + "cnt"
	
	if(!onlineAnalysis)
		return 0
	endif

	DFREF home = GetDataFolderDFR()
	NewDataFolder/o/s root:OA
	NVAR OA_timer
	OA_timer = startMStimer					// troubleshooting
	NVAR BinSize
	NVAR DO_counter
	DO_counter = (mod(DO_counter+1, 8))	
	NVAR HighPassFilter

	Wave NumSpikes, NumSpikesX			// waves needed for COM calculation
	Wave ChThreshold, ChMapping, weightX
	NumSpikes = 0							// start from 0
	wave SmoothIn, SmoothOut				// for SmoothXOP
	
	// Compile spike times
	variable i, j
	wave w = $(recDF+"wv0")
	for ( i=0 ; i<NumChans ; i+=1 )
		if ( ChThreshold[i] != 0 )			// if threshold has been set
			wave w = $recDF+"wv"+num2str(i)
			if ( HighPassFilter )
				SmoothIn = w
				SmoothXOP/L=30 SmoothIn, SmoothOut
				FindLevels/EDGE=1/Q/D=W_FindLevels SmoothOut, ChThreshold[i]
			else
				FindLevels/EDGE=1/Q/D=W_FindLevels w, ChThreshold[i]
			endif
			NumSpikes[i] = V_levelsFound		// store the number of events for this ch
		endif
	endfor

	NVAR Shift, PixelSize, COM
	if ( 0 )			// off-line use: creates dummy data: square wave ramp of position
		variable position
		position = mod(cnt/10,8)*6
		NumSpikes = round( 5*exp(-( (p-position)/4)^2))
		NumSpikes = NumSpikes[p]<0 ? 0 : NumSpikes[p]		// replace negative spike numbers
	endif

	// compute COM
	if ( sum(NumSpikes)>0 )			// were any spikes logged?
		COM = FindCenterOfMass(numspikes, numspikesX, ChMapping, weightX)
	else
		COM = NaN					// can't say for lack of events
	endif

	variable damping = 0.25
	if ( sum(NumSpikes)<10 )
		damping *= sum(NumSpikes)/10		// more uncertainty with low spike counts
	endif

	if ( NumType(COM)==0 )						// is COM a valid number?
		Shift = COM / PixelSize * damping 			// feedback is negative
	else
		Shift = 0								// do nothing if undefined
	endif
	
	SetDataFolder home
	OA_timer = stopMStimer(OA_timer)/10^6
	onlineAnalysis=0
	return 0
end


// This initialization procedure is started when you check the analyze box. It will run once and then kill itself.
function TrackObjSimple_OA_init(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR running=$recDF+"running"
	
	DFREF home = GetDataFolderDFR()
	NewDataFolder/o/s root:OA

	string/g RoutineName = "TrackObjSimple"

	NVAR length=$recDF+"length"					// temporal size of blocks, from recording procs
	variable/g DO_counter=0						// "timestamp" for stimulus computer
	variable/g OA_timer
	variable/g BinSize = 0.06						// size of time bins sets temporal resolution
	variable/g Shift, Velocity						// control signals
	variable/g PixelSize = 5.4e-6					// how large are pixels on the retina?
	variable/g COM = 0							// Center of Mass	

	make/o/n=(numChans, length*625) SpikeTimes=0		// array of spike times, with enough space for rates up to 625 Hz
	make/o/n=(numChans) NumSpikes						// how many spikes found on each channel

	make/o/n=(8) NumSpikesX								// how many spikes on each electrode/x-pos?  auto-set to 8 for 1D bar stimulus
	make/o/n=(1,dimsize(NumSpikesX,0)) weightX = q-3.5	// absolute position of each electrode
	WeightX *= 100e-6									// electrode spacing

	wave/z ChThreshold = $"root:Thresholds:ChThreshold"
	if ( WaveExists(ChThreshold)==0 )
		print "Cannot find ChThreshold wave: creating it, but thresholds will need to be set."
		make/o/n=(numChans) ChThreshold
	else
		duplicate/o ChThreshold, $"root:OA:ChThreshold"		// copy to this DF
		wave ChThreshold = $"root:OA:ChThreshold"			// and redirect wave
	endif
	if ( abs(chThreshold[4]) < 10 )			// probably hasn't been rescaled if it's too small
		chThreshold /= 0.00030518		// scaling factor for a +/- 10V range, assumed to be constant
	endif

	wave/z ChMapping
	if ( WaveExists(ChMapping)==0 )
		print "Cannot find ChMapping wave."
		LoadWave/H/p=path1 "c:Tobi:ChMapping.ibw"
	endif

	NVAR length=$recDF+"length"
	make/o/n=(length/delta) SmoothIn, SmoothOut			// placeholder waves because SmoothXOP currently requires FP32 format

	CtrlNamedBackground OA_init, stop
	CtrlNamedBackground OA_init, kill
	
	if(running)
		CtrlNamedBackground OnAnalysis,start
	endif
	SetDataFolder home
end


// This finalization procedure is started when you uncheck the analyze box. It will run once and then kill itself.
function TrackObjSimple_OA_finish(s)
	STRUCT WMBackgroundStruct &s
	
	KillStrings/z RoutineName

	CtrlNamedBackground OA_finish, stop
	CtrlNamedBackground OA_finish, kill
end

// More complicated version; the position of activity is estimated at a resolution
// greater than the read frequency
// threshold all channels with a set threshold (defined with SetChanThresholds offline)
// calculate center-of-mass of neural excitation
// output a value to the digital lines that shifts the stimulus appropriately
function TrackObj1_OA(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR onlineAnalysis=$recDF+"onlineAnalysis"
	NVAR runTime=$recDF+"runTime"
	NVAR cnt = $recDF + "cnt"
	
	if(!onlineAnalysis)
//		return 0
	endif

	DFREF home = GetDataFolderDFR()
	NewDataFolder/o/s root:OA
	
	NVAR OA_timer
	OA_timer = startMStimer			// troubleshooting

	Wave SpikeTimes, NumSpikes2D, NumSpikesX, COM_wave			// waves needed for COM calculation
	Wave ChThreshold, ChMapping, weightX, weightT
	SpikeTimes = 0
	NumSpikes2D = 0			// start from 0
	NVAR BinSize
	NVAR DO_counter
	DO_counter = (mod(DO_counter+1, 8))	
	NVAR HighPassFilter
	
	// Compile spike times
	variable i, j
	wave w = $(recDF+"wv0")
	wave SmoothIn, SmoothOut
	for ( i=0 ; i<NumChans ; i+=1 )
		if ( ChThreshold[i] != 0 )			// if threshold has been set
			wave w = $recDF+"wv"+num2str(i)
			if ( HighPassFilter )
				SmoothIn = w
				SmoothXOP/L=30 SmoothIn, SmoothOut
				FindLevels/EDGE=1/Q/D=W_FindLevels SmoothOut, ChThreshold[i]
			else
				FindLevels/EDGE=1/Q/D=W_FindLevels w, ChThreshold[i]
			endif
			SpikeTimes[i][0] = V_levelsFound		// length of this column?
			if ( V_levelsFound>0 )
				SpikeTimes[i][1,dimsize(W_FindLevels,0)] = W_FindLevels[p-1]			// spike times
				// can SpikeTimes be omitted?  Yes, as long as a different and smaller bin size doesn't need to be computed later!\
				// see what time savings come from removing this write step!
			endif
				
			// bin spike times
			for ( j=0 ; j<V_levelsFound ; j+=1 )
				NumSpikes2D[i][floor(W_FindLevels[j]/BinSize)] += 1
			endfor
		endif
	endfor

	if ( 1 )			// create dummy data (debugging): triangular wave over channel number
		variable position
		for ( i=0 ; i<dimsize(NumSpikes2D,1) ; i+=1 )
			position = mod(cnt/10,8)*6+i*6
			NumSpikes2D[][i] = round( 5*exp(-( (p-position)/4)^2)+gnoise(0.5))
		endfor
		NumSpikes2D = NumSpikes2D[p][q]<0 ? 0 : NumSpikes2D[p][q]		// rectify
	endif

	if ( sum(NumSpikes2D)>0 )			// were any spikes logged?
		FindCenterOfMass(numspikes2D, numspikesX, ChMapping, weightX, COM_wave=COM_wave)
	else
		COM_wave = 0				// position is undefined, so do nothing
	endif
	
	NVAR Shift, PixelSize
	COM_wave = COM_wave[p]*WeightT[p]			// temporal weighting
	Shift = sum(COM_wave) / PixelSize * -1			// feedback is negative 
	if ( NumType(Shift) !=0 )						// if invalid number
		Shift = 0						// if undefined, do nothing
	endif
	
	SetDataFolder home
	OA_timer = stopMStimer(OA_timer)/10^6
	onlineAnalysis=0
	return 0
end


// This initialization procedure is started when you check the analyze box. It will run once and then kill itself.
function TrackObj1_OA_init(s)
	STRUCT WMBackgroundStruct &s
	
	NVAR running=$recDF+"running"
	
	DFREF home = GetDataFolderDFR()
	NewDataFolder/o/s root:OA

	string/g RoutineName = "TrackObj1"

	NVAR length=$recDF+"length"					// temporal size of blocks, from recording procs
	variable/g DO_counter=0						// "timestamp" for stimulus computer
	variable/g OA_timer
	variable/g BinSize = 0.015						// size of time bins sets temporal resolution
	variable/g Shift, Velocity						// control signals
	variable/g PixelSize = 5.4e-6					// how large are pixels on the retina?
	
	if ( round(length/BinSize) != length/BinSize )		// if not integer multiples
		printf "BinSize for analysis (%3.1W1Ps) is not an integer multiple of the loop time (%3.1W1Ps). Not debugged yet for this case: aborting! \r", BinSize, length
		dowindow/f RecordMEA
		checkbox cb3, value=0
		return -1
	endif
	variable NumTimeBins = length/BinSize
	make/o/n=(numChans, length*625) SpikeTimes=0		// array of spike times, with enough space for rates up to 625 Hz
	make/o/n=(numChans, NumTimeBins) NumSpikes2D		// how many spikes found on each channel
	make/o/n=(8, NumTimeBins) NumSpikesX				// how many spikes on each electrode/x-pos?  auto-set to 8 for 1D bar stimulus
	make/o/n=(8, NumTimeBins) COM_wave				// COM as a function of bin
	make/o/n=(1,dimsize(NumSpikesX,0)) weightX = q-3.5	// absolute position of each electrode
	WeightX *= 100e-6				// electrode spacing
	make/o/n=(NumTimeBins) WeightT					// how to weight bins?

	if ( 1 )			// perform weighting in time: query user
		variable TimeWeighting
		Prompt TimeWeighting, "Weighting scheme", popup, "Uniform;Arithmatic - N:..:3:2:1;Geometric;Most Recent Only;Custom;"
		DoPrompt "Choose time average",TimeWeighting
		variable WaveSum
		switch (TimeWeighting)
			case 1:		// uniform
				WeightT = 1/NumTimeBins
				break
			case 2:		// arithmatic
				WeightT = p+1
				break
			case 3:		// geometric
				WeightT = 0.5^(NumTimeBins-p)
				break
			case 4:		// most recent only
				WeightT = 0
				WeightT[NumTimeBins-1] = 1
				break
			case 5:		// custom
				print "User must edit WeightT directly and verify normalization!"
				WeightT = 1/NumTimeBins
				edit WeightT
				doupdate
				break
		endswitch
		WaveSum = sum(WeightT)
		WeightT /= WaveSum
	else
		WeightT = 1/NumTimeBins			// default averaging
	endif

	wave/z ChThreshold = $"root:Thresholds:ChThreshold"
	if ( WaveExists(ChThreshold)==0 )
		print "Cannot find ChThreshold wave: creating it, but thresholds need to be set."
		make/o/n=(numChans) ChThreshold				// make in OA (current) data folder
	else
		duplicate/o ChThreshold, $"root:OA:ChThreshold"		// copy to this DF
		wave ChThreshold = $"root:OA:ChThreshold"			// and redirect wave
	endif
	if ( abs(chThreshold[4]) < 10 )			// probably hasn't been rescaled
		chThreshold /= 0.00030518
	endif

	wave/z ChMapping
	if ( WaveExists(ChMapping)==0 )
		print "Cannot find ChMapping wave."
		LoadWave/H/p=path1 "c:Tobi:ChMapping.ibw"
	endif

	NVAR length=$recDF+"length"
	make/o/n=(length/delta) SmoothIn, SmoothOut			// dummy waves

	CtrlNamedBackground OA_init, stop
	CtrlNamedBackground OA_init, kill
	
	if(running)
		CtrlNamedBackground OnAnalysis,start
	endif
	SetDataFolder home
end


// This finalization procedure is started when you uncheck the analyze box. It will run once and then kill itself.
function TrackObj1_OA_finish(s)
	STRUCT WMBackgroundStruct &s
	
	KillStrings/z RoutineName

	CtrlNamedBackground OA_finish, stop
	CtrlNamedBackground OA_finish, kill
end


// fast function, for inclusion in online analysis routines
// recognizes whether passed a 1 or 2-D NumSpikes array by absence/presence of optional parameter COM_wave
// doesn't do any checking of dimensionality, so passing the wrong size inputs will get an error from matrixop
Function FindCenterOfMass(numspikes, numspikesX, map, weightX[, COM_wave])
wave numspikes			// array with the spike count for each channel
wave NumSpikesX		// array with the spike count per electrode (x pos)
wave map				// 1-D array with the xposition of each channel
wave weightX				// (1 x #Xpos) array with the position of each electrode relative to screen center
wave COM_wave			// for 1 2D NumSpikes wave, this matches the second dimension (time bins)

	variable COM, i, j
	if ( paramisdefault(COM_wave) )
		NumSpikesX = 0
		for ( i=4 ; i<dimsize(numspikes,0) ; i+=1 )		// start at 4 because first 4 channels aren't array electrodes!
			NumSpikesX[Map[i][2]] += NumSpikes[i]
		endfor
		COM = sum(numspikesX)
		numspikesx *= weightX						// weight by position
		COM = sum(numspikesx)/COM
		return COM
	else
		NumSpikesX=0
				
		for ( j=0 ; j<dimsize(numspikes,1) ; j+=1 )		// go through all time bins
			for ( i=4 ; i<dimsize(numspikes,0) ; i+=1 )			// start at 4 because first 4 channels aren't array electrodes!
				NumSpikesX[Map[i][2]][j] += NumSpikes[i][j]
			endfor
		endfor
		matrixop/o COM_wave = sumcols(NumSpikesX)
		matrixop/o COM_wave = ( (WeightX x NumSpikesX)/COM_wave )^t			// transpose so it's a 1D wave
		return 1
	endif

End

//////////////////////


//Menu "Tobi"
//	"Set Thresholds for all Channels", /q, SetChanThresholds()
//end
// use this function to read in, iteratively, each channel
// user adjusts threshold for each channel individually
// and each is saved in the appropriate wave.
Function SetChanThresholds()

	DFREF home = GetDataFolderDFR()

	if ( DataFolderExists("root:Thresholds") )
		SetDataFolder root:Thresholds
	else
		NewDataFolder/o/s root:Thresholds
	endif
	
	wave/z ChThreshold
	if ( WaveExists(ChThreshold)==0 )
		make/o/n=(numChans) ChThreshold 			// set threshold for each channel separately
	endif

	variable i, Refnum
	open/R/F="All Files:.*;Bin Files (*.bin):.bin;" refnum	// find file name
	if ( stringmatch(S_filename, "") == 1 )
		print "Aborted by user."
		return -1
	endif
	string/g CurrentFile = S_filename

	variable SmoothFlag = 30
	if ( smoothFlag>0 )
		printf "Smoothing waves by %d points.\r", SmoothFlag
	endif

	string/g WaveBaseName = "ch"		// string that has data folder and all but ending index of the waves to look for
	for ( i=0 ; i<numChans ; i+=1 )
//		getchannel(i, 30, filename=S_fileName, quiet=1)				// read in each wave
		getchannel1(i, 25, 58, filename=S_fileName, quiet=1)				// read in each wave		
		wave output
		duplicate/o output, $(WaveBaseName+num2istr(i))
		wave w = $(WaveBaseName+num2istr(i))
		if  ( smoothFlag > 0 )
			SmoothXOP/L=(SmoothFlag) output, w
		endif
	endfor
	killwaves/z output					// reduce clutter
	
	dowindow/f SetChanThresholds_win
	if ( V_flag==0 )			// if window doesn't exist...
		display/N=SetChanThresholds_win /W=(35.25,42.5,669.75,312.5)
	endif
	appendtograph $(WaveBaseName+"0")
	string wavesPresent = TraceNameList("",";",1)
	if ( itemsinlist(wavesPresent)>1 )
		removefromgraph $stringfromlist(0, wavesPresent)
	endif
	setdrawlayer/k userfront
	setdrawenv xcoord=prel, ycoord=left, save
	drawline 0, ChThreshold[0], 1, chThreshold[0]
	
	ModifyGraph cbRGB=(56576,56576,56576)
	ControlBar 47

	Button NextCh,pos={8,10},size={50,20},proc=SetChanThresholds_button,title="Next Ch"
	Button PrevCh,pos={66,10},size={50,20},proc=SetChanThresholds_button,title="Prev Ch"

	variable/g ChanPntr=0
	SetVariable ch,pos={132,8},size={70,24},proc=SetChanThresholds_setVar,title="Ch"
	SetVariable ch,fSize=16,limits={0,63,1},value= ChanPntr
	variable/g Threshold_value=0
	SetVariable Threshold,pos={212,11},size={111,16},bodyWidth=60,proc=SetChanThresholds_setVar,title="Threshold"
	SetVariable Threshold,format="%.3f"
	SetVariable Threshold,limits={-inf,inf,0.02},value= Threshold_value
	variable/g OnlineSpikeCountCh=0
	SetVariable OnlineSpikeCountCh,pos={667,7},size={110,30},title="\\JRW\\Z07hich Chan\r to playback?"
	SetVariable OnlineSpikeCountCh,fSize=10,format="%d"
	SetVariable OnlineSpikeCountCh,limits={0,63,1},value= OnlineSpikeCountCh

	Button SetTo2sdev,pos={328,3},size={90,35},proc=SetChanThresholds_button,title="Set This Thresh \rto   3*sdev"
	Button SetTo2sdev,fSize=9
	Button SetAllTo2sdev,pos={438,3},size={80,35},proc=SetChanThresholds_button,title="\\Z08Set All Thresh\rto 3*sdev"
	Button SetAllTo2sdev,fSize=9
	Button SetAllToZero,pos={527,3},size={80,35},proc=SetChanThresholds_button,title="Set All Thresh\rto 0"
	Button SetAllToZero,fSize=9

	Button SmoothAll,pos={613,3},size={50,35},proc=SetChanThresholds_button,title="Smooth\rAll"
	Button SmoothAll,fSize=9

	SetDataFolder home
End
// Button procedures for above
Function SetChanThresholds_button(B_Struct) : ButtonControl
	STRUCT WMButtonAction &B_Struct

	if ( B_Struct.eventCode != 1 )			// only react when button clicked
		return 0
	endif
	
	DFREF home = GetDataFolderDFR()
	SetDataFolder root:Thresholds

	wave ChThreshold
	NVAR ChanPntr
	NVAR Threshold_value
	SVAR WaveBaseName

	variable i
	StrSwitch ( B_Struct.ctrlName)
		case "SetTo2sdev" :
			wave w = $(WaveBaseName+num2str(ChanPntr))
			wavestats/q w
			Threshold_value = V_sdev*3+V_avg
			ChThreshold[ChanPntr] = Threshold_value

			break
		case "SetAllTo2sdev" :
			for ( i=0 ; i<NumChans ; i+=1 )
				wave w = $(WaveBaseName+num2str(i))
				wavestats/q w
				if ( i > 3 )
					ChThreshold[i]  = -1		
				else
					ChThreshold[i]  = V_sdev*3+V_avg
				endif
			endfor
			break
		case "SetAllToZero" :
			ChThreshold = 0
			break
		case "NextCh" :
			ChanPntr += 2 		// fall through on purpose to "PrevCh" case
		case "PrevCh" :
			ChanPntr -= 1
			ChanPntr = mod(ChanPntr+numChans, numChans)
			wave w = $(WaveBaseName+num2str(ChanPntr))
			replacewave trace=$stringfromlist(0, wavelist("*", ";", "WIN:")) w
			break
		case "SmoothAll" :
			variable smoothing=30
			printf "Smoothing all waves with a %d point square window (via SmoothXOP).\r", smoothing
			for ( i=0 ; i<NumChans ; i+=1 )
				wave w = $(WaveBaseName+num2str(i))
				duplicate/o/free w, f
				SmoothXOP/l=(smoothing) w, f
				w = f
			endfor

			break
	EndSwitch
	Threshold_value = ChThreshold[ChanPntr]
	setdrawlayer/k userfront
	setdrawenv xcoord=prel, ycoord=left, save
	drawline 0, ChThreshold[ChanPntr], 1, chThreshold[ChanPntr]
	
	SetDataFolder home
End
// Set Variable Control Box functions for above
Function SetChanThresholds_setVar (ctrlName,varNum,varStr,varName) : SetVariableControl
	String ctrlName
	Variable varNum	// value of variable as number
	String varStr		// value of variable as string
	String varName	// name of variable
	
	DFREF home = GetDataFolderDFR()
	SetDataFolder root:Thresholds

	wave ChThreshold
	NVAR ChanPntr
	NVAR Threshold_value
	SVAR WaveBaseName
	
	StrSwitch ( ctrlName )
		case "ch" :
			ChanPntr = mod(ChanPntr, numChans)
			wave w = $(WaveBaseName+num2str(ChanPntr))
			replacewave trace=$stringfromlist(0, wavelist("*", ";", "WIN:")) w
			Threshold_value = ChThreshold[ChanPntr]
			break
		case "Threshold" :
			ChThreshold[ChanPntr] = Threshold_value
			break
	EndSwitch
	setdrawlayer/k userfront
	setdrawenv xcoord=prel, ycoord=left, save
	drawline 0, ChThreshold[ChanPntr], 1, chThreshold[ChanPntr]
	
	SetDataFolder home
End


