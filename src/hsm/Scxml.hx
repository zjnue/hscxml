package hsm;

import hsm.scxml.Interp;
import hsm.scxml.Types;
import hsm.scxml.tools.DrawTools;
import hsm.scxml.tools.DataTools;

import hxworker.Worker;

#if (js || flash)
import hsm.scxml.Base;
#else
import sys.FileSystem;
#end

#if flash
@:file("swf/Interp.swf") class InterpByteArray extends flash.utils.ByteArray {}
#end

class Scxml {
	
	var worker : Worker;
	
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
		
		try {
			postToWorker( "interpret", [content] );
		} catch( e:Dynamic ) {
			log("ERROR: worker: e = " + Std.string(e));
			if( parentEventHandler != null )
				parentEventHandler( new Event("done.invoke") );
		}
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
	
	inline function postToWorker( cmd : String, ?args : Array<Dynamic> ) : Void {
		worker.call( cmd, args );
	}
	
	public inline function getDot() {
		#if !(js || flash)
		//return DrawTools.getDot(interp.topNode);
		#end
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
