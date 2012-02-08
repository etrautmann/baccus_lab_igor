#pragma rtGlobals=1		// Use modern global access method.
//#pragma IndependentModule = RealTimeDev
//SetIgorOption IndependentModuleDev=1
//S#include "c:Documents and Settings:Baccus Lab:Desktop:Tobi:TestProcs"
		// to allow these procedures to call my scratch
//#include "C:Tobi:Igor DAQ procs:Tobi Online Analysis"

CONSTANT numChans=64, delta=0.0001
StrCONSTANT WiringType="NRSE",recDF="root:Recording:"
StrCONSTANT OA_DF="root:OA:"
StrCONSTANT room="d239"

function setDefaultGlobals()

	NewDataFolder /o OA
	NewDataFolder /o/s Recording
	
	variable /g length=.1					//Block Size in second
	variable /g blockSize=length/delta		//Total size of block in samples
	variable /g FIFOsize=length/delta*2		//Buffer Size
	variable /g saveFile=1					//To save (1) or not to save (0)
	variable /g cInject=0					//To inject current (1) or not to inject current (0)
	variable /g oAnalysis=1				//To perform online analysis (1) or not (0)
	variable /g fileLength=1650				//Length of each file in seconds
	variable /g totTime=10					//Total recording time, can be larger than fileLenght
	variable /g numDigitalPulse=1			//Number of digital pulses being sent to stimulus (visual) computer
	variable /g lengthDigitalPulse=.2		//Lenght of the digital pulse in seconds
	variable /g FIFOrange=10
	variable /g isPathSet=0
	variable /g running=0
	variable /g runTime=0
	variable /g loopTime
	variable /g loopTimer
	variable /g PhotodiodeLevel=-.1			//Level, in volts, of the photodiode signal to trigger current injection.
										//Remember that Photodiode display is the negative of what the device sees
	
	string /g saveName=getDate()			//Name or core name for saved file
	string /g analysisFunction="---"			//Name of online analysis function
	string /g cWave=""					//Name of wave in igor data folder that contains the current waveform
										//		must end with "_cur"
										//Range of y values cannot exceed 10 to -10
										//The sample rate and number of samples is set by the wave scaling and
										//		the number of data points in the waves.
	string /g timeString="Time:"
	string /g colorList=""
	string /g FIFOname="BaccusFIFO"
	string /g NIDAQdevice=""
	
	SetDataFolder root:

	// Benchmark options
	make/o/n=(10000,2) RunTimeBenchmark=0
	// second column for online analysis loop
	setscale/p x, 0, length, "s", RunTimeBenchmark
	setdimlabel 1, 0, acquire, RunTimeBenchmark
	setdimlabel 1, 1, analysis, RunTimeBenchmark

end

Menu "Record"
	"Setup New Run",/q, changeSettings()
	"Tobi Show Display - development", /q,showDisplay()
	"Reset recording vars", /q, ClearRecCache()
	"Set Thresholds for all Channels", /q, SetChanThresholds()
end

// reset everything
Function ClearRecCache()
	setdatafolder root:
	killdatafolder/z root:OA
	killdatafolder/z root:Recording
end

//This is what happens when you press start in the display
function Record()

	NVAR length=$recDF+"length"
	NVAR blockSize=$recDF+"blockSize"
	NVAR saveFile=$recDF+"saveFile"
	NVAR cInject=$recDF+"cInject"
	NVAR oAnalysis=$recDF+"oAnalysis"
	NVAR fileLength=$recDF+"fileLength"
	NVAR totTime=$recDF+"totTime"
	NVAR running=$recDF+"running"
	NVAR PhotoDiodeLevel=$recDF+"PhotodiodeLevel"
	
	SVAR FIFOname=$recDF+"FIFOname"
	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	SVAR saveName=$recDF+"saveName"
	SVAR cWave=$recDF+"cWave"
	
	running=1
	
	cleanTimers()
	
	SetDataFolder recDF
	
	variable /g cnt=0									//Counter for the number of blocks recorded
	variable /g reps=ceil(totTime/length)					//Total number of blocks to be recorded
	variable /g repsPerFile=ceil(fileLength/length)			//Number of blocks in a single file
	variable /g fileNum=0								//Which file is being saved to
	variable /g transferFIFO							//Running count of points to transfer from the buffer to waves
	variable /g runningTime							//Amount of time recorded
	variable /g onlineAnalysis=0						//Ready to perform an online analysis
	
	SetDataFolder root:
	
	NVAR cnt=$recDF+"cnt"
	NVAR reps=$recDF+"reps"
	NVAR repsPerFile=$recDF+"repsPerFile"
	NVAR fileNum=$recDF+"fileNum"
	NVAR transferFIFO=$recDF+"transferFIFO"
	
	SetDataFolder recDF
	
	variable i
	variable refnum,shouldIstop
	
	//Create and open files for saving
	if(saveFile)
		make /o/n=(ceil(reps/repsPerFile))  fileNums
		if(numpnts(fileNums)>1) //If you are saving to multiple files
print "if saving to multiple files..."
			for(i=0;i<numpnts(fileNums);i+=1)
				open /P=path1/F=".bin"/R/Z=1 refnum as saveName+num2char(97+i)+".bin" //checking if file exists
				if(v_flag!=0) //file does not exists
					open /P=path1/F=".bin" refnum as saveName+num2char(97+i)+".bin"		//create file
				else //file exists
					close refnum
					shouldIstop=fileExists(saveName+num2char(97+i)+".bin",filenums,i)		//ask if you want to overwrite file
					if(shouldIstop)
						return 0
					endif
				endif
				if(i==numpnts(fileNums)-1)
					writeHeader(refnum,0)
				else
					writeHeader(refnum,1)
				endif
				fileNums[i]=refnum
			endfor
		else //If you are saving to only one file
			open /P=path1/F=".bin"/R/Z=1 refnum as saveName+".bin" //checking if file exists
			if(v_flag!=0) //file does not exist
				open /P=path1/F=".bin" refnum as saveName+".bin"	//create file
			else //file exists
				close refnum
				shouldIstop=fileExists(saveName+".bin",filenums,i)	//ask if you want to overwrite file
				if(shouldIstop)
					return 0
				endif
			endif
			writeHeader(refnum,1)
			fileNums[i]=refnum
		endif
		fileNum=fileNums[0]
	endif
	SetDataFolder root:
	
	//If you are injecting current this inilializes the waveform generator
	if(cInject && stringmatch(cwave,"")==0 && WaveExists($cWave))
		DAQmx_WaveformGen /DEV=NIDAQdevice /TRIG={"/"+NIDAQdevice+"/ai/StartTrigger"} cWave+",0"
	endif
	
	makeFIFO()
	string FIFOchans=getChannelInfo()
	
	CtrlNamedBackground WriteToWave,proc=WriteToWaveAndFile		//Makes the recording procedure a background task named WriteToWave
	
	runningTime=0
	CtrlFIFO $FIFOname,start

		
