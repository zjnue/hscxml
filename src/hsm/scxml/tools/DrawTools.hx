package hsm.scxml.tools;

import hsm.scxml.Node;
import hsm.scxml.Types;
import hsm.scxml.tools.NodeTools;

using hsm.scxml.tools.NodeTools;

#if haxe3
private typedef Hash<T> = haxe.ds.StringMap<T>;
#end

class DrawTools {
	
	/**
	dot sadly does not have great support for hsm's
	with lots or trials and help from links such as these (thanks), hopefully we'll get there
	http://osdir.com/ml/video.graphviz/2005-09/msg00021.html
	http://www.graphviz.org/content/dot-cluster-self-transition
	**/
	public static function getDot( node : Node, ?depth : Int = 0, states:Hash<Node>=null ) : String {
		
		if (states == null)
			states = new Hash<Node>();
		if (node.isState() && node.exists("id"))
			states.set(node.get("id"), node);
		
		var out = "";
		
		switch( node.name ) {
		
			case "scxml":
			
				out += getIndent(depth) + "digraph statechart {\n\n";
				out += getIndent(depth+1) + "graph[compound=true,overlap=false];\n";
				out += getIndent(depth+1) + "edge[fontname=\"Helvetica\",fontsize=10,arrowhead=vee];\n";
				out += getIndent(depth+1) + "node[fontname=\"Helvetica\",fontsize=10,shape=Mrecord];\n\n";
				//out += getIndent(depth+1) + "node[fontname=\"Helvetica\",fontsize=10,shape=rect,style=rounded];\n\n";
				
				for (child in node)
					out += getDot(child, depth+1, states);
				
				out += "\n" + getDotTransitions(node, depth+1, states);
				out += getIndent(depth) + "}\n";
			
			case "state":
			
				if( node.hasChildStates() ) {
				
					out += getIndent(depth) + "subgraph cluster_" + node.get("id") + "{\n\n";
					out += getIndent(depth+1) + "fontname=\"Helvetica\";\n";
					out += getIndent(depth+1) + "fontsize=10;\n";
					out += getIndent(depth+1) + "label = \"" + (node.exists("id") ? node.get("id") : "UNKNOWN_ID") + "\";\n\n";
					
					// transition to self hack - add an invisible node for every cluster
					out += getIndent(depth+1) + "invis_" + node.get("id") + "[style=invis,shape=circle,label=\"\",width=0.001,height=0.001];\n\n";
					
					for (child in node)
						out += getDot(child, depth+1, states);
					
					out += getIndent(depth) + "}\n";
					
				} else
					out += getIndent(depth) + node.get("id") + "[label=\"" + node.get("id") + "\",labelloc=t];\n";
			
			case "initial":
			
				out += getIndent(depth) + "initial_"+node.parent.get("id") + "[style=filled,shape=circle,color=black,label=\"\",width=.2,height=.2];\n";
			
			case "final":
			
				out += getIndent(depth) + node.get("id") + "[style=filled,shape=doublecircle,label=\"" + node.get("id") + "\",width=.2,height=.2];\n";
				
			default:
			
			/* TODO
			case "parallel": 	n = new Parallel(parent);
			case "history":		n = new History(parent);
			case "onentry":		n = new OnEntry(parent);
			case "onexit":		n = new OnExit(parent);
			case "transition":	n = new Transition(parent);
			case "datamodel":	var d = new DataModel(parent); data.add(d); n = d;
			case "data":		n = new Data(parent);
			case "invoke":		n = new Invoke(parent);
			case "finalize":	n = new Finalize(parent);
			case "content":		n = new Content(parent);
			case "log", "raise", "assign":	
				n = new Exec(parent);
			default:
				throw "node type not yet implemented: " + x.nodeName;*/
		}
		
		return out;
	}
	
	public static function getDotTransitions( node : Node, ?depth : Int = 0, states:Hash<Node>=null ) :String {
	
		var out = "";
		
		for( child in node ) {
		
			if( child.isTTransition() && node.isTInitial() ) {
				
				var tailId = "initial_" + node.parent.get("id");
				var headId = child.get("target");
				var targetNode = states.get(headId);
				out += getIndent(depth) + tailId + "->" +
					 (isCluster(targetNode) ? targetNode.getChildStates().first().get("id") + "[lhead=cluster_" + headId + "]" : headId);
				out += "\n";
			
			} else if( child.isTTransition() && node.exists("id") && child.exists("target") ) {
				
				var tailId = node.get("id");
				var headId = child.get("target");
					
				// cluster self-transition hack
				if( isCluster(node) && (tailId == headId) ) {
					
					var nodeId = tailId;
					var clusterId = "cluster_" + nodeId;
					var invisId = "invis_" + nodeId;
					
					out += getIndent(depth) + "__x__ [style=invis];\n";
					out += getIndent(depth) + node.getChildStates().first().get("id") + "-> __x__ [dir=none,ltail="+clusterId+",headclip=false];\n";
					out += getIndent(depth) + "__x__ ->" + invisId + "[lhead="+clusterId+",tailclip=false];";
					
				} else {
					
					var targetNode = states.get(headId);
					
					out += getIndent(depth) + 
						(isCluster(node) ? node.getChildStates().first().get("id") : tailId) + "->" + 
						(isCluster(targetNode) ? targetNode.getChildStates().first().get("id") : headId);
						
					var hasCluster = isCluster(node) || isCluster(targetNode);
					if( hasCluster ) out += "[";
					var propArr = [];
					if( isCluster(node) ) propArr.push( "ltail=cluster_" + tailId );
					if( isCluster(targetNode) ) propArr.push( "lhead=cluster_" + headId );
					if( hasCluster ) out += propArr.join(";") + "]";
					
				}	
				
				out += "\n";	
				
			} else if( child.isState() || child.isTInitial() ) {
				
				out += getDotTransitions(child, depth, states);
				
			}
		}
		
		return out;
	}
	
	inline static function isCluster( node : Node ) {
		return node.hasChildStates();
	}
	
	static function getIndent( depth:Int, sep:String="  " ) {
		var indent = "";
		for( i in 0...depth )
			indent += sep;
		return indent;
	}
}

