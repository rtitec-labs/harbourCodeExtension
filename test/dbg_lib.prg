// DO NOT REMOVE THIS PRAGMA
// if the debugger code has DEBUGINFO the program will crash for stack overflow 
#pragma -B-

#include <hbdebug.ch>
#include <hbmemvar.ch>
#include <hboo.ch>
#include <hbclass.ch>

#ifndef HB_DBG_CS_LEN
#define HB_DBG_CS_MODULE      1  /* module name (.prg file) */
#define HB_DBG_CS_FUNCTION    2  /* function name */
#define HB_DBG_CS_LINE        3  /* start line */
#define HB_DBG_CS_LEVEL       4  /* eval stack level of the function */
#define HB_DBG_CS_LOCALS      5  /* an array with local variables */
#define HB_DBG_CS_STATICS     6  /* an array with static variables */
#define HB_DBG_CS_LEN         6
#endif

#ifndef HB_DBG_VAR_LEN
#define HB_DBG_VAR_NAME          1  /* variable name */
#define HB_DBG_VAR_INDEX         2  /* index */
#define HB_DBG_VAR_TYPE          3  /* type of variable: "L", "S", "G" */
#define HB_DBG_VAR_FRAME         4  /* eval stack level of the function or static frame */
#define HB_DBG_VAR_LEN           4
#endif

#define CRLF e"\r\n"
#ifndef DBG_PORT
// Temp, I hope to find another way to do InterProcessCommunication that uses ProcessId as unique key
// in the meanwhile, you can change the port using compiler command line argumend -D to set DBG_PORT
// to another value, it is useful if you need to debug 2 programm in the same time.
#define DBG_PORT 6110
#endif

// returns .T. if need step
static procedure CheckSocket(lStopSent) 
	LOCAL tmp, lNeedExit := .F.
	LOCAL t_oDebugInfo := __DEBUGITEM()
	lStopSent := iif(empty(lStopSent),.F.,lStopSent)
	// if no server then start it.
	if(empty(t_oDebugInfo['socket']))
		hb_inetInit()
		t_oDebugInfo['socket'] := hb_inetCreate(1000)
		hb_inetConnect("127.0.0.1",DBG_PORT,t_oDebugInfo['socket'])
	endif
	do while .T.
		if hb_inetErrorCode(t_oDebugInfo['socket']) <> 0
			//? "socket error",hb_inetErrorDesc( t_oDebugInfo['socket'] )
			//disconnected?
			t_oDebugInfo['lRunning'] := .T.
			t_oDebugInfo['aBreaks'] := {=>}
			t_oDebugInfo['maxLevel'] := nil
			return 
		endif
		
		do while hb_inetDataReady(t_oDebugInfo['socket']) = 1
			tmp := hb_inetRecvLine(t_oDebugInfo['socket'])
			if .not. empty(tmp)
				//? "<<", tmp
				if subStr(tmp,4,1)==":"
					sendCoumpoundVar(tmp, hb_inetRecvLine(t_oDebugInfo['socket']))
					loop
				endif
#ifndef __XHARBOUR__
#define BEGIN_C switch tmp
#define COMMAND case 
#dedine END_COM exit
#define END_C endswitch
#else
#define BEGIN_C do case
#define COMMAND case tmp=
#define END_COM 
#define END_C endcase
#endif
				BEGIN_C
					COMMAND "PAUSE"
						t_oDebugInfo['lRunning'] := .F.
						if .not. lStopSent
							hb_inetSend(t_oDebugInfo['socket'],"STOP:pause"+CRLF)
							lStopSent := .T.
						endif
						END_COM
					COMMAND "GO"
						t_oDebugInfo['lRunning'] := .T.
						lNeedExit := .T.
						END_COM
					COMMAND "STEP" // go to next line of code even if is in another procedure
						t_oDebugInfo['lRunning'] := .F.
						lNeedExit := .T.
						END_COM
					COMMAND "NEXT" // go to next line of same procedure
						t_oDebugInfo['lRunning'] := .T.
						t_oDebugInfo['maxLevel'] := t_oDebugInfo['__dbgEntryLevel']
						lNeedExit := .T.
						END_COM
					COMMAND "EXIT" // go to callee procedure
						t_oDebugInfo['lRunning'] := .T.
						t_oDebugInfo['maxLevel'] := t_oDebugInfo['__dbgEntryLevel'] -1
						lNeedExit := .T.
						END_COM
					COMMAND "STACK" 
						sendStack()
						END_COM
					COMMAND "BREAKPOINT"
						setBreakpoint(hb_inetRecvLine(t_oDebugInfo['socket']))
						END_COM
					COMMAND "LOCALS"
						sendLocals(hb_inetRecvLine(t_oDebugInfo['socket']),tmp)
						END_COM							
					COMMAND "STATICS"
						sendStatics(hb_inetRecvLine(t_oDebugInfo['socket']),tmp)
						END_COM
					COMMAND "PRIVATES"
						sendFromInfo(tmp,hb_inetRecvLine(t_oDebugInfo['socket']),HB_MV_PRIVATE, .T.)
						END_COM
					COMMAND "PRIVATE_CALLEE"
						sendFromInfo(tmp,hb_inetRecvLine(t_oDebugInfo['socket']),HB_MV_PRIVATE, .F.)
						END_COM
					COMMAND "PUBLICS"
						sendFromInfo(tmp,hb_inetRecvLine(t_oDebugInfo['socket']),HB_MV_PUBLIC)
						END_COM
					//COMMAND "GLOBALS"
					//	sendVariables(HB_MV_PUBLIC,.F.)
					//	END_COM
					//COMMAND "EXTERNALS"
					//	sendVariables(HB_MV_PUBLIC,.F.)
					//	END_COM
					COMMAND "EXPRESSION"
						sendExpression(hb_inetRecvLine(t_oDebugInfo['socket']))
						END_COM
					COMMAND "INERROR"
						//? "INERROR",t_oDebugInfo['inError']
						if t_oDebugInfo['inError']
							hb_inetSend(t_oDebugInfo['socket'],"INERROR:True"+CRLF)
						else
							hb_inetSend(t_oDebugInfo['socket'],"INERROR:False"+CRLF)
						endif
						END_COM
					COMMAND "ERROR_VAR"
						hb_inetRecvLine(t_oDebugInfo['socket'])
						hb_inetSend(t_oDebugInfo['socket'],"ERROR_VAR 0"+CRLF)
						if t_oDebugInfo['inError']
							hb_inetSend(t_oDebugInfo['socket'],"ERR:0:0::Error:O:" + format(t_oDebugInfo['error'])+CRLF)
						endif
						hb_inetSend(t_oDebugInfo['socket'],"END"+CRLF)
					END_COM
				END_C	
