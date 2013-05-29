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
	// see 5.10.1 The Internal Structure of Events
	public var name : String;
	public var type : String;
	public var sendid : String;
	public var origin : String;
	public var origintype : String;
	public var invokeid : String;
	public var data : Dynamic;
	// ?
	public var raw : String;
	
	public function new( name : String, ?data : Dynamic ) {
		this.name = name;
		this.data = {};
		this.type = "platform";
		this.raw = "";
		if( data != null )
			for( key in Reflect.fields(data) )
				Reflect.setField(this.data, key, Reflect.field(data, key));
	}
	public function toString() {
		var out = "[Event: " + name;
		for( field in Reflect.fields(data) )
			out += "\n\t" + field + " = " + Std.string(Reflect.field(data, field));
		if( out != "[Event: " + name )
			out += "\n";
		return out + "]";
	}
}

class Set<T> {
	public var l : List<T>;
	public function new( ?s : Set<T> ) { l = s != null ? s.toList().clone() : new List<T>(); }
	public inline function add( i : T ) { if( !Lambda.has(l, i) ) l.add( i ); }
	public inline function delete( i : T ) { return l.remove( i ); }
	public inline function union( s : Set<T> ) { for( i in s ) add(i); }
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
		for ( item in l ) out += Std.string(item) + "\n";
		return out;
	}
}

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
	
	function sortEventData( e0 : TTimerData, e1 : TTimerData ) {
		return Std.int((e0.time - e1.time) * 1000);
	}
	
	public function addTimer( delaySec : Float, cb : Void -> Void ) {
		mutex.acquire();
		queue.push( { time : Timer.stamp() + delaySec, func : cb } );
		queue.sort(sortEventData);
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
			while( queue.length > 0 ) {
				if( queue[0].time <= now )
					ready.push(queue.shift());
				else {
					wake = queue[0].time;
					break;
				}
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
