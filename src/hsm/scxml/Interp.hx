package hsm.scxml;

import hsm.scxml.Types;
import hsm.scxml.Node;
import hsm.scxml.Compiler;
import hsm.scxml.tools.NodeTools;

//eval
import hscript.Parser;
import hscript.Interp;

using hsm.scxml.tools.ListTools;
using hsm.scxml.tools.NodeTools;

/**

B Algorithm for SCXML Interpretation

This section presents a normative algorithm for the interpretation of an SCXML document. Implementations are free to implement SCXML interpreters in any way they choose, but they must behave as if they were using the algorithm defined here.

The fact that SCXML implements a variant of the Statechart formalism does not as such determine a semantics for SCXML. Many different Statechart variants have been proposed, each with its own semantics. This section presents an informal semantics of SCXML documents, as well as a normative algorithm for the interpretation of SCXML documents.
Informal Semantics

The following definitions and highlevel principles and constraint are intended to provide a background to the normative algorithm, and to serve as a guide for the proper understanding of it.
Preliminary definitions

state
    An element of type <state>, <parallel>, <final> or <scxml>.
pseudo state
    An element of type <initial> or <history>.
transition target
    A state, or an element of type <history>.
atomic state
    A state of type <state> with no child states, or a state of type <final>.
compound state
    A state of type <state> with at least one child state.
start state
    A dummy state equipped with a transition which when triggered by the Run event leads to the initial state(s). Added by the interpreter with an id guaranteed to be unique within the statemachine. The only role of the start state is to simplify the algorithm.
configuration
    The maximal consistent set of states (including parallel and final states) that the machine is currently in. We note that if a state s is in the configuration c, it is always the case that the parent of s (if any) is also in c. Note, however, that <scxml> is not a(n explicit) member of the configuration.
source state
    The source state of a transition is the atomic state from which the transition departs.
target state
    A target state of a transition is a state that the transition is entering. Note that a transition can have zero or more target states.
targetless transition
    A transition having zero target states.
eventless transition
    A transition lacking the 'event' attribute.
external event
    An SCXML event appearing in the external event queue. Such events are either sent by external sources or generated with the <send> element.
internal event
    An event appearing in the internal event queue. Such events are either raised automatically by the platform or generated with the <event> element.
microstep
    A microstep involves the processing of a single transition (or, in the case of parallel states, a single set of transitions.) A microstep may change the the current configuration, update the datamodel and/or generate new (internal and/or external) events. This, by causality, may in turn enable additional transitions which will be handled in the next microstep in the sequence, and so on.
macrostep
    A macrostep consists of a sequence (a chain) of microsteps, at the end of which the state machine is in a stable state and ready to process an external event. Each external event causes an SCXML state machine to take exactly one macrostep. However, if the external event does not enable any transitions, no microstep will be taken, and the corresponding macrostep will be empty.

Principles and Constraints

We state here some principles and constraints, on the level of semantics, that SCXML adheres to:

Encapsulation
    An SCXML processor is a pure event processor. The only way to get data into an SCXML statemachine is to send external events to it. The only way to get data out is to receive events from it.
Causality
    There shall be a causal justification of why events are (or are not) returned back to the environment, which can be traced back to the events provided by the system environment.
Determinism
    An SCXML statemachine which does not invoke any external event processor must always react with the same behavior (i.e. the same sequence of output events) to a given sequence of input events (unless, of course, the statemachine is explicitly programmed to exhibit an non-deterministic behavior). In particular, the availability of the <parallel> element must not introduce any non-determinism of the kind often associated with concurrency. Note that observable determinism does not necessarily hold for state machines that invoke other event processors.
Completeness
    An SCXML interpreter must always treat an SCXML document as completely specifying the behavior of a statemachine. In particular, SCXML is designed to use priorities (based on document order) to resolve situations which other statemachine frameworks would allow to remain under-specified (and thus non-deterministic, although in a different sense from the above).
Run to completion
    SCXML adheres to a run to completion semantics in the sense that an external event can only be processed when the processing of the previous external event has completed, i.e. when all microsteps (involving all triggered transitions) have been completely taken.
Termination
    A microstep always terminates. A macrostep may not. A macrostep that does not terminate may be said to consist of an infinitely long sequence of microsteps. This is currently allowed.

Algorithm

This section presents a normative algorithm for the interpretation of SCXML documents. Implementations are free to implement SCXML interpreters in any way they choose, but they must behave as if they were using the algorithm defined here. Note that the algorithm assumes a Lisp-like semantics in which the empty Set null is equivalent to boolean 'false' and all other entities are equivalent to 'true'.
Datatypes

These are the abstract datatypes that are used in the algorithm.

datatype List
   function head()      // Returns the head of the list
   function tail()      // Returns the tail of the list
   function append(l)   // Returns the list appended with l
   function filter(f)   // Returns the list of elements that satisfy the predicate f
   function some(f)     // Returns true if some element in the list satisfies the predicate f
   function every(f)    // Returns true if every element in the list satisfies the predicate f

datatype OrderedSet
   procedure add(e)     // Adds e to the set
   procedure delete(e)  // Deletes e from the set
   function member(e)   // Is e a member of set?
   function isEmpty()   // Is the set empty?
   function toList()    // Converts the set to a list that reflects the order in which elements were added.
   function diff(set2)  // Returns an OrderedSet containing all members of OrderedSet that are not in set2. 


datatype Queue
   procedure enqueue(e) // Puts e last in the queue
   function dequeue()   // Removes and returns first element in queue
   function isEmpty()   // Is the queue empty?

datatype BlockingQueue
   procedure enqueue(e) // Puts e last in the queue
   function dequeue()   // Removes and returns first element in queue, blocks if queue is empty


 */

