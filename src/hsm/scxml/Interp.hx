package hsm.scxml;

import hsm.scxml.Types;
import hsm.scxml.Node;
import hsm.scxml.Compiler;
import hsm.scxml.Model;
import hsm.scxml.tools.NodeTools;

using hsm.scxml.tools.ArrayTools;
using hsm.scxml.tools.ListTools;
using hsm.scxml.tools.NodeTools;

#if neko
import neko.vm.Thread;
import neko.vm.Mutex;
#elseif cpp
import cpp.vm.Thread;
import cpp.vm.Mutex;
#end

#if haxe3
private typedef Hash<T> = haxe.ds.StringMap<T>;
#end

class Interp {
	
	var d : Node;
	
	public function new() {
		log = function(msg:String) trace(msg);
	}
	
	// invoke related
	public var parentEventHandler : Event -> Void;
	public var invokeId : String;
	
	public var onInit : Void -> Void;
	public var log : String -> Void;
	public var topNode( get_topNode, never ) : Node;
	
	function get_topNode() { return d; }
	
	public function postEvent( evt : Event ) {
		externalQueue.enqueue( evt );
	}
	
	var invokedDataMutex:Mutex;
	var timerThread : TimerThread;
	var mainThread : Thread;
	
	public function start() {
		
		mainThread = Thread.create(mainEventLoop);
		mainThread.sendMessage(Thread.current());
		Thread.readMessage(true);
		
		// TODO check if timer needs to stop earlier
		timerThread.quit();
	}
	
	public function stop() {
		running = false;
	}
	
	var configuration : Set<Node>;
	var statesToInvoke : Set<Node>;
	var datamodel : Model;
	var internalQueue : Queue<Event>;
	var externalQueue : BlockingQueue<Event>;
	var historyValue : Hash<List<Node>>;
	var running : Bool;
	var binding : String;
	
	function entryOrder( s0 : Node, s1 : Node ) {
		return documentOrder(s0, s1);
	}
	
	function exitOrder( s0 : Node, s1 : Node ) {
		return documentOrder(s1, s0);
	}
	
	inline function documentOrder( s0 : Node, s1 : Node ) {
		return s0.pos - s1.pos;
	}
	
	public function interpret(doc:Xml) {
		
		if( !valid(doc) ) failWithError();
		expandScxmlSource(doc);
		
		var compiler = new Compiler();
		var result = compiler.compile(doc, null);
		d = result.node;
		
		//log("d = \n" + d.toString());
		
		configuration = new Set();
		statesToInvoke = new Set();
		internalQueue = new Queue();
		externalQueue = new BlockingQueue();
		historyValue = new Hash();
		
		extraInit();
		
		var model = "hscript";//d.exists("datamodel") ? d.get("datamodel") : "hscript";
		switch( model ) {
			case "null":
				datamodel = new NullModel(d);
			case "ecmascript":
				datamodel = new EcmaScriptModel(d);
			case "xpath":
				datamodel = new XPathModel(d);
			case "hscript":
				datamodel = new HScriptModel(d);
			default:
		}
		datamodel.log = log;
		datamodel.isInState = function(id:String) {
			for( state in configuration )
				if( id == state.get("id") )
					return true;
			return false;
		};
		
		binding = d.exists("binding") ? d.get("binding") : "early";
		initializeDatamodel( datamodel, result.data, (binding != "early") );
		
		timerThread = new TimerThread();
		running = true;
		executeGlobalScriptElements(d);
		
		enterStates( [d.initial().next().transition().next()].toList() );
		if( onInit != null )
			onInit();
	}
	
	function extraInit() {
		cancelledSendIds = new Hash();
		invokedData = new Hash();
		invokedDataMutex = new Mutex();
	}
	
	function valid( doc : Xml ) {
		// FIXME
		return true;
	}
	
	inline function failWithError() {
		// FIXME
		throw "failWithError";
	}
	
	static var genStateId : Int = 0;
	
	function expandScxmlSource( x : Xml ) {
		if( x.nodeType != Xml.Element )
			return;
		if( Lambda.has(["state", "parallel", "final"], x.nodeName) && !x.exists("id") )
			x.set("id", "__gen_id__"+genStateId++);
		var hasInitial = false;
		for( el in x.elements() ) {
			if( el.nodeName == "initial" )
				hasInitial = true;
			expandScxmlSource(el);
		}
		if( x.exists("initial") || (!x.exists("initial") && Lambda.has(["scxml", "state"], x.nodeName) && !hasInitial) ) {
			var ins = Xml.createElement("initial");
			var trans = Xml.createElement("transition");
			var tval = x.exists("initial") ? x.get("initial") : null;
			if( tval == null ) {
				for( el in x.elements() )
					if( Lambda.has(["state", "parallel", "final"], el.nodeName) ) {
						tval = el.get("id");
						break;
					}
			}
			if( tval == null )
				return;
			trans.set("target", tval);
			ins.insertChild(trans, 0);
			x.insertChild(ins, 0);
			x.remove("initial");
		}
	}
	
	function executeGlobalScriptElements( doc : Node ) {
		var globalScripts = doc.script();
		for( script in globalScripts )
			executeContent(script);
	}
	