#undef BEGIN_C
#undef COMMAND 
#undef END_C
			endif
		enddo
		if lNeedExit
			return
		endif	
		if t_oDebugInfo['lRunning']
			if inBreakpoint()
				t_oDebugInfo['lRunning'] := .F.
				if .not. lStopSent
					hb_inetSend(t_oDebugInfo['socket'],"STOP:break"+CRLF)
					lStopSent := .T.
				endif
			endif
			if __dbgInvokeDebug(.F.)
				t_oDebugInfo['lRunning'] := .F.
				if .not. lStopSent
					hb_inetSend(t_oDebugInfo['socket'],"STOP:AltD"+CRLF)
					lStopSent := .T.
				endif
			endif
			if .not. empty(t_oDebugInfo['maxLevel']) 
				if t_oDebugInfo['maxLevel'] < t_oDebugInfo['__dbgEntryLevel']
					// we are not in the same procedure
					return
				endif
				t_oDebugInfo['maxLevel'] := nil
				t_oDebugInfo['lRunning'] := .F.
				if .not. lStopSent
					hb_inetSend(t_oDebugInfo['socket'],"STOP:next"+CRLF)
					lStopSent := .T.
				endif
			endif
		endif	
		if t_oDebugInfo['lRunning'] 
			return
		else
			if .not. lStopSent
				hb_inetSend(t_oDebugInfo['socket'],"STOP:step"+CRLF)
				lStopSent := .T.
			endif
			hb_idleSleep(0.1)
		endif
	enddo
	// unreachable code
return

static procedure sendStack() 
	local i,d,p, line, module, functionName,l, start := 3
	LOCAL t_oDebugInfo := __DEBUGITEM()
	local aStack := t_oDebugInfo['aStack']
	if t_oDebugInfo['inError']
		start := 4
	endif
	d := __dbgProcLevel()-1
	hb_inetSend(t_oDebugInfo['socket'],"STACK " + alltrim(str(d-start+1))+CRLF)
	//? "send stack---", d, d-start+1
	for i:=start to d
		l := d-i+1
		IF ( p := AScan( aStack, {| a | a[ HB_DBG_CS_LEVEL ] == l } ) ) > 0
			line			:= aStack[p,HB_DBG_CS_LINE]
			module			:= aStack[p,HB_DBG_CS_MODULE]
			functionName	:= aStack[p,HB_DBG_CS_FUNCTION]
			//? i," DEBUG ", module+":"+alltrim(str(line))+ ":"+functionName + "- ("+ ;
			//	procFile(i)+":"+alltrim(str(procLine(i)))+ ":"+ProcName(i) +")", l
		else
			line			:= procLine(i)
			module			:= procFile(i)
			functionName	:= ProcName(i)
			//? i,"NODEBUG", module+":"+alltrim(str(line))+ ":"+functionName, l
		endif
		hb_inetSend(t_oDebugInfo['socket'], module+":"+alltrim(str(line))+ ;
			":"+functionName+CRLF)
	next
	//? "---"
return

static function format(value) 
	switch valtype(value)
		case "U"
			return "nil"
		case "C"
		case "M"
			if at('"',value)==0
				return '"'+value+'"'
			elseif at("'",value)==0
				return "'"+value+"'"
			else
				return "["+value+"]" //i don't like it decontexted 
			endif
		case "N"
			return alltrim(str(value))
		case "L"
			return iif(value,".T.",".F.")
		case "D"
			return 'd"'+left(hb_TsToStr(value),10)+'"'
		case "T"
			return 't"'+hb_TsToStr(value)+'"'
		case "A"
		case "H"
			return alltrim(str(len(value)))
		case "B"
			return "{|| ...}"
		case "O"
			//return value:ClassName()+" "+alltrim(str(len(value)))
			return value:ClassName()+" "+alltrim(str(len(__objGetMsgList(value,.T.,HB_MSGLISTALL))))
		case "P"
			return "Pointer"
		case "S"
			RETURN "@" + value:name + "()"
		endswitch
return ""

static function GetStackId(level,aStack)
	local l := __DEBUGITEM()['__dbgEntryLevel'] - level
	if empty(aStack)
		aStack := __DEBUGITEM()['aStack']
	endif
return AScan( aStack, {| a | a[ HB_DBG_CS_LEVEL ] == l } )

static function GetStackAndParams(cParams, aStack) 
	local aParams := hb_aTokens(cParams,":")
	local iStack
	local iStart := val(aParams[2])
	local iCount := val(aParams[3])
	local idx := val(aParams[1])
	local l := __DEBUGITEM()['__dbgEntryLevel'] - idx
	iStack := GetStackId(idx,aStack)
return {iStack, iStart, iCount,l,idx} //l and idx used by sendFromInfo

