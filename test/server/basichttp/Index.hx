import hsm.scxml.Types;

class Index {

	public static function main() {
		checkPost();
	}
	
	static var data : Array<{key:String, value:Dynamic}>;
	static var evt : Event;
	
	static function checkPost() {
	
		evt = null;
		var dec = function(data) return data;
		
		var params = haxe.web.Request.getParams();
		if( params.keys().hasNext() ) {
			var name = null;
			var contentVal = null;
			var data = [];
			for( key in params.keys() ) {
				if( key == "_scxmleventname" ) {
					name = dec(params.get(key));
					data.push({key:key, value:dec(params.get(key))});
				} else if( key == "__data__" ) {
					contentVal = dec(params.get(key));
					break;
				} else {
					data.push({key:key, value:dec(params.get(key))});
				}
			}
			if( name == null )
				name = "HTTP.POST";
			if( params.exists("httpResponse") && dec(params.get("httpResponse")) == "true" )
				name = "HTTP.2.00";
			#if neko
			data.push({key:"method", value:neko.Web.getMethod()});
			#end
			evt = new Event( name );
			if( contentVal == null )
				copyFrom( evt.data, data );
			else
				evt.data = contentVal;
		}
		
		if( evt != null ) {
			var pong = haxe.Serializer.run(evt.toObj());
			neko.Lib.println(pong);
		}
		
		neko.Web.cacheModule(checkPost);
	}
	
	public static function copyFrom( evtData : {}, fromData : Array<{key:String, value:Dynamic}>, copy : Bool = false ) {
		var data = copy ? fromData.copy() : fromData;
		for( item in data ) {
			if( Reflect.hasField(evtData, item.key) ) {
				var val = Reflect.field(evtData, item.key);
				if( Std.is(val, Array) ) {
					val.push(item.value);
				} else {
					Reflect.setField(evtData, item.key, [val, item.value]);
				}
			} else
				Reflect.setField(evtData, item.key, item.value);
		}
		return evtData;
	}
	
	static function log( msg : String ) {
		Sys.stdout().writeString( msg + "\n" );
	}
}
