package hsm.scxml;

using hsm.scxml.tools.ListTools;

class Event {
	public var name : String;
	public var data : Hash<Dynamic>;
	var h : Hash<String>;
	public function new( name : String, ?data : Dynamic ) {
		this.name = name;
		this.data = new Hash();
		if( data != null )
			for( key in Reflect.fields(data) )
				this.data.set(key, Reflect.field(data, key) );
		h = new Hash();
	}
	public function set( key : String, val : Dynamic ) {
		h.set(key, val);
	}
	public function get( key ) {
		return h.get(key);
	}
}

class DModel { // check: calling this Datamodel causes cpp to clash with DataModel in Node.hx
	var doc : Node;
	var h : Hash<Dynamic>;
	public function new( d : Node ) {
		doc = d;
		h = new Hash();
	}
	public function set( key : String, val : Dynamic ) {
		h.set(key, val);
	}
	public function get( key ) {
		return h.get(key);
	}
}

class Set<T> {
	public var l : List<T>;
	public function new( ?s : Set<T> ) l = s != null ? s.toList().clone() : new List<T>()
	public inline function add( i : T ) l.add( i )
	public inline function delete( i : T ) return l.remove( i )
	public inline function clear() return l = new List<T>()
	public inline function isEmpty() return l.isEmpty()
	public inline function toList() return l
	public inline function iterator() return l.iterator()
	public function member( i : T ) : Bool {
		for( item in l )
			if( item == i )
				return true;
		return false;
	}
	public function diff( s : Set<T> ) : Set<T> {
		if( s == null )
			return this;
		var out = new Set<T>();
		for( i in l ) {
			var skip = false;
			for( j in s ) {
				if ( i == j ) {
					skip = true;
					break;
				}
			}
			if( !skip )
				out.add( i );
		}
		return out;
	}
	public function sort( f : T -> T -> Int ) {
		var arr = Lambda.array(l);
		arr.sort(f);
		var s2 = new Set<T>(); // check why we create a new set here
		for( i in arr )
			s2.add(i);
		return s2;
	}
	public inline function add2( i : T ) {
		l.add( i ); return this;
	}
	public inline static function ofList<T>( l : List<T> ) : Set<T> {
		var s = new Set<T>();
		s.l = l;
		return s;
	}
}

class Queue<T> {
	var l : List<T>;
	public function new() l = new List<T>()
	public inline function enqueue( i : T ) l.add( i )
	public inline function dequeue() return l.pop()
	public inline function isEmpty() return l.isEmpty()
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