class Interp {
	
	public var onInit : Void -> Void;
	public var log : String -> Void;
	
	var d : Node;
	var hparse : hscript.Parser;
	var hinterp : hscript.Interp;
	
	public function new() {
		hparse = new hscript.Parser();
		hinterp = new hscript.Interp();
		log = function(msg:String) trace(msg);
	}
	
	public var topNode( get_topNode, never) : Node;
	function get_topNode() return d
	
/**

Global variables

The following variables are global from the point of view of the algorithm. Their values will be set in the procedureinterpret().

global datamodel;
global configuration;
global previousConfiguration
global statesToInvoke
global datamodel
global internalQueue;
global externalQueue;
global historyValue;
global continue

Predicates

The following binary predicates are used for determining the order in which states are entered and exited.

entryOrder // Ancestors precede descendants, with document order being used to break ties
exitOrder  // Descendants precede ancestors, with reverse document order being used to break ties

 */
	var datamodel : DModel;
	var configuration : Set<Node>;
	var previousConfiguration : Set<Node>;
	var statesToInvoke : Set<Node>;
	var internalQueue : Queue<Event>;
	public var externalQueue : BlockingQueue<Event>;
	var historyValue : Hash<List<Node>>;
	private var cont : Bool; // continue

/**

Procedures and Functions

This section defines the procedures and functions that make up the core of the SCXML interpreter.

 */
	
	/** 
	 * perform inplace expansions of states by including SCXML source referenced 
	 * by urls (see 3.13 Referencing External Files) and change initial attributes 
	 * to initial container children with empty transitions to the state from the attribute
	 */
	//TODO: XInclude
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
	function valid( doc : Xml ) { // FIXME
		return true;
	}
	function executeGlobalScriptElements( doc : Node ) { // FIXME
	}
	
	// some datamodel funcs
	static var sessionId:Int = 0;
	function getSessionId() {
		return Std.string(sessionId++);
	}
	
/**

procedure interpret(scxml,id)

The purpose of this procedure is to initialize the interpreter and to start processing. It is called with a parsed representation of an SCXML document.

In order to interpret an SCXML document, first convert initial attributes to <initial> container children with transitions to the state specified by the attribute (such transitions will not contain any executable content). Then (optionally) validate the resulting SCXML, and throw an exception if validation fails. Create an empty configuration complete with a new populated instance of the data model and a execute the global scripts. Create the two queues to handle events and set the global continue variable to true. Finally call enterState on the initial transition that is a child of scxml and start the interpreter's event loop.

procedure interpret(doc):
    expandScxmlSource(doc)
    if not valid(doc): failWithError()
    configuration = new OrderedSet()
    previousConfiguration = new OrderedSet()
    statesToInvoke = new OrderedSet()
    datamodel = new Datamodel(doc)
    executeGlobalScriptElements(doc)
    internalQueue = new Queue()
    externalQueue = new BlockingQueue()
    continue = true
    enterState([doc.initial.transition])
    startEventLoop()
 
  */
	public function interpret(doc:Xml) {
		
		expandScxmlSource(doc);
		if( !valid(doc) ) throw "doc invalid";
		
		var compiler = new Compiler();
		var result = compiler.compile(doc, null);
		d = result.node;
		
		log("d = \n" + d.toString());
		
		configuration = new Set();
		previousConfiguration = new Set();
		statesToInvoke = new Set();
		
		datamodel = new DModel(d);
		var _sessionId = getSessionId();
		var _name = doc.exists("name") ? doc.get("name") : _sessionId;
		datamodel.set("_sessionId", _sessionId);
		datamodel.set("_name", _name);
		initDatamodel(result.data);
		
		executeGlobalScriptElements(d);
		internalQueue = new Queue();
		externalQueue = new BlockingQueue();
		externalQueue.onNewContent = checkBlockingQueue;
		historyValue = new Hash();
		cont = true;
		
		initHInterp();
		
		var transition = d.initial().next().transition().next();
		var s = new List<Node>().add2(transition);
		enterStates(s);
		//startEventLoop();
		if (onInit != null) onInit();
	}
	
