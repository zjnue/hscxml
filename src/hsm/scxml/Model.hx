package hsm.scxml;

import hscript.Parser;
import hscript.Interp;

import hsm.scxml.Node;
import hsm.scxml.Types;

#if haxe3
private typedef Hash<T> = haxe.ds.StringMap<T>;
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
	
	var illegalLhs : Array<String>;
	var illegalExpr : Array<String>;
	var illegalValues : Array<String>;
	
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
		illegalLhs = [];
		illegalExpr = [];
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
		var _name = doc.exists("name") ? doc.get("name") : null;
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

	inline static var BASE64_CHARS : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";
	
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
		var _name = doc.exists("name") ? doc.get("name") : null;
		hinterp.variables.set("_sessionid", _sessionId);
		hinterp.variables.set("_name", _name);
		hinterp.variables.set("Std", Std);
		hinterp.variables.set("Type", Type);
		hinterp.variables.set("_ioprocessors", {});
		setIoProc("http://www.w3.org/TR/scxml/#SCXMLEventProcessor", {location : "default"});
		
		illegalExpr = ["continue", "return"];
		illegalLhs = ["_sessionid", "_name", "_ioprocessors", "_event"];
		illegalValues = illegalExpr.concat(illegalLhs);
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
		var encKey = haxe.BaseCode.encode( key, BASE64_CHARS );
		var procs : {} = hinterp.variables.get("_ioprocessors");
		return Reflect.hasField( procs, encKey );
	}
	
	override public function getIoProc( key : String ) {
		var encKey = haxe.BaseCode.encode( key, BASE64_CHARS );
		var procs : {} = hinterp.variables.get("_ioprocessors");
		return Reflect.hasField(procs, encKey) ? Reflect.field(procs, encKey) : null;
	}
	
	override public function setIoProc( key : String, value : TEvtProc ) {
		var encKey = haxe.BaseCode.encode( key, BASE64_CHARS );
		var procs : {} = hinterp.variables.get("_ioprocessors");
		Reflect.setField( procs, encKey, value );
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
		var r = ~/_ioprocessors\['(.*)'\]/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + "_ioprocessors." + haxe.BaseCode.encode( r.matched(1), BASE64_CHARS ) + r.matchedRight();
		var program = hparse.parseString(expr);
		var bytes = hscript.Bytes.encode(program);
		program = hscript.Bytes.decode(bytes);
		return hinterp.execute(program);
	}
	
	override public function doCond( expr : String ) : Bool {
		if( expr == "")
			return true;
		expr = expr.split("===").join("==");
		expr = expr.split("String(").join("Std.string(");
		expr = expr.split(".slice(").join(".substr(");
		expr = expr.split("'undefined'").join("null");
		expr = expr.split("undefined").join("null");
		
		var r = ~/typeof ([a-zA-Z0-9\._]+) /;
		while( r.match(expr) )
			if( !exists(r.matched(1)) )
				expr = r.matchedLeft() + "null " + r.matchedRight();
			else
				expr = r.matchedLeft() + "Type.getClassName(Type.getClass(" + r.matched(1) + ")) " + r.matchedRight();
		
		// for obj['Var'] access
		var r2 = ~/([a-zA-Z0-9\._]+)\['(.*)'\]/;
		while( r2.match(expr) )
			expr = 	r2.matchedLeft() + r2.matched(1) + "." + r2.matched(2) + r2.matchedRight();
		
		var val = null;
		if( Lambda.has(illegalExpr, expr) )
			throw "Illegal expr used in cond: " + expr;
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