static procedure sendLocals(cParams,prefix) 
	LOCAL t_oDebugInfo := __DEBUGITEM()
	local aStack := t_oDebugInfo['aStack']
	local aParams := GetStackAndParams(cParams,aStack)
	local iStack := aParams[1]
	local iStart := aParams[2]
	local iCount := aParams[3]
	local i, aInfo, value, cLine
	//? "sendLocals", cParams, alltrim(str(aParams[5]))
	hb_inetSend(t_oDebugInfo['socket'],prefix+" "+alltrim(str(aParams[5]))+CRLF)
	if iStack>0
		if iCount=0
			iCount := len(aStack[iStack,HB_DBG_CS_LOCALS])
		endif
		for i:=iStart to iStart+iCount
			if(i>len(aStack[iStack,HB_DBG_CS_LOCALS]))
				exit
			endif
			aInfo := aStack[iStack,HB_DBG_CS_LOCALS,i]
			value := __dbgVMVarLGet( __dbgProcLevel()-aInfo[ HB_DBG_VAR_FRAME ], aInfo[ HB_DBG_VAR_INDEX ] )
			// LOC:LEVEL:IDX::
			cLine := left(prefix,3) + ":" + alltrim(str(aInfo[ HB_DBG_VAR_FRAME ])) + ":" + ;
					alltrim(str(aInfo[ HB_DBG_VAR_INDEX ])) + "::" + ;
					aInfo[HB_DBG_VAR_NAME] + ":" + valtype(value) + ":" + format(value)
			hb_inetSend(t_oDebugInfo['socket'],cLine + CRLF )
		next
	endif
	hb_inetSend(t_oDebugInfo['socket'],"END"+CRLF)
return

static procedure sendStatics(cParams,prefix) 
	LOCAL t_oDebugInfo := __DEBUGITEM()
	local aStack := t_oDebugInfo['aStack']
	local aModules := t_oDebugInfo['aModules']
	local cModule, idxModule, nVarMod, nVarStack
	local aParams := GetStackAndParams(cParams,aStack)
	local iStack := aParams[1]
	local iStart := aParams[2]
	local iCount := aParams[3]
	local i, aInfo, value, cLine

	if iStack>0
		cModule := lower(allTrim(aStack[iStack,HB_DBG_CS_MODULE]))
		idxModule := aScan(aModules, {|v| v[1]=cModule})
	else
		idxModule := 0
	endif
	if idxModule>0
		nVarMod:=len(aModules[idxModule,4])
	else
		nVarMod:=0
	endif
	nVarStack := iif(iStack>0,len(aStack[iStack,HB_DBG_CS_STATICS]),0)
	iStart:= iif(iStart>nVarMod+nVarStack  , nVarMod+nVarStack , iStart )
	iStart:= iif(iStart<1				   , 1				   , iStart )
	iCount:= iif(iCount<1				   , nVarMod+nVarStack , iCount )

	hb_inetSend(t_oDebugInfo['socket'],prefix+" "+alltrim(str(aParams[5]))+CRLF)
	for i:=iStart to iStart+iCount
		if i<=nVarMod
			aInfo := aModules[idxModule,4,i]	
		elseif i<=nVarMod+nVarStack
			aInfo := aStack[iStack,HB_DBG_CS_STATICS,i-nVarMod]
		else
			exit
		endif
		value := __dbgVMVarSGet( aInfo[ HB_DBG_VAR_FRAME ], aInfo[ HB_DBG_VAR_INDEX ] )
		// LOC:LEVEL:IDX::
		cLine := left(prefix,3) + ":"+alltrim(str(iStack))+":" + alltrim(str(i)) + "::" + ;
				 aInfo[HB_DBG_VAR_NAME] + ":" + valtype(value) + ":" + format(value)
		hb_inetSend(t_oDebugInfo['socket'],cLine + CRLF )
	next
	hb_inetSend(t_oDebugInfo['socket'],"END"+CRLF)
return

static function MyGetSta(iStack,varIndex)
	LOCAL t_oDebugInfo := __DEBUGITEM()
	local aStack := t_oDebugInfo['aStack']
	local aModules := t_oDebugInfo['aModules']
	LOCAL cModule, idxModule
	local nVarMod, aInfo, nVarStack := iif(iStack>0,len(aStack[iStack,HB_DBG_CS_STATICS]),0)
	if iStack>0
		cModule := lower(allTrim(aStack[iStack,HB_DBG_CS_MODULE]))
		idxModule := aScan(aModules, {|v| v[1]=cModule})
	else
		idxModule := 0
	endif
	if idxModule>0
		nVarMod:=len(aModules[idxModule,4])
	else
		nVarMod:=0
	endif
	if varIndex<=nVarMod
		aInfo := aModules[idxModule,4,varIndex]	
	elseif varIndex<=nVarMod+nVarStack
		aInfo := aStack[iStack,HB_DBG_CS_STATICS,varIndex-nVarMod]
	else
		return nil
	endif
return  __dbgVMVarSGet( aInfo[ HB_DBG_VAR_FRAME ], aInfo[ HB_DBG_VAR_INDEX ] )

static procedure sendFromInfo(prefix, cParams, HB_MV, lLocal) 
	LOCAL t_oDebugInfo := __DEBUGITEM()
	local aStack := t_oDebugInfo['aStack']
	local nVars := __mvDbgInfo( HB_MV )
	local aParams := GetStackAndParams(cParams,aStack)
	//local iStack := aParams[1]
	local iStart := aParams[2]
	local iCount := aParams[3]
	local iLevel := aParams[4]
	local i, cLine, cName, value
	local nLocal := __mvDbgInfo( HB_MV_PRIVATE_LOCAL, iLevel )
	hb_inetSend(t_oDebugInfo['socket'],prefix+" "+alltrim(str(aParams[5]))+CRLF)
	if iCount=0
		iCount := nVars
	endif
	//? "send From Info", cParams, alltrim(str(aParams[5])), nVars, HB_MV, iLevel
	for i:=iStart to iStart+iCount
	//for i:=1 to nVars
		if i > nVars
			loop
		endif
		if HB_MV = HB_MV_PRIVATE 
			if lLocal .and. i>nLocal
				loop
			endif
			if .not.  lLocal .and. i<=nLocal
				loop
			endif
		endif
		value := __mvDbgInfo( HB_MV, i, @cName )
		// PRI::i:
		cLine := left(prefix,3) + "::" + alltrim(str(i)) + "::" +;
				  cName + ":" + valtype(value) + ":" + format(value)
		hb_inetSend(t_oDebugInfo['socket'],cLine + CRLF )
	next

	hb_inetSend(t_oDebugInfo['socket'],"END"+CRLF)
