package hsm;

import hsm.scxml.Interp;
import hsm.scxml.Types;
import hsm.scxml.tools.DrawTools;
import hsm.scxml.tools.DataTools;

import hxworker.Worker;

#if neko
import neko.vm.Thread;
#elseif cpp
import cpp.vm.Thread;
#end

#if (js || flash)
import hsm.scxml.Base;
#else
import sys.FileSystem;
#end

#if flash
@:file("Interp.swf") class InterpByteArray extends flash.utils.ByteArray {}
#end

class Scxml {
	
	var worker : Worker;
	
	public var path : String;
	public var onInit : Void -> Void;
	public var log : String -> Void;
	public var parentEventHandler : Event -> Void;

	var content : String;
	var data : Array<{key:String, value:Dynamic}>;
	
	public function new( src : String = null, content : String = null, data : Array<{key:String, value:Dynamic}> = null ) {
		#if !(js || flash)
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
		
		var input = #if js "interp.js" #elseif flash new InterpByteArray() #else hsm.scxml.Interp #end;
		worker = new Worker( input, handleWorkerMessage, handleWorkerError );
		
		#if (js || flash)
		try {
			postToWorker( "path", [path] );
			postToWorker( "interpret", [content] );
		} catch( e:Dynamic ) {
			log("ERROR: worker: e = " + Std.string(e));
			if( parentEventHandler != null )
				parentEventHandler( new Event("done.invoke") );
		}
		#else
		var c = Thread.create(createInterp);
		c.sendMessage(content);
		c.sendMessage(onInit);
		c.sendMessage(log);
		c.sendMessage(parentEventHandler);
		c.sendMessage(worker);
		c.sendMessage(path);
		#end
	}
	
	function handleWorkerMessage( data : Dynamic ) {
		var msg = Worker.uncompress( data );
		switch( msg.cmd ) {
			case "log": if( log != null ) log(msg.args[0]);
			case "onInit": onInit();
			case "postEvent":
				if( parentEventHandler != null ) {
					parentEventHandler( cast(msg.args[0], Event) );
				}
			case "sendDomEvent":
				var args = msg.args;
				sendDomEvent( args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7] );
			default:
				log("worker msg received: cmd = " + msg.cmd + " args = " + Std.string(msg.args));
		}
	}
	
	function handleWorkerError( msg : String ) {
		log("worker error: " + msg);
	}
	
	function postToWorker( cmd : String, ?args : Array<Dynamic> ) : Void {
		#if (js || flash)
		worker.call( cmd, args );
		#else
		if( cmd == "interpret" ) args = [Xml.parse(args[0]).firstElement()];
		if( args == null ) args = [];
		Reflect.callMethod( worker.inst, Reflect.field(worker.inst, cmd), args );
		#end
	}
	
	public inline function getDot() {
		#if !(js || flash)
		//return DrawTools.getDot(interp.topNode);
		#end
	}
	
	public function terminate() {
		worker.terminate();
	}
	
	public inline function start() {
		postToWorker( "start" );
	}
	
	public inline function stop() {
		postToWorker( "stop" );
	}
	
	public inline function postEvent( evt : Event ) {
		postToWorker( "postEvent", [evt] );
	}
	
	#if !(js || flash)
	function createInterp() {
		var content = Thread.readMessage(true);
		var onInit = Thread.readMessage(true);
		var log = Thread.readMessage(true);
		var parentEventHandler = Thread.readMessage(true);
		var worker = Thread.readMessage(true);
		var path = Thread.readMessage(true);
		
		var interp = new hsm.scxml.Interp();
		interp.path = path;
		interp.onInit = onInit;
		if( log != null ) interp.log = log;
		if( parentEventHandler != null ) interp.parentEventHandler = parentEventHandler;
		worker.inst = interp;
		
		try {
			interp.interpret( Xml.parse(content).firstElement() );
		} catch( e:Dynamic ) {
			log("ERROR: e = " + Std.string(e));
			parentEventHandler( new Event("done.invoke") );
		}
	}
	#end
	
	function sendDomEvent( fromInvokeId : String, target : String, iface : String, domEvtType : String, 
		cancelable : Bool, bubbles : Bool, contentVal : String, data : Array<{key:String, value:Dynamic}> ) {

		if( iface != "CustomEvent" ) {
			log("sendDomEvent interface not yet implemented: " + iface);
			postToWorker( "sendDomEventFailed", [fromInvokeId] );
			return;
		}
		
		#if js
		var nodes : Array<js.html.Element> = null;
		var detail : Dynamic = null;
		var event : js.CustomEvent = null;
		
		try {
			nodes = new js.JQuery(target).get();
			if( nodes.length == 0 ) {
				log("sendDomEvent target not found: " + target);
				postToWorker( "sendDomEventFailed", [fromInvokeId] );
				return;
			}
			detail = contentVal != null ? contentVal : DataTools.copyFrom( {}, data );
			event = new js.CustomEvent( domEvtType, { bubbles : bubbles, cancelable : cancelable, detail : detail } );
			
		} catch( e:Dynamic ) {
			log("sendDomEvent failed for target: " + target);
			postToWorker( "sendDomEventFailed", [fromInvokeId] );
			return;
		}
		
		for( node in nodes )
			node.dispatchEvent( cast event );
		#end
	}
}
