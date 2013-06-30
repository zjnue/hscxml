package hxworker;

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
	var channelIn : flash.system.MessageChannel;
	var channelOut : flash.system.MessageChannel;
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
		
		feedMainThread = Thread.create( feedMain );
		feedMainThread.sendMessage( Thread.current() );
		feedMainThread.sendMessage( onData );
		
		sendErrorToMainThread = Thread.create( sendErrorToMain );
		sendErrorToMainThread.sendMessage( Thread.current() );
		sendErrorToMainThread.sendMessage( onError );
		
		thread = Thread.create( createInst );
		thread.sendMessage( Thread.current() );
		thread.sendMessage( input );
		thread.sendMessage( this );
		thread.sendMessage( sendErrorToMainThread );
		#end
	}
	
	#if !(js || flash)
	
	public inline function toMain( msg : Dynamic ) {
		feedMainThread.sendMessage( msg );
	}
	
	public inline function toInst( msg : Dynamic ) {
		thread.sendMessage( msg );
	}
	
	var thread : Thread;
	function createInst() {
		var main = Thread.readMessage( true );
		var clazz = Thread.readMessage( true );
		var worker = Thread.readMessage( true );
		var errorThread = Thread.readMessage( true );
		var inst = Type.createInstance( clazz, [] );
		inst.worker = worker;
		
		while( true ) {
			try {
				var msg = Thread.readMessage( true );
				inst.onMessage( msg );
			} catch( e:Dynamic ) {
				errorThread.sendMessage( "ERROR: " + e );
			}
		}
	}
	
	var sendErrorToMainThread : Thread;
	function sendErrorToMain() {
		var main = Thread.readMessage( true );
		var onError = Thread.readMessage( true );
		while( true ) {
			var msg = Thread.readMessage( true );
			onError( msg );
		}
	}
	
	var feedMainThread : Thread;
	function feedMain() {
		var main = Thread.readMessage( true );
		var onData = Thread.readMessage( true );
		while( true ) {
			var msg = Thread.readMessage( true );
			onData( msg );
		}
	}
	#end
	
	// data received here is passed from main (parent) to this worker
	public function call( cmd : String, ?args : Array<Dynamic> ) : Void {
		if( args == null ) args = [];
		#if js
		inst.postMessage( compress(cmd, args) );
		#elseif flash
		channelOut.send( compress(cmd, args) );
		#else
		toInst( compress(cmd, args) );
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