//	doDigitalPulse()			// temp disable...
	// each specific online analysis should be already initialized by now, via the default background function
	OnlineAnalysis_init()			// start digital task, create output log if desired
	
	wave RunTimeBenchmark
	redimension/n=(10000, -1) RunTimeBenchmark
	RunTimeBenchmark = 0
	
// always start right away, for testing purposes
	if(cInject)
		DAQmx_Scan /DEV=NIDAQdevice /TRIG={NIDAQdevice+"/ai0",2,0,PhotodiodeLevel}  FIFO=FIFOname+FIFOchans		//Triggers off of the photodiode
	else
		DAQmx_Scan /DEV=NIDAQdevice  FIFO=FIFOname+FIFOchans		//Starts immediately
	endif
	transferFIFO=0

	CtrlNamedBackground WriteToWave,start
	if(oAnalysis)
//		CtrlNamedBackground OnAnalysis,start		// TAS disable
	endif
end

// Prompts user to either overwrite a preexisting file or quit record
function fileExists(stringName,filenums,num)
	string stringName
	wave filenums
	variable num

	variable /g doOverwrite
	variable well
	newPanel /k=2 /N=ToOverwriteOrNot
	TitleBox tb1 win=ToOVerWriteOrNot,fsize=14,frame=0,title="File already exists"
	Button b1 win=ToOVerWriteOrNot,title="Overwrite?",pos={10,20},size={60,20},proc=overwriteFile
	Button b2 win=ToOVerWriteOrNot,title="Quit?",size={60,20},proc=quitRun
	PauseForUser ToOVerWriteOrNot
//	movewindow /w=RecordMEA 2,2,2,2		// TAS
	well=doOverwrite
	killVariables doOverwrite
	variable refnum
	if(well) //overwrite preexisitng file
		open /P=path1/F=".bin" refnum as stringName
		filenums[num]=refnum
	else //quit recording
		SetDataFolder root:
		doMiniStop()
		return 1
	endif
end

function overwriteFile(name)
	string name
	NVAR doOverwrite
	
	doOverwrite=1
	KillWindow ToOVerWriteOrNot
end

function quitRun(name)
	string name
	NVAR doOverwrite
	
	doOverwrite=0
	KillWindow ToOVerWriteOrNot
end

function writeHeader(refnum,whichFile)
	variable refnum
	variable whichFile
	
	NVAR length=$recDF+"length"
	NVAR fileLength=$recDF+"fileLength"
	NVAR totTime=$recDF+"totTime"
	NVAR blockSize=$recDF+"blockSize"
	NVAR FIFOrange=$recDF+"FIFOrange"
	
	wave whichChan=$recDF+"whichChan"
	
	variable headerSize
	variable nscans
	
	if (fileLength>=TotTime)
		nscans=TotTime/delta
	elseif(whichFile)
		nscans=fileLength/delta
	else
		nscans=(TotTime-(floor(TotTime/fileLength)*fileLength))/delta
	endif
		
	variable type=2
	variable version=1
	variable numberOfChannels=numpnts(whichChan)
	variable scanRate=1/delta
	variable scaleMult=FIFOrange*2/2^16		//To convert from 16 bit data to volts
	variable scaleOff=-FIFOrange
	variable dateSize=strlen(date())
	String dateStr=date()
	variable timeSize=strlen(time())
	String timeStr=time()
	String userStr="recorded in "+room
	variable userSize=strlen(userStr)
	
	headerSize=200

	fSetPos refnum,0
	FBinWrite /b=2 /f=3 /u refnum,headerSize
	FBinWrite /b=2 /f=2 refnum,type
	FBinWrite /b=2 /f=2 refnum,version
	
	Fstatus refnum
	SetDataFolder recDF
	variable /g nscansPos=v_filePos
	SetDataFolder root:
	
	FBinWrite /b=2 /f=3 /u refnum,nscans
	FBinWrite /b=2 /f=3 refnum,numberOfChannels
	FBinWrite /b=2 /f=2 refnum,whichChan
	FBinWrite /b=2 /f=4 refnum,scanRate
	FBinWrite /b=2 /f=3 refnum,blockSize			
	FBinWrite /b=2 /f=4 refnum,scaleMult
	FBinWrite /b=2 /f=4 refnum,scaleOff
	FBinWrite /b=2 /f=3 refnum,dateSize
	FBinWrite /b=2 refnum,dateStr
	FBinWrite /b=2 /f=3 refnum,timeSize
	FBinWrite /b=2 refnum,timeStr
	FBinWrite /b=2 /f=3 refnum,userSize
	FBinWrite /b=2 refnum,userStr
	
	Fstatus refnum
	headerSize=v_filePos
	fsetPOS refnum,0
	
	FBinWrite /b=2/f=3/u refnum,headerSize
	
	fsetPos refnum,headerSize
end

