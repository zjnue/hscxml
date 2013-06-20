import hsm.scxml.Types;
import hsm.scxml.Interp;

class Run {

	static var args : Array<String>;
	
	public static function main() {
		if( args == null ) {
			args = Sys.args();
			if( args.length < 1 ) {
				var params = haxe.web.Request.getParams();
				if( params.keys().hasNext() ) {
					var parts = [];
					if( params.exists("type") )
						parts.push( params.get("type") );
					if( params.exists("first") )
						parts.push( params.get("first") );
					if( params.exists("count") )
						parts.push( params.get("count") );
					if( parts.length > 0 )
						args = parts;
				} else
					throw "Not enough arguments specified. Usage:\nneko run.n [ecma|xpath|hscript]\n";
			}
			
			init();
		}
	}
	
	static var data : Array<{key:String, value:Dynamic}>;
	static var evt : Event;
	static var isFirstRequest : Bool = true;
	
	static function checkPost() {
		evt = null;
		if( isFirstRequest ) {
			isFirstRequest = false;
		} else {
			var params = haxe.web.Request.getParams();
			if( params.keys().hasNext() ) {
				var name = null;
				var contentVal = null;
				var data = [];
				for( key in params.keys() ) {
					if( key == "_scxmleventname" ) {
						name = params.get(key);
						data.push({key:key, value:params.get(key)});
					} else if( key == "__data__" ) {
						contentVal = params.get(key);
						break;
					} else {
						log("params.get(key) = " + params.get(key));
						data.push({key:key, value:haxe.Unserializer.run(params.get(key))});
					}
				}
				if( name == null )
					name = "HTTP.POST";
				if( params.exists("httpResponse") && params.get("httpResponse") == "true" )
					name = "HTTP.2.00";
				data.push({key:"hmm", value:"POST"}); // FIXME check
				
				evt = new Event( name );
				if( contentVal == null )
					Interp.setEventData( evt.data, data );
				else
					evt.data = contentVal;
			}
		}
		
		if( sm == null )
			doNext();
		else if( sm != null && evt != null ) {
			sm.postEvent( evt );
		}
		
		neko.Web.cacheModule(checkPost);
	}
	
	static function log( msg : String ) {
		Sys.stdout().writeString( msg + "\n" );
	}
	
	static var cwd : String = null;
	static var src = "";
	
	static var failsJs : Array<String>;
	static var failsBasicHttpProc : Array<String>;
	static var failsXPath : Array<String>;
	static var failsTodo : Array<String>;
	static var failsAll : Array<String>;
	
	static var from : String = null;
	static var fromFound : Bool = false;
	static var count : Int = -1;
	static var unexpectedResults : Array<String>;
	static var paths : Array<String>;
	
	static var sm : hsm.Scxml = null;
	static var done : Bool = false;
	static var path : String;
	
	static function init() {
	
		cwd = Sys.getCwd();
		
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
			throw "Unknown target " + Std.string(args[1]) +". Usage:\nneko run.n [ecma|xpath|hscript]\n";
		}
		
		failsJs = [
			"test330.scxml", // "JavaScript 'in' operator not supported yet."
			"test452.scxml", // "JavaScript object function 'new testobject();' not supported yet."
		];
		
		// "Basic HTTP Processor now supported via dev server."
		#if web
		failsBasicHttpProc = [];
		#else
		failsBasicHttpProc = [
			"test201.scxml",
			"test509.scxml",
			"test510.scxml",
			"test513.scxml",
			"test518.scxml",
			"test519.scxml",
			"test520.scxml",
			"test522.scxml",
			"test531.scxml",
			"test532.scxml",
			"test534.scxml",
			"test567.scxml",
		];
		#end
		
		// "XPath Data Model not yet implemented."
		failsXPath = [
			"test463.scxml",
			"test464.scxml",
			"test465.scxml",
			"test466.scxml",
			"test468.scxml",
			"test469.scxml",
			"test470.scxml",
			"test473.scxml",
			"test474.scxml",
			"test475.scxml",
			"test476.scxml",
			"test477.scxml",
			"test478.scxml",
			"test479.scxml",
			"test480.scxml",
			"test481.scxml",
			"test482.scxml",
			"test483.scxml",
			"test537.scxml",
			"test542.scxml",
			"test543.scxml",
			"test544.scxml",
			"test546.scxml",
			"test547.scxml",
			"test555.scxml",
			"test568.scxml",
		];
		
		failsTodo = [
			//"test250.scxml",
			//"test501.scxml",
			//"test530.scxml",
			//"test569.scxml",
			//"test557.scxml",
			//"test561.scxml",
			//"test558.scxml",
			//"test578.scxml",
		];
		
		failsAll = failsJs.concat(failsBasicHttpProc).concat(failsXPath).concat(failsTodo);
		
		// provides tmp jump option
		from = args.length > 1 ? args[1] : null;
		fromFound = false;
		count = args.length > 2 ? Std.parseInt(args[2])  : -1;
		
		sm = null;
		unexpectedResults = [];
		paths = sys.FileSystem.readDirectory(cwd + src);
		
		#if web
		checkPost();
		#else
		doNext();
		#end
	}
	
	static function doNext() {
		
		if( paths.length == 0 ) {
			finish();
			return;
		}
		
		path = paths.shift();
		
		if( from != null ) {
			if( !fromFound )
				if( path != from ) {
					doNext();
					return;
				} else 
					fromFound = true;
		}
		
		log("\n## " + path + " ##");
		
		done = false;
		var stamp = haxe.Timer.stamp();
		
		try {
			sm = new hsm.Scxml( cwd + src + "/" + path );
			sm.log = smLog;
			sm.parentEventHandler = parentEventHandler;
			sm.init( null, function() {
				if( evt != null ) {
					sm.postEvent( evt );
				}
				sm.start();
			});
		} catch( e : Dynamic ) {
			log("\nERROR " + Std.string(e) + "\n");
		}
		
		#if (!web)
		while( !done && ((haxe.Timer.stamp() - stamp) < 32) )
			Sys.sleep(0.1);
		
		if( count != -1)
			if( --count == 0 ) {
				finish();
				return;
			}
		
		doNext();
		#end
	}
	
	static function move() {
		evt = null;
		if( count != -1)
			if( --count == 0 ) {
				finish();
				return;
			}
		
		doNext();
	}
	
	static function parentEventHandler( evt : Event) {
		if( evt.name.indexOf("done.invoke") != -1 ) {
			#if web
			move();
			#else
			done = true;
			#end
		}
	}
	
	static function smLog( msg : String ) {
		if( msg.indexOf("Outcome:") >= 0 ) {
			var success = ( msg.indexOf("fail") == -1 );
			var expectFail = Lambda.has(failsAll, path);
			if( success ) {
				if( expectFail ) {
					msg = ">>>>>>>>>>>> UNEXPECTED RESULT : Expected FAIL, Got PASS";
					unexpectedResults.push( path + " :: " + msg );
				} else
					msg = "PASS";
			} else {
				if( expectFail )
					msg = "FAIL";
				else {
					msg = ">>>>>>>>>>>> UNEXPECTED RESULT : Expected PASS, Got FAIL";
					unexpectedResults.push( path + " :: " + msg );
				}
			}
		}
		log(msg);
	}
	
	static function finish() {
		log("\n------------------------------------------------------");
		log("UNEXPECTED RESULTS: " + unexpectedResults.length);
		for( result in unexpectedResults )
			log(result);
		log("------------------------------------------------------");
		#if web
		Sys.exit(0);
		#end
	}
}
