import sys.FileSystem;
import sys.io.File;

class Copy {

	static var testsOnly : Bool = true;

	public static function main() {
		moveTests();
	}
	
	public static function moveTests() {
		
		var cwd = Sys.getCwd();
		
		var src = cwd + "w3c";
		var destTest = cwd + "txml";
		var destXsl = cwd + "xsl";
		
		copy( src, destTest, ["txml", "txt"] );
		copy( src, destXsl, ["xsl"] );
		
	}
	
	public static function copy( path : String, dest : String, exts : Array<String> ) {
		for( name in FileSystem.readDirectory(path) ) {
			var newPath = path + "/" + name;
			if( FileSystem.isDirectory( newPath ) ) {
				copy( newPath, dest, exts );
			} else {
				var ext = name.split(".").pop();
				if( Lambda.has(exts, ext) ) {
					File.copy( newPath, dest + "/" + name );
				}
			}
		}
	}

}