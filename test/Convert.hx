class Convert {

	public static function main() {
	
		var args = Sys.args();
		
		if( args.length < 1 )
			throw "Not enough arguments specified. Usage:\nneko convert.n [ecma|xpath|hscript]\n";
					
		var cwd = Sys.getCwd();
		
		if( !sys.FileSystem.exists(cwd + "txml") )
			throw "txml source folder does not exist.";
		if( !sys.FileSystem.exists(cwd + "xsl") )
			throw "xsl source folder does not exist.";
			
		var xsl = "";
		var out = "";
		
		switch( args[0] ) {
		case "ecma":
			if( !sys.FileSystem.exists(cwd + "xsl/confEcma.xsl") )
				throw "stylesheet xsl/confEcma.xml not found.";
			xsl = "confEcma.xsl";
			out = "ecma";
		
		case "xpath":
			if( !sys.FileSystem.exists(cwd + "xsl/confXPath.xsl") )
				throw "stylesheet xsl/confXPath.xsl not found.";
			xsl = "confXPath.xsl";
			out = "xpath";
				
		case "hscript":
			throw "Not yet supported";
			
		default:
			throw "Unknown target " + Std.string(args[1]) +". Usage:\nneko convert.n [ecma|xpath|hscript]\n";
		}
		
		for( path in sys.FileSystem.readDirectory(cwd + "txml") ) {
			
			var parts = path.split(".");
			if( parts.pop() != "txml" )
				continue;
			
			new sys.io.Process("xsltproc", ["xsl/" + xsl, "txml/" + path, "-o", out + "/" + parts.join("") + ".xml"]);
		}
		
	}

}
