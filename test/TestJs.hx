import hsm.scxml.Types;

@:expose
class TestJs {
	
	static var s : hsm.Scxml;
	
	public static function main() {
		
		haxe.Log.trace = function(msg:String, ?pos:haxe.PosInfos) {
			msg = StringTools.htmlEscape(msg).split("\n").join("<br/>").split("\t").join("&nbsp;&nbsp;&nbsp;&nbsp;");
			js.Browser.document.getElementById("haxe:trace").innerHTML += msg + "<br/>";
		}
		
		var scxmlStr = haxe.Resource.getString("scxmlStr");
		trace(scxmlStr);
		
		s = new hsm.Scxml(null, scxmlStr);
		s.log = function(msg) trace(msg);
		s.init(null, function() {
			s.start();
		});
		
	}
	
	public static function sendEvent( event : js.html.MouseEvent ) {
		trace("\nTestJs sendEvent called..");
		
		var scxmlEvent = new hsm.scxml.Event( event.type );
		scxmlEvent.data = event.detail;
		
		s.postEvent( scxmlEvent );
	}
}