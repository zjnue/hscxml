package hsm.scxml;

import hsm.scxml.Types;
import hsm.scxml.Node;
import hsm.scxml.Compiler;
import hsm.scxml.Model;
import hsm.scxml.Base;

using hsm.scxml.tools.ArrayTools;
using hsm.scxml.tools.ListTools;
using hsm.scxml.tools.NodeTools;
using hsm.scxml.tools.DataTools;
using hsm.scxml.Const;

#if neko
import neko.vm.Thread;
#elseif cpp
import cpp.vm.Thread;
#elseif java
import java.vm.Thread;
#end

#if haxe3
private typedef Hash<T> = haxe.ds.StringMap<T>;
#end

class Interp extends Base {
	
	public function new() {
		super();
	}
	
	public function start() {
		mainEventLoop();
	}
	
	public function stop() {
		running = false;
	}
	
	inline function entryOrder( s0 : Node, s1 : Node ) {
		return documentOrder(s0, s1);
	}
	
	inline function exitOrder( s0 : Node, s1 : Node ) {
		return documentOrder(s1, s0);
	}
	
	inline function documentOrder( s0 : Node, s1 : Node ) {
		return s0.pos - s1.pos;
	}
	
	var nodeMap : Map<String, Node>;
	
	function setLookups( node : Node ) {
		nodeMap = new Map();
		mapNode(node);
	}
	
	function mapNode( node : Node ) {
		for( child in node ) {
			if( child.exists("id") )
				nodeMap.set( child.get("id"), child );
			mapNode(child);	
		}
	}
	
	public function interpret(doc:Xml) {
		
		if( !valid(doc) ) failWithError();
		expandScxmlSource(doc);
		
		var compiler = new Compiler();
		var result = compiler.compile(doc, null);
		d = result.node;
		
		setLookups(d);
		
		//log("d = \n" + d.toString());
		
		configuration = new Set();
		statesToInvoke = new Set();
		internalQueue = new Queue();
		externalQueue = new BlockingQueue( checkBlockingQueue );
		historyValue = new Hash();
		
		extraInit();
		
		var model = d.exists("datamodel") ? d.get("datamodel") : "hscript";
		switch( model ) {
			case "null":
				datamodel = new NullModel();
			case "ecmascript":
				datamodel = new EcmaScriptModel();
			case "xpath":
				datamodel = new XPathModel();
			case "hscript":
				datamodel = new HScriptModel();
			default:
		}
		datamodel.log = log;
		datamodel.isInState = function(id:String) {
			for( state in configuration )
				if( id == state.get("id") )
					return true;
			return false;
		};
		datamodel.init(d);
		
		var me = this;
		binding = d.exists("binding") ? d.get("binding") : "early";
		initializeDatamodel( datamodel, result.data, (binding != "early"), function() {
			initTimer();
			running = true;
			try {
				executeGlobalScriptElements(d);
			} catch( e:Dynamic ) {
				stopTimers();
				parentEventHandler(new Event("done.invoke"));
				return;
			}
			enterStates( [d.initial().next().transition().next()].toList(), function() {
				if( me.onInit != null )
					me.onInit();
			});
		});
	}
	
	function valid( doc : Xml ) {
		// FIXME
		return true;
	}
	
	inline function failWithError() {
		// FIXME
		throw "failWithError";
	}
	
	function executeGlobalScriptElements( doc : Node ) {
		var globalScripts = doc.script();
		for( script in globalScripts )
			executeContent(script);
	}
	
	var initLoadAsyncNum : Int;
	var initLoadCb : Void->Void;
	var startChecking : Bool;
	