	function initializeDatamodel( datamodel : Model, dms : Iterable<DataModel>, setValsToNull : Bool = false ) {
		if( !(datamodel.supportsVal && datamodel.supportsProps) )
			return;
		for( dm in dms )
			for( d in dm ) {
				var id = d.get("id");
				if( setValsToNull )
					datamodel.set(id, null);
				else if( d.exists("src") )
					setFromSrc(id, d.get("src"));
				else {
					var val = "";
					if( d.exists("expr") )
						val = d.get("expr");
					else
						val = getTypedDataStr( cast(d, Data).content );
					try {
						datamodel.set(id, datamodel.doVal(val));
					} catch( e:Dynamic ) {
						datamodel.set(id, null);
						raise( new Event("error.execution") );
					}
				}
			}
	}
	
	function mainEventLoop() {
		var main = Thread.readMessage(true);
		while( running ) {
			var enabledTransitions : Set<Node> = null;
			var macrostepDone = false;
			while( running && !macrostepDone ) {
				enabledTransitions = selectEventlessTransitions();
				if( enabledTransitions.isEmpty() ) {
					if( internalQueue.isEmpty() )
						macrostepDone = true;
					else {
						var internalEvent = internalQueue.dequeue();
						setEvent(internalEvent);
						enabledTransitions = selectTransitions(internalEvent);
					}
				}
				if( !enabledTransitions.isEmpty() )
					microstep(enabledTransitions.toList());
			}
			if( !running )
				break;
			for( state in statesToInvoke )
				for( inv in state.invoke() )
					invoke(inv);
			statesToInvoke.clear();
			if( !internalQueue.isEmpty() )
				continue;
			var externalEvent = externalQueue.dequeue();
			if( isCancelEvent(externalEvent) ) {
				running = false;
				continue;
			}
			setEvent(externalEvent);
			for( state in configuration )
				for( inv in state.invoke() ) {
					if( inv.get("invokeid") == externalEvent.invokeid )
						applyFinalize(inv, externalEvent);
					if( inv.exists("autoforward") && inv.get("autoforward") == "true" )
						send(inv.get("id"), externalEvent);
				}
			enabledTransitions = selectTransitions(externalEvent);
			if( !enabledTransitions.isEmpty() )
				microstep(enabledTransitions.toList());
		}
		//log("mainEventLoop: exitInterpreter");
		exitInterpreter();
		main.sendMessage("done");
	}
	
	function isCancelEvent( evt : Event ) {
		return (evt.sendid != null && cancelledSendIds.exists(evt.sendid));
	}
	
	function exitInterpreter() {
		var statesToExit = configuration.toList().sort(exitOrder);
		for( s in statesToExit ) {
			for( onexit in s.onexit() )
				executeBlock(onexit);
			for( inv in s.invoke() )
				cancelInvoke(inv);
			configuration.delete(s);
			if( s.isTFinal() && s.parent.isTScxml() )
				returnDoneEvent( getDoneData(s) );
		}
	}
	
	function selectEventlessTransitions() {
		var enabledTransitions = new Set<Node>();
		var atomicStates = configuration.toList().filter(NodeTools.isAtomic).sort(documentOrder);
		for( state in atomicStates )
			for( s in [state].toList().append(getProperAncestors(state, null)) ) {
				var exitLoop = false;
				for( t in s.transition() ) {
					if( !t.exists("event") && conditionMatch(t) ) {
						enabledTransitions.add(t);
						exitLoop = true;
						break;
					}
				}
				if( exitLoop )
					break;
			}
		enabledTransitions = removeConflictingTransitions(enabledTransitions);
		return enabledTransitions;
	}
	
	function selectTransitions( event : Event ) {
		var enabledTransitions = new Set<Node>();
		var atomicStates = configuration.toList().filter(NodeTools.isAtomic).sort(documentOrder);
		for( state in atomicStates )
			for( s in [state].toList().append(getProperAncestors(state, null)) ) {
				var exitLoop = false;
				for( t in s.transition() )
					if( t.exists("event") && nameMatch(t.get("event"), event.name) && conditionMatch(t) ) {
						enabledTransitions.add(t);
						exitLoop = true;
						break;
					}
				if( exitLoop )
					break;
			}
		enabledTransitions = removeConflictingTransitions(enabledTransitions);
		return enabledTransitions;
	}
	
	function removeConflictingTransitions( enabledTransitions : Set<Node> ) {
		var filteredTransitions = new Set<Node>();
		for( t1 in enabledTransitions.toList() ) {
			var t1Preempted = false;
			var transitionsToRemove = new Set<Node>();
			for( t2 in filteredTransitions.toList() )
				if( computeExitSet([t1].toList()).hasIntersection(computeExitSet([t2].toList())) )
					if( getSourceState(t1).isDescendant(getSourceState(t2)) )
						transitionsToRemove.add(t2);
					else {
						t1Preempted = true;
						break;
					}
			if( !t1Preempted ) {
				for( t3 in transitionsToRemove.toList() )
					filteredTransitions.delete(t3);
				filteredTransitions.add(t1);
			}
		}
		return filteredTransitions;
	}
	
