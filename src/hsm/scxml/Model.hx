package hsm.scxml;

import hscript.Parser;
import hscript.Interp;

import hsm.scxml.Node;
import hsm.scxml.Types;

#if haxe3
import haxe.crypto.BaseCode;
private typedef Hash<T> = haxe.ds.StringMap<T>;
#else
import haxe.BaseCode;
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
		hinterp.variables.set("Xml", Xml);
		hinterp.variables.set("Lambda", Lambda);
		hinterp.variables.set("_ioprocessors", {});
		setIoProc("http://www.w3.org/TR/scxml/#SCXMLEventProcessor", {location : "#_internal"});
		setIoProc("scxml", {location : "#_internal"});
		setIoProc("http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor", {location : "http://localhost:2000"});
		setIoProc("basichttp", {location : "http://localhost:2000"});
		setIoProc("http://www.w3.org/TR/scxml/#DOMEventProcessor", {location : "#_internal"});
		setIoProc("dom", {location : "#_internal"});
		
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
		return Reflect.hasField( hinterp.variables.get("_ioprocessors"), encProcKey(key) );
	}
	
	override public function getIoProc( key : String ) {
		var encKey = encProcKey(key);
		var procs : {} = hinterp.variables.get("_ioprocessors");
		return Reflect.hasField(procs, encKey) ? Reflect.field(procs, encKey) : null;
	}
	
	override public function setIoProc( key : String, value : TEvtProc ) {
		Reflect.setField( hinterp.variables.get("_ioprocessors"), encProcKey(key), value );
	}
	
	inline function encProcKey( key : String ) : String {
		return BaseCode.encode( key, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789__" );
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
		var r = ~/_ioprocessors\['([:\/\.a-zA-Z0-9#]+)'\]/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + "_ioprocessors." + encProcKey(r.matched(1)) + r.matchedRight();
		
		// [].concat(Var1, [4]) becomes Var1.concat([4])
		var r = ~/\[\].concat\((.+),[ ]*(.+)[ ]*\)/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + r.matched(1) + ".concat(" + r.matched(2) + ")" + r.matchedRight();
		
		expr = expr.split("!==").join("!=");
		expr = expr.split("===").join("==");
		expr = expr.split("String(").join("Std.string(");
		expr = expr.split(".slice(").join(".substr(");
		expr = expr.split("'undefined'").join("null");
		expr = expr.split("undefined").join("null");
		
		// _event.raw.search(/Var1=2/) or _event.raw.search(/Varparam1=1/)
		var r = ~/search\(\/(.*)\/\)/;
		while( r.match(expr) ) {
			var matched = r.matched(1);
			if( matched.indexOf("Var") == 0 ) {
				var tmp = r.matched(1).substr(3).split("=");
				if( ~/^[a-zA-Z_][a-zA-Z0-9_]*/.match(tmp[0]) )
					matched = tmp[0] + "=" + tmp[1];
			}
			expr = r.matchedLeft() + "search('" + matched + "')" + r.matchedRight();
		}
		
		var r = ~/typeof ([a-zA-Z0-9\._]+) /;
		while( r.match(expr) )
			if( !exists(r.matched(1)) )
				expr = r.matchedLeft() + "null " + r.matchedRight();
			else
				expr = r.matchedLeft() + "(try Type.getClassName(Type.getClass(" + r.matched(1) + ")) catch(e:Dynamic) null) " + r.matchedRight();
		
		// for obj['Var'] access
		var r = ~/([a-zA-Z0-9\._]+)\['(.*)'\]/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + r.matched(1) + "." + r.matched(2) + r.matchedRight();
		
		// converts _event.data.getElementsByTagName('book')[1].getAttribute('title') etc
		var r = ~/[ ]*([a-zA-Z0-9\._]+).getElementsByTagName\((.*)\)\[(.*)\]/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + "Lambda.array({iterator:function() return " + r.matched(1) + ".elementsNamed(" + r.matched(2) + ")})[" + r.matched(3) + "]" + r.matchedRight();
		expr = expr.split("getAttribute").join("get");
		
		var program = hparse.parseString(expr);
		var bytes = hscript.Bytes.encode(program);
		program = hscript.Bytes.decode(bytes);
		return hinterp.execute(program);
	}
	
	override public function doCond( expr : String ) : Bool {
		if( expr == "")
			return true;
		var val : Dynamic = null;
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

