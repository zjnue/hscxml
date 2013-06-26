package hsm.scxml.tools;

import hsm.scxml.Model;
import hsm.scxml.Node;
import hsm.scxml.Types;

class DataTools {
	
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
	
	public static function setSubInstData( xml : Xml, data : Array<{key:String,value:Dynamic}> ) {
		var models = xml.elementsNamed("datamodel");
		if( models.hasNext() )
			for( dataNode in models.next().elementsNamed("data") ) {
				var nodeId = dataNode.get("id");
				for( d in data )
					if( d.key == nodeId ) {
						dataNode.set("expr", Std.string(d.value));
						break;
					}
			}
		return xml;
	}
	
	public static inline function trim( str : String ) {
		var r = ~/[ \n\r\t]+/g;
		return StringTools.trim(r.replace(str, " "));
	}
	
	public static inline function stripEndSlash( str : String ) {
		return (str.substr(-1) == "/") ? str.substr(0,str.length-1) : str;
	}
	
	public static inline function getDuration( delay : String ) {
		return ( delay == null || delay == "" ) ? 0 : Std.parseFloat(delay.split("s").join(""));
	}
}