	function microstep( enabledTransitions : List<Node> ) {
		exitStates(enabledTransitions);
		executeTransitionContent(enabledTransitions);
		enterStates(enabledTransitions);
	}
	
	function exitStates( enabledTransitions : List<Node> ) {
		var statesToExit = computeExitSet(enabledTransitions);
		for( s in statesToExit )
			statesToInvoke.delete(s);
		statesToExit.l = statesToExit.toList().sort(exitOrder);
		for( s in statesToExit )
			for( h in s.history() ) {
				var f = h.get("type") == "deep" ?
					function(s0:Node) return s0.isAtomic() && s0.isDescendant(s) :
					function(s0:Node) return s0.parent == s;
				historyValue.set( h.get("id"), configuration.toList().filter(f) );
			}
		for( s in statesToExit ) {
			for( onexit in s.onexit() )
				executeBlock(onexit);
			for( inv in s.invoke() )
				cancelInvoke(inv);
			configuration.delete(s);
		}
	}
	
	function getSourceState( transition : Node ) {
		var source = transition.parent;
		while( !source.isState() && source.parent != null )
			source = source.parent;
		return source;
	}
	
	function computeExitSet( transitions : List<Node> ) {
		var statesToExit = new Set<Node>();
		for( t in transitions ) {
			if( !t.exists("target") ) // ZB: added
				continue;
			var domain = getTransitionDomain(t);
			for( s in configuration )
				if( s.isDescendant(domain) )
					statesToExit.add(s);
		}
		return statesToExit;
	}
	
	function executeTransitionContent( enabledTransitions : List<Node> ) {
		for( t in enabledTransitions )
			executeBlock(t);
	}
	
	function enterStates( enabledTransitions : List<Node> ) {
		var statesToEnter = new Set<Node>();
		var statesForDefaultEntry = new Set<Node>();
		computeEntrySet( enabledTransitions, statesToEnter, statesForDefaultEntry );
		for( s in statesToEnter.toList().sort(entryOrder) ) {
			configuration.add(s);
			statesToInvoke.add(s);
			if( binding == "late" && s.isFirstEntry ) {
				var dms : Iterator<DataModel> = cast s.datamodel();
				initializeDatamodel( datamodel, {iterator:function() return dms}, false );
				s.isFirstEntry = false;
			}
			for( onentry in s.onentry() )
				executeBlock(onentry);
			if( statesForDefaultEntry.isMember(s) )
				executeBlock(s.initial().next().transition().next());
			if( s.isTFinal() ) {
				if( s.parent.isTScxml() )
					running = false;
				else {
					var parent = s.parent;
					var grandparent = parent.parent;
					internalQueue.enqueue( new Event("done.state." + parent.get("id"), getDoneData(s)) );
					if( grandparent.isTParallel() )
						if( grandparent.getChildStates().every(isInFinalState) )
							internalQueue.enqueue( new Event("done.state." + grandparent.get("id")) );
				}
			}
		}
	}
	
	function computeEntrySet( transitions : List<Node>, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node> ) {
		for( t in transitions )
			statesToEnter.union( Set.ofList(getTargetStates(t)) );
		for( s in statesToEnter )
			addDescendantStatesToEnter( s, statesToEnter, statesForDefaultEntry );
		for( t in transitions ) {
			var ancestor = getTransitionDomain(t);
			for( s in getTargetStates(t) )
				addAncestorStatesToEnter( s, ancestor, statesToEnter, statesForDefaultEntry );
		}
	}
	
	function addDescendantStatesToEnter( state : Node, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node> ) {
		if( state.isTHistory() )
			if( historyValue.exists(state.get("id")) )
				for( s in historyValue.get(state.get("id")) ) {
					addDescendantStatesToEnter( s, statesToEnter, statesForDefaultEntry );
					addAncestorStatesToEnter( s, state.parent, statesToEnter, statesForDefaultEntry );
				}
			else
				for( t in state.transition() )
					for( s in getTargetStates(t) ) {
						addDescendantStatesToEnter( s, statesToEnter, statesForDefaultEntry );
						addAncestorStatesToEnter( s, state.parent, statesToEnter, statesForDefaultEntry );
					}
		else {
			statesToEnter.add(state);
			if( state.isCompound() ) {
				statesForDefaultEntry.add(state);
				for( s in getTargetStates(state.initial().next().transition().next()) ) {
					addDescendantStatesToEnter( s, statesToEnter, statesForDefaultEntry );
					addAncestorStatesToEnter( s, state, statesToEnter, statesForDefaultEntry );
				}
			}
			else
				if( state.isTParallel() )
					for( child in state.getChildStates() )
						if( !statesToEnter.l.some(function(s) return s.isDescendant(child)) )
							addDescendantStatesToEnter( child, statesToEnter, statesForDefaultEntry );
		}
	}
	
	function addAncestorStatesToEnter( state : Node, ancestor : Node, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node> ) {
		for( anc in getProperAncestors(state,ancestor) ) {
			statesToEnter.add(anc);
			if( anc.isTParallel() )
				for( child in anc.getChildStates() )
					if( !statesToEnter.l.some(function(s) return s.isDescendant(child)) )
						addDescendantStatesToEnter( child, statesToEnter, statesForDefaultEntry );
		}
	}
	