return 

static function getValue(req) 
	local aInfos := hb_aTokens(req,":")
	local v, i, aIndices, cName
	//? "getValue", req
#ifndef __XHARBOUR__
#define BEGIN_T switch aInfos[1]
#define TYPE case 
#define ENDTYPE exit
#define END_T endswitch
#else
#define BEGIN_T do case
#define TYPE case aInfos[1]=
#define ENDTYPE 
#define END_T endcase
#endif
	
	BEGIN_T
		TYPE "ERR"
			v := __DEBUGITEM()["error"]
			ENDTYPE
		TYPE "LOC"
			v := __dbgVMVarLGet(__dbgProcLevel()-val(aInfos[2]),val(aInfos[3]))
			ENDTYPE
		TYPE "STA"
			v := MyGetSta(val(aInfos[2]),val(aInfos[3]))
			ENDTYPE
		TYPE "GLO"
			v := __dbgVMVarSGet(val(aInfos[2]),val(aInfos[3]))
			ENDTYPE
		TYPE "EXT"
			v := __dbgVMVarSGet(val(aInfos[2]),val(aInfos[3]))
			ENDTYPE
		TYPE "PRI"
			v := __mvDbgInfo(HB_MV_PRIVATE,val(aInfos[3]), @cName)
			ENDTYPE
		TYPE "PUB"
			v := __mvDbgInfo(HB_MV_PUBLIC,val(aInfos[3]), @cName)
			ENDTYPE
		TYPE "EXP"
			// TODO: aInfos[3] can include a : 
			v := evalExpression( aInfos[3], val(aInfos[2]))
		END_T
#undef BEGIN_T
#undef TYPE
#undef END_T
	// some variable changes its type during execution. mha
	if at(valtype(v),"AHO") == 0
		return {}
	endif
	req := aInfos[1]+":"+aInfos[2]+":"+aInfos[3]+":"+aInfos[4]
	if len(aInfos[4])>0
		aIndices := hb_aTokens(aInfos[4],",")
		for i:=1 to len(aIndices)
			switch(valtype(v))
				case "A"
					v:=v[val(aIndices[i])]
					exit
				case "H"
					if i>len(v)
						v := nil
					else
						v := hb_HValueAt(v,val(aIndices[i]))
					endif
					exit
				case "O"
					v :=  __dbgObjGetValue(val(aInfos[2]),v,aIndices[i])
			endswitch
		next
	endif	
return v

STATIC FUNCTION __dbgObjGetValue( nProcLevel, oObject, cVar )

   LOCAL xResult
   LOCAL oErr

#ifdef __XHARBOUR__
   TRY
      xResult := dbgSENDMSG( nProcLevel, oObject, cVar )
   CATCH
      TRY
         xResult := dbgSENDMSG( 0, oObject, cVar )
      CATCH
         xResult := oErr:description
      END
   END
#else
   BEGIN SEQUENCE WITH {|| Break() }
      xResult := __dbgSENDMSG( nProcLevel, oObject, cVar )

   RECOVER
      BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
         /* Try to access variables using class code level */
         xResult := __dbgSENDMSG( 0, oObject, cVar )
      RECOVER USING oErr
         xResult := oErr:description
      END SEQUENCE
   END SEQUENCE
#endif
   RETURN xResult

static procedure sendCoumpoundVar(req, cParams ) 
	local value := getValue(@req)
	local aInfos := hb_aTokens(req,":")
	local aParams := GetStackAndParams(cParams)
	local iStart := aParams[2]
	local iCount := aParams[3], nMax := len(value)
	local i, idx,vSend, cLine, aData, idx2
	LOCAL t_oDebugInfo := __DEBUGITEM()
	//? "sendCoumpoundVar",req,cParams
	if valtype(value) == "O"
		//aData := __objGetValueList(value) // , value:aExcept())
		aData :=   __objGetMsgList( value )
		nMax := len(aData)
	endif
	hb_inetSend(t_oDebugInfo['socket'],req+CRLF)
	if right(req,1)<>":"
		req+=","
	endif
	if iCount=0
		iCount := nMax
	endif
	for i:=iStart to iStart+iCount
	//for i:=1 to nVars
		if i > nMax
			loop
		endif
		switch(valtype(value))
			case "A"
				idx2 := idx := alltrim(str(i))
				vSend:=value[i]
				exit
			case "H"
				vSend:=hb_HValueAt(value,i)
				idx2 := format(hb_HKeyAt(value,i))
				idx := alltrim(str(i))
				exit
			case "O"
				idx2 := idx := aData[i]
				vSend := __dbgObjGetValue(VAL(aInfos[2]),value, aData[i])
				exit
		endswitch
		cLine := req + idx + ":" +;
			idx2 + ":" + valtype(vSend) + ":" + format(vSend)
		hb_inetSend(t_oDebugInfo['socket'],cLine + CRLF )
	next

	hb_inetSend(t_oDebugInfo['socket'],"END"+CRLF)	
return

