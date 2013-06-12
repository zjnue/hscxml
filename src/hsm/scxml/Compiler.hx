package hsm.scxml;

import hsm.scxml.Node;
import hsm.scxml.Types;

class Compiler {
	
	public function new() {
	}
	
	public function compile( x : Xml, parent : Node, ?data : List<DataModel>, ?count : Int = -1 ) : { node : Node, data : List<DataModel> } {
		var n : Node = null;
		var pos : Int = (count == -1) ? 0 : count;
		var addChildren = true;
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
			case "datamodel":	n = new DataModel(parent); data.add(cast n);
			case "data":		n = new Data(parent); if( !x.exists("expr") ) setContent(cast(n, Data), x); addChildren = false;
			case "send":		n = new Send(parent);
			case "invoke":		n = new Invoke(parent);
			case "finalize":	n = new Finalize(parent);
			case "donedata":	n = new DoneData(parent);
			case "content":		n = new Content(parent); if( !x.exists("expr") ) setContent(cast(n, Content), x); addChildren = false;
			case "param":		n = new Param(parent);
			case "log", "raise", "if", "elseif", "else", "foreach", "cancel":
				n = new Exec(parent);
			case "script":		n = new Script(parent); if( !x.exists("src") ) setContent(cast(n, Script), x); addChildren = false;
			case "assign":		n = new Assign(parent); if( !x.exists("expr") ) setContent(cast(n, Assign), x); addChildren = false;
			default:
				throw "node type not yet implemented: " + x.nodeName;
		}
		n.pos = pos;
		n.name = x.nodeName;
		if( addChildren )
			for( child in x.elements() )
				n.addNode( compile(child, n, data, ++pos).node );
		for( att in x.attributes() )
			n.set(att, StringTools.htmlUnescape(x.get(att)));
		return { node : n, data : data };
	}
	
	function setContent( contentNode : {content:String}, xml : Xml  ) {
		var buf = new StringBuf();
		for( child in xml )
			buf.add( child.toString() );
		contentNode.content = trim(buf.toString());
	}
	
	inline function trim( str : String ) {
		var r = ~/[ \n\r\t]+/g;
		return StringTools.trim(r.replace(str, " "));
	}
	
}