	function isInFinalState( s : Node ) : Bool {
		var self = this;
		if( s.isCompound() )
			return s.getChildStates().some( function(s0) return s0.isTFinal() && self.configuration.isMember(s0) );
		else if( s.isTParallel() )
			return s.getChildStates().every(isInFinalState);
		else 
			return false;
	}
	
	function getTransitionDomain( transition : Node ) {
		var targetStates = getTargetStates(transition);
		var sourceState = getSourceState(transition);
		if( targetStates.isEmpty() )
			return sourceState;
		else if( transition.get("type") == "internal" && sourceState.isCompound() 
				&& targetStates.every(function(s) return s.isDescendant(sourceState)) )
			return sourceState;
		else
			return findLCCA( [sourceState].toList().append(targetStates) );
	}
	
	function findLCCA( stateList : List<Node> ) {
		for( anc in getProperAncestors(stateList.head(),null).filter(function(s) return s.isCompound() || s.isTScxml()) )
			if( stateList.tail().every(function(s) return s.isDescendant(anc)) )
				return anc;
		return null;
	}
	
	function getProperAncestors( state1 : Node, state2 : Null<Node> = null ) : List<Node> {
		var l = new List<Node>();
		if( state1.isTScxml() ) // ZB: added
			l.add(state1);
		while( state1.parent != state2 )
			l.add( state1 = state1.parent );
		return l;
	}
	
	function nameMatch( descriptors : String, event : String ) {
		for( desc in descriptors.split(" ") ) {
			if( desc == "*" || desc == event ) return true;
			if( desc.substr(-2) == ".*" )
				desc = desc.substr(0, -2);
			else if( desc.substr(-1) == "." )
				desc = desc.substr(0, -1);
			if( event.indexOf(desc) == 0 && (event.length == desc.length || event.charAt(desc.length) == ".") )
				return true;
		}
		return false;
	}
	
	function conditionMatch( transition : Node ) : Bool {
		try {
			if( transition.exists("cond") && datamodel.supportsCond )
				return datamodel.doCond( transition.get("cond") );
		} catch( e:Dynamic ) {
			raise( new Event("error.execution") );
			return false;
		}
		return true;
	}
	
	function getDefaultInitialState( s : Node ) : Node {
		var childStates = s.getChildStates();
		var initial = s.initial();
		if( initial.hasNext() ) {
			var id = initial.next().transition().next().get("target");
			return childStates.filter(function(s0) return s0.get("id") == id).iterator().next(); // optimize
		} else
			return childStates.iterator().next();
	}
	
	var invokedData : Hash<Dynamic>;
	
	function cancelInvoke( inv : Node ) {
		var id = inv.exists("id") ? inv.get("id") : null;
		if( id == null ) {
			var idlocation = inv.exists("idlocation") ? inv.get("idlocation") : null;
			if( idlocation == null ) {
				log("Warning, tried to cancel invoke with no 'id' or 'idlocation' specified.");
				return;
			}
			id = datamodel.get(idlocation);
		}
		if( hasInvokedData(id) ) {
			var data : {type:String, instance:hsm.scxml.Interp} = getInvokedData(id);
			data.instance.running = false;
			data.instance.parentEventHandler = function( evt : Event ) {};
		} else {
			log("Warning, cancel invoke data missing for id: " + id);
		}
	}
	
	// TODO check, evt does not seem necessary here
	function applyFinalize( inv : Node, evt : Event ) {
		for( f in inv.finalize() )
			executeBlock(f);
	}
	
	function send( invokeid : String, evt : Event ) {
		if( !hasInvokedData(invokeid) )
			throw "check";
			
		var invData = getInvokedData(invokeid);
		if( !isScxmlInvokeType(invData.type) )
			throw "Invoke type currently not supported: " + invData.type;
		
		var inst = cast( invData.instance, hsm.scxml.Interp );
		inst.postEvent(evt);
	}
	
	inline function isScxmlInvokeType( type : String ) {
		return (type == "http://www.w3.org/TR/scxml/" || type == "scxml");
	}
	
	function getDoneData( n : Node ) {
		var val : Dynamic = null;
		for( d in n.donedata() ) {
			if( val != null )
				break;
			var params = [];
			var content = [];
			for( child in d ) {
				if( child.isTParam() )
					params.push(child);
				else if( child.isTContent() )
					content.push(child);
			}
			if( content.length > 0 && params.length > 0 )
				throw "check";
			if( content.length > 1 )
				throw "Send may contain only one content child.";
			if( content.length > 0 )
				val = parseContent(content);
			else {
				try {
					val = {};
					setEventData(val, parseParams(params));
				} catch( e:Dynamic ) {
					raise( new Event("error.execution") );
				}
			}
		}
		return val;
	}
	
	function returnDoneEvent( doneData : Dynamic ) : Void {
		if( parentEventHandler == null )
			return;
		
		var data = doneData; // FIXME make a copy
		
		if( invokeId == null )
			throw "No invoke id specified.";
		
		var evt = new Event( "done.invoke." + invokeId );
		evt.invokeid = invokeId;
		parentEventHandler(evt);
	}
	