	function initializeDatamodel( datamodel : Model, dms : Iterable<DataModel>, setValsToNull : Bool = false, cb : Void->Void ) {
		if( !(datamodel.supportsVal && datamodel.supportsProps) ) {
			cb(); return;
		}
		initLoadAsyncNum = 0;
		initLoadCb = cb;
		startChecking = false;
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
						val = datamodel.getTypedDataStr( cast(d, Data).content );
					try {
						var v = datamodel.doVal(val);
						datamodel.set(id, v);
					} catch( e:Dynamic ) {
						datamodel.set(id, null);
						raise( new Event( Event.ERROR_EXEC ) );
					}
				}
			}
		startChecking = true;
		checkInitLoadAsync( false );
	}
	
	function checkInitLoadAsync( dec : Bool ) {
		if( dec ) initLoadAsyncNum--;
		if( !startChecking ) return;
		if( initLoadAsyncNum == 0 ) initLoadCb();
	}
	
	function checkBlockingQueue() {
		var externalEvent = externalQueue.dequeue();
		if( externalEvent != null ) {
			if( isCancelEvent(externalEvent) ) {
				running = false;
				mainEventLoop();
				return;
			}
			setEvent(externalEvent);
			for( state in configuration )
				for( inv in state.invoke() ) {
					if( inv.get("invokeid") == externalEvent.invokeid )
						applyFinalize(inv, externalEvent);
					if( inv.exists("autoforward") && inv.get("autoforward") == "true" )
						send(inv.get("id"), externalEvent);
				}
			var enabledTransitions = selectTransitions(externalEvent);
			if( !enabledTransitions.isEmpty() )
				microstep(enabledTransitions.toList(), mainEventLoop);
			else
				mainEventLoop();
		}
		else if( running ) 
			externalQueue.callOnNewContent = true;
		else
			log("checkBlockingQueue: externalEvent = " + Std.string(externalEvent) + " running = " + Std.string(running));
	}
	
	function mainEventLoop() {
		if( running ) {
			var enabledTransitions : Set<Node> = null;
			var macrostepDone = false;
			mainEventLoopNext(enabledTransitions, macrostepDone);
		} else {
			stopTimers();
			exitInterpreter();
		}
	}
	
	function mainEventLoopNext( enabledTransitions : Set<Node>, macrostepDone : Bool ) : Void {
		if( running && !macrostepDone ) {
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
			if( !enabledTransitions.isEmpty() ) {
				microstep(enabledTransitions.toList(), mainEventLoopNext.bind(enabledTransitions, macrostepDone));
			} else
				mainEventLoopNext(enabledTransitions, macrostepDone);
		} else {
			if( !running ) {
				mainEventLoop();
				return;
			}
			for( state in statesToInvoke )
				for( inv in state.invoke() )
					invoke(inv);
			statesToInvoke.clear();
			if( !internalQueue.isEmpty() ) {
				mainEventLoop();
				return;
			}
			checkBlockingQueue();
		}
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
				for( t in s.transition() )
					if( !t.exists("event") && conditionMatch(t) ) {
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
	
	function microstep( enabledTransitions : List<Node>, cb : Void->Void ) {
		exitStates(enabledTransitions);
		executeTransitionContent(enabledTransitions);
		enterStates(enabledTransitions, cb);
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
		for( t in transitions )
			if( t.exists("target") ) {
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
	
	function enterStates( enabledTransitions : List<Node>, cb : Void->Void ) {
		var statesToEnter = new Set<Node>();
		var statesForDefaultEntry = new Set<Node>();
		// initialize the temporary table for default content in history states
		defaultHistoryContent = new Hash<Iterable<Node>>();
		computeEntrySet( enabledTransitions, statesToEnter, statesForDefaultEntry );
		var states : List<Node> = statesToEnter.toList().sort(entryOrder);
		enterStatesNext(states, statesToEnter, statesForDefaultEntry, cb);
	}
	
	function enterStatesNext( states : List<Node>, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node>, cb : Void->Void ) {
		if( states.length == 0 ) {
			cb(); return;
		}
		var s = states.pop();
		configuration.add(s);
		statesToInvoke.add(s);
		if( binding == "late" && s.isFirstEntry ) {
			s.isFirstEntry = false;
			var dms : Iterator<DataModel> = cast s.datamodel();
			initializeDatamodel( datamodel, {iterator:function() return dms}, false, 
				enterStatesNextContinued.bind(s, states, statesToEnter, statesForDefaultEntry, cb)
			);
		} else
			enterStatesNextContinued(s, states, statesToEnter, statesForDefaultEntry, cb);
	}
	
	function enterStatesNextContinued( s : Node, states : List<Node>, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node>, cb : Void->Void ) {
		for( onentry in s.onentry() )
			executeBlock(onentry);
		if( statesForDefaultEntry.isMember(s) )
			executeBlock(s.initial().next().transition().next());
		if( s.exists("id") && defaultHistoryContent.exists(s.get("id")) )
			executeBlock(defaultHistoryContent.get(s.get("id")));
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
		enterStatesNext( states, statesToEnter, statesForDefaultEntry, cb );
	}
	
	function computeEntrySet( transitions : List<Node>, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node> ) {
		for( t in transitions ) {
			for( s in getTargetStates(t) )
				addDescendantStatesToEnter( s, statesToEnter, statesForDefaultEntry );
			var ancestor = getTransitionDomain(t);
			for( s in getEffectiveTargetStates(t) )
				addAncestorStatesToEnter( s, ancestor, statesToEnter, statesForDefaultEntry );
		}
	}
	
	function addDescendantStatesToEnter( state : Node, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node> ) {
		if( state.isTHistory() )
			if( historyValue.exists(state.get("id")) ) {
				for( s in historyValue.get(state.get("id")) )
					addDescendantStatesToEnter( s, statesToEnter, statesForDefaultEntry );
				for( s in historyValue.get(state.get("id")) )
					addAncestorStatesToEnter( s, state.parent, statesToEnter, statesForDefaultEntry );
			} else {
				defaultHistoryContent.set(state.parent.get("id"), state.transition().next());
				for( s in getTargetStates(state.transition().next()) )
					addDescendantStatesToEnter( s, statesToEnter, statesForDefaultEntry );
				for( s in getTargetStates(state.transition().next()) )
					addAncestorStatesToEnter( s, state.parent, statesToEnter, statesForDefaultEntry );
			}
		else {
			statesToEnter.add(state);
			if( state.isCompound() ) {
				statesForDefaultEntry.add(state);
				for( s in getTargetStates(state.initial().next().transition().next()) )
					addDescendantStatesToEnter( s, statesToEnter, statesForDefaultEntry );
				for( s in getTargetStates(state.initial().next().transition().next()) )
					addAncestorStatesToEnter( s, state, statesToEnter, statesForDefaultEntry );
			} else if( state.isTParallel() )
				for( child in state.getChildStates() )
					if( !statesToEnter.some(function(s) return s.isDescendant(child)) )
						addDescendantStatesToEnter( child, statesToEnter, statesForDefaultEntry );
		}
	}
	
	function addAncestorStatesToEnter( state : Node, ancestor : Node, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node> ) {
		for( anc in getProperAncestors(state,ancestor) ) {
			statesToEnter.add(anc);
			if( anc.isTParallel() )
				for( child in anc.getChildStates() )
					if( !statesToEnter.some(function(s) return s.isDescendant(child)) )
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
		var targetStates = getEffectiveTargetStates(transition);
		var sourceState = getSourceState(transition);
		if( targetStates.isEmpty() )
			return null;
		else if( transition.get("type") == "internal" && sourceState.isCompound() 
				&& targetStates.every(function(s) return s.isDescendant(sourceState)) )
			return sourceState;
		else
			return findLCCA( [sourceState].toList().append(targetStates.toList()) );
	}
	
	function findLCCA( stateList : List<Node> ) {
		for( anc in getProperAncestors(stateList.head(),null).filter(function(s) return s.isCompound() || s.isTScxml()) )
			if( stateList.tail().every(function(s) return s.isDescendant(anc)) )
				return anc;
		return null;
	}
	
	function getEffectiveTargetStates( transition : Node ) : Set<Node> {
		var targets = new Set<Node>();
		for( s in getTargetStates(transition) )
			if( s.isTHistory() ) {
				if( historyValue.exists(s.get("id")) )
					targets.union( Set.ofList(historyValue.get(s.get("id"))) );
				else
					targets.union( getEffectiveTargetStates(s.transition().next()) );
			} else
				targets.add(s);
		return targets;
	}
	
	function getTargetStates( transition : Node ) : List<Node> {
		var l = new List<Node>();
		if( transition.exists("target") )
			l = [for( id in transition.get("target").split(" ") ) nodeMap.get(id)].toList();
		return l;
	}
	
	function getProperAncestors( state1 : Node, state2 : Null<Node> = null ) : List<Node> {
		var l = new List<Node>();
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
			raise( new Event( Event.ERROR_EXEC ) );
			return false;
		}
		return true;
	}
	
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
		if( hasWorker(id) ) {
			postToWorker( id, "stop" );
			postToWorker( id, "killParentHandler" );
			postToWorker( id, "exitInterpreter" );
		} else {
			log("Warning, cancel invoke data missing for id: " + id);
		}
	}
	
	function killParentHandler() {
		#if !(js || flash)
		parentEventHandler = function( evt : Event ) {};
		#end
	}
	
	// TODO check, evt does not seem necessary here
	function applyFinalize( inv : Node, evt : Event ) {
		for( f in inv.finalize() )
			executeBlock(f);
	}
	
	function send( invokeid : String, evt : Event ) {
		if( !hasWorker(invokeid) )
			throw "check";
		var worker = getWorker(invokeid);
		if( !worker.type.isScxmlInvokeType() )
			throw "Invoke type currently not supported: " + worker.type;
		postToWorker( invokeid, "postEvent", [evt] );
	}
	
	function getDoneData( n : Node ) {
		var val : Dynamic = null;
		for( d in n.donedata() ) {
			if( val != null )
				break;
			var params = [], content = [];
			for( child in d ) {
				if( child.isTParam() ) params.push(child);
				else if( child.isTContent() ) content.push(child);
			}
			if( content.length > 0 && params.length > 0 )
				throw "check";
			if( content.length > 1 )
				throw "Send may contain only one content child.";
			if( content.length > 0 ) {
				var strVal = parseContent( content );
				val = datamodel.doVal( datamodel.getTypedDataStr( strVal ));
			} else {
				try {
					val = DataTools.copyFrom( {}, parseParams(params) );
				} catch( e:Dynamic ) {
					raise( new Event( Event.ERROR_EXEC ) );
				}
			}
		}
		return val;
	}
	
	function returnDoneEvent( doneData : Dynamic ) : Void {
		if( parentEventHandler == null )
			return;
		var data = doneData; // FIXME make a copy
		var evt = new Event( "done.invoke." + invokeId );
		evt.invokeid = invokeId;
		parentEventHandler(evt);
	}
	
	function sendEvent( evt : Event, delaySec : Float = 0, addEvent : Event -> Void ) {
		if( delaySec == 0 )
			addEvent(evt);
		else {
			#if (js || flash)
			var t = haxe.Timer.delay(function() {
				if( !isCancelEvent(evt) )
					addEvent(evt);
			}, Std.int(delaySec * 1000));
			timers.push(t);
			#else
			timerThread.addTimer(delaySec, function() {
				if( !isCancelEvent(evt) )
					addEvent(evt);
			});
			#end
		}
	}
	
	inline function isValidAndSupportedSendTarget( target : String ) {
		return Lambda.has(["#_internal", "#_parent", "#_scxml_" + datamodel.get("_sessionid")], target) || hasWorker(target.substr(2)) || datamodel.exists(target);
	}
	
	inline function isValidAndSupportedSendType( type : String ) {
		return datamodel.hasIoProc(type);
	}
	
	inline function ioProcessorSupportsPost() {
		return isValidAndSupportedSendType( Const.IOPROC_BASICHTTP );
	}
	
	function executeBlock( it : Iterable<Node> ) {
		for( i in it ) {
			try {
				executeContent(i);
			} catch( e : Dynamic ) {
				raise( new Event( Event.ERROR_EXEC ) );
				break;
			}
		}
	}
	
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
				
				var type = getAltProp( c, "type", "typeexpr" );
				if( type != null ) type = type.stripEndSlash();
				
				if( (type == null || type.isIoProcScxml()) && target != null && !isValidAndSupportedSendTarget(target) ) {
					if( target.indexOf("#_scxml_") == 0 ) {
						raise( new Event( Event.ERROR_COMMS, null, sendid, evtType ) );
						return;
					}
					raise( new Event( Event.ERROR_EXEC, null, sendid, evtType ) );
					throw "Invalid send target: " + target;
				}
				
				if( type.isIoProcBasicHttp() && (!ioProcessorSupportsPost() || target == null) ) {
					raise( new Event( Event.ERROR_COMMS, null, sendid, evtType ) );
					return;
				}
				
				if( type == null )
					type = Const.IOPROC_SCXML;
				if( type.isIoProcScxml() && event == null )
					throw "Send type " + type + " + requires either 'event' or 'eventexpr' to be defined.";
				if( !isValidAndSupportedSendType(type) ) {
					raise( new Event( Event.ERROR_EXEC, null, sendid, evtType ) );
					return;
				}

				var delay = getAltProp( c, "delay", "delayexpr" );
				if( delay != null && target == "_internal" )
					throw "Send properties 'delay' or 'delayexpr' may not be specified when target is '_internal'.";
					
				if( idlocation != null )
					datamodel.set(idlocation, getLocationId());
				
				var namelist = c.exists("namelist") ? c.get("namelist") : null;
				data = data.concat( getNamelistData(namelist) );
				
				var params = [], content = [];
				for( child in c ) {
					if( child.isTParam() ) params.push(child);
					else if( child.isTContent() ) content.push(child);
				}
				
				if( content.length > 0 && (namelist != null || params.length > 0) )
					throw "Send must not specify 'namelist' or <param> with <content>.";
				if( content.length > 1 )
					throw "Send may contain only one <content> child.";
				
				var contentVal = null;
				var paramsData = null;
				if( content.length > 0 ) {
					contentVal = parseContent( content );
					if( !content[0].exists("expr") )
						contentVal = datamodel.doVal( datamodel.getTypedDataStr( contentVal ));
				} else {
					paramsData = parseParams(params);
					data = data.concat(paramsData);
				}
				
				switch( type ) {
					
					case Const.IOPROC_SCXML, Const.IOPROC_SCXML_SHORT:
						
						// TODO check
						if( event == null ) return;
						
						var duration = delay.getDuration();
						var evt = new Event(event);
						
						evt.name = event;
						evt.type = evtType;
						evt.sendid = sendid;
						
						if( evtType == "external" ) {
							evt.origin = ( invokeId != null ) ? "#_" + invokeId : "#_internal";
							evt.origintype = type;
						}
						
						if( content.length > 0 )
							Reflect.setField(evt, "data", contentVal);
						else
							DataTools.copyFrom( evt.data, data, true );
						
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
								if( target != null && target.length > 2 )
									if( target.indexOf("#_") == 0 ) {
										var sub = target.substr(2);
										if( hasWorker(sub) )
											postToWorker( sub, "postEvent", [evt] );
									}
						}
						
						sendEvent( evt, duration, cb );
						
					case Const.IOPROC_BASICHTTP, Const.IOPROC_BASICHTTP_SHORT:

						var h = new haxe.Http(target);
						
						// make encoding explicit here
						h.setHeader("Content-Type", "application/x-www-form-urlencoded");
						
						//var enc = function(data) return haxe.Serializer.run(data);
						var enc = function(data) return StringTools.urlEncode(Std.string(data));
						
						if( contentVal != null ) {
							var tmp = contentVal.split("=");
							if( tmp[0] == "_scxmleventname" )
								h.setParameter("_scxmleventname", enc(tmp[1]));
							else
								h.setParameter("__data__", enc(contentVal));
						} else {
							for( d in data ) {
								h.setParameter(d.key, enc(d.value));
							}
						}
						if( event != null )
							h.setParameter("_scxmleventname", enc(event));
						if( c.exists("httpResponse") )
							h.setParameter("httpResponse", enc(c.get("httpResponse")));
						
						var me = this;
						h.onData = function(data) {
							log("basichttp: onData: data = " + data);
							try {
								var evtObj = haxe.Unserializer.run(data);
								me.postEvent( Event.fromObj(evtObj) );
							} catch( e : Dynamic ) { log("basichttp: onData error: " + Std.string(e)); }
						};
						h.onError = function(msg) {
							log("basichttp: onError: msg = " + msg);
						};
						h.onStatus = function(status:Int) {
							log("basichttp: onStatus: status = " + status);
						};
						
						h.request(true);
						
					case Const.IOPROC_DOM, Const.IOPROC_DOM_SHORT:
					
						#if (js || flash)
						var iface = c.exists("interface") ? c.get("interface") : "CustomEvent";
						var domEvtType = event;
						var cancelable = c.exists("cancelable") ? c.get("cancelable") == "true" : false;
						var bubbles = c.exists("bubbles") ? c.get("bubbles") == "true" : true;
						
						post("sendDomEvent", [invokeId, target, iface, domEvtType, cancelable, bubbles, contentVal, data]);
						#end
				}
				
			case "log":
				if( datamodel.supportsVal )
					log( (c.exists("label") ? c.get("label") + ": " : "") + Std.string( datamodel.doVal(c.get("expr")) ) );
				else
					log( (c.exists("label") ? c.get("label") + ": " : "") + c.get("expr") );
			case "raise":
				var evt = new Event(c.get("event"));
				evt.type = "internal";
				internalQueue.enqueue(evt);
			case "assign":
				if( !datamodel.supportsAssign )
					return;
				if( c.exists("expr") )
					datamodel.doAssign( c.get("location"), c.get("expr"), c.get("type"), c.get("attr") );
				else
					datamodel.doAssign( c.get("location"), datamodel.getTypedDataStr( cast(c, Assign).content ), c.get("type"), c.get("attr") );
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
				
				var tmp : Array<Dynamic> = datamodel.doVal(c.get("array"));
				var arr = tmp.copy();
				var item = c.exists("item") ? c.get("item") : null;
				
				if( !datamodel.isLegalVar(item) )
					throw "Illegal foreach item value used: " + item;
					
				var itemWasDefined = item != null && datamodel.exists(item);
				var itemPrevVal = itemWasDefined ? datamodel.get(item) : null;
				var index = c.exists("index") ? c.get("index") : null;
				var indexWasDefined = index != null && datamodel.exists(index);
				var indexPrevVal = indexWasDefined ? datamodel.get(index) : null;
				var count = Std.is(datamodel, XPathModel) ? 1 : 0;
				
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
	
	function invoke( inv : Node ) {
		
		if( !(datamodel.supportsVal && datamodel.supportsLoc) )
			return;
		
		try {
			//log("invoke(): inv.id = " + inv.get("id"));
			var type = getAltProp( inv, "type", "typeexpr" );
			if( type != null ) type = type.stripEndSlash();
			if( type != null && !type.isAcceptedInvokeType() )
				throw "Bad invoke type: " + type;
			// TODO check spec
			if( type == null )
				type = Const.INV_TYPE_SCXML_SHORT;
			
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
			
			// FIXME get confirmation on setting these two inv atts (see test 234 for instance)
			if( invokeid == null ) {
				id = getInvokeId(inv);
				inv.set("id", id);
				invokeid = id;
			}
			inv.set("invokeid", invokeid);
			
			var data = [];
			var namelist = inv.exists("namelist") ? inv.get("namelist") : null;
			data = data.concat( getNamelistData(namelist) );
			var autoforward = inv.exists("autoforward") ? inv.get("autoforward") : "false";
			
			var params = [], content = [], finalize = [];
			for( child in inv ) {
				if( child.isTParam() ) params.push(child);
				else if( child.isTContent() ) content.push(child);
				else if( child.isTFinalize() ) finalize.push(child);
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
					getFileContent(src, invokeContentReady.bind(invokeid, type, data, _));
			} else {
				contentVal = Std.string( parseContent(content) );
				invokeContentReady(invokeid, type, data, contentVal);
			}
			
		} catch( e : Dynamic ) {
			raise( new Event( Event.ERROR_EXEC ) );
		}
	}
	
	function invokeContentReady( invokeid : String, type : String, data : Array<{value:Dynamic, key:String}>, contentVal : String ) {
		try {
			switch( type ) {
				case Const.INV_TYPE_SCXML, Const.INV_TYPE_SCXML_SHORT:
					if( hasWorker(invokeid) )
						throw "Invoke id already exists: " + invokeid;
					createSubInst( contentVal, data, invokeid, type );
				default:
			}
		} catch( e : Dynamic ) {
			raise( new Event( Event.ERROR_EXEC ) );
		}
	}
	
	function setFromSrc( id : String, src : String ) {
		var val = null;
		if( src.indexOf("file:") >= 0 ) {
			getFileContent(src, setFromSrcContinued.bind(id, true, _));
		} else
			setFromSrcContinued(id, false, val );
	}
	
	function setFromSrcContinued( id : String, wasFileLoad : Bool, data : String ) {
		var val = wasFileLoad ? datamodel.getTypedDataStr( data ) : null;
		try {
			datamodel.set(id, datamodel.doVal(val));
		} catch( e:Dynamic ) {
			datamodel.set(id, null);
			raise( new Event( Event.ERROR_EXEC ) );
		}
		if( wasFileLoad )
			checkInitLoadAsync(true);
	}
	
	inline function getFileContent( src : String, dataCb : String->Void ) {
		var file = src.substr(5);
		initLoadAsyncNum++;
		
		#if (js || flash)
		
		var h = new haxe.Http( path + file );
		h.onData = function(data) { 
			log("getFileContent: data = " + data);
			dataCb( DataTools.trim(data) );
		}
		h.onError = function(msg) {
			log("getFileContent: msg = " + msg);
			dataCb(null);
		}
		h.request(false);
		
		#else
		
		var fullPath = sys.FileSystem.fullPath( path ) + "/" + file;
		dataCb( DataTools.trim(sys.io.File.getContent(fullPath)) );
		
		#end
	}
	
	public static function main() {
		new Interp().export();
	}
	
	override public function handleOnMessage( data : Dynamic ) {
		var msg = hxworker.Worker.uncompress( data );
		switch( msg.cmd ) {
			case "postEvent": postEvent( cast(msg.args[0], Event) );
			case "interpret": interpret( Xml.parse(msg.args[0]).firstElement() );
			case "path": path = Std.string(msg.args[0]);
			case "start": start();
			case "stop": stop();
			case "killParentHandler": parentEventHandler = function( evt : Event ) {};
			case "exitInterpreter": exitInterpreter();
			case "invokeId": invokeId = msg.args[0];
			#if (js || flash)
			case "sendDomEventFailed":
				if( msg.args[0] == null || msg.args[0] == "" ) {
					postEvent( new Event( Event.ERROR_COMMS ) );
					return;
				}
				var parts = msg.args[0].split(",");
				var fromInvokeId = parts.pop();
				if( fromInvokeId == null || fromInvokeId == "undefined" )
					fromInvokeId = parts.pop();
				postToWorker( fromInvokeId, "sendDomEventFailed", [parts.join(",")] );
			#end
		}
	}
}
