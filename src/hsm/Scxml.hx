package hsm;

import hsm.scxml.Interp;
import hsm.scxml.Types;
import hsm.scxml.tools.DrawTools;

#if neko
import neko.vm.Thread;
#elseif cpp
import cpp.vm.Thread;
#end

#if js
import js.Worker;
#else
import sys.FileSystem;
#end

class Scxml {
	#if js
	var worker : Worker;
	#else
	var interp : Interp;
	#end
	
	public var onInit : Void -> Void;
	public var log : String -> Void;
	public var parentEventHandler : Event -> Void;

	var content : String;
	var data : Array<{key:String, value:Dynamic}>;
	
	public function new( src : String = null, content : String = null, data : Array<{key:String, value:Dynamic}> = null ) {
		#if !js
		if( src != null ) {
			if( !FileSystem.exists(src) ) src = FileSystem.fullPath(src);
			if( !FileSystem.exists(src) ) throw "Invalid path: " + src;	
			content = sys.io.File.getContent(src);
		}
		#end
		this.content = content;
		this.data = data;
	}
	
	public function init( content : String = null, onInit : Void -> Void = null, log : String -> Void = null ) {
		if( content == null ) content = this.content;
		if( content == null ) throw "No content set";
		if( onInit == null && this.onInit == null ) throw "No onInit function set";
		if( onInit != null ) this.onInit = onInit;
		if( log == null ) log = this.log;
		
		var scxml = Xml.parse(content).firstElement();
		
		#if js
		
		worker = new Worker("interp.js");
		worker.addEventListener("message", function(e) {
			var msg = haxe.Unserializer.run(e.data);
			switch( msg.cmd ) {
				case "log": if( log != null ) log(msg.args[0]);
				case "onInit": onInit();
				case "postEvent":
					if( parentEventHandler != null ) {
						log("parentEventHandler: " + Std.string(msg.args[0]));
						parentEventHandler( cast(msg.args[0], Event) );
					}
				case "sendDomEvent":
					var args : Array<Dynamic> = msg.args;
					sendDomEvent(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
				default:
					trace("worker msg received: msg.cmd = " + msg.cmd + " msg.args = " + Std.string(msg.args));
			}
			
		});
		worker.addEventListener("error", function(e) {
			trace("worker error: " + e.message);
		});
		
		try {
			post("interpret", [content]);
		} catch( e:Dynamic ) {
			log("ERROR: worker: e = " + Std.string(e));
			if( parentEventHandler != null )
				parentEventHandler( new Event("done.invoke") );
		}
		
		#else
		var c = Thread.create(createInterp);
		c.sendMessage(scxml);
		c.sendMessage(onInit);
		c.sendMessage(log);
		c.sendMessage(parentEventHandler);
		#end
	}
	
	#if js
	
	public function post( cmd : String, args : Array<Dynamic> ) : Void {
		worker.postMessage( haxe.Serializer.run({cmd:cmd, args:args}) );
	}
	
	function sendDomEvent( fromInvokeId : String, target : String, iface : String, domEvtType : String, 
		cancelable : Bool, bubbles : Bool, contentVal : String, data : Array<{key:String, value:Dynamic}> ) {

		if( iface != "CustomEvent" ) {
			log("sendDomEvent type not yet implemented: " + domEvtType);
			post("sendDomEventFailed", [fromInvokeId]);
			return;
		}
		
		var nodes : Array<js.html.Element> = null;
		var detail : Dynamic = null;
		var event : js.CustomEvent = null;
		
		try {
			nodes = new js.JQuery(target).get();
			if( nodes.length == 0 ) {
				log("sendDomEvent target not found: " + target);
				return;
			}
			detail = contentVal;
			if( detail == null ) {
				detail = {};
				Interp.setEventData(detail, data);
			}
			var initObj  = {
				bubbles : bubbles,
				cancelable : cancelable,
				detail : detail
			};
			event = new js.CustomEvent( domEvtType, initObj );
			
		} catch( e:Dynamic ) {
			log("sendDomEvent failed for target: " + target);
			post("sendDomEventFailed", [fromInvokeId]);
			return;
		}
		
		for( node in nodes )
			node.dispatchEvent( cast event );
	}
	
	#else
	function createInterp() {
		var scxml = Thread.readMessage(true);
		var onInit = Thread.readMessage(true);
		var log = Thread.readMessage(true);
		var parentEventHandler = Thread.readMessage(true);
		
		interp = new hsm.scxml.Interp();
		interp.onInit = onInit;
		if( log != null ) interp.log = log;
		if( parentEventHandler != null ) interp.parentEventHandler = parentEventHandler;
		
		try {
			interp.interpret( scxml );
		} catch( e:Dynamic ) {
			log("ERROR: e = " + Std.string(e));
			parentEventHandler( new Event("done.invoke") );
		}
	}
	#end
	
	inline public function getDot() {
		#if !js
		return DrawTools.getDot(interp.topNode);
		#end
	}
	
	inline public function start() {
		#if js
		post("start", []);
		#else
		interp.start();
		#end
	}
	
	inline public function stop() {
		#if js
		post("stop", []);
		#else
		interp.stop();
		#end
	}
	
	public function postEvent( evt : Event ) {
		#if js
		post("postEvent", [evt]);
		#else
		if( interp != null ) {
			interp.postEvent( evt );
		}
		#end
	}
}
