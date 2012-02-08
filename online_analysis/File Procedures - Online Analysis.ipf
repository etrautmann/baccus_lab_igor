#pragma rtGlobals=1		// Use modern global access method.


// Function from David
function getChannel(chan,length[, filename, quiet])
	variable chan,length
	string filename			// optional file name to load in
	variable quiet				// set to suppress output to command line
	
	variable refnum
	if (paramisdefault(filename) == 0 )		// the optional parameter overrides everything
		open /R/F="All Files:.*;Bin Files (*.bin):.bin;" refnum as filename
	elseif ( 1 )			// toggle between query and hard coding
		open /R/F="All Files:.*;Bin Files (*.bin):.bin;" refnum
	else
		filename = "C:Documents and Settings:Baccus Lab:Desktop:Tobi:data:"
		filename += "111011_ResponseDelay2_100ms.bin"
//		filename += ".bin"
//		print "Loading channel from file "+ filename
		open/r/f=".bin" refnum as filename	
	endif
	fstatus refnum
	if ( paramisdefault(quiet) || quiet==0 )
		print "Loading file: "+S_path+S_filename
	endif
	
	readHeader(refnum)
	wave /t header
	variable headerSize=str2num(header[0][1])
	variable nscans=str2Num(header[3][1])
	variable numChans=str2Num(header[4][1])
	variable blockSize=str2num(header[6][1])
	variable scanRate=str2num(header[5][1])
	variable blockTime=blockSize/scanRate
	variable numBlocks=ceil(length/blockTime)
	variable totTime=nscans/scanRate
	numBlocks=min(ceil(totTime/blockTime),numBlocks)
	
	variable scaleMult=str2num(header[7][1])
	variable scaleOff=str2num(header[8][1])
	
	make /o/n=0 output
	make /o/n=(blockSize) block
	
	variable i
	for(i=0;i<numBlocks;i+=1)
		FsetPos refnum,0
		FsetPos refnum,headerSize+i*blockSize*numChans*2+chan*blockSIze*2
		FBinRead /b=2 /f=2 refnum,block
		concatenate /NP=0 "block;",output
	endfor
	
	setScale /p x,0,1/scanRate,output
	
	output+=scaleOff
	output*=scaleMult
	
	killwaves/z block
	close refnum
end

function readHeader(refnum)
	variable refnum
	
	variable storedPos
	FStatus refnum
	storedPos=v_filePos
	
	fSetPos refnum,0
	
	variable headerSize,type,version,nscans,numberOfChannels
	variable scanRate,blockSize,scaleMult,scaleOff,dateSize,timeSize,userSize
	String dateStr="",timeStr="",userStr=""
	
	
	FBinRead /b=2 /f=3 /u refnum,headerSize
	FBinRead /b=2 /f=2 refnum,type
	FBinRead /b=2 /f=2 refnum,version
	FBinRead /b=2 /f=3 /u refnum,nscans
	FBinRead /b=2 /f=3 refnum,numberOfChannels
	
	make /o/n=(numberOfChannels) whichChan
	
	FBinRead /b=2 /f=2 refnum,whichChan
	FBinRead /b=2 /f=4 refnum,scanRate
	FBinRead /b=2 /f=3 refnum,blockSize
	FBinRead /b=2 /f=4 refnum,scaleMult
	FBinRead /b=2 /f=4 refnum,scaleOff
	FBinRead /b=2 /f=3 refnum,dateSize
	dateStr=PadString(dateStr,dateSize,0)
	FBinRead /b=2 refnum,dateStr
	FBinRead /b=2 /f=3 refnum,timeSize
	timeStr=PadString(timeStr,timeSize,0)
	FBinRead /b=2 refnum,timeStr
	FBinRead /b=2 /f=3 refnum,userSize
	userStr=PadString(userStr,userSize,0)
	FBinRead /b=2 refnum,userStr
	
	make /o/t/n=(12,2) header
	header[0][0]="headerSize"
	header[0][1]=num2str(headerSize)
	header[1][0]="type"
	header[1][1]=num2str(type)
	header[2][0]="version"
	header[2][1]=num2str(version)
	header[3][0]="nscans"
	header[3][1]=num2str(nscans)
	header[4][0]="numberOfChannels"
	header[4][1]=num2str(numberOfChannels)
	header[5][0]="scanRate"
	header[5][1]=num2str(scanRate)
	header[6][0]="blockSize"
	header[6][1]=num2str(blockSize)
	header[7][0]="scaleMult"
	header[7][1]=num2str(scaleMult)
	header[8][0]="scaleOff"
	header[8][1]=num2str(scaleOff)
	header[9][0]="date"
	header[9][1]=dateStr
	header[10][0]="time"
	header[10][1]=timeStr
	header[11][0]="room"
	header[11][1]=userStr
	
	fsetPos refnum,storedPos
