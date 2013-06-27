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

class Base extends hxworker.WorkerScript {

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
		super();
		#if (js || flash)
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
		
		worker.setSharedProperty( hxworker.Worker.TO_SUB, outgoingChannel );
		worker.setSharedProperty( hxworker.Worker.FROM_SUB, incomingChannel );
		
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