	function initHInterp() {
		//hinterp.variables.set("log", log);
		//hinterp.variables.set("Std", Std);
		hinterp.variables.set("trace", log);
		hinterp.variables.set("datamodel", datamodel);
	}
	
	public function start() {
		startEventLoop();
	}
	
	public function destroy() {
		// TODO
	}
	
	function initDatamodel( dms : List<DataModel> ) {
		for( dm in dms ) {
			for( data in dm ) {
				if( !data.isTData() )
					continue;
				var id = data.get("id");
				var expr = data.get("expr");
				datamodel.set(id, eval(expr));
			}
		}
	}

/**

procedure startEventLoop()

Upon entering the state machine, we take all internally enabled transitions, namely those that either don't require an event or that are triggered by internal events. (Internal events can only be generated by the state machine itself.) When all such transitions have been taken, we move to the main event loop, which is driven by external events.

procedure procedure startEventLoop():
    initialStepComplete = false ;
    until initialStepComplete:
        enabledTransitions = selectEventlessTransitions()
        if enabledTransitions.isEmpty():
            if internalQueue.isEmpty(): 
                initialStepComplete = true 
            else:
                internalEvent = internalQueue.dequeue()
                datamodel["event"] = internalEvent
                enabledTransitions = selectTransitions(internalEvent)
        if not enabledTransitions.isEmpty():
             microstep(enabledTransitions.toList())
    mainEventLoop()

   */
	function startEventLoop() {
		var initialStepComplete = false;
		while( !initialStepComplete ) {
			var enabledTransitions : Set<Node> = selectEventlessTransitions();
			if( enabledTransitions.isEmpty() )
				if( internalQueue.isEmpty() )
					initialStepComplete = true;
				else {
					var internalEvent : Event = internalQueue.dequeue();
					datamodel.set("_event", internalEvent);
					enabledTransitions = selectTransitions(internalEvent);
				}
			if( !enabledTransitions.isEmpty() )
				microstep( enabledTransitions.toList() );
		}
		mainEventLoop();
	}

/**

procedure mainEventLoop()

This loop runs until we enter a top-level final state or an external entity cancels processing. In either case 'continue' will be set to false (see EnterStates, below, for termination by entering a top-level final state.)

Each iteration through the loop consists of three main steps: 1) execute any <invoke> tags for states that we entered on the last iteration through the loop 2) Wait for an external event and then execute any transitions that it triggers. However special preliminary processing is applied to the event if the state has executed any <invoke> elements. First, if this event was generated by an invoked process, apply <finalize> processing to it. Secondly, if any <invoke> elements have autoforwarding set, forward the event to them. These steps apply before the transitions are taken. 3) Take any subsequent internally enabled transitions, namely those that don't require an event or that are triggered by an internal event.

This event loop thus enforces run-to-completion semantics, in which the system process an external event and then takes all the 'follow-up' transitions that the processing has enabled before looking for another external event. For example, suppose that the external event queue contains events ext1 and ext2 and the machine is in state s1. If processing ext1 takes the machine to s2 and generates internal event int1, and s2 contains a transition t triggered by int1, the system is guaranteed to take t, no matter what transitions s2 or other states have that would be triggered by ext2. Note that this is true even though ext2 was already in the external event queue when int1 was generated. In effect, the algorithm treats the processing of int1 as finishing up the processing of ext1.

procedure procedure mainEventLoop():
    while continue:
        for state in statesToInvoke:
            for inv in state.invoke:
                invoke(inv)
        statesToInvoke.clear()
        previousConfiguration = configuration
        externalEvent = externalQueue.dequeue() # this call blocks until an event is available        
        datamodel["event"] = externalEvent
        for state in configuration:
            for inv in state.invoke:
                if inv.invokeid == externalEvent.invokeid:  # event is the result of an <invoke> in this state
                    applyFinalize(inv, externalEvent)
                if inv.autoforward:
                    send(inv.id, externalEvent)    
        enabledTransitions = selectTransitions(externalEvent)
        if not enabledTransitions.isEmpty():
            microstep(enabledTransitions.toList())
            # now take any newly enabled null transitions and any transitions triggered by internal events
            macroStepComplete = false 
            until macroStepComplete:
                enabledTransitions = selectEventlessTransitions()
                if enabledTransitions.isEmpty():
                    if internalQueue.isEmpty(): 
                        macroStepComplete = true 
                    else:
                        internalEvent = internalQueue.dequeue()
                        datamodel["event"] = internalEvent
                        enabledTransitions = selectTransitions(internalEvent)
                if not enabledTransitions.isEmpty():
                    microstep(enabledTransitions.toList())   
    # if we get here, we have reached a top-level final state or some external entity has set continue to false         
    exitInterpreter()      

    
 */
	
