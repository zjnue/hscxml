package hsm.scxml;

import hsm.scxml.Types;
import hsm.scxml.Node;
import hsm.scxml.Compiler;
import hsm.scxml.Model;
import hsm.scxml.tools.NodeTools;

using hsm.scxml.tools.ArrayTools;
using hsm.scxml.tools.ListTools;
using hsm.scxml.tools.NodeTools;

class Interp {
	
	var d : Node;
	
	public function new() {
		log = function(msg:String) trace(msg);
	}
	
	public var onInit : Void -> Void;
	public var log : String -> Void;
	public var topNode( get_topNode, never ) : Node;
	
	function get_topNode() return d
	
	public function postEvent( str : String ) {
		externalQueue.enqueue( new Event(str) );
	}
	
	public function start() {
		mainEventLoop();
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
		if( s0.isDescendant(s1) ) return 1;
		if( s1.isDescendant(s0) ) return -1;
		return documentOrder(s0, s1);
	}
	
	function exitOrder( s0 : Node, s1 : Node ) {
		if( s0.isDescendant(s1) ) return -1;
		if( s1.isDescendant(s0) ) return 1;
		return documentOrder(s1, s0);
	}
	
	inline function documentOrder( s0 : Node, s1 : Node ) {
		return ( s0.pos > s1.pos ) ? -1 : 1;
	}
	
	public function interpret(doc:Xml) {
		
		if( !valid(doc) ) failWithError();
		expandScxmlSource(doc);
		
		var compiler = new Compiler();
		var result = compiler.compile(doc, null);
		d = result.node;
		
		log("d = \n" + d.toString());
		
		configuration = new Set();
		statesToInvoke = new Set();
		internalQueue = new Queue();
		externalQueue = new BlockingQueue();
		externalQueue.onNewContent = checkBlockingQueue;
		historyValue = new Hash();
		
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
		
		binding = d.exists("binding") ? d.get("binding") : "early";
		initializeDatamodel( datamodel, result.data, (binding != "early") );
		
		running = true;
		executeGlobalScriptElements(d);
		
		enterStates( [d.initial().next().transition().next()].toList() );
		if( onInit != null )
			onInit();
	}
	
	function valid( doc : Xml ) {
		// FIXME
		return true;
	}
	
	inline function failWithError() {
		// FIXME
		throw "failWithError";
	}
	
	function expandScxmlSource( x : Xml ) { 
		if( x.nodeType == Xml.Element && x.exists("initial") ) {
			var tval = x.get("initial");
			var ins = Xml.createElement("initial");
			var trans = Xml.createElement("transition");
			trans.set("target", tval);
			ins.insertChild(trans, 0);
			x.insertChild(ins, 0);
			x.remove("initial");
		}
		for( el in x.elements() )
			expandScxmlSource(el);
	}
	
	function executeGlobalScriptElements( doc : Node ) {
		var globalScripts = doc.script();
		if( globalScripts.hasNext() )
			executeBlock([globalScripts.next()]);
	}
	
	function initializeDatamodel( datamodel : Model, dms : List<DataModel>, setValsToNull : Bool = false ) {
		if( !(datamodel.supportsVal && datamodel.supportsProps) )
			return;
		for( dm in dms )
			for( d in dm ) {
				var id = d.get("id");
				if( setValsToNull )
					datamodel.set(id, null);
				else if( d.exists("src") ) {
					setFromSrc(id, d.get("src"));
				} else {
					var val = "";
					if( d.exists("expr") )
						val = d.get("expr");
					else
						val = cast(d, Data).content;
					datamodel.set(id, datamodel.doVal(val));
				}
			}
	}
	
