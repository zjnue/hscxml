class TestJs {
	
	public static function main() {
		
		haxe.Log.trace = function(msg:String, ?pos:haxe.PosInfos) {
			msg = StringTools.htmlEscape(msg).split("\n").join("<br/>").split("\t").join("&nbsp;&nbsp;&nbsp;&nbsp;");
			js.Browser.document.getElementById("haxe:trace").innerHTML += msg + "<br/>";
		}
		
		var scxmlStr = haxe.Resource.getString("scxmlStr");
		trace(scxmlStr);
		
		var s = new hsm.Scxml(null, scxmlStr);
		s.log = function(msg) trace(msg);
		s.init(null, function() {
			s.start();
		});
		
	}
}