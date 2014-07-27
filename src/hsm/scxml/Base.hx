package hsm.scxml;

import hsm.scxml.Model;
import hsm.scxml.Node;
import hsm.scxml.Types;
using hsm.scxml.tools.DataTools;
using hsm.scxml.tools.NodeTools;

import hxworker.Worker;

#if neko
import neko.vm.Thread;
#elseif cpp
import cpp.vm.Thread;
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
	
	var timerThread : TimerThread;
	var mainThread : Thread;
	
	public var parentEventHandler : Event -> Void;
	public var onInit : Void -> Void;
	public var log : String -> Void;
	
	#end
	
	var d : Node;
	
	public var path : String;
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
	var defaultHistoryContent : Hash<Iterable<Node>>;

	public function new() {
		super();
		#if (js || flash)
		haxe.Serializer.USE_CACHE = true;
		#end
	}
	
	inline function initTimer() {
		#if (js || flash)
		timers = [];
		#else
		timerThread = new TimerThread();
		#end
	}
	
	inline function stopTimers() {
		#if (js || flash)
		for( t in timers )
			t.stop();
		#else
		timerThread.quit();
		#end
	}
	
	inline function extraInit() {
		cancelledSendIds = new Hash();
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
	
	function createSubInst( content : String, data : Array<{key:String, value:Dynamic}>, inv_id : String, type : String ) {
	
		var xml = Xml.parse(content).firstElement().setSubInstData(data);
		
		var input = #if js "interp.js" #elseif flash flash.Lib.current.loaderInfo.bytes #else hsm.scxml.Interp #end;
		var worker = new Worker( input, handleWorkerMessage.bind(_,inv_id), handleWorkerError );
		worker.type = type;
		setWorker(inv_id, worker);
		
		#if (js || flash)
		try {
			postToWorker( inv_id, "invokeId", [inv_id] );
			postToWorker( inv_id, "path", [path] );
			postToWorker( inv_id, "interpret", [xml.toString()] );
		} catch( e:Dynamic ) {
			log("ERROR: sub worker: e = " + Std.string(e));
		}
		#else
		
		var c = Thread.create( createChildInterp );
		c.sendMessage(Thread.current());
		c.sendMessage(content);
		c.sendMessage(data);
		c.sendMessage(inv_id);
		c.sendMessage(type);
		c.sendMessage(worker);
		c.sendMessage(path);
		Thread.readMessage(true);
		
		Sys.sleep(0.2); // FIXME erm, for now give new instance 'some time' to stabilize (see test 250)
		
		#end
	}
	
	// here we receive a message from the sub worker with invoke = inv_id
	override function handleWorkerMessage( data : Dynamic, inv_id : String ) {
		var msg = Worker.uncompress( data );
		switch( msg.cmd ) {
			case "log": if( log != null ) log("log-from-child: " + msg.args[0]);
			case "onInit": postToWorker( inv_id, "start" );
			case "postEvent": addToExternalQueue( cast(msg.args[0], Event) );
			case "sendDomEvent": msg.args[0] += "," + invokeId; post(msg.cmd, msg.args);
			default:
				log("Interp: sub worker msg received: cmd = " + msg.cmd + " args = " + Std.string(msg.args));
		}
	}
	
	function handleWorkerError( msg : String ) {
		log("worker error: " + msg);
	}
	
	function postToWorker( inv_id : String, cmd : String, ?args : Array<Dynamic> ) {
		var worker = getWorker(inv_id);
		#if (js || flash)
		worker.call( cmd, args );
		#else
		if( cmd == "interpret" ) args = [Xml.parse(args[0]).firstElement()];
		if( args == null ) args = [];
		Reflect.callMethod( worker.inst, Reflect.field(worker.inst, cmd), args );
		#end
	}
	
	#if !(js || flash)
	function createChildInterp() {
		
		var main = Thread.readMessage(true);
		var xmlStr = Thread.readMessage(true);
		var data : Array<{key:String,value:Dynamic}> = Thread.readMessage(true);
		var invokeid = Thread.readMessage(true);
		var type = Thread.readMessage(true);
		var worker = Thread.readMessage(true);
		var path = Thread.readMessage(true);
		
		var xml = Xml.parse(xmlStr).firstElement().setSubInstData(data);
		
		var me = this;
		var inst = new hsm.scxml.Interp();
		inst.invokeId = invokeid;
		inst.path = path;
		inst.parentEventHandler = function( evt : Event ) {
			me.addToExternalQueue(evt);
		};
		
		inst.log = function(msg) { log("log-from-child: " + msg); };
		inst.onInit = function() { inst.start(); };
		
		worker.inst = inst;
		
		main.sendMessage("done");
		
		inst.interpret( xml );
	}
	#end
}
