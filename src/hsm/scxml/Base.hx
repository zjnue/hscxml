package hsm.scxml;

import hsm.scxml.Model;
import hsm.scxml.Node;
import hsm.scxml.Types;
using hsm.scxml.tools.DataTools;
using hsm.scxml.tools.NodeTools;

#if js
import js.Worker;
#elseif flash
import flash.system.Worker;
import flash.system.WorkerDomain;
import flash.system.MessageChannel;
#end

#if neko
import neko.vm.Thread;
import neko.vm.Mutex;
#elseif cpp
import cpp.vm.Thread;
import cpp.vm.Mutex;
#end

#if haxe3
private typedef Hash<T> = haxe.ds.StringMap<T>;
#end

class Base #if (js || flash) extends WorkerScript #end {

	#if (js || flash)
	
	var timers : Array<haxe.Timer>;
	
	dynamic function parentEventHandler( evt : Event ) { post("postEvent", [evt]); }
	function onInit() { post("onInit", []); }
	function log( msg : String ) { post("log", [msg]); }
	
	#else
	
	var invokedDataMutex:Mutex;
	var timerThread : TimerThread;
	var mainThread : Thread;
	
	public var parentEventHandler : Event -> Void;
	public var onInit : Void -> Void;
	public var log : String -> Void;
	
	#end
	
	var d : Node;
	
	public var invokeId : String;
	public var topNode( get_topNode, never ) : Node;
	
	function get_topNode() { return d; }
	
	public function postEvent( evt : Event ) {
		externalQueue.enqueue( evt );
	}
	
	var configuration : Set<Node>;
	var statesToInvoke : Set<Node>;
	var datamodel : Model;
	var internalQueue : Queue<Event>;
	var externalQueue : BlockingQueue<Event>;
	var historyValue : Hash<List<Node>>;
	var running : Bool;
	var binding : String;
	
	var cancelledSendIds : Hash<Bool>;
	var invokedData : Hash<Dynamic>;

	public function new() {
		#if (js || flash)
		super();
		haxe.Serializer.USE_CACHE = true;
		#else
		log = function(msg:String) trace(msg);
		#end
	}
	
	inline function initTimer() {
		#if (js || flash)
		timers = [];
		#else
		timerThread = new TimerThread();
		#end
	}
	
	inline function extraInit() {
		cancelledSendIds = new Hash();
		invokedData = new Hash();
		#if !(js || flash)
		invokedDataMutex = new Mutex();
		#end
	}
	
	inline function raise( evt : Event ) {
		internalQueue.enqueue(evt);
	}
	
	inline function addToExternalQueue( evt : Event ) {
		externalQueue.enqueue(evt);
	}
	
	inline function setEvent( evt : Event ) {
		datamodel.setEvent(evt);
	}
	
	function getTypedDataStr( content : String, checkNum : Bool = true ) : String {
		if( content == null || content == "" )
			return content;
		if( checkNum ) {
			var isNum = Std.parseInt(content) != null;
			if( !isNum ) isNum = !Math.isNaN( Std.parseFloat(content) );
			if( isNum ) return content;
		}
		var isObj = false;
		try {
			var tmp = datamodel.doVal(content);
			isObj = Reflect.isObject(tmp);
		} catch( e:Dynamic ) isObj = false;
		if( isObj ) return content;
		var isXml = false;
		try {
			var tmp = Xml.parse(content);
			isXml = Std.is( tmp.firstElement(), Xml );
		} catch( e:Dynamic ) isXml = false;
		if( isXml ) return "Xml.parse( '" + content.split("'").join("\\'") + "' ).firstElement()";
		var isArray = false;
		try {
			var tmp = datamodel.doVal(content);
			isArray = Std.is( tmp, Array );
		} catch( e:Dynamic ) isArray = false;
		if( isArray ) return content;
		return "'" + content.split("'").join("\\'") + "'";
	}
	
	function getNamelistData( namelist : String ) {
		var data = [];
		if( namelist != null )
			for( name in namelist.split(" ") )
				data.push( { key : name, value : datamodel.doLoc(name) } );
		return data;
	}
	
	function parseContent( content : Array<Node> ) {
		var contentVal : Dynamic = null;
		try {
			if( content.length > 0 ) {
				var cnode = content[0];
				if( cnode.exists("expr") )
					contentVal = datamodel.doVal( cnode.get("expr") );
				else
					contentVal = StringTools.trim( cast(cnode, Content).content );
			}
		} catch( e:Dynamic ) {
			raise( new Event( Event.ERROR_EXEC ) );
			contentVal = "";
		}
		return contentVal;
	}
	
	function parseParams( params : Array<Node> ) {
		var data = [];
		for( param in params ) {
			var name = param.get("name");
			var expr = param.exists("expr") ? datamodel.doVal( param.get("expr") ) : null;
			var location = null;
			try {
				if( param.exists("location") ) {
					if( expr != null )
						throw "check";
					location = datamodel.doLoc( param.get("location") );
				} else {
					if( expr == null )
						throw "check";
				}
			} catch( e:Dynamic ) {
				raise( new Event( Event.ERROR_EXEC ) );
				continue;
			}
			data.push( { key : name, value : (expr != null ? expr : location) } );
		}
		return data;
	}
	
	static var genStateId : Int = 0;
	
	function expandScxmlSource( x : Xml ) {
		if( x.nodeType != Xml.Element )
			return;
		if( Lambda.has(["state", "parallel", "final"], x.nodeName) && !x.exists("id") )
			x.set("id", "__gen_id__"+genStateId++);
		var hasInitial = false;
		for( el in x.elements() ) {
			if( el.nodeName == "initial" )
				hasInitial = true;
			expandScxmlSource(el);
		}
		if( x.exists("initial") || (!x.exists("initial") && Lambda.has(["scxml", "state"], x.nodeName) && !hasInitial) ) {
			var ins = Xml.createElement("initial");
			var trans = Xml.createElement("transition");
			var tval = x.exists("initial") ? x.get("initial") : null;
			if( tval == null ) {
				for( el in x.elements() )
					if( Lambda.has(["state", "parallel", "final"], el.nodeName) ) {
						tval = el.get("id");
						break;
					}
			}
			if( tval == null )
				return;
			trans.set("target", tval);
			ins.insertChild(trans, 0);
			x.insertChild(ins, 0);
			x.remove("initial");
		}
	}
	
	static var locId : Int = 0;
	inline function getLocationId() {
		return "locId_" + locId++;
	}
	
	static var platformId : Int = 0;
	inline function getPlatformId() {
		return "platformId_" + platformId++;
	}
	
	function getInvokeId( inv : Node ) {
		var node = inv.parent;
		while( !node.isState() && node.parent != null )
			node = node.parent;
		return node.get("id") + "." + getPlatformId();
	}
	
	function getAltProp( n : Node, att0 : String, att1 : String ) {
		var prop = null;
		if( n.exists(att0) )
			prop = n.get(att0);
		if( n.exists(att1) ) {
			if( prop != null ) throw "Property specification for '" + att0 + "' and '" + att1 + "' should be mutually exclusive.";
			prop = datamodel.doVal( n.get(att1) );
		}
		return prop;
	}
	
	#if (js || flash)
	
	function createSubInst( content : String, data : Array<{key:String, value:Dynamic}>, invokeid : String, type : String ) {
		var xml = Xml.parse(content).firstElement().setSubInstData(data);
		#if js
		
		var worker = new Worker( "interp.js" );
		setInvokedData( invokeid, { type : type, instance : worker } );
		worker.addEventListener( "message", function(e) { handleWorkerMessage(e.data, invokeid); } );
		worker.addEventListener( "error", function(e) { handleWorkerError(e.message); } );
		
		#else
		
		var worker = WorkerDomain.current.createWorker( flash.Lib.current.loaderInfo.bytes );
		var outgoingChannel = Worker.current.createMessageChannel( worker );
		var incomingChannel = worker.createMessageChannel( Worker.current );
		
		worker.setSharedProperty( WorkerScript.TO_SUB, outgoingChannel );
		worker.setSharedProperty( WorkerScript.FROM_SUB, incomingChannel );
		
		incomingChannel.addEventListener( flash.events.Event.CHANNEL_MESSAGE, function(e) {
			while( incomingChannel.messageAvailable )
				handleWorkerMessage( incomingChannel.receive(), invokeid );
		});
		setInvokedData( invokeid, { type : type, instance : worker, incomingChannel : incomingChannel, outgoingChannel : outgoingChannel } );
		worker.start();
		
		#end
		try {
			postToWorker( invokeid, "invokeId", [invokeid] );
			postToWorker( invokeid, "interpret", [xml.toString()] );
		} catch( e:Dynamic ) {
			log("ERROR: sub worker: e = " + Std.string(e));
		}
	}
	
	function handleWorkerMessage( data : Dynamic, invokeid : String ) {
		var msg = haxe.Unserializer.run(data);
		switch( msg.cmd ) {
			case "log": if( log != null ) log("log-from-child: " + msg.args[0]);
			case "onInit": postToWorker( invokeid, "start" );
			case "postEvent": addToExternalQueue( cast(msg.args[0], Event) );
			case "sendDomEvent": msg.args[0] += "," + invokeId; post(msg.cmd, msg.args);
			default:
				log("Interp: sub worker msg received: msg.cmd = " + msg.cmd + " msg.args = " + Std.string(msg.args));
		}
	}
	
	function handleWorkerError( msg : String ) {
		log("worker error: " + msg);
	}
	
	function postToWorker( invokeId : String, cmd : String, ?args : Array<Dynamic> ) {
		if( args == null ) args = [];
		#if js
		var worker = getInvokedData(invokeId).instance;
		worker.postMessage( haxe.Serializer.run({cmd:cmd, args:args}) );
		#else
		var outgoingChannel = getInvokedData(invokeId).outgoingChannel;
		outgoingChannel.send( haxe.Serializer.run({cmd:cmd, args:args}) );
		#end
	}
	
	inline function setInvokedData( id : String, data : Dynamic ) {
		invokedData.set(id, data);
	}
	
	inline function getInvokedData( id : String ) {
		return invokedData.get(id);
	}
	
	inline function hasInvokedData( id : String ) {
		return invokedData.exists(id);
	}
	
	#else
	
	function createSubInst( content : String, data : Array<{key:String, value:Dynamic}>, invokeid : String, type : String ) {
		var c = Thread.create( createChildInterp );
		c.sendMessage(Thread.current());
		c.sendMessage(content);
		c.sendMessage(data);
		c.sendMessage(invokeid);
		c.sendMessage(type);
		Thread.readMessage(true);
		
		Sys.sleep(0.2); // FIXME erm, for now give new instance 'some time' to stabilize (see test 250)
	}
	
	function createChildInterp() {
		var main = Thread.readMessage(true);
		var xmlStr = Thread.readMessage(true);
		var data : Array<{key:String,value:Dynamic}> = Thread.readMessage(true);
		var invokeid = Thread.readMessage(true);
		var type = Thread.readMessage(true);
		
		var xml = Xml.parse(xmlStr).firstElement().setSubInstData(data);
		
		var me = this;
		var inst = new hsm.scxml.Interp();
		inst.invokeId = invokeid;
		inst.parentEventHandler = function( evt : Event ) {
			me.addToExternalQueue(evt);
		};
		inst.log = function(msg) { log("log-from-child: " + msg); };
		inst.onInit = function() { inst.start(); };
		
		setInvokedData(invokeid, {
			type : type,
			instance : inst
		});
		
		main.sendMessage("please continue..");
		
		inst.interpret( xml );
	}
	
	function setInvokedData( id : String, data : Dynamic ) {
		invokedDataMutex.acquire();
		invokedData.set(id, data);
		invokedDataMutex.release();
	}
	
	function getInvokedData( id : String ) {
		var data : Dynamic = null;
		invokedDataMutex.acquire();
		data = invokedData.get(id);
		invokedDataMutex.release();
		return data;
	}
	
	function hasInvokedData( id : String ) {
		var has = false;
		invokedDataMutex.acquire();
		has = invokedData.exists(id);
		invokedDataMutex.release();
		return has;
	}
	
	#end
}

