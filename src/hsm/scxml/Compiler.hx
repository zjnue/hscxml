package hsm.scxml;

import hsm.scxml.Node;
import hsm.scxml.Types;

class Compiler {
	
	public function new() {
	}
	
	public function compile( x : Xml, parent : Node, ?data : List<DataModel>, ?count : Int = -1 ) : { node : Node, data : List<DataModel> } {
		var n : Node = null;
		var pos : Int = (count == -1) ? 0 : count;
		if( data == null )
			data = new List<DataModel>();
		switch( x.nodeName ) {
			case "scxml":		n = new Scxml(parent);
			case "state":		n = new State(parent);
			case "parallel": 	n = new Parallel(parent);
			case "initial": 	n = new Initial(parent);
			case "final":		n = new Final(parent);
			case "history":		n = new History(parent);
			case "onentry":		n = new OnEntry(parent);
			case "onexit":		n = new OnExit(parent);
			case "transition":	n = new Transition(parent);
			case "datamodel":	var d = new DataModel(parent); data.add(d); n = d;
			case "data":		n = new Data(parent); if( !x.exists("expr") ) for( child in x ) cast(n, Data).content += child.toString();
			case "send":		n = new Send(parent);
			case "invoke":		n = new Invoke(parent);
			case "finalize":	n = new Finalize(parent);
			case "content":		n = new Content(parent);
			case "log", "raise", "assign", "if", "elseif", "else", "foreach":
				n = new Exec(parent);
			case "script":		n = new Script(parent); if( !x.exists("src") ) for( child in x ) cast(n, Script).content += child.toString();
			default:
				throw "node type not yet implemented: " + x.nodeName;
		}
		n.pos = pos;
		n.name = x.nodeName;
		for( child in x.elements() )
			n.addNode( compile(child, n, data, ++pos).node );
		for( att in x.attributes() )
			n.set(att, x.get(att));
		return { node : n, data : data };
	}
	
}
