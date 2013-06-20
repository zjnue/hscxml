package hsm;

import hsm.scxml.Interp;
import hsm.scxml.Types;
import hsm.scxml.tools.DrawTools;

#if neko
import neko.vm.Thread;
#elseif cpp
import cpp.vm.Thread;
#end

import sys.FileSystem;

class Scxml {
	var interp : Interp;
	
	public var onInit : Void -> Void;
	public var log : String -> Void;
	public var parentEventHandler : Event -> Void;

	var content : String;
	var data : Array<{key:String, value:Dynamic}>;
	
	public function new( src : String = null, content : String = null, data : Array<{key:String, value:Dynamic}> = null ) {
		if( src != null ) {
			if( !FileSystem.exists(src) ) src = FileSystem.fullPath(src);
			if( !FileSystem.exists(src) ) throw "Invalid path: " + src;	
			content = sys.io.File.getContent(src);
		}
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
		
		var c = Thread.create(createInterp);
		c.sendMessage(scxml);
		c.sendMessage(onInit);
		c.sendMessage(log);
		c.sendMessage(parentEventHandler);
	}
	
	function createInterp() {
		var scxml = Thread.readMessage(true);
		var onInit = Thread.readMessage(true);
		var log = Thread.readMessage(true);
		var parentEventHandler = Thread.readMessage(true);
		var me = this;
		
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
	
	inline public function getDot() {
		return DrawTools.getDot(interp.topNode);
	}
	
	inline public function start() {
		interp.start();
	}
	
	inline public function stop() {
		interp.stop();
	}
	
	public function postEvent( evt : Event ) {
		if( interp != null ) {
			interp.postEvent( evt );
		}
	}
	
}