// returns -1 if the module is not valid, 0 if the line is not valid, 1 in case of valid line
static function IsValidStopLine(cModule,nLine) 
	LOCAL iModule
	LOCAL t_oDebugInfo := __DEBUGITEM()
	local nIdx, nInfo, tmp
	cModule := lower(alltrim(cModule))
	iModule := aScan(t_oDebugInfo['aModules'],{|v| v[1]=cModule})
	if iModule=0
		return -1
	endif
	if nLine<t_oDebugInfo['aModules'][iModule,2]
		return 0
	endif
	nIdx := nLine - t_oDebugInfo['aModules'][iModule,2]
	tmp := Int(nIdx/8)
	if tmp>=len(t_oDebugInfo['aModules'][iModule,3])
		return 0
	endif
	nInfo = Asc(SubStr(t_oDebugInfo['aModules'][iModule,3],tmp+1,1))
return HB_BITAND(HB_BITSHIFT(nInfo, -(nIdx-tmp*8)),1)

static procedure setBreakpoint(cInfo) 
	LOCAL aInfos := hb_aTokens(cInfo,":"), idLine
	local nReq, nLine, nReason, nExtra
	LOCAL t_oDebugInfo := __DEBUGITEM()
	//? " BRAEK - ", cInfo
	nReq := val(aInfos[3])
	aInfos[2] := lower(aInfos[2])
	if aInfos[1]=="-"
		// remove
		if hb_HHasKey(t_oDebugInfo['aBreaks'],aInfos[2])
			idLine := aScan(t_oDebugInfo['aBreaks'][aInfos[2]], {|v| v[1]=nReq })
			if idLine>0
				aDel(t_oDebugInfo['aBreaks'][aInfos[2]],idLine)
				aSize(t_oDebugInfo['aBreaks'][aInfos[2]],len(t_oDebugInfo['aBreaks'][aInfos[2]])-1)
			endif
		endif
		hb_inetSend(t_oDebugInfo['socket'],"BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:request"+CRLF)
		//? "BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:request"
		return
	endif
	if aInfos[1]<>"+"
		hb_inetSend(t_oDebugInfo['socket'],"BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:invalid request"+CRLF)
		//? "BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:invalid request"
		return
	endif
	nLine := nReq
	while (nReason:=IsValidStopLine(aInfos[2],nLine))!=1
		nLine++
		if (nLine-nReq)>2
			exit
		endif
	enddo
	if nReason!=1
		nLine := nReq - 1
		while (nReason:=IsValidStopLine(aInfos[2],nLine))!=1
			nLine--
			if (nReq-nLine)>2
				exit
			endif
		enddo
	endif
	if nReason!=1
		if nReason==0
			hb_inetSend(t_oDebugInfo['socket'],"BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:invalid"+CRLF)
			//? "BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:invalid"
		else
			hb_inetSend(t_oDebugInfo['socket'],"BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:not found"+CRLF)
			//? "BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:not found"
		endif
		return
	endif
	if .not. hb_HHasKey(t_oDebugInfo['aBreaks'],aInfos[2])
		t_oDebugInfo['aBreaks'][aInfos[2]] := {}
	endif
	idLine := aScan(t_oDebugInfo['aBreaks'][aInfos[2]], {|v| v[1]=nLine })
	if idLine=0
		aAdd(t_oDebugInfo['aBreaks'][aInfos[2]],{nLine})
		idLine = len(t_oDebugInfo['aBreaks'][aInfos[2]])
	endif
	nExtra := 4
	do While len(aInfos) >= nExtra
		if .not. (aInfos[nExtra] $ "?CL")
			hb_inetSend(t_oDebugInfo['socket'],"BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:invalid request "+ aInfos[nExtra]+CRLF)
			//? "BREAK:"+aInfos[2]+":"+aInfos[3]+":-1:invalid request "+ aInfos[nExtra]
			return
		endif
		if aInfos[nExtra]='C' //count
			aInfos[nExtra+1] := Val(aInfos[nExtra+1])
		endif
		aAdd(t_oDebugInfo['aBreaks'][aInfos[2]][idLine],aInfos[nExtra])
		aAdd(t_oDebugInfo['aBreaks'][aInfos[2]][idLine],aInfos[nExtra+1])
		aAdd(t_oDebugInfo['aBreaks'][aInfos[2]][idLine],0)
		nExtra += 2
	enddo
	hb_inetSend(t_oDebugInfo['socket'],"BREAK:"+aInfos[2]+":"+aInfos[3]+":"+alltrim(str(nLine))+CRLF)
	//? "BREAK:"+aInfos[2]+":"+aInfos[3]+":"+alltrim(str(nLine))
return

static function inBreakpoint() 
	LOCAL aBreaks := __DEBUGITEM()['aBreaks']
	LOCAL nLine := procLine(3), aBreakInfo
	local idLine, cFile := lower(procFile(3)), nExtra := 2
	LOCAL ck
	if .not. hb_HHasKey(aBreaks,cFile)
		return .F.
	endif
	idLine := aScan(aBreaks[cFile], {|v| iif(!empty(v),(aBreakInfo:=v, v[1]=nLine),.F.) })
	if idLine = 0
		return  .F.
	endif
	//? "BRK in line " + str(nLine)
	do while len(aBreakInfo) >= nExtra
		switch aBreakInfo[nExtra]
			case '?'
			#ifdef __XHARBOUR__
				BEGIN SEQUENCE 
					ck:=evalExpression(aBreakInfo[nExtra+1],1)			
				END SEQUENCE
			#else
				TRY 
					ck:=evalExpression(aBreakInfo[nExtra+1],1)			
				END
			#endif
				if valtype(ck)<>'L' .or. ck=.F.
					//?? " check Exp .F."
					return .F.
				endif
				//?? "check Exp .T."
				exit
			case 'C'
				aBreakInfo[nExtra+2]+=1
				//?? " counts " + alltrim(str(aBreakInfo[nExtra+2])) + "<" + alltrim(str(aBreakInfo[nExtra+1]))
				if aBreakInfo[nExtra+2] < aBreakInfo[nExtra+1]
					return .F.
				endif
				exit
			case 'L'
				BreakLog(aBreakInfo[nExtra+1])
				return .F.
		endswitch
		nExtra +=3
	end if
	//?? " >>.t. "
