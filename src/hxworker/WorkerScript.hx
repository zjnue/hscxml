package hxworker;

class WorkerScript {
	
	#if flash
	var channelOut : flash.system.MessageChannel;
	var channelIn : flash.system.MessageChannel;
	#end
	
	public function new() {
		#if flash
		channelIn = flash.system.Worker.current.getSharedProperty( Worker.TO_SUB );
		channelOut = flash.system.Worker.current.getSharedProperty( Worker.FROM_SUB );
		channelIn.addEventListener( flash.events.Event.CHANNEL_MESSAGE, onMessage );
		#end
	}
	public function handleOnMessage( data : Dynamic ) : Void {}
	public function post( cmd : String, args : Array<Dynamic> ) : Void {
		#if js
		postMessage( haxe.Serializer.run({cmd:cmd, args:args}) );
		#elseif flash
		channelOut.send( haxe.Serializer.run({cmd:cmd, args:args}) );
		#end
	}
	function onMessage( e : Dynamic ) : Void {
		#if js
		handleOnMessage( e.data );
		#elseif flash
		while( channelIn.messageAvailable )
			handleOnMessage( channelIn.receive() );
		#end
	}
	function onError( e : Dynamic ) : Void {}
	#if js
	function postMessage( msg : Dynamic ) : Void {
		untyped __js__("self.postMessage( msg )");
	}
	#end
	
