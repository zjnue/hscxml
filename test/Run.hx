class Run {
	
	public static function main() {
	
		var args = Sys.args();
		
		if( args.length < 1 )
			throw "Not enough arguments specified. Usage:\nneko convert.n [ecma|xpath|hscript]\n";
					
		var cwd = Sys.getCwd();
		var src = "";
		
		switch( args[0] ) {
		case "ecma":
			src = "ecma";
			if( !sys.FileSystem.exists(cwd + "ecma") )
				throw "source folder ecma not found.";
		
		case "xpath":
			src = "xpath";
			if( !sys.FileSystem.exists(cwd + "xpath") )
				throw "source folder xpath not found.";
				
		case "hscript":
			throw "Not yet supported";
			
		default:
			throw "Unknown target " + Std.string(args[1]) +". Usage:\nneko convert.n [ecma|xpath|hscript]\n";
		}
		
		// provides tmp jump option
		var from = args.length > 1 ? args[1] : null;
		var fromFound = false;
		
		var sm : hsm.Scxml = null;
		
		for( path in sys.FileSystem.readDirectory(cwd + src) ) {
		
			if( from != null ) {
				if( !fromFound )
					if( path != from )
						continue;
					else 
						fromFound = true;
			}
		
			var content = sys.io.File.getContent(cwd + src + "/" + path);
			
			trace("\n\n[[[[[[[[[ Test: " + path + " ]]]]]]]]]]\n");
			
			sm = new hsm.Scxml();
			sm.init( content, function() sm.start() );
		}
		
	}
	
}