return .T.

static procedure BreakLog(cMessage)
	LOCAL cResponse := "", cCur, cExpr 
	LOCAL nCurly:=0, i
	for i:=1 to len(cMessage)
		cCur := subStr(cMessage,i,1)
		if nCurly=0
			if cCur = "{"
				nCurly := 1
				cExpr := ""
			else
				cResponse+=cCur
			endif
		else
			if cCur = "{"
				nCurly+=1
				cExpr+=cCur
			elseif cCur = "}"
				nCurly-=1
				if nCurly=0
					cResponse+=format(evalExpression(cExpr,1))
				endif
			else
				cExpr+=cCur
			endif
		endif
	next
	hb_inetSend(__DEBUGITEM()['socket'],"LOG:"+cResponse+CRLF)
return

//#define SAVEMODULES 
static procedure AddModule(aInfo) 
	LOCAL t_oDebugInfo := __DEBUGITEM()
	local i, idx
	#ifdef SAVEMODULES
		local j, tmp, cc,fFileModules
		if !file("modules.dbg")
			fclose(fcreate("modules.dbg"))
		endif
		fFileModules := fopen("modules.dbg",1+64)
		fSeek(fFileModules,0,2)
	#endif
	for i:=1 to len(aInfo)
		aInfo[i,1] := lower(alltrim(aInfo[i,1]))
		if len(aInfo[i,1])=0
			loop
		endif
		idx := aScan(t_oDebugInfo['aModules'], {|v| aInfo[i,1]=v[1]})
		if idx=0
			aAdd(aInfo[i],{}) //statics
			aadd(t_oDebugInfo['aModules'],aInfo[i])			
		else
			aAdd(aInfo[i],t_oDebugInfo['aModules'][idx,4])
			t_oDebugInfo['aModules'][idx] := aInfo[i]
		endif
		
		#ifdef SAVEMODULES
			fWrite(fFileModules,aInfo[i,1]+str(aInfo[i,2])+e"\r\n")
			for j:=1 to len(aInfo[i,3])*8
				tmp := Int(j/8)
				cc := asc(substr(aInfo[i,3],tmp+1,1))
				fWrite(fFileModules,str(j+aInfo[i,2])+str(HB_BITAND(HB_BITSHIFT(cc, -(j-tmp*8)),1))+str(cc)+e"\r\n")
				//? j, HB_BITAND(HB_BITSHIFT(cc, -(j-tmp*8)),1), cc
			next
		#endif
	next
	#ifdef SAVEMODULES
		fclose(fFileModules)
	#endif
return

static procedure AddStaticModule(idx,name,frame)
	LOCAL t_oDebugInfo := __DEBUGITEM()
	local currModule := t_oDebugInfo['aStack'][len(t_oDebugInfo['aStack']),HB_DBG_CS_MODULE]
	local idxModule
   currModule := lower(alltrim(currModule))
	idxModule := aScan(t_oDebugInfo['aModules'], {|v| v[1]==currModule})
	if idxModule=0
		aadd(t_oDebugInfo['aModules'],{currModule,0,{},{}})
		idxModule := len(t_oDebugInfo['aModules'])
	endif
	aAdd(t_oDebugInfo['aModules'][idxModule,4],{name,idx,"S",frame})
return

static function replaceExpression(xExpr, __dbg, name, value) 
	local aMatches := HB_REGEXALL("\b"+name+"\b",xExpr,.F./*CASE*/,/*line*/,/*nMat*/,/*nGet*/,.F.)
	local i, cVal
	if len(aMatches)=0
		return xExpr
	endif
	aadd(__dbg, value )
	cVal := "__dbg[" + allTrim(str(len(__dbg))) +"]"
	for i:=len(aMatches) to 1 step -1
		xExpr := left(xExpr,aMatches[i,1,2]-1) + cVal + substr(xExpr,aMatches[i,1,3]+1)
	next
return xExpr

static function evalExpression( xExpr, level ) 
	local oErr, xResult, __dbg := {}
	local i, cName, v
	LOCAL t_oDebugInfo := __DEBUGITEM(), lOldRunning
	local aStack := t_oDebugInfo['aStack']
	LOCAL iStack := GetStackId(level,aStack)
	local aModules := t_oDebugInfo['aModules']
	LOCAL cModule, idxModule := 0
	if iStack>0
		cModule := lower(aStack[iStack,HB_DBG_CS_MODULE])
		idxModule := aScan(aModules, {|v| v[1]=cModule})
	endif

	xExpr := strTran(xExpr,";",":")
	xExpr := strTran(xExpr,"::","self:")
	if iStack>0
		// replace all locals
		for i:=1 to len(aStack[iStack,HB_DBG_CS_LOCALS])
			xExpr := replaceExpression(xExpr, @__dbg, aStack[iStack,HB_DBG_CS_LOCALS,i,HB_DBG_VAR_NAME], ;
						__dbgVMVarLGet(__dbgProcLevel()-aStack[iStack,HB_DBG_CS_LOCALS, i, HB_DBG_VAR_FRAME], aStack[iStack,HB_DBG_CS_LOCALS, i, HB_DBG_VAR_INDEX]))
		next
		// replace all proc statics
		for i:=1 to len(aStack[iStack,HB_DBG_CS_STATICS])
			xExpr := replaceExpression(xExpr, @__dbg, aStack[iStack,HB_DBG_CS_STATICS,i,HB_DBG_VAR_NAME], ;
						__dbgVMVarSGet(aStack[iStack,HB_DBG_CS_STATICS, i, HB_DBG_VAR_FRAME],aStack[iStack,HB_DBG_CS_STATICS,i,HB_DBG_VAR_INDEX]))
		next
	endif
	// replace all public
	for i:=1 to __mvDbgInfo( HB_MV_PUBLIC )
		v:=__mvDbgInfo( HB_MV_PUBLIC, i, @cName )
		xExpr := replaceExpression(xExpr, @__dbg, cName, v)
	next
	// replace all private
	for i:=1 to __mvDbgInfo( HB_MV_PRIVATE )
		v:=__mvDbgInfo( HB_MV_PRIVATE, i, @cName )
		xExpr := replaceExpression(xExpr, @__dbg, cName, v)
	next
	// replace all module statics
	if idxModule>0
		for i:=1 to len(aModules[idxModule,4])
			xExpr := replaceExpression(xExpr, @__dbg, aModules[idxModule,4,i,HB_DBG_VAR_NAME], ;
						__dbgVMVarSGet(aModules[idxModule,4,i,HB_DBG_VAR_FRAME],aModules[idxModule,4,i,HB_DBG_VAR_INDEX]))
		next
	endif
	// ******
	lOldRunning := t_oDebugInfo['lRunning']
	t_oDebugInfo['lRunning'] := .T.
