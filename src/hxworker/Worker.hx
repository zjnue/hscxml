package hxworker;

#if neko
import neko.vm.Thread;
#elseif cpp
import cpp.vm.Thread;
#elseif java
import java.vm.Thread;
#end

class Worker {
	
	#if flash
	public static inline var TO_SUB = "toSub";
	public static inline var FROM_SUB = "fromSub";
	#end
	
	public var type : String;
	
	#if js
	var inst : js.html.Worker;
	#elseif flash
	var inst : flash.system.Worker;
	var channelIn : flash.system.MessageChannel;
	var channelOut : flash.system.MessageChannel;
	#else
	public var inst : Dynamic;
	var running : Bool = true;
	#end
	
	var onData : Dynamic -> Void;
	var onError : String -> Void;
	
	public function new( input : Dynamic, onData : Dynamic -> Void, onError : String -> Void, ?type : String ) {
		this.onData = onData;
		this.onError = onError;
		this.type = type;
		#if js
		inst = new js.html.Worker( input );
		inst.addEventListener( "message", function(e) { onData( e.data ); } );
		inst.addEventListener( "error", function(e) { onError( e.message ); } );
		#elseif flash
		inst = flash.system.WorkerDomain.current.createWorker( input );
		channelOut = flash.system.Worker.current.createMessageChannel( inst );
		channelIn = inst.createMessageChannel( flash.system.Worker.current );
		inst.setSharedProperty( TO_SUB, channelOut );
		inst.setSharedProperty( FROM_SUB, channelIn );
		channelIn.addEventListener( flash.events.Event.CHANNEL_MESSAGE, function(e) {
			while( channelIn.messageAvailable )
				onData( channelIn.receive() );
		});
		inst.start();
		#else
		//
		#end
	}
	
	// data received here is passed from main (parent) to this worker
	public function call( cmd : String, ?args : Array<Dynamic> ) : Void {
		if( args == null ) args = [];
		#if js
		inst.postMessage( compress(cmd, args) );
		#elseif flash
		channelOut.send( compress(cmd, args) );
		#else
		//
		#end
	}
	
	public function terminate() {
		#if (js || flash)
		inst.terminate();
		#end
	}
	
	public static inline function compress( cmd : String, args : Array<Dynamic> ) {
		#if (js || flash)
		return haxe.Serializer.run( {cmd:cmd, args:args} );
		#else
		return {cmd:cmd, args:args};
		#end
	}
	
	public static inline function uncompress( data : Dynamic ) : { cmd : String, args : Array<Dynamic> } {
		#if (js || flash)
		return haxe.Unserializer.run( data );
		#else
		return data;
		#end
	}
	
}
