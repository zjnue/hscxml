class TestSwf {
	
	public static function main() {
		
		var scxmlStr = haxe.Resource.getString("scxmlStr");
		trace(scxmlStr);
		
		var s = new hsm.Scxml(null, scxmlStr);
		s.log = function(msg) trace(msg);
		s.init(null, function() {
			s.start();
		});
		
	}
}