#ifndef __XHARBOUR__
	BEGIN SEQUENCE WITH {|oErr| BREAK( oErr ) }
		xResult := Eval(&("{|__dbg| "+xExpr+"}"),__dbg)
	RECOVER USING oErr
		xResult := oErr
	END SEQUENCE
#else
	TRY
		xResult := Eval(&("{|__dbg| "+xExpr+"}"),__dbg)
	CATCH oErr
		xResult := oErr
	END
#endif	
	t_oDebugInfo['lRunning'] := lOldRunning
return xResult

static procedure sendExpression( xExpr ) 
	LOCAL xResult
	   LOCAL cType, level, iDots := at(":",xExpr)
	   LOCAL t_oDebugInfo := __DEBUGITEM()
	level := val(left(xExpr,iDots))
	xResult :=  evalExpression( substr(xExpr,iDots+1), level)
	if valtype(xResult)="O" .and. xResult:ClassName() == "ERROR"
		cType := "E"
		xResult := xResult:description
	else
		cType := valtype(xResult)
		xResult := format(xResult)
	ENDIF
	hb_inetSend(t_oDebugInfo['socket'],"EXPRESSION:"+alltrim(str(level))+":"+cType+":"+xResult+CRLF)
return

STATIC PROCEDURE ErrorBlockCode( e )
	LOCAL t_oDebugInfo := __DEBUGITEM()
	if t_oDebugInfo["inError"] 
		return
	endif
	t_oDebugInfo["error"] := e
	t_oDebugInfo["inError"] := .T.
	t_oDebugInfo['lRunning'] := .F.
	hb_inetSend(t_oDebugInfo['socket'],"ERROR:"+e:Description+CRLF)
	__DEBUGITEM(t_oDebugInfo)
	CheckSocket(.T.)
	t_oDebugInfo := __DEBUGITEM()
	if !empty(t_oDebugInfo['userErrorBlock'])
		eval(t_oDebugInfo['userErrorBlock'], e)
	endif
return

