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
			throw "Unknown target " + Std.string(args[0]) +". Usage:\nneko convert.n [ecma|xpath|hscript]\n";
		}
		
		var prettify = true;
		
		if( args.length > 1 )
			prettify = (Std.string(args[1]) == "true");
		
		var stamp : Float;
		var fileName : String;
		
		for( path in sys.FileSystem.readDirectory(cwd + "txml") ) {
			
			var parts = path.split(".");
			if( parts.pop() != "txml" )
				continue;
				
			Sys.print("converting.. " + path);
			
			fileName = parts.join("") + ".scxml";
			stamp = haxe.Timer.stamp();
			
			// grab a stable build of the open-source saxon xslt 2.0 processor and place it in this folder
			// http://sourceforge.net/projects/saxon/files/Saxon-HE/9.4/SaxonHE9-4-0-7J.zip/download
			
			Sys.command("java", ["-jar", "saxon9he.jar", "-xsltversion:2.0", "-s:txml/" + path, "-xsl:xsl/" + xsl, "-o:" + out + "/" + fileName]);
			
			if( prettify ) {
			
				var content = sys.io.File.getContent(cwd + out + "/" + fileName);
				content = PrettyScxml.prettify(content);
				sys.io.File.saveContent(cwd + out + "/" + fileName, content);
				
			}
			
			Sys.print(" [" + Std.string( Std.int((haxe.Timer.stamp() - stamp) * 100) / 100) + "s]\n");
		}
		
	}

}