function fixHeader()
	NVAR repsPerFile=$recDF+"repsPerFile"
	NVAR cnt=$recDF+"cnt"
	NVAR reps=$recDF+"reps"
	NVAR blockSize=$recDF+"blockSize"
	NVAR nscansPos=$recDF+"nscansPos"
	
	SVAR saveName=$recDF+"saveName"
	
	wave fileNums=$recDF+"filenums"
	
	variable refnum
	variable whichFile=floor(cnt/repsPerFile)
	if(reps>repsPerFile)
		open /A/P=path1/F=".bin" refnum as saveName+num2char(97+whichFile)+".bin"
	else
		open /A/P=path1/F=".bin" refnum as saveName+".bin"
	endif
	
	variable nscans=(cnt-floor(cnt/repsPerFile)*repsPerFile)*blockSize
	
	Fstatus refnum
	fsetpos refnum,nscansPos
	FBinWrite /b=2 /f=3 /u refnum,nscans
	fsetpos refnum,v_logEOF
	close refnum 
	
	variable i
	for(i=whichFile+1;i<numpnts(fileNums);i+=1)
		DeleteFile /P=path1 saveName+num2char(97+i)+".bin"
	endfor
end

function makeFIFO()

	NVAR FIFOsize=$recDF+"FIFOsize"
	NVAR FIFOrange=$recDF+"FIFOrange"
	NVAR fileNum=$recDF+"fileNum"			// TAS
	
	SVAR FIFOname=$recDF+"FIFOname"
	
	wave /t chanName=$recDF+"chanName"
	wave whichChan=$recDF+"whichChan"
	
	NewFIFO $FIFOname
	variable i
	for(i=0;i<numpnts(whichChan);i+=1)
		NewFIFOChan /W $FIFOname,$chanName[whichChan[i]],0,1,-FIFOrange,FIFOrange,""
	endfor
// link directly to file - WON'T WORK WITH MULTIPLE FILES!!!!
//	CtrlFIFO $FIFOname, file=fileNum			// TAS
	CtrlFIFO $FIFOname,deltaT=delta
	CtrlFIFO $FIFOname,size=FIFOsize
end

function /S getChannelInfo()

	NVAR FIFOrange=$recDF+"FIFOrange"

	string channelstring =""
	
	wave whichChan=$recDF+"whichChan"
	
	variable i
	for(i=0;i<numpnts(whichChan);i+=1)
		if(whichChan[i]>3)
			channelstring+=";"+num2str(whichChan[i]+12)+"/"+WiringType+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",-1,0"
		elseif(whichChan[i]==0)
//			channelstring+=";"+num2str(whichChan[i])+"/"+WiringType+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",-1,0"
			channelstring+=";"+num2str(whichChan[i])+"/"+"RSE"+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",-1,0"
		else
//			channelstring+=";"+num2str(whichChan[i])+"/"+WiringType+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",1,0"
			channelstring+=";"+num2str(whichChan[i])+"/"+"RSE"+",-"+num2str(FIFOrange)+","+num2str(FIFOrange)+",1,0"
		endif
	endfor
	return channelstring 
end

//Digital pulse used to trigger WaitForRec() on the stimulus computer
function doDigitalPulse()
	
	NVAR numDigitalPulse=$recDF+"numDigitalPulse"
	NVAR lengthDigitalPulse=$recDF+"lengthDigitalPulse"
	NVAR cInject=$recDF+"cInject"
	
	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	
	variable numTicks=lengthDigitalPulse*60
	
	variable i,j
	
	DAQmx_DIO_Config /DEV=NIDAQdevice /CLK={"/"+NIDAQdevice+"/ctr0internaloutput"} /DIR=1 "/"+NIDAQdevice+"/port0/line0"
	fDAQmx_DIO_Write(NIDAQdevice, V_DAQmx_DIO_TaskNumber, 0)
	
	for(i=0;i<numDigitalPulse;i+=1)
		j=ticks+numTicks
		do
		while(j>ticks)
		
		fDAQmx_DIO_Write(NIDAQdevice, V_DAQmx_DIO_TaskNumber, 1)
		
		j=ticks+numTicks
		do
		while(j>ticks)
		
		fDAQmx_DIO_Write(NIDAQdevice, V_DAQmx_DIO_TaskNumber, 0)
	endfor
	
	fDAQmx_DIO_Finished(NIDAQdevice, V_DAQmx_DIO_TaskNumber)
end

function WriteToWaveAndFile(s)
	STRUCT WMBackgroundStruct &s

	NVAR reps=$recDF+"reps"
	NVAR repsPerFile=$recDF+"repsPerFile"
	NVAR transferFIFO=$recDF+"transferFIFO"
	NVAR cnt=$recDF+"cnt"
	NVAR length=$recDF+"length"
	NVAR fileNum=$recDF+"fileNum"
	NVAR saveFile=$recDF+"saveFile"
	NVAR runningTime=$recDF+"runningTime"
	NVAR runTime=$recDF+"runTime"
	NVAR blockSize=$recDF+"blockSize"
	NVAR onlineAnalysis=$recDF+"onlineAnalysis"
	NVAR loopTime=$recDF+"loopTime"
	NVAR loopTimer=$recDF+"loopTimer"
	
	SVAR timeString=$recDF+"timeString"
	SVAR FIFOname=$recDF+"FIFOname"
	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	
	FIFOStatus /q $FIFOname
	if(v_FIFOChunks<transferFIFO+blockSize)
		return 0
	endif

	variable timer=startMSTimer
	
	onlineAnalysis=0
	
	wave /t chanName=$recDF+"chanName"
	wave whichChan=$recDF+"whichChan"
	
	string chan
	variable i=0
	for(i=0;i<numpnts(whichChan);i+=1)
		wave wv=$recDF+"wv"+num2str(i)
		FIFO2wave /r=[transferFIFO,transferFIFO+blockSize-1] $FIFOname,$chanName[whichChan[i]],wv
		if(saveFile)
			FBinWrite /B=2/F=2 fileNum,wv
		endif
	endfor
	
	timeString="Time: "+num2str(runningTime)+" - "+num2str(runningTime+length)		//Updating time display
	runningTime+=length			//Updating display time
	transferFIFO+=blockSize
	cnt+=1
	
	if(saveFile)
		wave fileNums=$recDF+"filenums"
		if(mod(cnt,repsPerFile)==0)
			fileNum=fileNums[floor(cnt/repsPerFile)]
		endif
	endif

	onlineAnalysis=1
	// function to do all the analysis and digital output requried	
	SVAR RoutineName = root:OA:RoutineName
	STRUCT WMBackgroundStruct dummy
	strswitch ( RoutineName )
		case "OnlineSpikeCount":
			OnlineSpikeCount_OA(dummy)
			break
		case "TrackObjSimple":
			TrackObjSimple_OA(dummy)
			break
		case "TrackObj1":
			TrackObj1_OA(dummy)
			break
		default :
			printf "Global root:OA:RoutineName has an unrecognized value (%s).  Aborting.\r", RoutineName
			return -1
			break
	endswitch
	OnlineAnalysis_MainLoop()
	
	runTime=stopMSTimer(timer)/1e6
	
	if ( 1 )		// benchmark loop
		wave rtb = root:RunTimeBenchmark
		NVAR OA_timer = root:ThresholdCh:OA_timer
		rtb[cnt-1][0] = runTime
		rtb[cnt-1][1] = OA_timer
		loopTime=stopMSTimer(loopTimer)/1e6
		loopTimer=startMSTimer
	endif

	if(cnt>=reps)
		doStop(0)
	endif
	
	return 0
