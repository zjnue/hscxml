import sys.FileSystem;
import sys.io.File;

class PrettyScxml {

	public static function main() {
	
		var args = Sys.args();
		
		if( args.length < 1 )
			throw "Not enough arguments specified. Usage:\nneko prettify.n <file>\n";
					
		var cwd = Sys.getCwd();
		var path = args[0];
		
		if( !FileSystem.exists(cwd + path) )
			throw "File not found: " + cwd + path;
			
		var content = File.getContent(cwd + path);
		var xml = Xml.parse(content);
		
		Sys.print(doNode(xml));
	}
	
	public static function prettify( content : String ) {
		return doNode(Xml.parse(content));
	}
	
	static function doNode( n : Xml, indent:String="\t", level:Int=0 ) {
		
		var str = "";
		
		if( n.nodeType == Xml.Element ) {
		
			switch( n.nodeName ) {
				case "state", "final", "datamodel": str += "\n";
			}
		
			str += getIndent(indent, level) + getElementStart(n.nodeName);
			
			var tmpAttStr = "";
			for( att in n.attributes() ) {
				tmpAttStr += " " + att + "=\"" + n.get(att) + "\"";
			}
			
			if( tmpAttStr.length > 70 ) {
				str += "\n";
				for( att in n.attributes() ) {
					str += getIndent(indent, level+1) + att + "=\"" + n.get(att) + "\" \n";
				}
				str = str.substr(0, str.length-1);
			} else {
				str += tmpAttStr + ((tmpAttStr.length > 0) ? " " : "");
			}
			
			var children = Lambda.array( filteredChildren(n) );
			
			if( children.length == 0 )
				str += "/>\n";
			else {
				str += ">\n";
				
				var lev = level;
				
				for( child in children ) {
					
					if( child.nodeType == Xml.Element ) {
						
						switch( child.nodeName ) {
						case "elseif", "else":
							str += doNode( child, indent, lev );
						default:
							str += doNode( child, indent, lev+1 );
						}
						
					} else if( child.nodeType == Xml.PCData ) {
					
						var pcdata = StringTools.trim(child.toString());
						if( pcdata != "" ) {
							str += getIndent(indent, lev+1) + pcdata + "\n";
						}
					
					} else if( child.nodeType == Xml.Comment ) {
					
						str += getIndent(indent, lev+1) + child.toString() + "\n";
					}
				}
				
				str += getIndent(indent, level) + getElementClose(n.nodeName) + "\n";
			}
		
		} else if( n.nodeType == Xml.Comment ) {
		
			str += getIndent(indent, level) + n.toString() + "\n";
			
		} else if( n.nodeType == Xml.Document ) {
			
			for( child in n )
				str += getIndent(indent, level) + doNode( child, indent, level );
		}
		
		return str;
	}
	
	inline static function getElementStart( name : String ) {
		return "<" + name;
	}
	
	inline static function getElementClose( name : String ) {
		return "</" + name + ">";
	}
	
	inline static function filteredChildren( xml : Xml ) {
		return Lambda.filter( xml, function(x) return (x.nodeType == Xml.Element || x.nodeType == Xml.Comment || x.nodeType == Xml.PCData) );
	}
	
	inline static function getIndent( indent:String="\t", level:Int=0 ) {
		var str = "";
		for( i in 0...level )
			str += indent;
		return str;
	}
	
}
