package hsm.scxml;

using hsm.scxml.tools.ListTools;

#if haxe3
private typedef Hash<T> = haxe.ds.StringMap<T>;
#end

class Event {
	// see 5.10.1 The Internal Structure of Events
	public var name : String;
	public var type : String;
	public var sendid : String;
	public var origin : String;
	public var origintype : String;
	public var invokeid : String;
	public var data : Dynamic;
	// ?
	public var raw : String;
	
	public function new( name : String, ?data : Dynamic ) {
		this.name = name;
		this.data = {};
		this.type = "platform";
		this.raw = "";
		if( data != null )
			for( key in Reflect.fields(data) )
				Reflect.setField(this.data, key, Reflect.field(data, key));
	}
	public function toString() {
		var out = "[Event: " + name;
		for( field in Reflect.fields(data) )
			out += "\n\t" + field + " = " + Std.string(Reflect.field(data, field));
		if( out != "[Event: " + name )
			out += "\n";
		return out + "]";
	}
}

class Set<T> {
	public var l : List<T>;
	public function new( ?s : Set<T> ) { l = s != null ? s.toList().clone() : new List<T>(); }
	public inline function add( i : T ) { if( !Lambda.has(l, i) ) l.add( i ); }
	public inline function delete( i : T ) { return l.remove( i ); }
	public inline function union( s : Set<T> ) { for( i in s ) add(i); }
	public inline function isMember( i : T ) { return Lambda.has(l, i); }
	public function hasIntersection( s : Set<T> ) {
		for( i in s )
			if( Lambda.has(l, i) )
				return true;
		return false;
	}
	public inline function isEmpty() { return l.isEmpty(); }
	public inline function clear() { return l = new List<T>(); }
	public inline function toList() { return l; }
	public inline function iterator() { return l.iterator(); }
	public inline static function ofList<T>( l : List<T> ) : Set<T> {
		var s = new Set<T>();
		s.l = l;
		return s;
	}
}

class Queue<T> {
	var l : List<T>;
	public function new() { l = new List<T>(); }
	public inline function enqueue( i : T ) { l.add( i ); }
	public inline function dequeue() { return l.pop(); }
	public inline function isEmpty() { return l.isEmpty(); }
	public function toString() {
		var out = "";
		for ( item in l ) out += Std.string(item) + "\n";
		return out;
	}
}

class BlockingQueue<T> {
	var l : List<T>;
	public function new() { l = new List<T>(); callOnNewContent = false; }
	public var callOnNewContent : Bool;
	public var onNewContent : Void -> Void;
	public inline function enqueue( i : T ) {
		l.add( i );
		if (callOnNewContent) {
			callOnNewContent = false;
			onNewContent();
		}
	}
	public function dequeue() {
		//while( l.isEmpty() ) {}
		return l.pop();
	}
}
