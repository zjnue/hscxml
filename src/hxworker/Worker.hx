package hxworker;

#if flash
import flash.system.WorkerDomain;
import flash.system.MessageChannel;
#end

#if neko
import neko.vm.Thread;
#elseif cpp
import cpp.vm.Thread;
#end

class Worker {
	
	#if flash
	public static inline var TO_SUB = "toSub";
	public static inline var FROM_SUB = "fromSub";
	#end
	
	#if js
	public var inst : js.Worker;
	#elseif flash
	public var inst : flash.system.Worker;
	var channelIn : MessageChannel;
	var channelOut : MessageChannel;
	#else
	public var inst : Dynamic;
	var thread : Thread;
	#end
	
	public var type : String;
	public var onData : Dynamic -> Void;
	public var onError : String -> Void;
	
	public function new( input : Dynamic, onData : Dynamic -> Void, onError : String -> Void ) {
		this.onData = onData;
		this.onError = onError;
		#if js
		inst = new js.Worker( input );
		inst.addEventListener( "message", function(e) { onData( e.data ); } );
		inst.addEventListener( "error", function(e) { onError( e.message ); } );
		#elseif flash
		inst = WorkerDomain.current.createWorker( input );
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
