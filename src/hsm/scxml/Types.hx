package hsm.scxml;

using hsm.scxml.tools.ListTools;

#if neko
import neko.vm.Deque;
import neko.vm.Thread;
import neko.vm.Mutex;
import neko.vm.Lock;
#elseif cpp
import cpp.vm.Deque;
import cpp.vm.Thread;
import cpp.vm.Mutex;
import cpp.vm.Lock;
#end

import haxe.Timer;

#if haxe3
private typedef Hash<T> = haxe.ds.StringMap<T>;
#end

class Event {
	public static inline var ERROR_COMMS = "error.communication";
	public static inline var ERROR_EXEC = "error.execution";
	public var name : String;
	public var type : String;
	public var sendid : String;
	public var origin : String;
	public var origintype : String;
	public var invokeid : String;
	public var data : Dynamic;
	public var raw : RawEvent;
	public function new( name : String, data : Dynamic = null, sendid : String = null, type : String = "platform" ) {
		this.name = name;
		this.data = data == null ? {} : data;
		this.sendid = sendid;
		this.type = type;
		this.raw = new RawEvent(this);
	}
	public function toString( sep : String = " = " ) {
		return getString(sep);
	}
	public function getString( sep : String = " = " ) {
		var out = "[Event: " + name + " data: ";
		if( Std.is(data, {}) || Std.is(data, Dynamic) )
			for( field in Reflect.fields(data) )
				out += "\n\t" + field + sep + Std.string(Reflect.field(data, field));
		else
			out += "\n\t" + Std.string(data);
		return out + "\n]";
	}
}

class RawEvent {
	var event : Event;
	public function new( event : Event ) { this.event = event; }
	public inline function search( str : String ) { return toString().indexOf(str); }
	public function toString() { return event.getString("="); }
	function hxSerialize( s : haxe.Serializer ) {} // TODO fix raw serialization
	function hxUnserialize( s : haxe.Unserializer ) {}
}

class Set<T> {
	public var l : List<T>;
	public function new( ?s : Set<T> ) { l = s != null ? s.toList().clone() : new List<T>(); }
	public inline function add( i : T ) { if( !Lambda.has(l, i) ) l.add( i ); }
	public inline function delete( i : T ) { return l.remove( i ); }
	public inline function union( s : Set<T> ) { for( i in s ) add(i); }
	public inline function some( f : T -> Bool ) { return l.some(f); }
	public inline function every( f : T -> Bool ) { return l.every(f); }
	public inline function isMember( i : T ) { return Lambda.has(l, i); }
	public function hasIntersection( s : Set<T> ) {
		for( i in s )
			if( Lambda.has(l, i) )
				return true;
		return false;
	}
	public inline function isEmpty() { return l.isEmpty(); }
	public inline function clear() { return l = new List<T>(); }
	public inline function toList() { return l; }
	public inline function iterator() { return l.iterator(); }
	public inline static function ofList<T>( l : List<T> ) : Set<T> {
		var s = new Set<T>();
		s.l = l;
		return s;
	}
}

class Queue<T> {
	var l : List<T>;
	public function new() { l = new List<T>(); }
	public inline function enqueue( i : T ) { l.add( i ); }
	public inline function dequeue() { return l.pop(); }
	public inline function isEmpty() { return l.isEmpty(); }
	public function toString() {
		var out = "";
		for( item in l ) out += Std.string(item) + "\n";
		return out;
	}
}

#if (js || flash)
class BlockingQueue<T> {
	var l : List<T>;
	public function new( ?onNew : Void -> Void ) { l = new List<T>(); onNewContent = onNew; callOnNewContent = false; }
	public var callOnNewContent : Bool;
	public var onNewContent : Void -> Void;
	public inline function enqueue( i : T ) {
		l.add( i );
		if( callOnNewContent ) {
			callOnNewContent = false;
			onNewContent();
		}
	}
	public function dequeue() {
		return l.pop();
	}
}
#else
class BlockingQueue<T> {
	var dq : Deque<T>;
	public function new() { dq = new Deque<T>(); }
	public inline function enqueue( i : T ) { dq.add( i ); }
	public inline function dequeue() { return dq.pop(true); }
}

typedef TTimerData = {
	time : Float,
	func : Void->Void	
}

class TimerThread {
	var mutex : Mutex;
	var queueLock : Lock;
	var queue : Array<TTimerData>;
	var running : Bool;
	public function new() {
		queue = [];
		queueLock = new Lock();
		mutex = new Mutex();
		running = true;
		Thread.create( mainLoop );
	}
	public function addTimer( delaySec : Float, cb : Void -> Void ) {
		mutex.acquire();
		var time = Timer.stamp() + delaySec;
		var index = 0;
		while( index < queue.length && time >= queue[index].time )
			index++;
		queue.insert(index, { time : time, func : cb });
		mutex.release();
		queueLock.release();
	}
	public function quit( ?cb : Void -> Void ) {
		var me = this;
		addTimer( 0, function() {
			me.running = false;
			if( cb != null )  
				cb();
		} );
	}
	function mainLoop() {
		while( running ) {
			var wake : Null<Float> = null;
			var now = Timer.stamp();
			var ready = new Array<TTimerData>();
			mutex.acquire();
			while( queue.length > 0 )
				if( queue[0].time <= now )
					ready.push(queue.shift());
				else {
					wake = queue[0].time;
					break;
				}
			mutex.release();
			for( d in ready ) {
				d.func();
				if( !running )
					break;
			}
			if( !running )
				break;
			if( wake == null )
				queueLock.wait();
			else {
				var delay = wake - Timer.stamp();
				if( delay > 0 )
					queueLock.wait(delay);
			}
		}
	}
}
#end