	inline function raise( evt : Event ) {
		internalQueue.enqueue(evt);
	}
	
	inline function addToExternalQueue( evt : Event ) {
		externalQueue.enqueue(evt);
	}
	
	inline function setEvent( evt : Event ) {
		evt.raw = evt.toString();
		datamodel.setEvent(evt);
	}
	
	function sendEvent( evt : Event, delaySec : Float = 0, addEvent : Event -> Void ) {
		if( delaySec == 0 )
			addEvent(evt);
		else
			timerThread.addTimer(delaySec, function() {
				if( !isCancelEvent(evt) )
					addEvent(evt);
			});
	}
	
	inline function getDuration( delay : String ) {
		return ( delay == null || delay == "" ) ? 0 : Std.parseFloat(delay.split("s").join("")); // FIXME
	}
	
	inline function isValidAndSupportedSendTarget( target : String ) {
		return if( Lambda.has(["#_internal", "#_parent", "#_scxml_" + datamodel.get("_sessionid")], target ) ||
					(invokedData != null && hasInvokedData(target.substr(2))) )
			true;
		else
			datamodel.exists(target);
	}
	
	inline function isValidAndSupportedSendType( type : String ) {
		return datamodel.hasIoProc(type);
	}
	
	inline function ioProcessorSupportsPost() {
		return isValidAndSupportedSendType("http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor");
	}
	
	static var locId : Int = 0;
	inline function getLocationId() {
		return "locId_" + locId++;
	}
	
	static var platformId : Int = 0;
	inline function getPlatformId() {
		return "platformId_" + platformId++;
	}
	
	function getInvokeId( inv : Node ) {
		var node = inv.parent;
		while( !node.isState() && node.parent != null )
			node = node.parent;
		return node.get("id") + "." + getPlatformId();
	}
	
	function getAltProp( n : Node, att0 : String, att1 : String ) {
		var prop = null;
		if( n.exists(att0) )
			prop = n.get(att0);
		if( n.exists(att1) ) {
			if( prop != null ) throw "Property specification for '" + att0 + "' and '" + att1 + "' should be mutually exclusive.";
			prop = datamodel.doVal( n.get(att1) );
		}
		return prop;
	}
	
	function executeBlock( it : Iterable<Node> ) {
		for( i in it ) {
			try {
				executeContent(i);
			} catch( e : Dynamic ) {
				raise( new Event("error.execution") );
				break;
			}
		}
	}
	