	function mainEventLoop() {
		log("mainEventLoop: cont = " + Std.string(cont));
		if( cont ) {
			for( state in statesToInvoke )
				for( inv in state.invoke() )
					invoke(inv);
			statesToInvoke.clear();
			previousConfiguration = configuration;
			checkBlockingQueue();
		} else {
			log("mainEventLoop: exitInterpreter");
			// if we get here, we have reached a top-level final state or some external 
			// entity has set continue to false  
			exitInterpreter();
		}
	}
	
	function checkBlockingQueue() {
		var evt = externalQueue.dequeue();
		if( evt != null )
			mainEventLoopPart2(evt);
		else if( cont ) 
			externalQueue.callOnNewContent = true;
		else
			log("checkBlockingQueue: evt = " + Std.string(evt) + " cont = " + Std.string(cont));
	}
	
	function mainEventLoopPart2( evt : Event ) {
		datamodel.set("_event", evt);
        for( state in configuration )
            for( inv in state.invoke() ) {
                if( inv.get("id") == evt.get("invokeid") ) // event is the result of an <invoke> in this state
                    applyFinalize(inv, evt);
                if( inv.exists("autoforward") && inv.get("autoforward") == "true" )
                    send(inv.get("id"), evt);
			}
        var enabledTransitions = selectTransitions(evt);
        if( !enabledTransitions.isEmpty() ) {
            microstep( enabledTransitions.toList() );
            // now take any newly enabled null transitions and any transitions triggered by internal events
            var macroStepComplete = false;
            while( !macroStepComplete ) {
                enabledTransitions = selectEventlessTransitions();
                if( enabledTransitions.isEmpty() )
                    if( internalQueue.isEmpty() )
                        macroStepComplete = true;
                    else {
                        var internalEvent = internalQueue.dequeue();
                        datamodel.set("_event", internalEvent);
                        enabledTransitions = selectTransitions(internalEvent);
					}
                if( !enabledTransitions.isEmpty() )
                    microstep(enabledTransitions.toList());
			}
		}
		mainEventLoop();
	}

/**

procedure exitInterpreter()

The purpose of this procedure is to exit the current SCXML process by exiting all active states. If the machine is in a top-level final state, a Done event is generated. (Note that in this case, the final state will be the only active state.) The implementation of returnDoneEvent is platform-dependent, but if this session is the result of an <invoke> in another SCXML session, returnDoneEvent will cause the event done.invoke.<id> to be placed in the external event queue of that session, where <id> is the id generated in that session when the <invoke> was executed.

procedure exitInterpreter():
    statesToExit = configuration.toList().sort(exitOrder)
    for s in statesToExit:
        for content in s.onexit:
            executeContent(content)
        for inv in s.invoke:
            cancelInvoke(inv)
        configuration.delete(s)
        if isFinalState(s) and isScxmlState(s.parent):   
            returnDoneEvent(s.donedata)

 */

