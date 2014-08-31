package hsm.scxml;

#if haxe3
private typedef Hash<T> = haxe.ds.StringMap<T>;
#end

class Node {
	public var parent:Node;
	public var name:String;
	public var pos:Int; // position in document (used for sorting etc)
	public var isFirstEntry:Bool; // see enterStates in Interp
	public var atts:Hash<String>;
	var nodes:Array<Node>;
	//var cache:Hash<Node>;
	public function new(p:Node) {
		this.parent = p;
		this.isFirstEntry = true;
		this.atts = new Hash();
		this.nodes = new Array();
		//cache = new Hash();
	}
	public function set( key:String, val:String) {
		atts.set(key, val);
	}
	public function get( key:String ) : String {
		return atts.get(key);
	}
	public function exists( key:String ) : Bool {
		return atts.exists(key);
	}
	public function addNode( n:Node ) {
		nodes.push(n);
	}
	//public function cache() {
	//	nodes.push(n);
	//}
	public function list() : List<Node> {
		return Lambda.list(nodes);
	}
	public function iterator() : Iterator<Node> {
		return list().iterator();
	}
	public function toString() {
		return getString(this);
	}
	function getString( z : Node, n : Int=0 ) {
		var offset = "";
		for ( i in 0...n) offset += "      ";
		var a = "";
		for ( att in z.atts.keys() ) a += " :: " + att + " = " + z.atts.get(att);
//		a += "\n";
//		var no = "";
//		for ( node in z.list() )
//			no += getString(node,n+1);
		return offset + z.name + a;// + no;
	}
}

class Scxml extends Node {
	public function new(p:Node) { super(p); }
}

class State extends Node {
	public function new(p:Node) { super(p); }
}

class Parallel extends Node {
	public function new(p:Node) { super(p); }
}

class Final extends Node {
	public function new(p:Node) { super(p); }
}

class OnEntry extends Node {
	public function new(p:Node) { super(p); }
}

class OnExit extends Node {
	public function new(p:Node) { super(p); }
}

class Transition extends Node {
	public function new(p:Node) { super(p); }
}

class Initial extends Node {
	public function new(p:Node) { super(p); }
}

class History extends Node {
	public function new(p:Node) { super(p); }
}

class DataModel extends Node {
	public function new(p:Node) { super(p); }
}

class Data extends Node {
	public var content:String;
	public function new(p:Node) { super(p); content = null; }
}

class Send extends Node {
	public function new(p:Node) { super(p); }
}

class Content extends Node {
	public var content:String;
	public function new(p:Node) { super(p); content = null; }
}

class Param extends Node {
	public function new(p:Node) { super(p); }
}

class Invoke extends Node {
	public function new(p:Node) { super(p); }
}

class Finalize extends Node {
	public function new(p:Node) { super(p); }
}

class DoneData extends Node {
	public function new(p:Node) { super(p); }
}

class Exec extends Node {
	public function new(p:Node) { super(p); }
}

class Script extends Exec {
	public var content:String;
	public function new(p:Node) { super(p); content = null; }
}

class Assign extends Exec {
	public var content:String;
	public function new(p:Node) { super(p); content = null; }
}