#if (js || flash)

class WorkerScript {
	#if flash
	public static inline var TO_SUB = "toSub";
	public static inline var FROM_SUB = "fromSub";
	
	var outgoingChannel : MessageChannel;
	var incomingChannel : MessageChannel;
	#end
	public function new() {
		#if flash
		incomingChannel = Worker.current.getSharedProperty( TO_SUB );
		outgoingChannel = Worker.current.getSharedProperty( FROM_SUB );
		incomingChannel.addEventListener( flash.events.Event.CHANNEL_MESSAGE, onMessage );
		#end
	}
	public function handleOnMessage( data : Dynamic ) : Void {}
	public function onMessage( e : Dynamic ) : Void {
		#if js
		handleOnMessage( e.data );
		#else
		while( incomingChannel.messageAvailable )
			handleOnMessage( incomingChannel.receive() );
		#end
	}
	public function onError( e : Dynamic ) : Void {}
	public function post( cmd : String, args : Array<Dynamic> ) : Void {
		#if js
		postMessage( haxe.Serializer.run({cmd:cmd, args:args}) );
		#else
		outgoingChannel.send( haxe.Serializer.run({cmd:cmd, args:args}) );
		#end
	}
	#if js
	public function postMessage( msg : Dynamic ) : Void {
		untyped __js__("self.postMessage( msg )");
	}
	// TODO make sure all methods in Interp (our workerscript-to-be) are added here
	// use a macro for this eventually
	public function export() {
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
	}
	#end
}

#end