end


// Function from David
// hacked to add filename input, and arbitrary offset
// not aware of multi-file data sets
// not aware of improper offset or channel numbers!!!
// returns full path to file
function/S getChannel1(chan, offset, length[, filename, quiet])
	variable chan
	variable offset, length		// offset and length in seconds
	string filename			// optional file name to load in
	variable quiet				// set to suppress output to command line
	
	variable refnum
	if (paramisdefault(filename) == 0 )		// the optional parameter overrides everything
		open /R/F="All Files:.*;Bin Files (*.bin):.bin;" refnum as filename
	elseif ( 1 )			// toggle between query and hard coding
		open /R/F="Bin Files (*.bin):.bin;" refnum
	else
		filename = "C:Documents and Settings:Baccus Lab:Desktop:Tobi:data:"
		filename += "111011_ResponseDelay2_100ms.bin"
//		filename += ".bin"
//		print "Loading channel from file "+ filename
		open/r/f=".bin" refnum as filename	
	endif
	fstatus refnum
	if ( paramisdefault(quiet) || quiet==0 )
		print "Loading file: "+S_path+S_filename
	endif
	
	readHeader(refnum)
	wave /t header
	variable headerSize=str2num(header[0][1])
	variable nscans=str2Num(header[3][1])
	variable numChans=str2Num(header[4][1])
	variable blockSize=str2num(header[6][1])
	variable scanRate=str2num(header[5][1])
	variable pOffset = round(offset*scanRate)			// translate this to points, and round to an integer
	variable pLength = round(length*scanRate)		
	
	fstatus refnum
	make /o/n=0 output=NaN
	variable SamplesInFile = floor(((V_logEOF-headerSize)/2/numChans)/blockSize)*blockSize
				// round to last complete block, in case write to file crashed in the middle of a block...
	if ( pOffset<0 )
		print "Offset cannot be negative. Aborting."
		return ""
	elseif ( pOffset > SamplesInFile )
		printf "Offset beyond end of file (%.3f s).  Aborting.\r", SamplesInFile/ScanRate
		return ""
	elseif ( pOffset+pLength > SamplesInFile )
		printf "Asking for points beyond end of file (%.3f s).  Reducing length accordingly.\r", SamplesInFile/ScanRate
		pLength = SamplesInFile - pOffset
	endif

	variable numBlocks = ceil((pOffset+pLength)/blockSize) - floor(pOffset/blockSize)
	variable firstBlock = floor(pOffset/blockSize)
	variable scaleMult=str2num(header[7][1])
	variable scaleOff=str2num(header[8][1])
	
	variable i, fpos
	for(i=0;i<numBlocks;i+=1)
		if ( i==0 )		// beginning, in case offset is a fraction of the block size
			if ( mod(pOffset, blockSize) == 0 )
				make/o/n=(blockSize) block			// if no fractional offset
			else
				make /o/n=(blockSize - mod(pOffset, blockSize)) block
			endif

			fpos = headerSize + (firstBlock*numChans+chan)*2*blocksize + mod(pOffset, blockSize)*2
			FsetPos refnum, fpos
			FBinRead /b=2 /f=2 refnum, block
			Concatenate /NP=0 "block;", output
			Redimension/n=(BlockSize) block			// ...and reset for rest of if-loop
//	setScale /p x,offset,1/scanRate,output		// for testing

		elseif ( i==numBlocks-1 )		// end, to only read what's needed
			if ( mod(pOffset+pLength, blockSize) != 0 )
				redimension/n=(mod(pOffset+pLength, blockSize)) block		// fractional part remains
			endif
			
			fpos = headerSize + ((i+firstBlock)*numChans+chan) * blockSize*2
			FsetPos refnum, fpos
			FBinRead /b=2 /f=2 refnum,block
			concatenate /NP=0 "block;",output
		else		// in the middle
			fpos = headerSize + ((i+firstBlock)*numChans+chan) * blockSIze*2
			FsetPos refnum, fpos
			FBinRead /b=2 /f=2 refnum,block
			concatenate /NP=0 "block;",output
		endif
//		printf "%d\t", fpos
//		doupdate
	endfor
//	printf "\r"
	
	setScale /p x,pOffset/scanRate,1/scanRate,output
	output+=scaleOff
	output*=scaleMult

	killwaves/z block
	close refnum
	return S_path+S_filename
end