	function setEventData( evtData : {}, fromData : Array<{key:String, value:Dynamic}> ) {
		for( item in fromData ) {
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
	}
	
	function getTypedDataStr( content : String, checkNum : Bool = true ) : String {
		if( content == null || content == "" )
			return content;
		if( checkNum ) {
			// is content a number?
			var isNum = Std.parseInt(content) != null;
			if( !isNum ) isNum = !Math.isNaN( Std.parseFloat(content) );
			if( isNum ) return content;
		}
		// is content an object?
		var isObj = false;
		try {
			var tmp = datamodel.doVal(content);
			isObj = Std.is( tmp, {} );
		} catch( e:Dynamic ) { isObj = false; }
		if( isObj ) return content;
		// is content xml?
		var isXml = false;
		try {
			var tmp = Xml.parse(content);
			isXml = Std.is( tmp.firstElement(), Xml );
		} catch( e:Dynamic ) { isXml = false; }
		if( isXml ) return "Xml.parse( '" + content.split("'").join("\\'") + "' ).firstElement()";
		var isArray = false;
		try {
			var tmp = datamodel.doVal(content);
			isArray = Std.is( tmp, Array );
		} catch( e:Dynamic ) { isArray = false; }
		if( isArray ) return content;
		// else (default to string representation)
		return "'" + content.split("'").join("\\'") + "'";
	}
	
	var cancelledSendIds : Hash<Bool>;
	
	function executeContent( c : Node ) {
		switch( c.name ) {
			case "cancel":
				
				if( !datamodel.supportsVal )
					return;
				
				var sendid = getAltProp( c, "sendid", "sendidexpr" );
				cancelledSendIds.set(sendid, true);
					
			case "send":
				
				if( !datamodel.supportsVal && datamodel.supportsLoc )
					return;
				
				var data : Array<{key:String, value:Dynamic}> = [];
				var event = getAltProp( c, "event", "eventexpr" );
				var target = getAltProp( c, "target", "targetexpr" );
				
				var id = c.exists("id") ? c.get("id") : null;
				var idlocation = c.exists("idlocation") ? c.get("idlocation") : null;
				if( id != null && idlocation != null )
					throw "Send properties 'id' and 'idlocation' are mutually exclusive.";
					
				var sendid = null;
				if( id != null ) sendid = id;
				if( idlocation != null ) sendid = datamodel.get(idlocation);
				
				var evtType = target == "#_internal" ? "internal" : "external";
				
				if( target != null && !isValidAndSupportedSendTarget(target) ) {
					if( target.indexOf("#_scxml_") == 0 ) {
						raise( new Event("error.communication", null, sendid, evtType) );
						return;
					}
					raise( new Event("error.execution", null, sendid, evtType) );
					throw "Invalid send target: " + target;
				}
				var type = getAltProp( c, "type", "typeexpr" );
				
				if( type == "http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor" && !ioProcessorSupportsPost() ) {
					raise( new Event("error.communication", null, sendid, evtType) );
					return;
				}
				
				if( type == null )
					type = "http://www.w3.org/TR/scxml/#SCXMLEventProcessor";
				if( type == "http://www.w3.org/TR/scxml/#SCXMLEventProcessor" && event == null )
					throw "Send type http://www.w3.org/TR/scxml/#SCXMLEventProcessor requires either 'event' or 'eventexpr' to be defined.";
				if( !isValidAndSupportedSendType(type) ) {
					raise( new Event("error.execution", null, sendid, evtType) );
					return;
				}
				if( ioProcessorSupportsPost() && type == "http://www.w3.org/TR/scxml/#SCXMLEventProcessor" )
					type = "http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor";
				
				var delay = getAltProp( c, "delay", "delayexpr" );
				if( delay != null && target == "_internal" )
					throw "Send properties 'delay' or 'delayexpr' may not be specified when target is '_internal'.";
					
				if( idlocation != null )
					datamodel.set(idlocation, getLocationId());
				
				var namelist = c.exists("namelist") ? c.get("namelist") : null;
				data = data.concat( getNamelistData(namelist) );
				
				var params = [];
				var content = [];
				for( child in c ) {
					if( child.isTParam() )
						params.push(child);
					else if( child.isTContent() )
						content.push(child);
				}
				
//				if( (content.length == 0 && event == null) || (content.length > 0 && event != null) )
//					throw "Send must specify excatly one of 'event', 'eventexpr' or <content>.";
				if( content.length > 0 && (namelist != null || params.length > 0) )
					throw "Send must not specify 'namelist' or <param> with <content>.";
				if( content.length > 1 )
					throw "Send may contain only one <content> child.";
				
				var contentVal = null;
				var paramsData = null;
				if( content.length > 0 ) {
					contentVal = parseContent(content);
					if( !content[0].exists("expr") ) {
						// TODO report test 179 (worked around here), where 123 should be '123' for consistent evaluation
						contentVal = datamodel.doVal( getTypedDataStr(contentVal, false) );
					}
				} else {
					paramsData = parseParams(params);
					data = data.concat(paramsData);
				}
				
				if( event != null ) {
				
					switch( type ) {
						
						case "http://www.w3.org/TR/scxml/#SCXMLEventProcessor":
						
							var duration = getDuration(delay);
							var evt = new Event(event);
							
							evt.name = event;
							evt.type = evtType;
							evt.sendid = sendid;
							
							if( evtType == "external" ) {
								evt.origin = ( invokeId != null ) ? "#_" + invokeId : "#_internal";
								evt.origintype = "http://www.w3.org/TR/scxml/#SCXMLEventProcessor";
							}
							
							if( content.length > 0 )
								Reflect.setField(evt, "data", contentVal);
							else
								setEventData(evt.data, data.copy());
							
							var cb = addToExternalQueue;

							switch( target ) {
								case "#_internal":
									cb = raise;
									
								case "#_parent":
									if( parentEventHandler == null )
										throw "No parent event handler defined.";
									if( invokeId == null )
										throw "No invokeId specified and trying to communicate with parent.";
									evt.invokeid = invokeId;
									cb = parentEventHandler;
									
								default:
								
									if( target != null && target.length > 2 ) {
										
										if( target.indexOf("#_") == 0 ) {
											var sub = target.substr(2);
											if( hasInvokedData(sub) ) {
												var data : {type:String, instance:hsm.scxml.Interp} = getInvokedData(sub);
												data.instance.postEvent(evt);
											}
										}
									
									}
							}
							
							sendEvent( evt, duration, cb );
							
						case "http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor":
							// FIXME
						case "http://www.w3.org/TR/scxml/#DOMEventProcessor":
							// FIXME
					}

				}
				
			case "log":
				if( datamodel.supportsVal )
					log(c.get("label") + ": " + Std.string( datamodel.doVal(c.get("expr")) ) );
			case "raise":
				var evt = new Event(c.get("event"));
				evt.type = "internal";
				internalQueue.enqueue(evt);
			case "assign":
				if( !datamodel.supportsAssign )
					return;
				if( c.exists("expr") )
					datamodel.doAssign(c.get("location"), c.get("expr"));
				else
					datamodel.doAssign(c.get("location"), getTypedDataStr(cast(c, Assign).content));
			case "if":
				if( !datamodel.supportsCond )
					return;
				if( datamodel.doCond(c.get("cond")) ) {
					for( child in c ) {
						if( child.name == "elseif" || child.name == "else" )
							break;
						else
							executeContent( child );
					}
				} else {
					var matched = false;
					for( child in c ) {
						if( !matched && child.name == "elseif" )
							if( datamodel.doCond(child.get("cond")) ) {
								matched = true;
								continue;
							}
						
						if( !matched && child.name == "else" ) {
							matched = true;
							continue;
						}
						
						if( matched && (child.name == "elseif" || child.name == "else") )
							break;
							
						if( matched )
							executeContent( child );
					}
				}
			case "script":
				if( datamodel.supportsScript ) {
					if( c.exists("src") ) {
						var src = c.get("src");
						var h = new haxe.Http(src);
						h.onData = function(data:String) { datamodel.doScript( data ); };
						h.onError = function(err:String) { throw "Script error: " + err; }; 
						h.request(false);
					} else
						datamodel.doScript( cast(c, Script).content );
				}
			case "foreach":
				if( !(datamodel.supportsVal && datamodel.supportsProps) )
					return;
				
				var arr : Array<Dynamic> = datamodel.doVal(c.get("array")).copy();
				var item = c.exists("item") ? c.get("item") : null;
				
				if( !datamodel.isLegalVar(item) )
					throw "Illegal foreach item value used: " + item;
					
				var itemWasDefined = item != null && datamodel.exists(item);
				var itemPrevVal = itemWasDefined ? datamodel.get(item) : null;
				var index = c.exists("index") ? c.get("index") : null;
				var indexWasDefined = index != null && datamodel.exists(index);
				var indexPrevVal = indexWasDefined ? datamodel.get(index) : null;
				var count = 0;
				
				for( e in arr ) {
					if( item != null )
						datamodel.set(item, e);
					if( index != null )
						datamodel.set(index, count++);
					for( child in c )
						executeContent(child);
				}
				// it appears new foreach vars should remain set - see test 150
				if( item != null )
					if( itemWasDefined )
						datamodel.set(item, itemPrevVal);
					//else
					//	datamodel.remove(item);
				if( index != null )
					if( indexWasDefined )
						datamodel.set(index, indexPrevVal);
					//else
					//	datamodel.remove(index);
			
			default:
		}
	}
	
	function getNamelistData( namelist : String ) {
		var data = [];
		if( namelist != null ) {
			var names = namelist.split(" ");
			for( name in names )
				data.push({key:name, value:datamodel.doLoc(name)});
		}
		return data;
	}
	
	function parseContent( content : Array<Node> ) {
		var contentVal : Dynamic = null;
		try {
			if( content.length > 0 ) {
				var cnode = content[0];
				if( cnode.exists("expr") )
					contentVal = datamodel.doVal(cnode.get("expr"));
				else
					contentVal = StringTools.trim(cast(cnode, Content).content);
			}
		} catch( e:Dynamic ) {
			raise( new Event("error.execution") );
			contentVal = "";
		}
		return contentVal;
	}
	
	function parseParams( params : Array<Node> ) {
		var data = [];
		for( param in params ) {
			var name = param.get("name");
			var expr = param.exists("expr") ? datamodel.doVal(param.get("expr")) : null;
			var location = null;
			try {
				if( param.exists("location") ) {
					if( expr != null )
						throw "check";
					location = datamodel.doLoc(param.get("location"));
				} else {
					if( expr == null )
						throw "check";
				}
			} catch( e:Dynamic ) {
				raise( new Event("error.execution") );
				continue;
			}
			data.push({key:name, value:((expr != null) ? expr : location)});
		}
		return data;
	}
	
	static var hackInvId : Int = 0;
	
	function setInvokedData(id:String, data:Dynamic) {
		invokedDataMutex.acquire();
		invokedData.set(id, data);
		invokedDataMutex.release();
	}
	
	function getInvokedData(id:String) {
		var data : Dynamic = null;
		invokedDataMutex.acquire();
		data = invokedData.get(id);
		invokedDataMutex.release();
		return data;
	}
	
	function hasInvokedData(id:String) {
		var has = false;
		invokedDataMutex.acquire();
		has = invokedData.exists(id);
		invokedDataMutex.release();
		return has;
	}
	
	function invoke( inv : Node ) {
		
		if( !(datamodel.supportsVal && datamodel.supportsLoc) )
			return;
		
		try {
		
			//log("invoke(): inv.id = " + inv.get("id"));
		
			var type = getAltProp( inv, "type", "typeexpr" );
			if( type != null && !invokeTypeAccepted(type) )
				throw "Bad invoke type: " + type;
			// TODO check spec
			if( type == null )
				type = "scxml";
			
			var src = getAltProp( inv, "src", "srcexpr" );
			
			var id = inv.exists("id") ? inv.get("id") : null;
			var idlocation = inv.exists("idlocation") ? inv.get("idlocation") : null;
			if( id != null && idlocation != null )
				throw "Invoke properties 'id' and 'idlocation' are mutually exclusive.";
			var invokeid = id;
			if( idlocation != null ) {
				invokeid = getInvokeId(inv);
				datamodel.doAssign(idlocation, "'" + invokeid + "'");
			}
			
			// FIXME what do we do here if invokeid is still null?
			// this can be the case if neither id nor idlocation are set on inv
			// going by the tests, it seems we need to generate and set a new id for inv is it is still null here - check with spec
			if( invokeid == null ) {
				id = "hackInvId_" + (hackInvId++);
				inv.set("id", id);
				invokeid = id;
			}
			// TODO check this (see test 234)
			inv.set("invokeid", invokeid);
			
			var data = [];
			
			var namelist = inv.exists("namelist") ? inv.get("namelist") : null;
			data = data.concat( getNamelistData(namelist) );
			
			var autoforward = inv.exists("autoforward") ? inv.get("autoforward") : "false";
			
			var params = [];
			var content = [];
			var finalize = [];
			for( child in inv ) {
				if( child.isTParam() )
					params.push(child);
				else if( child.isTContent() )
					content.push(child);
				else if( child.isTFinalize() )
					finalize.push(child);
			}
			
			if( content.length > 0 && src != null )
				throw "Invoke properties 'src' or 'srcexpr' must not occur with <content>.";
			if( content.length > 1 )
				throw "Invoke must not have more than one <content> child.";
			if( finalize.length > 1 )
				throw "Invoke must not have more than one <finalize> child.";
			if( params.length > 0 && namelist != null )
				throw "Invoke property 'namelist' must not be specified with <param>.";
			
			var contentVal = null;
			var params = parseParams(params);
			data = data.concat( params );
			
			if( src != null ) {
				
				if( src.indexOf("file:") >= 0 )
					contentVal = getFileContent(src);
				
				//var http = new haxe.Http(src);
			
			} else {
				contentVal = Std.string( parseContent(content) );
			}
			
			switch( stripEndSlash(type) ) {
				
				case "http://www.w3.org/TR/scxml", "scxml":
				
					if( hasInvokedData(invokeid) )
						throw "Invoke id already exists: " + invokeid;
					
					var c = Thread.create(createChildInterp);
					c.sendMessage(contentVal);
					c.sendMessage(data);
					c.sendMessage(invokeid);
					c.sendMessage(type);
					
				default:
			}
			
		} catch( e : Dynamic ) {
			// cancel
			// raise error
		}
	}
	
	function createChildInterp() {
		var xmlStr = Thread.readMessage(true);
		var data : Array<{key:String,value:Dynamic}> = Thread.readMessage(true);
		var invokeid = Thread.readMessage(true);
		var type = Thread.readMessage(true);
		
		var xml = Xml.parse(xmlStr).firstElement();
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
		
		var me = this;
		var inst = new hsm.scxml.Interp();
		inst.invokeId = invokeid;
		inst.parentEventHandler = function( evt : Event ) {
			me.addToExternalQueue(evt);
		};
		inst.log = function(msg) { log("log-from-child: " + msg); };
		inst.onInit = function() { inst.start(); };
		
		setInvokedData(invokeid, {
			type : type,
			instance : inst
		});
		
		inst.interpret( xml );
	}
	
	function invokeTypeAccepted( type : String ) {
		switch( stripEndSlash(type) ) {
			case
				"http://www.w3.org/TR/scxml", "scxml": return true;//,
//				"http://www.w3.org/TR/ccxml/", "ccxml",
//				"http://www.w3.org/TR/voicexml30/", "voicexml30",
//				"http://www.w3.org/TR/voicexml21/", "voicexml21": return true;
			default:
				return false;
		}
	}
	
	inline function stripEndSlash( str : String ) {
		return (str.substr(-1) == "/") ? str.substr(0,str.length-1) : str;
	}
	
	function setFromSrc( id : String, src : String ) {
		var val = null;
		if( src.indexOf("file:") >= 0 )
			val = getTypedDataStr( getFileContent(src) );
		try {
			datamodel.set(id, datamodel.doVal(val));
		} catch( e:Dynamic ) {
			datamodel.set(id, null);
			raise( new Event("error.execution") );
		}
	}
	
	inline function getFileContent( src : String ) {
		var file = src.substr(5);
		var path = Sys.getCwd() + "ecma/"; // FIXME tmp hack (relative urls..)
		return trim( sys.io.File.getContent(path+file) );
	}
	
	// TODO find better place
	inline function trim( str : String ) {
		var r = ~/[ \n\r\t]+/g;
		return StringTools.trim(r.replace(str, " "));
	}
	
	/** node here is the transition to pass in **/
	function getTargetStates( node : Node ) : List<Node> {
		var l = new List<Node>();
		if( !node.exists("target") )
			return l;
		var ids = node.get("target").split(" ");
		var top = node;
		while( top.parent != null && !top.isTScxml() )
			top = top.parent;
		for( id in ids ) {
			var ts = getTargetState(top, id);
			for( tss in ts )
				l.add( tss );
		}
		return l;
	}
	
	// TODO optimize heavily - store states, history, etc in global vars for quick ref
	function getTargetState( s : Node, id : String ) : List<Node> {
		if( s.get("id") == id )
			return [s].toList();
		else {
			for( child in s.getChildStates() ) {
				var ss = getTargetState(child, id);
				if( ss != null )
					return ss;
			}
			for( h in s.history() ) {
				var hh = getTargetState(h, id);
				if( hh != null )
					return historyValue.exists( h.get("id") ) ?
						historyValue.get( h.get("id") ) : 
						getTargetStates( h.transition().next() );
			}
		}
		return null;
	}
}