end

function makeListBoxWaves()
	SetDataFolder recDF
	make /o/n=(numChans) chanSetting=0x30,whichChan=p
	make /o/t/n=(numChans) chanName
	variable i
	for(i=0;i<numChans;i+=1)
		chanName[i]="chan"+num2str(i)
	endfor
	SetDataFolder root:
end

Function CheckAll(name)
	String name

	wave CS=$recDF+"chanSetting"
	
	CS=CS | 0x10
	
	Button b1,title="Check Four",proc=CheckFour,win=Settings
End

Function CheckFour(name)
	String name
	
	wave CS=$recDF+"chanSetting"
	
	CS[0,3]=CS[p] | 0x10
	CS[4,numpnts(CS)-1]=CS[p] & ~0x10
	
	Button b1,title="Check All",proc=CheckAll,win=Settings
End

Function ResetDefaults(name)
	String name
	
	SetDefaultGlobals()
End

Function doneWithSetting(name)
	String name
	
	NVAR isPathSet=$recDF+"isPathSet"
	
	SetDataFolder recDF
	wave chanSetting
	wave whichChan
	
	duplicate /o chanSetting whichChan
	whichChan=(chanSetting & 0x10)==0x10 ? p : NaN
	sort whichChan,whichChan
	wavestats /q whichChan
	deletepoints v_npnts,v_numNaNs,whichChan
	
	KillWindow Settings
	
	variable deviceOn
	deviceOn=getDeviceName()
	
	if(deviceOn==0)
		changeSettings()
		return 0
	endif
	
	if(!isPathSet)
		NewPath /q/o/M="Where would you like to save your files?" path1
//		NewPath /q/o path1 "C:\Documents and Settings\Baccus Lab\Desktop\Tobi\data"
		PathInfo /S path1
	
		isPathSet=1
	endif
	
	SetDataFolder root:
	
	showDisplay()
End

function getDeviceName()

	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	
	string list=fDAQmx_DeviceNames()
	
	if(ItemsinList(list,";"))
		NIDAQdevice=StringFromList(0,list,";")
	elseif(ItemsinList(list,";")>1)
		NVAR thatOne
		chooseDevice(list)
		NIDAQdevice=StringFromList(thatOne,list,";")
		KillVariables /z thatOne
	else
		deviceIsOff()
		return 0
	endif
end

function chooseDevice(list)
	string list
	
	variable /g number=ItemsinList(list,";")
	variable /g thatOne
	
	variable which
	
	NewPanel /N=WhichDevice /K=2
	
	TitleBox tb1 win=WhichDevice,Frame=0,fsize=14,Title="Which Device?"
	CheckBox cb0 win=WhichDevice,value=1,mode=1,pos={0,30},title="1",proc=radioControl
	
	string CtrlName
	variable i
	for(i=1;i<number;i+=1)
		CtrlName="cb"+num2str(i)
		CheckBox $CtrlName win=WhichDevice,value=0,mode=1,title=num2str(i+1),proc=radioControl
	endfor
	
	Button b1 win=WhichDevice,title="Done",proc=choseDevice
	
	PauseForUser WhichDevice
end

Function radioControl(name,value)
	String name
	Variable value
	
	NVAR number
	NVAR thatOne
	
	string CtrlName
	
	variable i
	for(i=0;i<number;i+=1)
		CtrlName="cb"+num2str(i)
		CheckBox $CtrlName,value=StringMatch(name,CtrlName)
		if(StringMatch(name,CtrlName))
			thatOne=i
		endif
	endfor
End

function choseDevice(name)
	string name
	NVAR Number
	NVAR thatOne
	
	variable returnNumber=thatOne
	
	KillVariables /z Number
	KillWindow WhichDevice
end

function deviceIsOff()
	
	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	
	newPanel /N=DeviceOff /K=1
	TitleBox tb1 win=DeviceOff,Frame=0,fsize=14,title="Please turn NIDAQ on, then try again."
	PauseForUser DeviceOff
	return 0
end

