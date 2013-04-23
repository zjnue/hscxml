package hsm;

import hsm.scxml.Interp;
import hsm.scxml.Types;
import hsm.scxml.tools.DrawTools;

class Scxml {
	var interp : Interp;
	
	public var data( default, set_data ) : String;
	public var onInit( get_onInit, set_onInit ) : Void -> Void;
	public var log( get_log, set_log ) : String -> Void;
	
	public function new( ?_data : String ) {
		if (_data != null) data = _data;
		interp = new Interp();
	}
	
	public function init( ?_data : String, ?_onInit : Void -> Void ) {
		if (_data == null) _data = data;
		if (_data == null) throw "No data set";
		if (_onInit == null && onInit == null) throw "No onInit function set";
		if (_onInit != null) onInit = _onInit;
		var scxml = Xml.parse(_data).firstElement();
		interp.interpret(scxml);
	}
	
	inline public function getDot() {
		return DrawTools.getDot(interp.topNode);
	}
	
	inline public function start() {
		interp.start();
	}
	
	inline public function stop() {
		//interp.stop();
	}
	
	inline public function postEvent( str : String ) {
		interp.externalQueue.enqueue( new Event(str) );
	}
	
	inline function set_data( value : String ) {
		return data = value;
	}
	
	inline function get_onInit() : Void -> Void {
		return interp.onInit;
	}
	
	inline function set_onInit( value : Void -> Void ) {
		return interp.onInit = value;
	}
	
	inline function get_log() : String -> Void {
		return interp.log;
	}
	
	inline function set_log( value : String -> Void ) {
		return interp.log = value;
	}

}
