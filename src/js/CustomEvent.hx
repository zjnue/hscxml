package js;

@:native("CustomEvent")
extern class CustomEvent {
	public function new( type : String, initObj : {} ) : Void;
}