PROCEDURE __dbgEntry( nMode, uParam1, uParam2, uParam3 )
	local tmp, i
	LOCAL t_oDebugInfo
	if nMode = HB_DBG_GETENTRY
		return
	endif
	t_oDebugInfo := __DEBUGITEM()
	switch nMode
		case HB_DBG_MODULENAME
			if(empty(t_oDebugInfo))
				t_oDebugInfo := { ;
					'socket' =>  nil, ;
					'lRunning' =>  .F., ;
					'aBreaks' =>  {=>}, ;
					'aStack' =>  {}, ;
					'aModules' =>  {}, ;
					'maxLevel' =>  nil, ;
					'bInitStatics' => .F., ;
					'bInitGlobals' =>  .F., ;
					'bInitLines' =>  .F., ;
					'errorBlock' => nil, ;
					'userErrorBlock' => nil, ;
					'errorBlockHistory' => {}, ;
					'error' => nil, ;
					'inError' => .F., ;
					'__dbgEntryLevel' => 0 ;
				}
				__DEBUGITEM(t_oDebugInfo)
				#ifdef SAVEMODULES
					ferase("modules.dbg")
				#endif
			endif
			if at("_INITSTATICS", uParam1)<>0
				t_oDebugInfo['bInitStatics'] := .T.
			elseif at("_INITGLOBALS", uParam1)<>0
				t_oDebugInfo['bInitGlobals'] := .T.
			elseif at("_INITLINES", uParam1)<>0
				t_oDebugInfo['bInitLines'] := .T.
			endif
			i := rat(":",uParam1)
			tmp := Array(HB_DBG_CS_LEN)
			if tmp=0
				tmp[HB_DBG_CS_MODULE] := uParam1
				tmp[HB_DBG_CS_FUNCTION] := ""
			else
				tmp[HB_DBG_CS_MODULE] := left(uParam1,tmp-1)
				tmp[HB_DBG_CS_FUNCTION] := substr(uParam1,tmp+1)
			endif
			if(t_oDebugInfo['bInitStatics'])
				// Fix
				tmp[HB_DBG_CS_MODULE] := procFile(1)
				tmp[HB_DBG_CS_FUNCTION] := "(_INITSTATICS)"
			endif
			tmp[HB_DBG_CS_LINE] := procLine(1) // line
			tmp[HB_DBG_CS_LEVEL] := __dbgProcLevel()-1 // level
			tmp[HB_DBG_CS_LOCALS] := {} // locals
			tmp[HB_DBG_CS_STATICS] := {} // statics
			//? "MODULENAME", uParam1, uParam2, uParam3, valtype(uParam1), valtype(uParam2), valtype(uParam3),  __dbgProcLevel()-1,procLine(__dbgProcLevel()-1),procLine(__dbgProcLevel()-2),procLine(__dbgProcLevel()-3),procLine(1)
			aAdd(t_oDebugInfo['aStack'], tmp)
			exit
		case HB_DBG_LOCALNAME
			if t_oDebugInfo['bInitGlobals']
				//? "LOCALNAME - bInitGlobals", uParam1, uParam2, uParam3, valtype(uParam1), valtype(uParam2), valtype(uParam3),  __dbgProcLevel()-1,procLine(__dbgProcLevel()-1)
			else
				aAdd(t_oDebugInfo['aStack'][len(t_oDebugInfo['aStack'])][HB_DBG_CS_LOCALS], {uParam2, uParam1, "L", __dbgProcLevel()-1})
			endif
			exit
		case HB_DBG_STATICNAME
			if t_oDebugInfo['bInitStatics']
				//? "STATICNAME - bInitStatics", len(uParam1), uParam2, uParam3, valtype(uParam1), valtype(uParam2), valtype(uParam3)
				//aEval(uParam1,{|x,n| QOut(n,valtype(x),x)})
				AddStaticModule(uParam2, uParam3, uParam1)
			elseif t_oDebugInfo['bInitGlobals']
				//? "STATICNAME - bInitGlobals", uParam1, uParam2, uParam3
			else
				//? "STATICNAME", uParam1, uParam2, uParam3, valtype(uParam1), valtype(uParam2), valtype(uParam3),  __dbgProcLevel()
				//aEval(uParam1,{|x,n| QOut(n,valtype(x),x)})
				aAdd(t_oDebugInfo['aStack'][len(t_oDebugInfo['aStack'])][HB_DBG_CS_STATICS], {uParam3, uParam2, "S", uParam1})
			endif
			exit
		case HB_DBG_ENDPROC
			//? "EndPROC", uParam1, uParam2, uParam3, valtype(uParam1), valtype(uParam2), valtype(uParam3) 
			aSize(t_oDebugInfo['aStack'],len(t_oDebugInfo['aStack'])-1)
			if t_oDebugInfo['bInitLines']
				// I don't like this hack, shoud be better if in case of HB_DBG_ENDPROC 
				// uParam1 is the returned value, it allow to show it in watch too...
				* tmp := __GETLASTRETURN(10); ? 10,valtype(tmp),tmp
				* tmp := __GETLASTRETURN(11); ? 11,valtype(tmp),tmp
				tmp := __GETLASTRETURN(12) //; ? 12,valtype(tmp),tmp
				* tmp := __GETLASTRETURN(13); ? 13,valtype(tmp),tmp
				* tmp := __GETLASTRETURN(14); ? 14,valtype(tmp),tmp
				AddModule(tmp)
			endif

			t_oDebugInfo['bInitStatics'] := .F.
			t_oDebugInfo['bInitGlobals'] := .F.
			t_oDebugInfo['bInitLines'] := .F.
			exit
		case HB_DBG_SHOWLINE
			//TODO check if ErrorBlock is setted by user and save user's errorBlock
			t_oDebugInfo['__dbgEntryLevel'] := __dbgProcLevel()
			tmp := ErrorBlock()
			if empty(tmp) .or. empty(t_oDebugInfo['errorBlock']) .or. !(t_oDebugInfo['errorBlock']==tmp)
				//? "Error block changed " + procFile(1) + "("+alltrim(str(uParam1))+")"
				//check if the new error block is an oldone
				i:=aScan(t_oDebugInfo['errorBlockHistory'], {|x| x[1]==tmp })
				if i>0 // it is an old one!
					//? "OLD:" + alltrim(str(i))
					t_oDebugInfo['userErrorBlock'] := t_oDebugInfo['errorBlockHistory',i,2]
					t_oDebugInfo['errorBlock'] :=  t_oDebugInfo['errorBlockHistory',i,1]
				else
					//? "NEW:" + alltrim(str(i))
					t_oDebugInfo['userErrorBlock'] := tmp
					t_oDebugInfo['errorBlock'] :=  {| e | ErrorBlockCode( e ) }
					aAdd(t_oDebugInfo['errorBlockHistory'],{t_oDebugInfo['errorBlock'], tmp })
				endif
				__DEBUGITEM(t_oDebugInfo)
				ErrorBlock( t_oDebugInfo['errorBlock'] )
			endif
			t_oDebugInfo['error'] := nil
			t_oDebugInfo['inError'] := .F.
			t_oDebugInfo['aStack'][len(t_oDebugInfo['aStack'])][HB_DBG_CS_LINE] := uParam1			
			CheckSocket()
			__dbgInvokeDebug(.F.)
			exit
	endswitch

#pragma BEGINDUMP

#include <hbapi.h>
#include <hbstack.h>
#include <hbvmint.h>
#include <hbapiitm.h>
#include <stdio.h>

HB_FUNC( __GETLASTRETURN )
{
	PHB_ITEM pItem = hb_stackItemFromTop( -1-hb_parni(1) );
	hb_itemReturn( HB_IS_BYREF( pItem ) ? hb_itemUnRef( pItem ) : pItem );
}

static PHB_ITEM sDebugInfo = NULL;
HB_FUNC( __DEBUGITEM )
{
	if(!sDebugInfo)
	{
		sDebugInfo = hb_itemNew(0);
	}
	if(hb_pcount()>0)
	{
		hb_itemCopy(sDebugInfo, hb_param(1,HB_IT_ANY));
	}
	hb_itemReturn(sDebugInfo);
}

#pragma ENDDUMP
