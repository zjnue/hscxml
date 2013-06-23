package js;

@:native("Worker")
extern class Worker {
   public function new( script : String ) : Void;
   public function postMessage( msg : Dynamic ) : Void;
   public function addEventListener( type : Dynamic , cb : Dynamic -> Void ) : Void;
}