package hsm.scxml;

import hscript.Parser;
import hscript.Interp;

import hsm.scxml.Node;

class Model {
	
	static var sessionId:Int = 0;
	
	public var supportsProps : Bool;
	public var supportsCond : Bool;
	public var supportsLoc : Bool;
	public var supportsVal : Bool;
	public var supportsAssign : Bool;
	public var supportsScript : Bool;
	
	public var isInState( default, set_isInState ) : String -> Bool;
	public var log( default, set_log ) : String -> Void;
	
	public function new( doc : Node ) {
		init(doc);
	}
	
	function init( doc : Node ) {
		supportsProps = false;
		supportsCond = false;
		supportsLoc = false;
		supportsVal = false;
		supportsAssign = false;
		supportsScript = false;
	}
	
	function set_isInState( value : String -> Bool ) {
		return isInState = value;
	}
	
	function set_log( value : String -> Void ) {
		return log = value;
	}
	
	public function getSessionId() {
		return Std.string(sessionId++);
	}
	
	public function get( key : String ) : Dynamic {
		return null;
	}
	
	public function set( key : String, val : Dynamic ) {
		
	}
	
	public function exists( key : String ) : Bool {
		return false;
	}
	
	public function remove( key : String ) {
		
	}
	
	public function doCond( expr : String ) : Bool {
		return false;
	}
	
	public function doLoc( expr : String ) : Dynamic  {
		return null;
	}
	
	public function doVal( expr : String ) : Dynamic  {
		return null;
	}
	
	public function doAssign( loc : String, val : String ) : Dynamic  {
		return null;
	}
	
	public function doScript( expr : String ) : Dynamic  {
		return null;
	}
}

class NullModel extends Model {
	
	var h : Hash<Dynamic>;
	
	public function new( doc : Node ) {
		super(doc);
	}
	
	override function init( doc : Node ) {
		super.init(doc);
		supportsCond = true;
		h = new Hash();
		var _sessionId = getSessionId();
		var _name = doc.exists("name") ? doc.get("name") : _sessionId;
		h.set("_sessionId", _sessionId);
		h.set("_name", _name);
	}
	
	override public function set( key : String, val : Dynamic ) {
		h.set(key, val);
	}
	
	override public function doCond( expr : String ) : Bool {
		var r = ~/$In\(['"]*([a-zA-Z0-9._]+)['"]*\)/;
		if( r.match(expr.split(" ").join("")) )
			return isInState(r.matched(1));
		return false;
	}
}

class EcmaScriptModel extends Model {
	public function new( doc : Node ) {
		super(doc);
	}
}

class XPathModel extends Model {
	public function new( doc : Node ) {
		super(doc);
	}
}

class HScriptModel extends Model {

	var hparse : hscript.Parser;
	var hinterp : hscript.Interp;
	
	public function new( doc : Node ) {
		super(doc);
	}
	
	override function init( doc : Node ) {
		supportsProps = true;
		supportsCond = true;
		supportsLoc = true;
		supportsVal = true;
		supportsAssign = true;
		supportsScript = true;
		
		hparse = new hscript.Parser();
		hinterp = new hscript.Interp();
		
		var _sessionId = getSessionId();
		var _name = doc.exists("name") ? doc.get("name") : _sessionId;
		hinterp.variables.set("_sessionId", _sessionId);
		hinterp.variables.set("_name", _name);
	}
	
	override function set_isInState( value : String -> Bool ) {
		hinterp.variables.set("In", value);
		return isInState = value;
	}
	
	override function set_log( value : String -> Void ) {
		hinterp.variables.set("trace", value);
		return log = value;
	}
	
	override public function get( key : String ) : Dynamic {
		return hinterp.variables.get( key );
	}
	
	override public function set( key : String, val : Dynamic ) {
		hinterp.variables.set( key, val );
	}
	
	override public function exists( key : String ) : Bool {
		return hinterp.variables.exists( key );
	}
	
	override public function remove( key : String ) {
		hinterp.variables.remove( key );
	}
	
	function eval( expr : String ) : Dynamic {
		var program = hparse.parseString(expr);
		var bytes = hscript.Bytes.encode(program);
		program = hscript.Bytes.decode(bytes);
		return hinterp.execute(program);
	}
	
	override public function doCond( expr : String ) : Bool {
		return eval(expr);
	}
	
	override public function doLoc( expr : String ) : Dynamic   {
		return eval(expr);
	}
	
	override public function doVal( expr : String ) : Dynamic   {
		return eval(expr);
	}
	
	override public function doAssign( loc : String, val : String ) : Dynamic  {
		return eval(loc + " = " + val);
	}
	
	override public function doScript( expr : String ) : Dynamic  {
		return eval(expr);
	}
}