	function exitInterpreter() {
		var statesToExit = new Set<Node>(configuration);
		for( s in statesToExit.sort(exitOrder) ) {
			if( s.onexit().hasNext() )
				for( content in s.onexit().next() )
					executeContent(content);
			for( inv in s.invoke() )
				cancelInvoke(inv);
			configuration.delete(s);
			if( s.isTFinal() && s.parent.isTScxml() )
				returnDoneEvent(s.get("donedata"));
		}
	}
	
/**

function selectEventlessTransitions()

This function selects all transitions that are enabled in the current configuration that do not require an event trigger. First test if the state has been preempted by a transition that has already been selected and that will cause the state to be exited when it is taken. If the state has not been preempted, find a transition with no 'event' attribute whose condition evaluates to true. If multiple matching transitions are present, take the first in document order. If none are present, search in the state's ancestors in ancestry order until one is found. As soon as such a transition is found, add it to enabledTransitions, and proceed to the next atomic state in the configuration. If no such transition is found in the state or its ancestors, proceed to the next state in the configuration. When all atomic states have been visited and transitions selected, return the set of enabled transitions.

function selectEventlessTransitions():
    enabledTransitions = new OrderedSet()
    atomicStates = configuration.toList().filter(isAtomicState).sort(documentOrder)
    for state in atomicStates:
        if not isPreempted(state, enabledTransitions):
            loop: for s in [state].append(getProperAncestors(state, null)):
                for t in s.transition:
                    if not t.event and conditionMatch(t): 
                        enabledTransitions.add(t)
                        break loop
    return enabledTransitions


 */
	function selectEventlessTransitions() {
		var enabledTransitions = new Set<Node>();
		var atomicStates = configuration.toList().filter(NodeTools.isAtomic).sort(documentOrder);
		for( state in atomicStates )
			if( !isPreempted(state, enabledTransitions) )
				for( s in new List<Node>().add2(state).append(getProperAncestors(state, null)) ) {
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
		return enabledTransitions;
	}

/**

function selectTransitions(event)

The purpose of the selectTransitions()procedure is to collect the transitions that are enabled by this event in the current configuration.

Create an empty set of enabledTransitions. For each atomic state test if the state has been preempted by a transition that has already been selected and that will cause the state to be exited when it is taken. If the state has not been preempted, find a transition whose 'event' attribute matches event and whose condition evaluates to true. If multiple matching transitions are present, take the first in document order. If none are present, search in the state's ancestors in ancestry order until one is found. As soon as such a transition is found, add it to enabledTransitions, and proceed to the next atomic state in the configuration. If no such transition is found in the state or its ancestors, proceed to the next state in the configuration. When all atomic states have been visited and transitions selected, return the set of enabled transitions.

function selectTransitions(event):
    enabledTransitions = new OrderedSet()
    atomicStates = configuration.toList().filter(isAtomicState).sort(documentOrder)
    for state in atomicStates:
        if not isPreempted(state, enabledTransitions):
            loop: for s in [state].append(getProperAncestors(state, null)):
                for t in s.transition:
                    if t.event and nameMatch(t.event, event.name) and conditionMatch(t):
                        enabledTransitions.add(t)
                        break loop
    return enabledTransitions


 */
	function selectTransitions( event : Event ) {
		var enabledTransitions = new Set<Node>();
		var atomicStates = configuration.toList().filter(NodeTools.isAtomic).sort(documentOrder);
		for( state in atomicStates )
			if( !isPreempted(state, enabledTransitions) )
				for( s in new List<Node>().add2(state).append(getProperAncestors(state, null)) ) {
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
		return enabledTransitions;
	}

/**

function isPreempted(s transitionList)

Return true if a transition T in transitionList exits an ancestor of state s. In this case, taking T will pull the state machine out of s and thus we say that it preempts the selection of a transition from s. Such preemption will occur only if s is a descendant of a parallel region and T exits that region. If we did not do this preemption check, we could end up in an illegal configuration, namely one in which there were multiple active states that were not all descendants of a common parallel ancestor.

function isPreempted(s transitionList):
    preempted = false 
    for t in transitionList:
        if t.target:
            LCA = findLCA([t.source].append(getTargetStates(t.target)))
            if isDescendant(s,LCA):
                preempted = true 
                break
    return preempted

 */
	function isPreempted( s : Node, transitionList : Set<Node> ) {
		for( t in transitionList )
			if( t.exists("target") ) {
				var lca = findLCA( new List<Node>().add2(t.parent).append(getTargetStates(t)) );
				if( s.isDescendant(lca) )
					return true;
			}
		return false;
	}
	
/**

procedure microstep(enabledTransitions)

The purpose of the microstep procedure is to process a single set of transitions. These may have been enabled by an external event, an internal event, or by the presence or absence of certain values in the datamodel at the current point in time. The processing of the enabled transitions must be done in parallel ('lock step') in the sense that their source states must first be exited, then their actions must be executed, and finally their target states entered.

If a single atomic state is active, then enabledTransitions will contain only a single transition. If multiple states are active (i.e., we are in a parallel region), then there may be multiple transitions, one per active atomic state (though some states may not select a transition.) In this case, the transitions are taken in the document order of the atomic states that selected them.

procedure microstep(enabledTransitions):
    exitStates(enabledTransitions)
    executeTransitionContent(enabledTransitions)
    enterStates(enabledTransitions)


 */
	function microstep( enabledTransitions : List<Node> ) {
		exitStates(enabledTransitions);
		executeTransitionContent(enabledTransitions);
		enterStates(enabledTransitions);
	}
	
/**

procedure exitStates(enabledTransitions)

Create an empty statesToExit set. For each transition t in enabledTransitions, if t is targetless then do nothing, else let LCA be the least common ancestor state of the source state and target states of t. Add to the statesToExit set all states in the configuration that are descendants of LCA. Next remove all the states on statesToExit from the set of states that will have invoke processing done at the start of the next macrostep. (Suppose macrostep M1 consists of microsteps m11 and m12. We may enter state s in m11 and exit it in m12. We will add s to statesToInvoke in m11, and must remove it in m12. In the subsequent macrostep M2, we will apply invoke processing to all states that were enter, and not exited, in M1.) Then convert statesToExit to a list and sort it in exitOrder.

For each state s in the list, if s has a deep history state h, set the history value of h to be the list of all atomic descendants of s that are members in the current configuration, else set its value to be the list of all immediate children of s that are members of the current configuration. Again for each state s in the list, first execute any onexit handlers, then cancel any ongoing invocations, and finally remove s from the current configuration.

[NOTE: this function must be updated to handle transitions with 'type'="internal". It currently treats all transitions as if they were external.]

procedure exitStates(enabledTransitions):
    statesToExit = new OrderedSet()
    for t in enabledTransitions:
        if t.target:
            LCA = findLCA([t.source].append(getTargetStates(t.target)))
            for s in configuration:
                if isDescendant(s,LCA):
                    statesToExit.add(s)
    for s in statesToExit:
        statesToInvoke.delete(s)
    statesToExit = statesToExit.toList().sort(exitOrder)
    for s in statesToExit:
        for h in s.history:
            if h.type == "deep":
                f = lambda s0: isAtomicState(s0) and isDescendant(s0,s) 
            else:
                f = lambda s0: s0.parent == s
            historyValue[h.id] = configuration.toList().filter(f)
    for s in statesToExit:
        for content in s.onexit:
            executeContent(content)
        for inv in s.invoke:
            cancelInvoke(inv)
        configuration.delete(s)


 */
	function exitStates( enabledTransitions : List<Node> ) {
		var statesToExit = new Set<Node>();
		for( t in enabledTransitions ) {
			if( t.exists("target") ) {
				var lca = findLCA( new List<Node>().add2(t.parent).append(getTargetStates(t)) );
				for( s in configuration )
					if( s.isDescendant(lca) )
						statesToExit.add(s);
			}
		}
		for( s in statesToExit )
			statesToInvoke.delete(s);
		statesToExit = statesToExit.sort(exitOrder);
		for( s in statesToExit ) {
			for( h in s.history() ) {
				var f = h.get("type") == "deep" ?
					function(s0:Node) return s0.isAtomic() && s0.isDescendant(s) :
					function(s0:Node) return s0.parent == s;
				historyValue.set( h.get("id"), configuration.toList().filter(f) );
			}
		}
		for( s in statesToExit ) {
			var onexit = s.onexit();
			if( onexit.hasNext() )
				for( content in onexit.next() )
					executeContent(content);
			for( inv in s.invoke() )
				cancelInvoke(inv);
			configuration.delete(s);
		}
	}
	
/**

procedure executeTransitionContent(enabledTransitions)

For each transition in the list of enabledTransitions, execute its executable content.

procedure executeTransitionContent(enabledTransitions):
    for t in enabledTransitions:
        executeContent(t)


 */
	function executeTransitionContent( enabledTransitions : List<Node> ) {
		for( t in enabledTransitions )
			for( content in t )
				executeContent(content);
	}
	
/**

procedure enterStates(enabledTransitions)

Create an empty statesToEnter set, and an empty statesForDefaultEntry set. For each transition t in enabledTransitions, if t is targetless then do nothing, else let LCA be the least common ancestor state of the source state and target states of t. For each target state s, call statesToEnte. This will add to statesToEnter s plus all states that will have to be entered in order to enter s. (This may include s's ancestors or parallel siblings.) If LCA is a parallel state, call statesToEnter on each of its children.)

We now have a complete list of all the states that will be entered as a result of taking the transitions in enabledTransitions. Add them to statesToInvoke so that invoke processing can be done at the start of the next macrostep. Convert statesToEnter to a list and sort it in enterorder. For each state s in the list, first add s to the current configuration, then execute any onentry handlers. If s's initial state is being entered by default, execute any executable content in the initial transition. Finally, if s is a final state, generate relevant Done events. If we have reached a top-level final state, set continue to false as a signal to stop processing.

procedure enterStates(enabledTransitions):
    statesToEnter = new OrderedSet()
    statesForDefaultEntry = new OrderedSet()
    for t in enabledTransitions:
        if t.target:
            LCA = findLCA([t.source].append(getTargetStates(t.target)))
            for s in getTargetStates(t.target):
                addStatesToEnter(s,LCA,statesToEnter,statesForDefaultEntry)
            if isParallelState(LCA):
                for child in getChildStates(LCA):
                    addStatesToEnter(child,LCA,statesToEnter,statesForDefaultEntry)
    for s in statesToEnter:
        statesToInvoke.add(s)
    statesToEnter = statesToEnter.toList().sort(enterOrder)
    for s in statesToEnter:
        configuration.add(s)
        for content in s.onentry:
            executeContent(content)
        if statesForDefaultEntry.member(s):
            executeContent(s.initial.transition)
        if isFinalState(s):
            parent = s.parent
            grandparent = parent.parent
            internalQueue.enqueue(new Event("done.state." + parent.id, parent.donedata))
			if isParallelState(grandparent):
                if getChildStates(grandparent).every(isInFinalState):
				    internalQueue.enqueue(new Event("done.state." + grandparent.id, grandparent.donedata))
					
	for s in configuration:
        if isFinalState(s) and isScxmlState(s.parent):
            continue = false

 */
	function enterStates( enabledTransitions : List<Node> ) {
		var statesToEnter = new Set<Node>();
		var statesForDefaultEntry  = new Set<Node>();
		for ( t in enabledTransitions ) {
			if( t.exists("target") ) {
				var targetStates = getTargetStates(t);
				var lca = findLCA( new List<Node>().add2(t.parent).append(targetStates) );
				for( s in targetStates ) {
					addStatesToEnter( s, lca, statesToEnter, statesForDefaultEntry );
				}
				if( lca.isTParallel() )
					for( child in lca.childStates() )
						addStatesToEnter( child, lca, statesToEnter, statesForDefaultEntry );
			}
		}
		for( s in statesToEnter )
			statesToInvoke.add(s);
		statesToEnter = statesToEnter.sort(enterOrder);
		for ( s in statesToEnter ) {
			configuration.add(s);
			var onentry = s.onentry();
			if ( onentry.hasNext() )
				for( content in onentry.next() )
					executeContent(content);
			if( statesForDefaultEntry.member(s) )
				for( content in s.initial().next().transition().next() )
					executeContent(content);
			if( s.isTFinal() ) {
				var parent = s.parent;
				var grandparent = parent.parent;
				internalQueue.enqueue( new Event("done.state." + parent.get("id"), parent.get("donedata")) );
				if( grandparent.isTParallel() )
					if( grandparent.childStates().every(isInFinalState) )
						internalQueue.enqueue( new Event("done.state." + grandparent.get("id"), grandparent.get("donedata")) );
			}
		}
		for( s in configuration )
			if( s.isTFinal() && s.parent.isTScxml() ) {
				log("s = " + s);
				cont = false;
			}
	}
	
	// FIXME - see definition
	function enterOrder( s0 : Node, s1 : Node ) {
		if( s0.isDescendant(s1) ) return 1;
		if( s1.isDescendant(s0) ) return -1;
		return documentOrder(s0, s1);
	}
	
	// FIXME - see definition
	function exitOrder( s0 : Node, s1 : Node ) {
		if( s0.isDescendant(s1) ) return -1;
		if( s1.isDescendant(s0) ) return 1;
		return documentOrder(s1, s0);
	}
	
/**

procedure addStatesToEnter(s,root,statesToEnter,statesForDefaultEntry)

The purpose of this procedure is to add to statesToEnter all states that must be entered as a result of entering state s. Note that this procedure permanently modifies both statesToEnter and statesForDefaultEntry.

First, If s is a history state then add either the history values associated with sor s's default target to statesToEnter. Else (if s is not a history state), add >s to statesToEnter. Then, if s is a parallel state, add each of s's children to statesToEnter. Else, if s is a compound state, add s to statesForDefaultEntry and add its default initial state to statesToEnter. Finally, for each ancestor anc of s, add anc to statesToEnter and if anc is a parallel state, add any child of anc that does not have a descendant on statesToEnter to statesToEnter.

procedure addStatesToEnter(s,root,statesToEnter,statesForDefaultEntry):
    if isHistoryState(s):
         if historyValue[s.id]:
             for s0 in historyValue[s.id]:
                  addStatesToEnter(s0,s,statesToEnter,statesForDefaultEntry)
         else:
             for t in s.transition:
                 for s0 in getTargetStates(t.target):
                     addStatesToEnter(s0,s,statesToEnter,statesForDefaultEntry)
    else:
        statesToEnter.add(s)
        if isParallelState(s):
            for child in getChildStates(s):
                addStatesToEnter(child,s,statesToEnter,statesForDefaultEntry)
        elif isCompoundState(s):
            statesForDefaultEntry.add(s)
            for tState in getTargetStates(s.initial):
                addStatesToEnter(tState, s, statesToEnter, statesForDefaultEntry)
        for anc in getProperAncestors(s,root):
            statesToEnter.add(anc)
            if isParallelState(anc):
                for pChild in getChildStates(anc):
                    if not statesToEnter.toList().some(lambda s2: isDescendant(s2,pChild)):
                          addStatesToEnter(pChild,anc,statesToEnter,statesForDefaultEntry)


 */
	function addStatesToEnter( s : Node, root : Node, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node> ) {
		if( s.isTHistory() ) {
			if( historyValue.exists(s.get("id")) ) {
				for( s0 in historyValue.get(s.get("id")) )
					addStatesToEnter( s0, s, statesToEnter, statesForDefaultEntry );
			} else {
				for( t in s.transition() )
					for( s0 in getTargetStates(t) )
						addStatesToEnter( s0, s, statesToEnter, statesForDefaultEntry );
			}
		} else {
			statesToEnter.add(s);
			if( s.isTParallel() )
				for( child in s.childStates() )
					addStatesToEnter( child, s, statesToEnter, statesForDefaultEntry );
			else if( s.isCompound() ) {
				statesForDefaultEntry.add(s);
				var initial = s.initial();
				if( initial.hasNext() )
					for( tState in getTargetStates( initial.next().transition().next() ) )
						addStatesToEnter( tState, s, statesToEnter, statesForDefaultEntry );
			}
			for( anc in getProperAncestors(s, root) ) {
				statesToEnter.add(anc);
				if( anc.isTParallel() )
					for( pChild in anc.childStates() )
						if( !statesToEnter.toList().some(function(s2) return s2.isDescendant(pChild)) )
							addStatesToEnter( pChild, anc, statesToEnter, statesForDefaultEntry );
			}
		}
	}
	
/**

procedure isInFinalState(s)

Return true if s is a compound <state> and one of its children is an active <final> state (i.e. is a member of the current configuration), or if s is a <parallel> state and isInFinalState is true of all its children.

function isInFinalState(s):
    if isCompoundState(s):
        return getChildStates(s).some(lambda s: isFinalState(s) and configuration.member(s))
    elif isParallelState(s):
        return getChildStates(s).every(isInFinalState)
    else:
        return false

 */
	function isInFinalState( s : Node ) : Bool {
		var self = this;
		if( s.isCompound() )
			return s.childStates().some( function(s0) return s0.isTFinal() && self.configuration.member(s0) );
		else if( s.isTParallel() )
			return s.childStates().every(isInFinalState);
		else 
			return false;
	}
	
/**

function findLCA(stateList)

The Least Common Ancestor is the element s such that s is a proper ancestor of all states on stateList and no descendant of s has this property. Note that there is guaranteed to be such an element since the <scxml> wrapper element is a common ancestor of all states. Note also that since we are speaking of proper ancestor (parent or parent of a parent, etc.) the LCA is never a member of stateList.

function findLCA(stateList):
    for anc in getProperAncestors(stateList.head(), null):
        if stateList.tail().every(lambda s: isDescendant(s,anc)):
            return anc

 */
	function findLCA( stateList : List<Node> ) {
		for( ancestor in getProperAncestors(stateList.head(), null) )
			//if( stateList.filter(function(s:Node) return s != stateList.head()).every(function(s) return s.isDescendant(ancestor)) )
			if( stateList.filter( // cpp fix
				function(s:Node) {
					var head = stateList.head();
					if (s == head) return false;
					return true;
				}
			).every(function(s) return s.isDescendant(ancestor)) )
				return ancestor;
		return null; // error
	}
	
	function documentOrder( s0 : Node, s1 : Node ) {
		if( s0.pos > s1.pos )
			return -1;
		return 1;
	}
	
	function sendDoneEvent( id : String ) { // FIXME
	}
	
	function cancelInvoke( inv : Node ) { // FIXME
		
	}
	
	function nameMatch( str1 : String, str2 : String ) {
		return str2.indexOf(str1) == 0;
	}

	function eval( expr : String ) : Dynamic {
		var program = hparse.parseString(expr);
		var bytes = hscript.Bytes.encode(program);
		program = hscript.Bytes.decode(bytes);
		return hinterp.execute(program);
	}
	
	function conditionMatch( transition : Node ) : Bool {
		if( transition.exists("cond") )
			return eval(transition.get("cond"));
		return true;
	}
	
	function getDefaultInitialState( s : Node ) : Node {
		var childStates = s.childStates();
		var initial = s.initial();
		if( initial.hasNext() ) {
			var id = initial.next().transition().next().get("target");
			return childStates.filter(function(s0) return s0.get("id") == id).iterator().next(); // optimize
		} else
			return childStates.iterator().next();
	}
	
	function applyFinalize(inv:Node, evt:Event) {
		
	}
	
	function send(invokeid:String, evt:Event) {
	}
	
	function returnDoneEvent(doneData : Dynamic) : Void {
		// FIXME
	}
	
	//function sendDoneEventToParent() {
		//hmm
	//}
	
	function executeContent( c : Node ) { // FIXME
		switch (c.name) {
			case "log":
				log("<log> :: label = " + c.get("label") + " :: expr = " + Std.string(c.get("expr")) + 
					" :: value = " + Std.string(eval(c.get("expr"))) );
			case "raise":
				internalQueue.enqueue(new Event(c.get("event")));
			case "assign":
				datamodel.set(c.get("location"), eval(c.get("expr")));
			case "if":
				if( eval(c.get("cond")) ) {
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
							if( eval(child.get("cond")) ) {
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
				eval( cast(c, Script).content );
				
		}
	}
	
	function executeInvoke( i : Node ) {
		return "id??"; // FIXME
	}
	
	function invoke(inv:Node) {
		return "??"; // FIXME
	}
	
	function getProperAncestors( c : Node, limit : Null<Node> = null ) : List<Node> {
		var l = new List<Node>();
		while( c.parent != limit )
			l.add( c = c.parent );
		return l;
	}
	
	function getTargetStates( node : Node ) : List<Node> {
		var l = new List<Node>();
		var ids = node.get("target").split(" ");
		var top = node;
		while( !(top.parent == null) && !(top.isTScxml()) )
			top = top.parent;
		for( id in ids ) {
			l.add( getTargetState(top, id) );
		}
		return l;
	}
	
	function getTargetState( s : Node, id : String ) : Node {
		if( s.get("id") == id ) {
			return s;
		} else {
			for( child in s.childStates() ) {
				var ss = getTargetState(child, id);
				if( ss != null )
					return ss;
			}
		}
		return null;
	}
	
}
