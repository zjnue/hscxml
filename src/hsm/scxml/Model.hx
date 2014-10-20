package hsm.scxml;

import hscript.Parser;
import hscript.Interp;

import hsm.scxml.Node;
import hsm.scxml.Types;

#if flash
import flash.xml.XML;
import flash.xml.XMLList;
import flash.xml.XMLNode;
import flash.xml.XMLNodeType;
import memorphic.xpath.XPathQuery;
import memorphic.xpath.model.XPathContext;
#end

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
	
	public function new() {
	}
	
	public function init( doc : Node ) {
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
	
	inline function encProcKey( key : String ) : String {
		return BaseCode.encode( key, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789__" );
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
	
	public function doAssign( loc : String, val : Dynamic, ?type : String, ?attr : String ) : Dynamic {
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
	
	public function getTypedDataStr( content : String ) : String {
		if( content == null || content == "" )
			return "";//content;
		var isNum = Std.parseInt(content) != null;
		if( !isNum ) isNum = !Math.isNaN( Std.parseFloat(content) );
		if( isNum ) return content;
		var isObj = false;
		try {
			var tmp = doVal(content);
			isObj = Reflect.isObject(tmp);
		} catch( e:Dynamic ) isObj = false;
		if( isObj ) return content;
		var isXml = false;
		try {
			var tmp = Xml.parse(content);
			isXml = Std.is( tmp.firstElement(), Xml );
		} catch( e:Dynamic ) isXml = false;
		if( isXml ) return "Xml.parse( '" + content.split("'").join("\\'") + "' ).firstElement()";
		var isArray = false;
		try {
			var tmp = doVal(content);
			isArray = Std.is( tmp, Array );
		} catch( e:Dynamic ) isArray = false;
		if( isArray ) return content;
		return "'" + content.split("'").join("\\'") + "'";
	}
}

class NullModel extends Model {
	
	var h : Hash<Dynamic>;
	
	public function new() {
		super();
	}
	
	override public function init( doc : Node ) {
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
		var r = ~/In\(['"]+([a-zA-Z0-9._]+)['"]+\)/;
		if( r.match(expr.split(" ").join("")) )
			return isInState(r.matched(1));
		return false;
	}
	
	override public function toString() {
		return "[NullModel: " + Std.string(h) + "]";
	}
}

class EcmaScriptModel extends HScriptModel {
	
	public function new() {
		super();
	}
	
	override function eval( expr : String ) : Dynamic {
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
		
		// var1 instanceof Array
		var r = ~/([a-zA-Z0-9\._]+) instanceof ([a-zA-Z0-9\._]+)/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + "Std.is(" + r.matched(1) + ", " + r.matched(2) + ") " + r.matchedRight();
		
		// 'name' in _event
		var r = ~/(['a-zA-Z0-9\._]+) in ([a-zA-Z0-9\._]+)/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + "Reflect.hasField(" + r.matched(2) + ", " + r.matched(1) + ") " + r.matchedRight();
		
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
		
		// for new testobject();
		var r = ~/new ([a-zA-Z0-9\._]+)\(\);/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + r.matched(1) + "()" + r.matchedRight();
		
		// for function testobject() {
    	// 		this.bar = 0;}
		var r = ~/function ([a-zA-Z0-9\._]+)\(\)[\r\n\t ]*\{[\r\n\t ]*this.bar[\r\n\t ]*=[\r\n\t ]*0;\}/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + r.matched(1) + " = function() { return {bar:0}; }" + r.matchedRight();
		
		var program = hparse.parseString(expr);
		var bytes = hscript.Bytes.encode(program);
		program = hscript.Bytes.decode(bytes);
		return hinterp.execute(program);
	}
	
	override public function doScript( expr : String ) : Dynamic {
		expr = StringTools.trim(expr);
		expr = expr.split("var ").join(""); // tmp workaround - see test 302
		return eval(expr);
	}
	
	override public function toString() {
		return "[EcmaScriptModel: " + Std.string(hinterp.variables) + "]";
	}
}

#if flash
class XPathModel extends Model {
	
	var x : XML;
	var context : XPathContext;
	
	public function new() {
		super();
	}
	
	static function __init__() {
		XML.ignoreWhitespace = true;
		XML.prettyPrinting = true;
	}
	
	override public function init( doc : Node ) {
		super.init(doc);
		
		supportsProps = true;
		supportsCond = true;
		supportsLoc = true;
		supportsVal = true;
		supportsAssign = true;
		supportsScript = true;
		
		var _sessionId = getSessionId();
		var _name = doc.exists("name") ? doc.get("name") : null;
		
		context = new XPathContext();
		x = new XML("<datamodel></datamodel>");
		set("_ioprocessors",
			'<processor name="${Const.IOPROC_SCXML}"><location>#_internal</location></processor>
			<processor name="${Const.IOPROC_SCXML_SHORT}"><location>#_internal</location></processor>
			<processor name="${Const.IOPROC_BASICHTTP}"><location>http://localhost:2000</location></processor>
			<processor name="${Const.IOPROC_BASICHTTP_SHORT}"><location>http://localhost:2000</location></processor>
			<processor name="${Const.IOPROC_DOM}"><location>#_internal</location></processor>
			<processor name="${Const.IOPROC_DOM_SHORT}"><location>#_internal</location></processor>'
		);
		set("_sessionid", _sessionId);
		set("_name", _name);
		untyped context.functions["In"] = xpIsInState;
		
		illegalExpr = [];
		illegalLhs = [".."];
		illegalValues = illegalExpr.concat(illegalLhs);
	}
	
	function xpIsInState(context:XPathContext, state:String) {
		return isInState(state);
	}
	
	override public function getTypedDataStr( content : String ) : String {
		return content;
	}

	override public function get( key : String ) : Dynamic {
		var out : Dynamic = null;
		if( exists(key) )
			out = untyped context.variables[key];
		return fromXPathValue(out);
	}

	function fromXPathValue( value : Dynamic ) : Dynamic {
		if( value == null || Std.is(value, Float) || Std.is(value, String) || Std.is(value, Bool) )
			return value;
		if( Std.is(value, XMLList) ) {
			var arr = [];
			var list = cast(value, XMLList);
			var len = list.length();
			for( i in 0...len )
				arr.push( list[i] );
			return arr.length == 1 ? arr[0] : arr;
		}
		return null;
	}
	
	function getBool( val : Dynamic ) {
		if( Std.is(val, Bool) )
			return val;
		else if( Std.is(val, Float) )
			return val != 0;
		else if( Std.is(val, String) )
			return val != null;
		else if( Std.is(val, XMLList) )
			return cast(val, XMLList).length() != 0;
		else
			return false;
	}
	
	override public function exists( key : String ) : Bool {
		return context.variables.hasOwnProperty(key);
	}

	override public function setEvent( evt : Event ) {
		var xmlStr = obj2XmlStr(evt.toObj(), 0);
		set("_event", xmlStr);
	}

	function obj2XmlStr( obj : Dynamic, level : Int ) {
		var str = "";
		if (Std.is(obj, String) || Std.is(obj, Float) || Std.is(obj, Array)) {
			str += Std.string(obj);
		} else if( Std.is(obj, Hash) ) {
			var tmp : Hash<Dynamic> = cast obj;
			for( key in tmp.keys() ) {
				var val = tmp.get(key);
				if( level == 0 ) {
					str += val == null ?
						"<" + key + "/>" :
						"<" + key + ">" + obj2XmlStr(val, level+1) + "</" + key + ">";
				} else {
					str += val == null ?
						"<data id=\"" + key + "\"/>" :
						"<data id=\"" + key + "\">" + obj2XmlStr(val, level+1) + "</data>";
				}
			}
		} else if( Std.is(obj, {}) || Std.is(obj, Dynamic) ) {
			for( field in Reflect.fields(obj) ) {
				var val = Reflect.field(obj, field);
				if( level == 0 ) {
					str += val == null ?
						"<" + field + "/>" :
						"<" + field + ">" + obj2XmlStr(val, level+1) + "</" + field + ">";
				} else {
					str += val == null ?
						"<data id=\"" + field + "\"/>" :
						"<data id=\"" + field + "\">" + obj2XmlStr(val, level+1) + "</data>";
				}
			}
		}
		return str;
	}

	override public function set( key : String, val : Dynamic ) {
		if( Std.is(val, XML) ) {
			untyped context.variables[key] = val;
			return;
		}
		var node : XML = null;
		
		if( exists(key) ) {
			var tmp = untyped context.variables[key];
			if( Std.is(tmp, XMLList) )
				node = cast(tmp, XMLList)[0];
		} else {
			node = new XML('<data id="$key"/>');
			x.appendChild(node);
			var func = function(context:XPathContext, x:XML, key:String) {
				var q = new XPathQuery("/datamodel/data[@id='" + key +"']", context);
				return q.exec(x);
			};
			untyped context.variables[key] = func(context, x, key);
		}
		var children : XMLList = node.children();
		var i = children.length();
		while( --i >= 0 )
			untyped __delete__(children, Reflect.fields(children)[i]);
		if( val == null )
			return;
		
		try {
			if( Std.is(val, XML) )
				node.appendChild( val );
			else if( Std.is(val, XMLList) ) {
				var tmpl = cast(val, XMLList);
				for( i in 0...tmpl.length() )
					node.appendChild( tmpl[i] );
			} else
				node.appendChild( new XML(Std.string(val)) );
		} catch( e : Dynamic ) {
			var xmlStr = "<p>" + Std.string(val) + "</p>";
			var xml = new XML(xmlStr);
			var children = xml.children();
			for( i in 0...children.length() )
				node.appendChild( children[i] );
		}
	}
	
	override public function hasIoProc( key : String ) {
		return doCond("/datamodel/data[@id='_ioprocessors']/processor[@name='" + key + "']");
	}
	
	function eval( expr : String ) : Dynamic {
		var val : Dynamic = null;
		try {
			var query = new XPathQuery(expr, context);
			val = query.exec(x);
		} catch( e : Dynamic ) {
			val = expr;
		}
		return val;
	}
	
	override public function doCond( expr : String ) : Bool {
		var out = false;
		try {
			var val = eval(expr);
			out = getBool(val);
		} catch( e : Dynamic ) {
			return false;
		}
		return out;
	}
	
	override public function isLegalVar( value : String ) {
		return !Lambda.has(illegalValues, value.split("'").join("").split("\"").join(""));
	}
	
	override public function doLoc( loc : String ) : Dynamic {
		try {
			var result = eval(loc);
			return fromXPathValue(result);
		} catch( e : Dynamic ) {
			var id = getIdentifier(loc);
			if( id != null && !exists(id)) {
				set(id, null);
				return doLoc(loc);
			}
		}
		return null;
	}
	
	inline function getIdentifier( str : String ) {
		var r = ~/\$([a-zA-Z_]+[a-zA-Z0-9_]*)/;
		return r.match(str) ? r.matched(1) : null;
	}
	
	override public function doVal( expr : String ) : Dynamic {
		return expr == null ? null : fromXPathValue( eval(expr) );
	}
	
	function doLocLocal( loc : String ) : Dynamic {
		try {
			return eval(loc);
		} catch( e : Dynamic ) {
			var id = getIdentifier(loc);
			if( id != null && !exists(id)) {
				set(id, null);
				return doLocLocal(loc);
			}
		}
		return null;
	}
	
	inline function doValLocal( expr : String ) : Dynamic {
		return expr == null ? null : eval(expr);
	}
	
	override public function doAssign( loc : String, val : Dynamic, ?type : String, ?attr : String ) : Dynamic {
		var tmp : Dynamic = doLocLocal(loc);
		var list : XMLList = null;
		if( Std.is(tmp, XML) )
			list = new XML("<p>" + tmp.toXMLString() + "</p>").elements();
		else if( Std.is(tmp, XMLList) )
			list = cast tmp;
		
		var value : Dynamic = null;
		try {
			value = doValLocal(val);
		} catch( e : Dynamic ) {
			value = new XML(Std.string(val));
		}
		var len = list.length();
		if( Std.is(tmp, XML) && type == "addattribute" ) {
			doAssignInner( tmp, val, value, type, attr );
			return null;
		}
		for( i in 0...len )
			if( !doAssignInner( list[i], val, value, type, attr ) )
				return null;
		return null;
	}
	
	function doAssignInner( el : XML, val : Dynamic, value : Dynamic, ?type : String, ?attr : String ) {
		switch( el.nodeKind() ) {
			case "attribute":
				var pre = value;
				try {
					value = new XML(value);
				} catch( e : Dynamic ) {
					value = pre;
				}
				if( Std.is(value, XML) && value.hasComplexContent() )
					throw "bad attribute value";
				
				var p = el.parent();
				var atts = p.attributes();
				for( i in 0...atts.length() ) {
					if( atts[i] == el ) {
						atts[i] = new XML(Std.string(val));
						break;
					}
				}
			
			case "element":
				if( type == null ) {
					var children : XMLList = el.children();
					var i = children.length();
					while( --i >= 0 )
						untyped __delete__(children, Reflect.fields(children)[i]);
				}
				// make copy: see test470
				if( Std.is(value, XMLList) )
					value = value.copy();
				else if( Std.is(value, String) )
					value = new XML(value);
				if( type == null )
					el.appendChild(value);
				else {
					switch( type ) {
						case "firstchild": el.prependChild(value);
						case "lastchild": el.appendChild(value);
						case "nextsibling": el.parent().insertChildAfter(el, value);
						case "previoussibling": el.parent().insertChildBefore(el, value);
						case "replace": el.parent().replace(el.childIndex(), value);
						case "delete": el.parent().replace(el.childIndex(), "");
						case "addattribute": Reflect.setField(el, "@"+attr, value);
					}
				}
		}
		return true;
	}
	
	override public function toString() {
		return "[XPathModel: " + Std.string(x.toXMLString()) + "]";
	}
}
#else
class XPathModel extends Model {
	public function new() {
		super();
	}
}
#end

class HScriptModel extends Model {

	var hparse : hscript.Parser;
	var hinterp : hscript.Interp;
	
	public function new() {
		super();
	}
	
	override public function init( doc : Node ) {
		supportsProps = true;
		supportsCond = true;
		supportsLoc = true;
		supportsVal = true;
		supportsAssign = true;
		supportsScript = true;
		
		hparse = new hscript.Parser();
		hparse.allowJSON = true;
		hinterp = new hscript.Interp();
		
		var _sessionId = getSessionId();
		var _name = doc.exists("name") ? doc.get("name") : null;
		hinterp.variables.set("_sessionid", _sessionId);
		hinterp.variables.set("_name", _name);
		hinterp.variables.set("Array", Array);
		hinterp.variables.set("Std", Std);
		hinterp.variables.set("Type", Type);
		hinterp.variables.set("Xml", Xml);
		hinterp.variables.set("Reflect", Reflect);
		hinterp.variables.set("Lambda", Lambda);
		hinterp.variables.set("_ioprocessors", {});
		hinterp.variables.set("In", isInState);
		hinterp.variables.set("trace", log);
		
		setIoProc( Const.IOPROC_SCXML, {location : "#_internal"} );
		setIoProc( Const.IOPROC_SCXML_SHORT, {location : "#_internal"} );
		setIoProc( Const.IOPROC_BASICHTTP, {location : "http://localhost:3000"} );
		setIoProc( Const.IOPROC_BASICHTTP_SHORT, {location : "http://localhost:3000"} );
		setIoProc( Const.IOPROC_DOM, {location : "#_internal"} );
		setIoProc( Const.IOPROC_DOM_SHORT, {location : "#_internal"} );
		
		illegalExpr = ["continue", "return"];
		illegalLhs = ["_sessionid", "_name", "_ioprocessors", "_event"];
		illegalValues = illegalExpr.concat(illegalLhs);
	}
	
	override function set_isInState( value : String -> Bool ) {
		if( hinterp != null )
			hinterp.variables.set("In", value);
		return isInState = value;
	}
	
	override function set_log( value : String -> Void ) {
		if( hinterp != null )
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
	
	override public function get( key : String ) : Dynamic {
		return hinterp.variables.get( key );
	}
	
	override public function set( key : String, val : Dynamic ) {
		if( Lambda.has(illegalValues, key) )
			throw "Tried to set illegal key: " + key;
		hinterp.variables.set( key, val );
	}
	
	override public function exists( key : String ) : Bool {
		var out = false;
		try {
			var tmp = eval(key);
			out = true;
		} catch( e : Dynamic ) {}
		return out;
	}
	
	override public function remove( key : String ) {
		hinterp.variables.remove( key );
	}
	
	function eval( expr : String ) : Dynamic {
		var r = ~/_ioprocessors\['([:\/\.a-zA-Z0-9#]+)'\]/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + "_ioprocessors." + encProcKey(r.matched(1)) + r.matchedRight();
		
		// for obj['Var'] access
		var r = ~/([a-zA-Z0-9\._]+)\['(.*)'\]/;
		while( r.match(expr) )
			expr = 	r.matchedLeft() + r.matched(1) + "." + r.matched(2) + r.matchedRight();
		
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
	
	override public function doAssign( loc : String, val : Dynamic, ?type : String, ?attr : String ) : Dynamic {
		if( !exists(loc) )
			throw "Trying to assign a value to an undeclared variable.";
		if( Lambda.has(illegalValues, loc) )
			throw "Tried to assign to illegal location: " + loc;
		return eval(loc + " = " + val);
	}
	
	override public function doScript( expr : String ) : Dynamic {
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