	// TODO make sure all methods in Interp (our workerscript-to-be) are added here
	// use a macro for this eventually
	public function export() {
		#if js
		var script = this;
		untyped __js__("self.onmessage = script.onMessage");
		untyped __js__("self.onerror = script.onError");
		untyped __js__("self.post = script.post");
		untyped __js__("self.handleOnMessage = script.handleOnMessage");
		untyped __js__("self.handleWorkerMessage = script.handleWorkerMessage");
		untyped __js__("self.handleWorkerError = script.handleWorkerError");
		untyped __js__("self.createSubInst = script.createSubInst");
		untyped __js__("self.d = script.d");
		untyped __js__("self.parentEventHandler = script.parentEventHandler");
		untyped __js__("self.invokeId = script.invokeId");
		untyped __js__("self.onInit = script.onInit");
		untyped __js__("self.log = script.log");
		untyped __js__("self.topNode = script.topNode");
		untyped __js__("self.timers = script.timers");
		untyped __js__("self.configuration = script.configuration");
		untyped __js__("self.statesToInvoke = script.statesToInvoke");
		untyped __js__("self.datamodel = script.datamodel");
		untyped __js__("self.internalQueue = script.internalQueue");
		untyped __js__("self.externalQueue = script.externalQueue");
		untyped __js__("self.historyValue = script.historyValue");
		untyped __js__("self.running = script.running");
		untyped __js__("self.binding = script.binding");
		untyped __js__("self.genStateId = script.genStateId");
		untyped __js__("self.invokedData = script.invokedData");
		untyped __js__("self.locId = script.locId");
		untyped __js__("self.platformId = script.platformId");
		untyped __js__("self.cancelledSendIds = script.cancelledSendIds");
		untyped __js__("self.new = script.new");
		untyped __js__("self.get_topNode = script.get_topNode");
		untyped __js__("self.postEvent = script.postEvent");
		untyped __js__("self.start = script.start");
		untyped __js__("self.stop = script.stop");
		untyped __js__("self.entryOrder = script.entryOrder");
		untyped __js__("self.exitOrder = script.exitOrder");
		untyped __js__("self.documentOrder = script.documentOrder");
		untyped __js__("self.interpret = script.interpret");
		untyped __js__("self.extraInit = script.extraInit");
		untyped __js__("self.valid = script.valid");
		untyped __js__("self.failWithError = script.failWithError");
		untyped __js__("self.expandScxmlSource = script.expandScxmlSource");
		untyped __js__("self.executeGlobalScriptElements = script.executeGlobalScriptElements");
		untyped __js__("self.initializeDatamodel = script.initializeDatamodel");
		untyped __js__("self.mainEventLoop = script.mainEventLoop");
		untyped __js__("self.checkBlockingQueue = script.checkBlockingQueue");
		untyped __js__("self.isCancelEvent = script.isCancelEvent");
		untyped __js__("self.exitInterpreter = script.exitInterpreter");
		untyped __js__("self.selectEventlessTransitions = script.selectEventlessTransitions");
		untyped __js__("self.selectTransitions = script.selectTransitions");
		untyped __js__("self.removeConflictingTransitions = script.removeConflictingTransitions");
		untyped __js__("self.microstep = script.microstep");
		untyped __js__("self.exitStates = script.exitStates");
		untyped __js__("self.getSourceState = script.getSourceState");
		untyped __js__("self.computeExitSet = script.computeExitSet");
		untyped __js__("self.executeTransitionContent = script.executeTransitionContent");
		untyped __js__("self.enterStates = script.enterStates");
		untyped __js__("self.computeEntrySet = script.computeEntrySet");
		untyped __js__("self.addDescendantStatesToEnter = script.addDescendantStatesToEnter");
		untyped __js__("self.addAncestorStatesToEnter = script.addAncestorStatesToEnter");
		untyped __js__("self.isInFinalState = script.isInFinalState");
		untyped __js__("self.getTransitionDomain = script.getTransitionDomain");
		untyped __js__("self.findLCCA = script.findLCCA");
		untyped __js__("self.getProperAncestors = script.getProperAncestors");
		untyped __js__("self.nameMatch = script.nameMatch");
		untyped __js__("self.conditionMatch = script.conditionMatch");
		untyped __js__("self.getDefaultInitialState = script.getDefaultInitialState");
		untyped __js__("self.cancelInvoke = script.cancelInvoke");
		untyped __js__("self.applyFinalize = script.applyFinalize");
		untyped __js__("self.send = script.send");
		untyped __js__("self.isScxmlInvokeType = script.isScxmlInvokeType");
		untyped __js__("self.getDoneData = script.getDoneData");
		untyped __js__("self.returnDoneEvent = script.returnDoneEvent");
		untyped __js__("self.raise = script.raise");
		untyped __js__("self.addToExternalQueue = script.addToExternalQueue");
		untyped __js__("self.setEvent = script.setEvent");
		untyped __js__("self.sendEvent = script.sendEvent");
		untyped __js__("self.isValidAndSupportedSendTarget = script.isValidAndSupportedSendTarget");
		untyped __js__("self.isValidAndSupportedSendType = script.isValidAndSupportedSendType");
		untyped __js__("self.ioProcessorSupportsPost = script.ioProcessorSupportsPost");
		untyped __js__("self.getLocationId = script.getLocationId");
		untyped __js__("self.getPlatformId = script.getPlatformId");
		untyped __js__("self.getInvokeId = script.getInvokeId");
		untyped __js__("self.getAltProp = script.getAltProp");
		untyped __js__("self.executeBlock = script.executeBlock");
		untyped __js__("self.executeContent = script.executeContent");
		untyped __js__("self.getTypedDataStr = script.getTypedDataStr");
		untyped __js__("self.getNamelistData = script.getNamelistData");
		untyped __js__("self.parseContent = script.parseContent");
		untyped __js__("self.parseParams = script.parseParams");
		untyped __js__("self.setInvokedData = script.setInvokedData");
		untyped __js__("self.getInvokedData = script.getInvokedData");
		untyped __js__("self.hasInvokedData = script.hasInvokedData");
		untyped __js__("self.invoke = script.invoke");
		untyped __js__("self.postToWorker = script.postToWorker");
		untyped __js__("self.invokeTypeAccepted = script.invokeTypeAccepted");
		untyped __js__("self.setFromSrc = script.setFromSrc");
		untyped __js__("self.getFileContent = script.getFileContent");
		untyped __js__("self.getTargetStates = script.getTargetStates");
		untyped __js__("self.getTargetState = script.getTargetState");
		#end
	}

}