function changeSettings() 

	ClearRecCache()		// TAS for clean reset
	
	NVAR /Z length=$recDF+"length"
	if (!NVAR_Exists(length))	
		setDefaultGlobals()
	endif
	
	if(WaveExists($recDF+"chanName")==0)
		makeListBoxWaves()
	endif
	
	NVAR /Z FIFOrange=$recDF+"FIFOrange"
	
	wave whichChan=$recDF+"whichChan"

	NewPanel /W=(447,44,782,511)/N=Settings /K=2
	ListBox lb1,pos={0,30},size={150,400},listWave=$recDF+"chanName"
	ListBox lb1,selWave=$recDF+"chanSetting",mode= 4
	
	if(numpnts(whichChan)<numChans)
		Button b1,pos={5,5},size={80,20},proc=CheckAll,title="Check All"
	else
		Button b1,pos={5,5},size={80,20},proc=CheckFour,title="Check Four"
	endif
	
	Button b2,pos={180,5},size={100,20},proc=ResetDefaults,title="Reset Defaults"
	SetVariable setvar0,pos={160,30},size={160,17},title="File Length (s)"
	SetVariable setvar0,font="Helvetica",fSize=14,value= $recDF+"fileLength"
	SetVariable setvar1,pos={160,50},size={160,17},title="Block Length (s)"
	SetVariable setvar1,font="Helvetica",fSize=14,value= $recDF+"length"
	SetVariable setvar2,pos={160,70},size={160,17},title="Stim Trigger"
	SetVariable setvar2,font="Helvetica",fSize=14,value= $recDF+"PhotodiodeLevel"
	variable popStart=whatIsTheRange()
	PopupMenu pm1 fsize=14,mode=popStart,pos={160,150},title="DAQ Range"
	PopupMenu pm1 proc=DAQRange,value="10;5;2;1"
	Button b3,pos={200,440},size={80,20},proc=doneWithSetting,title="Set"
end

function showDisplay()

	NVAR /Z blockSize=$recDF+"blockSize"
	NVAR /Z length=$recDF+"length"
	if (!NVAR_Exists(length))	
		setDefaultGlobals()
	endif
	
	if(WaveExists($recDF+"chanName")==0)
		makeListBoxWaves()
	endif
	
	NVAR FIFOrange=$recDF+"FIFOrange"
	NVAR saveFile=$recDF+"saveFile"
	NVAR cInject=$recDF+"cInject"
	NVAR oAnalysis=$recDF+"oAnalysis"
	
	variable deviceOn
	deviceOn=getDeviceName()
	
	if(deviceOn==0)
		return 0
	endif
	
	wave whichChan=$recDF+"whichChan"
	
	variable topPercentage=1
	
	doWindow RecordMEA
	if(V_flag==1)
		killWindow RecordMEA
	endif
	
	SetDataFolder recDF
	
	variable i,j,k
	for(i=0;i<numChans;i+=1)
		killwaves /z $"wv"+num2str(i)
	endfor
	
	for(i=0;i<numpnts(whichChan);i+=1)
		make /o/w/n=(blockSize) wv
		setscale /p x,0,delta,wv
		duplicate /o wv $"wv"+num2str(i)
	endfor
	
	killwaves /z wv
	
	SetDataFolder root:
	
	display /N=RecordMEA /k=1/w=(35.25,42.5,919.5,275.75)
	setwindow recordMEA, hook(hSelecteChannels)=GetSelectedChannel
	
	if (waveExists($OA_DF+"w_selected"))
		wave w_selected=$OA_DF+"w_selected"
		w_selected=0
	else
		make /o/n=(numChans) $OA_DF+"w_selected"=0
		wave w_selected=$OA_DF+"w_selected"
	endif
	
	variable VertSize=(numpnts(whichChan)<16) ? topPercentage/numpnts(whichChan) : topPercentage/16
	variable horizSize=.96/ceil(numpnts(whichChan)/16)
	variable horizPlace,vertPlace
	string botAxis,leftAxis
	
	k=0
	for(i=0;i<ceil(numpnts(whichChan)/16);i+=1)
		horizPlace=i*horizSize+i*.04/3
		botAxis="b"+num2str(i)
		for(j=0;j<min(numpnts(whichChan),16);j+=1)
			vertPlace=topPercentage-(j+1)*vertSize
			leftAxis="l"+num2str(j)
			wave wv=$recDF+"wv"+num2str(k)
			if(waveexists(wv))
//				appendtograph /b=$botAxis /l=$leftAxis wv
//				modifygraph axisenab($botAxis)={horizPlace,horizPlace+horizSize},axisenab($leftAxis)={vertPlace,vertPlace+vertSize}
			endif
			k+=1
		endfor
	endfor
	
	modifygraph /W=RecordMEA freepos={0,kwfraction}
	modifygraph /W=RecordMEA rgb=(0,0,0),nticks=2,ZisZ=1,btLen=1.5
	ModifyGraph /W=RecordMEA tick=3,nticks=0,axRGB=(65535,65535,65535)
	ModifyGraph tlblRGB=(65535,65535,65535),alblRGB=(65535,65535,65535)
//	movewindow /w=RecordMEA 2,2,2,2			// TAS

	controlbar 30	
	button bstart win=RecordMEA,fcolor=(3,52428,1),pos={10,5},fsize=14,title="Start",proc=StartStopButton
	SetVariable setvar0,size={140,5},pos={70,5},title="Time (s)"
	SetVariable setvar0,fSize=14,value= $recDF+"totTime"
	PopupMenu pm1 fsize=14,mode=1,pos={550,5},title="Scale"
	PopupMenu pm1 proc=displayRange,value=doPopUpMenu()
	Slider s1 win=RecordMEA,vert=0,value=length,pos={40,880},size={250,0},fsize=5
	variable numTicks=length/.25/2
	Slider s1 live=0,limits={.25,length,.25},proc=timeRescale,ticks=numTicks
	displayRange("pm1",1,"10")
	saveFileButtons(saveFile)
	cInjectButtons()
	analyzeButtons()
	
// TAS
	if ( 0 )		// switch to old testing behavior, where digital output determined by user controls
		SetDataFolder recDF
		variable /g DO_Value = 1			// digital value to write to port
		variable/g DO_Start = 0			// when flag is set, write digital lines
		variable/g DO_End = 0			// when flag is set, end digital output (reset to 0)
		
		SetVariable DigitalOut0,pos={824,7},size={60,16},title="DO0",limits={0,255,1}, value=_NUM:22
		SetVariable DigitalOut1,pos={892,7},size={60,16},title="DO1",limits={0,255,1}, value=_NUM:22
		SetVariable DigitalOut2,pos={965,7},size={60,16},title="DO2",limits={0,255,1}, value=_NUM:22
		//	SetVariable DigitalOut value=DO_Value
		// no global variable!!!
		CheckBox WriteDigitalPort,pos={1043,9},size={106,14},title="Write to digital port"
		CheckBox WriteDigitalPort,variable=DO_Start
		
		SetDataFolder root:
		//	PopUpMenu pm3, mode=1	
	elseif ( 1 )		// or to new behavior, where it's run by online analysis
	
	endif
