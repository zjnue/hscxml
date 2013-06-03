package hsm.scxml;

import hscript.Parser;
import hscript.Interp;

import hsm.scxml.Node;
import hsm.scxml.Types;

#if haxe3
private typedef Hash<T> = haxe.ds.StringMap<T>;
private typedef Md5 = haxe.crypto.Md5;
#else
private typedef Md5 = haxe.Md5;
#end

typedef TEvtProc = {location:String};

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
	
	var illegalValues : Array<Dynamic>;
	
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
		illegalValues = [];
	}
	
	function set_isInState( value : String -> Bool ) {
		return isInState = value;
	}
	
	function set_log( value : String -> Void ) {
		return log = value;
	}
	
	public function hasIoProc( key : String ) {
		return false;
	}
	
	public function getIoProc( key : String ) {
		return null;
	}
	
	public function setIoProc( key : String, value : TEvtProc ) {
		
	}
	
	public function getSessionId() {
		return "sessionid_"+Std.string(sessionId++);
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
	
	public function doLoc( expr : String ) : Dynamic {
		return null;
	}
	
	public function doVal( expr : String ) : Dynamic {
		return null;
	}
	
	public function doAssign( loc : String, val : String ) : Dynamic {
		return null;
	}
	
	public function doScript( expr : String ) : Dynamic {
		return null;
	}
	
	public function isLegalVar( value : String ) {
		return true;
	}
	
	public function setEvent( evt : Event ) {
	
	}
	
	public function toString() {
		return "[Model]";
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
		h.set("_sessionid", _sessionId);
		h.set("_name", _name);
		h.set("_ioprocessors", new Hash<TEvtProc>());
	}
	
	override public function set( key : String, val : Dynamic ) {
		h.set(key, val);
	}
	
	override public function doCond( expr : String ) : Bool {
		if( expr == "" )
			return true;
		var r = ~/$In\(['"]*([a-zA-Z0-9._]+)['"]*\)/;
		if( r.match(expr.split(" ").join("")) )
			return isInState(r.matched(1));
		return false;
	}
	
	override public function toString() {
		return "[NullModel: " + Std.string(h) + "]";
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
		hinterp.variables.set("_sessionid", _sessionId);
		hinterp.variables.set("_name", _name);
		var _ioprocessors = new Hash<TEvtProc>();
		hinterp.variables.set("_ioprocessors", _ioprocessors);
		setIoProc("http://www.w3.org/TR/scxml/#SCXMLEventProcessor", {location : "default"});
		
		illegalValues = ["continue", "_sessionid", "_name", "_ioprocessors", "_event"];
	}
	
	override function set_isInState( value : String -> Bool ) {
		hinterp.variables.set("In", value);
		return isInState = value;
	}
	
	override function set_log( value : String -> Void ) {
		hinterp.variables.set("trace", value);
		return log = value;
	}
	
	override public function hasIoProc( key : String ) {
		var md5Key = Md5.encode(key);
		var procs : Hash<TEvtProc> = hinterp.variables.get("_ioprocessors");
		return procs.exists( md5Key );
	}
	
	override public function getIoProc( key : String ) {
		var md5Key = Md5.encode(key);
		var procs : Hash<TEvtProc> = hinterp.variables.get("_ioprocessors");
		return procs.exists( md5Key ) ? procs.get( md5Key ) : null;
	}
	
	override public function setIoProc( key : String, value : TEvtProc ) {
		var md5Key = Md5.encode(key);
		var procs : Hash<TEvtProc> = hinterp.variables.get("_ioprocessors");
		procs.set( md5Key , value );
	}
	
	override public function get( key : String ) : Dynamic {
		return hinterp.variables.get( key );
	}
	
	override public function set( key : String, val : Dynamic ) {
		if( Lambda.has(illegalValues, key) )
			throw "Tried to set illegal key: " + key;
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
		if( expr == "")
			return true;
		expr = expr.split("===").join("==");
		expr = expr.split("&lt;").join("<");
		expr = expr.split("&gt;").join(">");
		var val = null;
		try {
			val = eval(expr);
		} catch( e:Dynamic ) {
			log("error: e = " + Std.string(e));
		}
		if( val == null && exists(expr) )
			return true;
		return Std.is(val, Bool) ? val : (val != null);
	}
	
	override public function doLoc( expr : String ) : Dynamic {
		return eval(expr);
	}
	
	override public function doVal( expr : String ) : Dynamic {
		return eval(expr);
	}
	
	override public function doAssign( loc : String, val : String ) : Dynamic {
		if( !exists(loc) )
			throw "Trying to assign a value to an undeclared variable.";
		if( Lambda.has(illegalValues, loc) )
			throw "Tried to assign to illegal location: " + loc;
		return eval(loc + " = " + val);
	}
	
	override public function doScript( expr : String ) : Dynamic {
		expr = StringTools.trim(expr);
		expr = expr.split("var ").join(""); // tmp workaround - see test 302
		return eval(expr);
	}
	
	override public function isLegalVar( value : String ) {
		return !Lambda.has(illegalValues, value.split("'").join("").split("\"").join(""));
	}
	
	override public function setEvent( evt : Event ) {
		hinterp.variables.set( "_event", evt );
	}
	
	override public function toString() {
		return "[HScriptModel: " + Std.string(hinterp.variables) + "]";
	}
}