	function mainEventLoop() {
		if( running ) {
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
			if( !running ) {
				running = false;
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
		} else {
			log("mainEventLoop: exitInterpreter");
			exitInterpreter();
		}
	}
	
	function checkBlockingQueue() {
		var evt = externalQueue.dequeue();
		if( evt != null )
			mainEventLoopPart2(evt);
		else if( running ) 
			externalQueue.callOnNewContent = true;
		else
			log("checkBlockingQueue: evt = " + Std.string(evt) + " running = " + Std.string(running));
	}
	
	function mainEventLoopPart2( externalEvent : Event ) {
		if( isCancelEvent(externalEvent) ) {
			running = false;
			mainEventLoop();
			return;
		}
		setEvent(externalEvent);
		for( state in configuration )
			for( inv in state.invoke() ) {
				if( inv.get("invokeid") == externalEvent.get("invokeid") )
					applyFinalize(inv, externalEvent);
				if( inv.exists("autoforward") && inv.get("autoforward") == "true" )
					send(inv.get("id"), externalEvent);
			}
		var enabledTransitions = selectTransitions(externalEvent);
		if( !enabledTransitions.isEmpty() )
			microstep(enabledTransitions.toList());
		mainEventLoop();
	}
	
	function isCancelEvent( evt : Event ) {
		// FIXME
		return false;
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
				returnDoneEvent(s.get("donedata"));
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
				initializeDatamodel( datamodel, cast s.datamodel(), false );
				s.isFirstEntry = false;
			}
			for( onentry in s.onentry() )
				executeBlock(onentry);
			if( statesForDefaultEntry.isMember(s) )
				for( content in s.initial().next().transition().next() )
					executeBlock(content);
			if( s.isTFinal() ) {
				if( s.parent.isTScxml() )
					running = false;
				else {
					var parent = s.parent;
					var grandparent = parent.parent;
					internalQueue.enqueue( new Event("done.state." + parent.get("id"), s.get("donedata")) );
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
		if( targetStates == null )
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
	
	function sendDoneEvent( id : String ) {
		// FIXME
	}
	
	function cancelInvoke( inv : Node ) {
		// FIXME
	}
	
	function nameMatch( str1 : String, str2 : String ) {
		return str1 == "*" ? true : str2.indexOf(str1) == 0;
	}
	
	function conditionMatch( transition : Node ) : Bool {
		if( transition.exists("cond") && datamodel.supportsCond )
			return datamodel.doCond( transition.get("cond") );
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
	
	function applyFinalize( inv : Node, evt : Event ) {
		// FIXME
	}
	
	function send( invokeid : String, evt : Event ) {
		// FIXME
	}
	
	function returnDoneEvent( doneData : Dynamic ) : Void {
		// FIXME
	}
	
	inline function raise( evt : Event ) {
		internalQueue.enqueue(evt);
	}
	
	inline function setEvent( evt : Event ) {
		datamodel.set("_event", evt);
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
	
	function executeContent( c : Node ) {
		switch( c.name ) {
			case "log":
				if( datamodel.supportsVal )
					log("<log> label: " + c.get("label") + " val: " + Std.string( datamodel.doVal(c.get("expr")) ) );
			case "raise":
				internalQueue.enqueue(new Event(c.get("event")));
			case "assign":
				if( datamodel.supportsAssign )
					datamodel.doAssign(c.get("location"), c.get("expr"));
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
				if( datamodel.supportsScript )
					datamodel.doScript( cast(c, Script).content );
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
					executeBlock(c);
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
	
	function executeInvoke( i : Node ) {
		return "??"; // FIXME
	}
	
	function invoke( inv : Node ) {
		return "??"; // FIXME
	}
	
	function setFromSrc( id : String, src : String ) {
		// FIXME
	}
	
	/** node here is the transition to pass in **/
	function getTargetStates( node : Node ) : List<Node> {
		var l = new List<Node>();
		var ids = node.get("target").split(" ");
		var top = node;
		while( !(top.parent == null) && !(top.isTScxml()) )
			top = top.parent;
		for( id in ids )
			l.add( getTargetState(top, id) );
		return l;
	}
	
	function getTargetState( s : Node, id : String ) : Node {
		if( s.get("id") == id )
			return s;
		else {
			for( child in s.getChildStates() ) {
				var ss = getTargetState(child, id);
				if( ss != null )
					return ss;
			}
		}
		return null;
	}
}