end

function saveFileButtons(which)
	variable which
	
	if(which)
		checkbox cb1 win=RecordMEA,mode=0,pos={220,5},fsize=14,value=1,title="Save File",proc=doSave
		SetVariable setvar1,size={180,5},pos={305,5},title="File Name"
		SetVariable setvar1,fSize=14,value= $recDF+"saveName"
		button b2 win=RecordMEA,pos={490,5},fsize=14,title="Path",proc=changePath
	else
		checkbox cb1 win=RecordMEA,mode=0,pos={220,5},fsize=14,title="Save File",proc=doSave
	endif
	
end

function cInjectButtons()

	NVAR cInject=$recDF+"cInject"
	SVAR cWave=$recDF+"cWave"
	
	cInject=1
	cWave=""

	PopupMenu pm3 fsize=14,mode=2,pos={648,5},title="cInject"
	PopupMenu pm3 proc=getCurWave,value=GetInjectList()

end

Function /t getInjectList()
	string list="Start Immediately;"+"---;"+WaveList("*_cur",";","")
		
	return list
end

Function getCurWave(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	NVAR cInject=$recDF+"cInject"
	SVAR cWave=$recDF+"cWave"
	
	if(popNum==1)
		cInject=0
		cWave=""
	elseif(popNum==2)
		cInject=1
		cWave=""
	else
		cInject=1
		cWave=popStr
	endif
end

function analyzeButtons()

	string list=FunctionList("*_OA",";","")
//	print "list: \t", list
	if(ItemsInList(list,";")>=1)			// TAS changed to >= from >, since template isn't found by an independent procedure
		PopupMenu pm2 fsize=14,mode=1,pos={900,5},title=""
		PopupMenu pm2 proc=getOAfunc,value=GetOAlist()
		checkbox cb3 win=RecordMEA,mode=0,pos={800,7},fsize=14,title="Run Analysis",proc=setAnalysis
	endif
end

Function /t getOAlist()
	string list="---;"+FunctionList("*_OA",";","")
	list=RemoveFromList("Template_OA",list)
	
	return list
end

Function getOAfunc(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	SVAR analysisFunction=$recDF+"analysisFunction"
	
	analysisFunction=popStr
end

Function StartStopButton(ctrlName) : ButtonControl
	String ctrlName
	if( cmpstr(ctrlName,"bStart") == 0 )
		doStart()
	else
		doStop(1)
	endif
End

Function doStart()
	
	NVAR saveFile=$recDF+"saveFile"
	NVAR cInject=$recDF+"cInject"
	NVAR oAnalysis=$recDF+"oAnalysis"
	
	SVAR timeString=$recDF+"timeString"
	SVAR saveName=$recDF+"saveName"
	SVAR cWave=$recDF+"cWave"
	SVAR analysisFunction=$recDF+"analysisFunction"
	
	Button bStart win=RecordMEA,fcolor=(65535,0,0),title="Stop",rename=bstop
	
	killControl /W=RecordMEA setvar0
	KillControl /W=RecordMEA cb1
	KillControl /W=RecordMEA setvar1
	KillControl /W=RecordMEA b2
	KillControl /W=RecordMEA pm3
	titlebox tb1 win=RecordMEA,fsize=14,pos={100,5},variable=timeString
	
	if(saveFile)
		titlebox tb2 win=RecordMEA,fsize=14,pos={300,5},frame=0,title="Saved to "+saveName
	endif
	
	if(cInject && stringMatch(cWave,"")==0)
		titlebox tb3 win=RecordMEA,fsize=14,pos={700,5},frame=0,title="Injecting "+cWave
	endif
	
	Record()
	
End

Function doStop(early)
	variable early
	
	NVAR saveFile=$recDF+"saveFile"
	NVAR cInject=$recDF+"cInject"
	NVAR cnt=$recDF+"cnt"
	NVAR runningTime=$recDF+"runningTime"
	NVAR running=$recDF+"running"
	
	SVAR timeString=$recDF+"timeString"
	SVAR FIFOname=$recDF+"FIFOname"
	SVAR NIDAQdevice=$recDF+"NIDAQdevice"
	
	variable refnum
	variable i
	wave fileNums=$recDF+"filenums"
	
	CtrlNamedBackground _all_,stop=1
	CtrlNamedBackground WriteToWave, kill
	
	if(cInject)
		fDAQmx_WaveformStop(NIDAQdevice)
		make /o/n=100 rezero
		setscale /p x,0,delta,rezero
		DAQmx_WaveformGen /DEV=NIDAQdevice /NPRD=1 "rezero,0;"
	endif
	
	fDAQmx_ScanStop(NIDAQdevice)
	CtrlFIFO $FIFOname,stop
	if(saveFile)
		for(i=0;i<numpnts(fileNums);i+=1)
			refnum=fileNums[i]
			close refnum
		endfor
	endif
	
	KillFIFO $FIFOname
	
	if(early && saveFile)
		fixHeader()	
	endif

// TAS house-keeping
	OnlineAnalysis_stop()
	
	wave RunTimeBenchmark = root:RunTimeBenchmark
	redimension/n=(cnt+5, -1) RunTimeBenchmark		// TAS
	cnt=0
	runningTime=0
	running=0
	timeString="Time: "
	
	doMiniStop()

End

Function doMiniStop()
	NVAR saveFile=$recDF+"saveFile"
	NVAR oAnalysis=$recDF+"oAnalysis"
	
	doWindow /f RecordMEA

	Button bStop win=RecordMEA,fcolor=(3,52428,1),title="Start",rename=bStart
	KillControl tb1
	KillControl tb2
	KillControl tb3
	SetVariable setvar0,size={140,5},pos={70,5},title="Time (s)"
	SetVariable setvar0,fSize=14,value= $recDF+"totTime"
	saveFileButtons(saveFile)
	cInjectButtons()
End

Function doSave(ctrlName,checked) : CheckBoxControl
	String ctrlName
	Variable checked
	
	NVAR saveFile=$recDF+"saveFile"
	
	if(Checked)
		saveFile=1
		saveFileButtons(saveFile)
	else
		saveFile=0
		KillControl setvar1
		KillControl b2
	endif
End

Function changePath(name)
	String name
	
	NewPath /q/o/M="Where would you like to save your files?" path1
End

Function setAnalysis(ctrlName,checked) : CheckBoxControl
	String ctrlName
	Variable checked
	
	NVAR running=$recDF+"running"
	
	NVAR oAnalysis=$recDF+"oAnalysis"
	SVAR analysisFunction=$recDF+"analysisFunction"
	
	if(Checked)
		oAnalysis=1
		if(!stringMatch(analysisFunction,"---"))
			KillControl pm2
			titlebox tb4 win=RecordMEA,fsize=14,pos={1050,5},frame=0,title="running "+analysisFunction
			CtrlNamedBackground OnAnalysis, proc=$analysisFunction
			CtrlNamedBackground OA_init, proc=$analysisFunction+"_init"
			CtrlNamedBackground OA_init,start
		endif
	else
		if(!stringMatch(analysisFunction,"---"))
			if(running)
				CtrlNamedBackground OnAnalysis,stop
			endif
			CtrlNamedBackground OnAnalysis, kill
			CtrlNamedBackground OA_finish, proc=$analysisFunction+"_finish"
			CtrlNamedBackground OA_finish,start
			oAnalysis=0
			KillControl tb4
			PopupMenu pm2 win=RecordMEA,fsize=14,mode=1,pos={1020,5},title=""
			PopupMenu pm2 proc=getOAfunc,value=getOAlist()
			analysisFunction="---"
		endif
	endif
End

Function displayRange(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	wave whichChan=$recDF+"whichChan"
	
	variable range=2^16/(2^(popnum-1))/2
	
	variable i
	for(i=0;i<min(numpnts(whichChan),16);i+=1)
//		SetAxis $"l"+num2str(i) -range,range			// TAS, no display
	endfor
end

Function DAQRange(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	NVAR FIFOrange=$recDF+"FIFOrange"
	
	switch(popNum)
		case 1:
			FIFOrange=10
			break
		case 2:
			FIFOrange=5	
			break
		case 3:
			FIFOrange=2
			break
		case 4:
			FIFOrange=1
			break
	endswitch
end

Function timeRescale(name, value, event) : SliderControl
	String name
	Variable value
	Variable event
	
	wave whichChan=$recDF+"whichChan"	
				
	variable i
	for(i=0;i<ceil(numpnts(whichChan)/16);i+=1)
		SetAxis $"b"+num2str(i) 0,value
	endfor	
					
	return 0
End

function /S doPopUpMenu()

	NVAR FIFOrange=$recDF+"FIFOrange"
	
	string options=""
	
	variable i,range=FIFOrange
	for(i=0;range>.1;i+=1)
		range=floor(FIFOrange/(2^i)*1000)/1000
		options+=num2str(range)+";"
	endfor
	
	return options
end

function /S getDate()

	String expr="([[:alpha:]]+), ([[:alpha:]]+) ([[:digit:]]+), ([[:digit:]]+)"
	String dayOfWeek, monthName, dayNumStr, yearStr
	SplitString/E=(expr) date(), dayOfWeek, monthName, dayNumStr, yearStr
	
	string year=yearStr[2,3]
	
	variable month
	
	make/o/t/n=12 monthConvert
	monthConvert[0]="Jan"
	monthConvert[1]="Feb"
	monthConvert[2]="Mar"
	monthConvert[3]="Apr"
	monthConvert[4]="May"
	monthConvert[5]="Jun"
	monthConvert[6]="Jul"
	monthConvert[7]="Aug"
	monthConvert[8]="Sep"
	monthConvert[9]="Oct"
	monthConvert[10]="Nov"
	monthConvert[11]="Dec"
	
	string s1
	string monthStr
	variable i
	for(i=0;i<numpnts(monthConvert);i+=1)
		s1=monthConvert[i]
		if(StringMatch(monthName,s1))
			month=i+1
		endif
	endfor
	if(month<10)
		monthStr="0"+num2str(month)
	else
		monthStr=num2str(month)
	endif
	
	string dateStr=monthStr+dayNumStr+year
	return dateStr
end

function whatIsTheRange()
	NVAR FIFOrange=$recDF+"FIFOrange"
	
	variable range
	switch(FIFOrange)
		case 10:
			range=1
			break
		case 5:
			range=2	
			break
		case 2:
			range=3
			break
		case 1:
			range=4
			break
	endswitch
	
	return range
end

function cleanTimers()
	variable i,j
	for(i=0;i<10;i+=1)
		j=stopMSTimer(i)
	endfor
end

Function GetSelectedChannel(s)
	// Allows you to click in the MEAGRAPH and select/deselect channels for online analysis
	// In order for this function to work, the following line has to be executed after creation of the MEAGRAPH
	//	setwindow recordMEA, hook(hSelecteChannels)=GetSelectedChannel
	// This function uses and modifies wave $OA_DF+"w_selected"
	STRUCT WMWinHookStruct &s
	
	// access the wave holding all the info related with the channels struct and unpack it
			
	switch(s.eventCode)
		case 3:		//mousedown
			wave w_selected=$OA_DF+"w_selected"
			if (!waveExists(w_selected))
				make /n=64 $OA_DF+"w_selected"=1
				wave w_selected=$OA_DF+"w_selected"
			endif
			
			// (*) Get current screen position and size
			getWindow recordMEA, gsizeDC	// generates variables v_left, v_top, v_right, v_bottom with display info

			// (*) Take margins into account
			v_right*=(1-.021)+.021
			v_bottom*=(1-.094)								

			// (*) Convert the relative positions hpos and vpos into a channel number
			//	I'm assuming that there are 16 x 4 plots
			variable selectedRow = floor(s.mouseLoc.v*16/v_bottom)
			variable selectedCol =  floor(s.mouseLoc.h*4/v_right)
			if (selectedCol<0 || selectedCol>3 || selectedRow < 0 || selectedRow >15)
				// do nothing
			else
				variable selectedCh = selectedRow + 16*selectedCol
				if (w_selected[selectedCh])
					// Deselect item. Remove item from list and change color to balck
					w_selected[selectedCH] = 0
					modifygraph /w=recordMEA/z rgb($"wv"+num2str(selectedCH))=(0,0,0)
				else
					// Select item. Remove item from list and change color to red
					w_selected[selectedCH] = 1
					modifygraph /w=recordMEA/z rgb($"wv"+num2str(selectedCH))=(65535,0,0)
				endif
			endif

			break
	EndSwitch
end

function AcqErrorHook()
	string error
	do 
		error = fDAQmx_ErrorString()
		print error
	while ( stringmatch("",error)==1 )		// get all non-zero errors off the stack
end



//// Tobi's  procedures, added here because independent modules can't call outside functions

// Initialize output task
function DigitalOut_start()

	DFREF StartDF = GetDataFolderDFR()
	NewDataFolder/o/s root:DigitalOutput
	
	string/g NIDAQdevice = fDAQmx_DeviceNames()
	
	if( ItemsinList(NIDAQdevice,";") )
		NIDAQdevice=StringFromList(0,NIDAQdevice,";")
	elseif(ItemsinList(NIDAQdevice,";")>1)
		print "More than one device available!!!  Aborting."
		return -1
	endif

	make/o/n=1/b I16				// signed-16-bit integer
	make/o/n=1/b/u U16			// unsigned 16-bit integer
	string/g DIO_group

	sprintf DIO_group, "/%s/port0", NIDAQdevice
	DAQmx_DIO_Config/DEV=(NIDAQdevice)/DIR=1/LGRP=0 DIO_group
		// set up Digital Output for port0
	variable/g TaskNum_P0 = V_DAQmx_DIO_TaskNumber		// created by DIO_Config

	sprintf DIO_group, "/%s/port1", NIDAQdevice
	DAQmx_DIO_Config/DEV=(NIDAQdevice)/DIR=1/LGRP=0 DIO_group
		// set up Digital Output for port1
	variable/g TaskNum_P1 = V_DAQmx_DIO_TaskNumber		// created by DIO_Config

	sprintf DIO_group, "/%s/port2", NIDAQdevice
	DAQmx_DIO_Config/DEV=(NIDAQdevice)/DIR=1/LGRP=0 DIO_group
		// set up Digital Output for port2
	variable/g TaskNum_P2 = V_DAQmx_DIO_TaskNumber		// created by DIO_Config

	setdatafolder StartDF

end

// release DAQ task
function DigitalOut_stop()

	DFREF StartDF = GetDataFolderDFR()
	SetDataFolder root:DigitalOutput

	SVAR NIDAQdevice
	SVAR DIO_group
	NVAR TaskNum_P0, TaskNum_P1, TaskNum_P2

	fDAQmx_DIO_Finished(NIDAQdevice, TaskNum_P0)
	fDAQmx_DIO_Finished(NIDAQdevice, TaskNum_P1)
	fDAQmx_DIO_Finished(NIDAQdevice, TaskNum_P2)
	NIDAQdevice = ""
	DIO_group = ""
	TaskNum_P0 = -1
	TaskNum_P1 = -1
	TaskNum_P2 = -1

	SetDataFolder StartDF
end

// writes two values to the digital lines.  Note that the intracellular computer (takes input via parallel port)
// has a dead 0 and 2 line, and can only transmit 15 lines: to make this programming easier, ignore first 4 lines.
// That's equivalent to running this filter past any input: y = v0 & 0x007FF0
function DigitalOut_write(v, c)
variable v				// 8-bit integer: encodes shift
variable c				// 3-bit integer: encodes counter

	DFREF StartDF = GetDataFolderDFR()
	SetDataFolder root:DigitalOutput

	variable t, v0, v1, v2
	wave I16, U16			// since all variables are doubles, use these INT waves to recast

// OLD - for all 24 bits!
//	v2 = floor(v0/2^16) & 255
//	v1 = floor(v0/2^8) & 255
//	v0 = v0&255
	I16 = v
	U16 = I16[p]				// change number format
	t = (c*2^8 + U16)*2^4
	if ( (t<2^4 || t>2^15-1) & t!=0 )
		printf "Value exceeds range of an unsigned 15-bit integer: v=%d, c=%d.  Expected unexpected results.", v, c
	endif

	v0 = t & (15*2^4)
	v1 = (t & (15*2^8))/2^8 + c*2^4
	if ( 0 )			// debugging
		printf "%d\t\t%d\r", i16[0], u16[0]
		printf "%d\t\t%d\t\t%d\t\t\t",v, c, t
		printf "%X\t\t%X\t\t%X\t\t\t",v, c, t
		printf "%X\t\t%X\r",v0, v1
	endif

	SVAR NIDAQdevice
	SVAR DIO_group
	NVAR TaskNum_P0, TaskNum_P1, TaskNum_P2
	
 	fDAQmx_DIO_Write(NIDAQdevice, TaskNum_P0, v0)
 	fDAQmx_DIO_Write(NIDAQdevice, TaskNum_P1, v1)
// 	fDAQmx_DIO_Write(NIDAQdevice, TaskNum_P2, v2)			// port 2 is currently useless: may be eventually fixed

	SetDataFolder StartDF

 end
 
 Function OutputBlip()
 
 	DigitalOut_start()
 	
 	variable i
 	
 	DigitalOut_write(0,0)

 	i = ticks + 10			// 1 tick = 1/60 s
 	do
 	while ( i>ticks)
 	DigitalOut_write(1+257+1*2^16,0xFF)

 	i = ticks + 1		// 1 tick = 1/60 s
 	do
 	while ( i>ticks)
 	DigitalOut_write(3+3*256+3*2^16, 0xFF)

 	i = ticks + 2			// 1 tick = 1/60 s
 	do
 	while ( i>ticks)
 	DigitalOut_write(0,0)
 	
 	DigitalOut_stop()
 end

