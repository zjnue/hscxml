package hsm.scxml;

import hsm.scxml.Types;
import hsm.scxml.Node;
import hsm.scxml.Compiler;
import hsm.scxml.tools.NodeTools;

import hscript.Parser;
import hscript.Interp;

using hsm.scxml.tools.ListTools;
using hsm.scxml.tools.NodeTools;

// similar issues with new spec mentioned here:
// http://lists.w3.org/Archives/Public/www-voice/2013JanMar/0024.html

/**
	<h2>A Algorithm for SCXML Interpretation</h2>
	
	<p>This section contains a normative algorithm for the interpretation of an SCXML document.
	Implementations are free to implement SCXML interpreters in any way they choose, but they MUST 
	behave as if they were using the algorithm defined here.</p>
	
	<p>The fact that SCXML implements a variant of the Statechart formalism does not as such determine 
	a semantics for SCXML. Many different Statechart variants have been proposed, each with its own semantics. 
	This section presents an informal semantics of SCXML documents, as well as a normative algorithm 
	for the interpretation of SCXML documents.</p>
	
	<h2>Informal Semantics</h2>
	
	<p>[This section is informative.]</p>
	
	<p>The following definitions and highlevel principles and constraint are intended to provide a background 
	to the normative algorithm, and to serve as a guide for the proper understanding of it.<p>
	
	<h3>Preliminary definitions</h3>
	
	<p>[
	state
	    An element of type <state>, <parallel>, or <final>.
	pseudo state
	    An element of type <initial> or <history>.
	transition target
	    A state, or an element of type <history>.
	atomic state
	    A state of type <state> with no child states, or a state of type <final>.
	compound state
	    A state of type <state> with at least one child state.
	configuration
	    The maximal consistent set of states (including parallel and final states) that the machine is currently in. 
		We note that if a state s is in the configuration c, it is always the case that the parent of s (if any) 
		is also in c. Note, however, that <scxml> is not a(n explicit) member of the configuration.
	source state
	    The source state of a transition is the state which contains the transition.
	target state
	    A target state of a transition is a state that the transition is entering. Note that a transition can have 
		zero or more target states.
	targetless transition
	    A transition having zero target states.
	eventless transition
	    A transition lacking the 'event' attribute.
	external event
	    An SCXML event appearing in the external event queue. Such events are either sent by external sources or 
		generated with the <send> element.
	internal event
	    An event appearing in the internal event queue. Such events are either raised automatically by the platform 
		or generated with the <raise> or <send> elements.
	microstep
	    A microstep involves the processing of a single transition (or, in the case of parallel states, a single set 
		of transitions.) A microstep may change the the current configuration, update the datamodel and/or generate 
		new (internal and/or external) events. This, by causality, may in turn enable additional transitions which 
		will be handled in the next microstep in the sequence, and so on.
	macrostep
	    A macrostep consists of a sequence (a chain) of microsteps, at the end of which the state machine is in a 
		stable state and ready to process an external event. Each external event causes an SCXML state machine to 
		take exactly one macrostep. However, if the external event does not enable any transitions, no microstep 
		will be taken, and the corresponding macrostep will be empty. 
	]</p>
	
	<h3>Principles and Constraints</h3>
	
	<p>We state here some principles and constraints, on the level of semantics, that SCXML adheres to:<p>
	
	<p>[
	Encapsulation
	    An SCXML processor is a pure event processor. The only way to get data into an SCXML statemachine is to send 
		external events to it. The only way to get data out is to receive events from it.
	Causality
	    There shall be a causal justification of why events are (or are not) returned back to the environment, which 
		can be traced back to the events provided by the system environment.
	Determinism
	    An SCXML statemachine which does not invoke any external event processor must always react with the same 
		behavior (i.e. the same sequence of output events) to a given sequence of input events (unless, of course, 
		the statemachine is explicitly programmed to exhibit an non-deterministic behavior). In particular, the 
		availability of the <parallel> element must not introduce any non-determinism of the kind often associated 
		with concurrency. Note that observable determinism does not necessarily hold for state machines that 
		invoke other event processors.
	Completeness
	    An SCXML interpreter must always treat an SCXML document as completely specifying the behavior of a 
		statemachine. In particular, SCXML is designed to use priorities (based on document order) to resolve 
		situations which other statemachine frameworks would allow to remain under-specified (and thus non-deterministic, 
		although in a different sense from the above).
	Run to completion
	    SCXML adheres to a run to completion semantics in the sense that an external event can only be processed 
		when the processing of the previous external event has completed, i.e. when all microsteps (involving all 
		triggered transitions) have been completely taken.
	Termination
	    A microstep always terminates. A macrostep may not. A macrostep that does not terminate may be said to 
		consist of an infinitely long sequence of microsteps. This is currently allowed.
	]</p>
	
	<h2>Algorithm</h2>
	
	<p>[This section is normative.]</p>
	
	<p>This section presents a normative algorithm for the interpretation of SCXML documents. Implementations are 
	free to implement SCXML interpreters in any way they choose, but they must behave as if they were using the 
	algorithm defined here. Note that the algorithm assumes a Lisp-like semantics in which the empty Set null is equivalent 
	to boolean 'false' and all other entities are equivalent to 'true'.</p>
	
	<h3>Datatypes</h3>
	
	<p>These are the abstract datatypes that are used in the algorithm.</p>
	
	<p>[
	datatype List
	   function head()      // Returns the head of the list
	   function tail()      // Returns the tail of the list
	   function append(l)   // Returns the list appended with l
	   function filter(f)   // Returns the list of elements that satisfy the predicate f
	   function some(f)     // Returns true if some element in the list satisfies the predicate f
	   function every(f)    // Returns true if every element in the list satisfies the predicate f
	
	datatype OrderedSet
	   procedure add(e)     // Adds e to the set if it is not already a member
	   procedure delete(e)  // Deletes e from the set
	   function member(e)   // Is e a member of set?
	   function isEmpty()   // Is the set empty?
	   function toList()    // Converts the set to a list that reflects the order in which elements were originally added.
	   procedure clear()    // Remove all elements from the set (make it empty)   
	
	
	datatype Queue
	   procedure enqueue(e) // Puts e last in the queue
	   function dequeue()   // Removes and returns first element in queue
	   function isEmpty()   // Is the queue empty?
	
	datatype BlockingQueue
	   procedure enqueue(e) // Puts e last in the queue
	   function dequeue()   // Removes and returns first element in queue, blocks if queue is empty
	]</p>
**/
class Interp {
	
	var d : Node;
	var hparse : hscript.Parser;
	var hinterp : hscript.Interp;
	
	public function new() {
		hparse = new hscript.Parser();
		hinterp = new hscript.Interp();
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
	
/**
	<h3>Global variables</h3>
	
	<p>The following variables are global from the point of view of the algorithm. 
	Their values will be set in the procedureinterpret().</p>
	
	<p>[
	global configuration
	global statesToInvoke
	global datamodel
	global internalQueue
	global externalQueue
	global historyValue
	global running
	global binding
	]</p>
	
	<h3>Predicates</h3>
	
	<p>The following binary predicates are used for determining the order in which states 
	are entered and exited.</p>
	
	<p>[
	entryOrder // Ancestors precede descendants, with document order being used to break ties 
	    (Note:since ancestors precede descendants, this is equivalent to document order.)
	exitOrder  // Descendants precede ancestors, with reverse document order being used to break ties 
	    (Note: since descendants follow ancestors, this is equivalent to reverse document order.)
	]</p>
**/
	
	// FIXME report: spec above mentions entryOrder, whereas enterOrder is used in the code

	var configuration : Set<Node>;
	var statesToInvoke : Set<Node>;
	var datamodel : DModel;
	var internalQueue : Queue<Event>;
	var externalQueue : BlockingQueue<Event>;
	var historyValue : Hash<List<Node>>;
	var running : Bool;
	var binding : String;

/**
	<h3>Procedures and Functions</h3>
	
	<p>This section defines the procedures and functions that make up the core of the SCXML interpreter.</p>
**/

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
	
	inline function documentOrder( s0 : Node, s1 : Node ) {
		return ( s0.pos > s1.pos ) ? -1 : 1;
	}
	
	// FIXME report: both initializeDatamodel and initializeDataModel used in the spec

	/**
		<h5>procedure interpret(scxml,id)</h5>
		
		<p>The purpose of this procedure is to initialize the interpreter and to start processing.</p>
		
		<p>In order to interpret an SCXML document, first (optionally) perform [XInclude] processing and 
		(optionally) validate the document, throwing an exception if validation fails. Then convert initial 
		attributes to <initial> container children with transitions to the state specified by the attribute. 
		(This step is done purely to simplify the statement of the algorithm and has no effect on the 
		system's behavior. Such transitions will not contain any executable content). Create an empty 
		configuration complete with a new populated instance of the data model and a execute the global 
		scripts. Create the two queues to handle events and set the global running variable to true. 
		Finally call enterStates on the initial transition that is a child of scxml and start the 
		interpreter's event loop.</p>
		
		<p>[
		procedure interpret(doc):
		    if not valid(doc): failWithError()
		    expandScxmlSource(doc)
		    configuration = new OrderedSet()
		    statesToInvoke = new OrderedSet()
		    datamodel = new Datamodel(doc)
		    executeGlobalScriptElements(doc)
		    internalQueue = new Queue()
		    externalQueue = new BlockingQueue()
		    running = true
		    binding = doc.binding
		    if binding == "early":
		        initializeDatamodel(datamodel, doc)
		    executeTransitionContent([doc.initial.transition])
		    enterStates([doc.initial.transition])
		    mainEventLoop()
		]</p>
	**/
	public function interpret(doc:Xml) {
		
		if( !valid(doc) ) failWithError();
		expandScxmlSource(doc);
		
		var compiler = new Compiler();
		var result = compiler.compile(doc, null);
		d = result.node;
		
		log("d = \n" + d.toString());
		
		configuration = new Set();
		statesToInvoke = new Set();
		
		datamodel = new DModel(d);
		
		// check
		var _sessionId = getSessionId();
		var _name = doc.exists("name") ? doc.get("name") : _sessionId;
		datamodel.set("_sessionId", _sessionId);
		datamodel.set("_name", _name);
		//initDatamodel(result.data);
		
		executeGlobalScriptElements(d);
		
		internalQueue = new Queue();
		externalQueue = new BlockingQueue();
		externalQueue.onNewContent = checkBlockingQueue;
		
		//check
		historyValue = new Hash();
		
		running = true;
		binding = d.exists("binding") ? d.get("binding") : "early";
		
		if( binding == "early" )
			initializeDatamodel(datamodel, d);
		
		initHInterp();
		
		var transition = d.initial().next().transition().next();
		var s = new List<Node>().add2(transition);
		enterStates(s);
		//mainEventLoop();
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
	
	// perform inplace expansions of states by including SCXML source referenced 
	// by urls (see 3.13 Referencing External Files) and change initial attributes 
	// to initial container children with empty transitions to the state from the attribute
	// TODO: XInclude
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
	
	// some datamodel funcs
	static var sessionId:Int = 0;
	function getSessionId() {
		return Std.string(sessionId++);
	}
	
	function executeGlobalScriptElements( doc : Node ) {
		// FIXME
	}
	
	function initHInterp() {
		//hinterp.variables.set("log", log);
		//hinterp.variables.set("Std", Std);
		hinterp.variables.set("trace", log);
		hinterp.variables.set("datamodel", datamodel);
	}
	
	/*
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
	}*/
	
	function initializeDatamodel( datamodel : DModel, doc : Node ) {
		// FIXME
	}

	/**
		<h5>procedure mainEventLoop()</h5>
		
		<p>This loop runs until we enter a top-level final state or an external entity cancels processing. 
		In either case 'running' will be set to false (see EnterStates, below, for termination by 
		entering a top-level final state.)</p>
		
		<p>At the top of the loop, we have either just entered the state machine, or we have just processed 
		an external event. Each iteration through the loop consists of four main steps:</p>
		
		<ol>
		<li>Take any internally enabled transitions, namely those that don't require an event or that are triggered by an internal event.</li> 
		<li>execute any <invoke> tags for states that we entered on the last iteration through the loop</li> 
		<li>repeat step 1 to handle any errors raised by the <invoke> elements.</li> 
		<li>When the internal event queue is empty, wait for an external event and then execute any transitions that it triggers.</li>
		</ol>
		
		<p>However special preliminary processing is applied to the event if the state has executed any <invoke> elements. 
		First, if this event was generated by an invoked process, apply <finalize> processing to it. 
		Secondly, if any <invoke> elements have autoforwarding set, forward the event to them. 
		These steps apply before the transitions are taken.</p>
		
		<p>This event loop thus enforces run-to-completion semantics, in which the system process an external 
		event and then takes all the 'follow-up' transitions that the processing has enabled before looking for 
		another external event. For example, suppose that the external event queue contains events ext1 and ext2 
		and the machine is in state s1. If processing ext1 takes the machine to s2 and generates internal event 
		int1, and s2 contains a transition t triggered by int1, the system is guaranteed to take t, no matter 
		what transitions s2 or other states have that would be triggered by ext2. Note that this is true even though 
		ext2 was already in the external event queue when int1 was generated. In effect, the algorithm treats the 
		processing of int1 as finishing up the processing of ext1.</p>
		
		<p>[
		procedure mainEventLoop():
		    while running:
		        enabledTransitions = null
		        stable = false
		        # Here we handle eventless transitions and transitions 
		        # triggered by internal events until machine is stable
		        while running and not stable:
		            enabledTransitions = selectEventlessTransitions()
		            if enabledTransitions.isEmpty():
		                if internalQueue.isEmpty(): 
		                    stable = true
		                else:
		                    internalEvent = internalQueue.dequeue()
		                    datamodel["_event"] = internalEvent
		                    enabledTransitions = selectTransitions(internalEvent)
		            if not enabledTransitions.isEmpty()::
		                microstep(enabledTransitions.toList())
		        # Here we invoke whatever needs to be invoked
		        for state in statesToInvoke:
		            for inv in state.invoke:
		                inv.invoke(inv)
		        statesToInvoke.clear()
		        # Invoking may have raised internal error events and we
		        # need to back up and handle those too        
		        if not internalQueue.isEmpty():
		            continue
		         # A blocking wait for an external event.  Alternatively, if we have been invoked
		        # our parent session also might cancel us.  The mechanism for this is platform specific,
		        # but here we assume it's a special event we receive
		        externalEvent = externalQueue.dequeue()
		        if isCancelEvent(externalEvent)
		            running = false
		            continue
		        datamodel["_event"] = externalEvent
		        for state in configuration:
		            for inv in state.invoke:
		                if inv.invokeid == externalEvent.invokeid:
		                    applyFinalize(inv, externalEvent)
		                if inv.autoforward:
		                    send(inv.id, externalEvent) 
		        enabledTransitions = selectTransitions(externalEvent)
		        if not enabledTransitions.isEmpty()::
		            microstep(enabledTransitions.toList()) 
		    # If we get here, we have reached a top-level final state or have been cancelled          
		    exitInterpreter()            
		]</p>
	**/
	function mainEventLoop() {
		log("mainEventLoop: running = " + Std.string(running));
		if( running ) {
			var enabledTransitions = null;
			var stable = false;
			// Here we handle eventless transitions and transitions 
			// triggered by internal events until machine is stable
			while( running && !stable ) {
				var enabledTransitions : Set<Node> = selectEventlessTransitions();
				if( enabledTransitions.isEmpty() ) {
					if( internalQueue.isEmpty() )
						stable = true;
					else {
						var internalEvent = internalQueue.dequeue();
						datamodel.set("_event", internalEvent);
						enabledTransitions = selectTransitions(internalEvent);
					}
				}
				if( !enabledTransitions.isEmpty() )
					microstep(enabledTransitions.toList());
			}
			// Here we invoke whatever needs to be invoked
			for( state in statesToInvoke )
				for( inv in state.invoke() )
					//inv.invoke(inv);
					inv.doInvoke();
	        statesToInvoke.clear();
			// Invoking may have raised internal error events and we
			// need to back up and handle those too        
	        if( !internalQueue.isEmpty() ) {
				mainEventLoop();
				return;
			}
			checkBlockingQueue();
		} else {
			log("mainEventLoop: exitInterpreter");
			// If we get here, we have reached a top-level final state or have been cancelled
			exitInterpreter();
		}
	}
	
	function checkBlockingQueue() {
		// A blocking wait for an external event.  Alternatively, if we have been invoked
		// our parent session also might cancel us.  The mechanism for this is platform specific,
		// but here we assume it's a special event we receive
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
        datamodel.set("_event", externalEvent);
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
	
	/**
		<h5>procedure exitInterpreter()</h5>
		
		<p>The purpose of this procedure is to exit the current SCXML process by exiting all active states. 
		If the machine is in a top-level final state, a Done event is generated. (Note that in this case, the 
		final state will be the only active state.) The implementation of returnDoneEvent is platform-dependent, 
		but if this session is the result of an <invoke> in another SCXML session, returnDoneEvent will cause 
		the event done.invoke.<id> to be placed in the external event queue of that session, where <id> is the 
		id generated in that session when the <invoke> was executed.</p>
		
		<p>[
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
		]</p>
	**/
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
		<h5>function selectEventlessTransitions()</h5>
		
		<p>This function selects all transitions that are enabled in the current configuration that do not 
		require an event trigger. First find a transition with no 'event' attribute whose condition 
		evaluates to true. If multiple matching transitions are present, take the first in document order. 
		If none are present, search in the state's ancestors in ancestry order until one is found. As soon as 
		such a transition is found, add it to enabledTransitions, and proceed to the next atomic state 
		in the configuration. If no such transition is found in the state or its ancestors, proceed to the 
		next state in the configuration. When all atomic states have been visited and transitions 
		selected, filter the set of enabled transitions, removing any that are preempted by other 
		transitions, then return the resulting set.</p>
		
		<p>[
		function selectEventlessTransitions():
		    enabledTransitions = new OrderedSet()
		    atomicStates = configuration.toList().filter(isAtomicState).sort(documentOrder)
		    for state in atomicStates:
		        loop: for s in [state].append(getProperAncestors(state, null)):
		            for t in s.transition:
		                if not t.event and conditionMatch(t): 
		                    enabledTransitions.add(t)
		                    break loop
		    enabledTransitions = filterPreempted(enabledTransitions)
		    return enabledTransitions
		]</p>
	**/
	function selectEventlessTransitions() {
		var enabledTransitions = new Set<Node>();
		var atomicStates = configuration.toList().filter(NodeTools.isAtomic).sort(documentOrder);
		for( state in atomicStates )
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
		enabledTransitions = filterPreempted(enabledTransitions);
		return enabledTransitions;
	}
	
	/**
		<h5>function selectTransitions(event)</h5>
		
		<p>The purpose of the selectTransitions()procedure is to collect the transitions that are 
		enabled by this event in the current configuration.</p>
		
		<p>Create an empty set of enabledTransitions. For each atomic state , find a transition whose 'event' 
		attribute matches event and whose condition evaluates to true. If multiple matching transitions are 
		present, take the first in document order. If none are present, search in the state's ancestors in ancestry 
		order until one is found. As soon as such a transition is found, add it to enabledTransitions, and proceed to 
		the next atomic state in the configuration. If no such transition is found in the state or its ancestors, 
		proceed to the next state in the configuration. When all atomic states have been visited and transitions 
		selected, filter out any preempted transitions and return the resulting set.</p>
		
		<p>[
		function selectTransitions(event):
		    enabledTransitions = new OrderedSet()
		    atomicStates = configuration.toList().filter(isAtomicState).sort(documentOrder)
		    for state in atomicStates:
		        loop: for s in [state].append(getProperAncestors(state, null)):
		            for t in s.transition:
		                if t.event and nameMatch(t.event, event.name) and conditionMatch(t):
		                    enabledTransitions.add(t)
		                    break loop
		    enabledTransitions = filterPreempted(enabledTransitions)
		    return enabledTransitions
		]</p>
	**/
	function selectTransitions( event : Event ) {
		var enabledTransitions = new Set<Node>();
		var atomicStates = configuration.toList().filter(NodeTools.isAtomic).sort(documentOrder);
		for( state in atomicStates )
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
		enabledTransitions = filterPreempted(enabledTransitions);
		return enabledTransitions;
	}
	
	/**
		<h5>function filterPreempted(enabledTransitions)</h5>
		
		<p>Filter out any transition in enabledTransitions that is preempted by a transition that precedes it in 
		enabledTransitions. Note that enabledTransitions will contain multiple transitions only if a parallel state is 
		active. In that case, we may have one transition selected for each of its children. These transitions 
		may conflict with each other in the sense that they have incompatible target states. When such a conflict occurs, 
		we select the first transition in document order and say that it preempts the other transitions.</p>
		
		<p>[
		function filterPreempted(enabledTransitions):
		    filteredTransitions = new OrderedSet()
		    for t in enabledTransitions:
		        # does any t2 in filteredTransitions preempt t? if not, add t to filteredTransitions
		        if not filteredTransitions.some(lambda t2: preemptsTransition(t2, t)):
		            filteredTransitions.add(t)
		    return filteredTransitions
		]</p>
	**/
	function filterPreempted( enabledTransitions : Set<Node> ) {
		var filteredTransitions = new Set<Node>();
		for( t in enabledTransitions ) {
			// does any t2 in filteredTransitions preempt t? if not, add t to filteredTransitions
			if( !filteredTransitions.toList().some(function(t2) return preemptsTransition(t2, t)) )
				filteredTransitions.add(t);
		}
		return filteredTransitions;
	}
	
	/**
		<h5>function preemptsTransition(t1, t2)</h5>
		
		<p>There are three types of transitions:</p>
		
		<ol>
		<li>targetless transitions</li>
		<li>transitions within a single child of <parallel></li>
		<li>transitions that cross child boundaries (including exiting and reentering a single child) 
			and/or leave the parallel region altogether.</li>
		</ol>
		
		<p>Type 1 transitions do not preempt any other transitions.
		Type 2 transitions preempt subsequent type 3 transitions (but not other type 2 transitions).
		Type 3 transitions preempt all other transitions.</p>
		
		<p>[
		function preemptsTransition(t1, t2):   
		       if isType2(t) and isType3(t2): return True
		        elif isType3(t): return True
		        else return False
		]</p>
	**/

/*
From: http://lists.w3.org/Archives/Public/www-voice/2013JanMar/0029.html

Question:
>> 13. I find the Type1/Type2/Type3 confusing for transitions. First, <transition> elements already have a 
"type" attribute that is unrelated; a better term (Category?) should be used. Secondly, the prose descriptions 
for both Type 2 and Type 3 do not seem rigorous. What is a "transition within a single child of <parallel>"? 
A transition that is in a state that is the sole child of a parallel? A single transition that is a direct child 
of a <parallel> node? Please revisit the preemptsTransition description and pseudo-code to make this subtle 
area for bugs robust and clear.
Answer:
> Yes, other people have commented that the definition of preemption is quite murky.  I'll have to work on 
clarifying it. "Category' is a better term than 'type' for the reason you mention. In the case of ""transition 
within a single child of <parallel>", it is a transition whose source and target are contained within a single 
<state> child of <parallel> and which can be taken without exiting that <state>.  
> Another way of stating the issue is that two transition conflict if their exit sets (the set of states that 
they exit) have a non-null intersection.  In case of conflict, we execute the 
first transition (in document order) and preempt the second.  
*/	
	
	function preemptsTransition( t1 : Node, t2 : Node ) {
		// FIXME
		return false;
	}
	
	/**
		<h5>procedure microstep(enabledTransitions)</h5>
		
		<p>The purpose of the microstep procedure is to process a single set of transitions. 
		These may have been enabled by an external event, an internal event, or by the presence or absence of 
		certain values in the datamodel at the current point in time. The processing of the enabled transitions must 
		be done in parallel ('lock step') in the sense that their source states must first be exited, then their 
		actions must be executed, and finally their target states entered.</p>
		
		<p>If a single atomic state is active, then enabledTransitions will contain only a single transition. 
		If multiple states are active (i.e., we are in a parallel region), then there may be multiple transitions, 
		one per active atomic state (though some states may not select a transition.) In this case, the transitions 
		are taken in the document order of the atomic states that selected them.</p>
		
		<p>[
		procedure microstep(enabledTransitions):
		    exitStates(enabledTransitions)
		    executeTransitionContent(enabledTransitions)
		    enterStates(enabledTransitions)
		]</p>
	**/
	function microstep( enabledTransitions : List<Node> ) {
		exitStates(enabledTransitions);
		executeTransitionContent(enabledTransitions);
		enterStates(enabledTransitions);
	}
	
	/**
		<h5>procedure exitStates(enabledTransitions)</h5>
		
		<p>Create an empty statesToExit set. For each transition t in enabledTransitions, if t is 
		targetless then do nothing, else then let the transition's ancestor state be the source state 
		(in the case of internal transitions) or (in the case of external transitions) the least common 
		compound ancestor state of the source state and target states of t. Add to the statesToExit set 
		all states in the configuration that are descendants of the ancestor. Next remove all the states 
		on statesToExit from the set of states that will have invoke processing done at the start of the 
		next macrostep. (Suppose macrostep M1 consists of microsteps m11 and m12. We may enter state s 
		in m11 and exit it in m12. We will add s to statesToInvoke in m11, and must remove it in m12. 
		In the subsequent macrostep M2, we will apply invoke processing to all states that were entered, 
		and not exited, in M1.) Then convert statesToExit to a list and sort it in exitOrder.</p>
		
		<p>For each state s in the list, if s has a deep history state h, set the history value of h to be the 
		list of all atomic descendants of s that are members in the current configuration, else set its value to 
		be the list of all immediate children of s that are members of the current configuration. Again for 
		each state s in the list, first execute any onexit handlers, then cancel any ongoing invocations, 
		and finally remove s from the current configuration.</p>
		
		<p>[
		procedure exitStates(enabledTransitions):
		   statesToExit = new OrderedSet()
		   for t in enabledTransitions:
		       if t.target:
		           tstates = getTargetStates(t.target)
		           if t.type == "internal" and isCompoundState(t.source) and tstates.every(lambda s: isDescendant(s,t.source))::
		               ancestor = t.source
		           else:
		               ancestor = findLCCA([t.source].append(getTargetStates(t.target)))
		           for s in configuration:
		               if isDescendant(s,ancestor):
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
		]</p>
	**/
	function exitStates( enabledTransitions : List<Node> ) {
		var statesToExit = new Set<Node>();
		for( t in enabledTransitions ) {
			if( t.exists("target") ) {
				var ancestor = null;
				var targetStates = getTargetStates(t);
				var sourceState = getSourceState(t);
				if( t.get("type") == "internal" && sourceState.isCompound() && targetStates.every(function(s) return s.isDescendant(sourceState)) )
					ancestor = sourceState;
				else
					ancestor = findLCCA( new List<Node>().add2(sourceState).append(getTargetStates(t)) );
				for( s in configuration )
					if( s.isDescendant(ancestor) )
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
	
	function getSourceState( transition : Node ) {
		var source = transition.parent;
		while( !source.isState() )
			source = source.parent;
		return source;
	}
	
	/**
		<h5>procedure executeTransitionContent(enabledTransitions)</h5>
		
		<p>For each transition in the list of enabledTransitions, execute its executable content.</p>
		
		<p>[
		procedure executeTransitionContent(enabledTransitions):
		    for t in enabledTransitions:
		        executeContent(t)
		]</p>
	**/
	function executeTransitionContent( enabledTransitions : List<Node> ) {
		for( t in enabledTransitions )
			for( content in t )
				executeContent(content);
	}
	
	// FIXME: report: both initializeDatamodel and initializeDataModel is used in spec's code.
	// current solution: us initializeDatamodel throughout
	
	/**
		<h5>procedure enterStates(enabledTransitions)</h5>
		
		<p>Create an empty statesToEnter set, and an empty statesForDefaultEntry set. For each transition t in 
		enabledTransitions, if t is targetless then do nothing, else for each target state s, call addStatesToEnter. 
		This will add to statesToEnter s plus any descendant states that will have to be entered by default once 
		s is entered. (If s is atomic, there will not be any such states.) Now for each target state s, add 
		any of s's ancestors that must be entered when s is entered. (These will be any ancestors of s that are 
		not currently active. Note that statesToEnter is a set, so it is harmless if the same ancestor is 
		entered multiple times.) In the case where the ancestor state is parallel, call addStatesToEnter on 
		any of its child states that do not already have a descendant on statesToEnter. (If a child state already 
		has a descendant on statesToEnter, it will get added to the list when we examine the ancestors 
		of that descendant.)</p>
		
		<p>We now have a complete list of all the states that will be entered as a result of taking the transitions 
		in enabledTransitions. Add them to statesToInvoke so that invoke processing can be done at the start of the 
		next macrostep. Convert statesToEnter to a list and sort it in entryOrder. For each state s in the list, first 
		add s to the current configuration. Then if we are using late binding, and this is the first time we have 
		entered s, initialize its data model. Then execute any onentry handlers. If s's initial state is being 
		entered by default, execute any executable content in the initial transition. Finally, if s is a final 
		state, generate relevant Done events. If we have reached a top-level final state, set running to false 
		as a signal to stop processing.</p>
		
		<p>[
		procedure enterStates(enabledTransitions):
		    statesToEnter = new OrderedSet()
		    statesForDefaultEntry = new OrderedSet()
		    for t in enabledTransitions:
		        if t.target:
		            tstates = getTargetStates(t.target)
		            if t.type == "internal" and isCompoundState(t.source) and tstates.every(lambda s: isDescendant(s,t.source)):
		                ancestor = t.source
		            else:
		                ancestor = findLCCA([t.source].append(tstates))
		            for s in tstates:
		                addStatesToEnter(s,statesToEnter,statesForDefaultEntry)
		            for s in tstates:
		                for anc in getProperAncestors(s,ancestor):
		                    statesToEnter.add(anc)
		                    if isParallelState(anc):
		                        for child in getChildStates(anc):
		                            if not statesToEnter.some(lambda s: isDescendant(s,child)):
		                                addStatesToEnter(child,statesToEnter,statesForDefaultEntry)  
		    statesToEnter = statesToEnter.toList().sort(enterOrder)
		    for s in statesToEnter:
		        configuration.add(s)
		        statesToInvoke.add(s)
		        if binding == "late" and s.isFirstEntry:
		            initializeDataModel(datamodel.s,doc.s)
		            s.isFirstEntry = false
		        for content in s.onentry:
		            executeContent(content)
		        if statesForDefaultEntry.member(s):
		            executeContent(s.initial.transition)
		        if isFinalState(s):
		            parent = s.parent
		            grandparent = parent.parent
		            internalQueue.enqueue(new Event("done.state." + parent.id, s.donedata))
		            if isParallelState(grandparent):
		                if getChildStates(grandparent).every(isInFinalState):
		                    internalQueue.enqueue(new Event("done.state." + grandparent.id))
		    for s in configuration:
		        if isFinalState(s) and isScxmlState(s.parent):
		            running = false
		]</p>
	**/
	function enterStates( enabledTransitions : List<Node> ) {
		var statesToEnter = new Set<Node>();
		var statesForDefaultEntry = new Set<Node>();
		for ( t in enabledTransitions ) {
			if( t.exists("target") ) {
				var ancestor = null;
				var targetStates = getTargetStates(t);
				var source = getSourceState(t);
				if( t.get("type") == "internal" && source.isCompound() && targetStates.every(function(s) return s.isDescendant(source)) )
					ancestor = source;
				else
					ancestor = findLCCA( new List<Node>().add2(source).append(targetStates) );
	            for( s in targetStates )
	                addStatesToEnter( s, statesToEnter, statesForDefaultEntry );
	            for( s in targetStates )
					for( anc in getProperAncestors(s,ancestor) ) {
						statesToEnter.add(anc);
						if( anc.isTParallel() )
							for( child in anc.childStates() )
								if( !statesToEnter.toList().some(function(s) return s.isDescendant(child)) )
									addStatesToEnter( child, statesToEnter, statesForDefaultEntry );
					}
			}
		}
		statesToEnter = statesToEnter.sort(enterOrder);
		for ( s in statesToEnter ) {
			configuration.add(s);
			statesToInvoke.add(s);
			if( binding == "late" && s.isFirstEntry ) {
				//initializeDatamodel(datamodel.s,doc.s);
				initializeDatamodel(datamodel, s);
				s.isFirstEntry = false;
			}
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
				running = false;
			}
	}
	
	// FIXME report: addStatesToEnter's signature in spec is different between comment and declaration
	
	/**
		<h5>procedure addStatesToEnter(state,root,statesToEnter,statesForDefaultEntry)</h5>
		
		<p>The purpose of this procedure is to add to statesToEnter state and/or any of its descendants 
		that must be entered as a result of state being the target of a transition. Note that this procedure 
		permanently modifies both statesToEnter and statesForDefaultEntry.</p>
		
		<p>First, If state is a history state then add either the history values associated with state or 
		state's default target to statesToEnter. Else (if state is not a history state), add state to statesToEnter. 
		Then, if state is a a compound state, add state to statesForDefaultEntry and recursively call 
		addStatesToEnter on its default initial state(s). Otherwise, if state is a parallel state, recursively 
		call addStatesToEnter on each of its child states.</p>
		
		<p>[
		procedure addStatesToEnter(state,statesToEnter,statesForDefaultEntry):
		    if isHistoryState(state):
		        if historyValue[state.id]:
		            for s in historyValue[state.id]:
		                addStatesToEnter(s,statesToEnter,statesForDefaultEntry)
		                for anc in getProperAncestors(s,state):
		                    statesToEnter.add(anc)
		        else:
		            for t in state.transition:
		                for s in getTargetStates(t.target):
		                    addStatesToEnter(s,statesToEnter,statesForDefaultEntry)
		    else:
		        statesToEnter.add(state)
		        if isCompoundState(state):
		            statesForDefaultEntry.add(state)
		            for s in getTargetStates(state.initial):
		                addStatesToEnter(s,statesToEnter,statesForDefaultEntry)
		        elif isParallelState(state):
		            for s in getChildStates(state):
		                addStatesToEnter(s,statesToEnter,statesForDefaultEntry)
		]</p>
	**/
	function addStatesToEnter( state : Node, statesToEnter : Set<Node>, statesForDefaultEntry : Set<Node> ) {
		if( state.isTHistory() ) {
			if( historyValue.exists(state.get("id")) ) {
				for( s in historyValue.get(state.get("id")) ) {
					addStatesToEnter( s, statesToEnter, statesForDefaultEntry );
					for( anc in getProperAncestors(s,state) )
						statesToEnter.add(anc);
				}
			} else
				for( t in state.transition() )
					for( s in getTargetStates(t) )
						addStatesToEnter( s, statesToEnter, statesForDefaultEntry );
		} else {
			statesToEnter.add(state);
			if( state.isCompound() ) {
				statesForDefaultEntry.add(state);
				var initial = state.initial();
				if( initial.hasNext() )
				for( s in getTargetStates( initial.next().transition().next() ) )
					addStatesToEnter( s, statesToEnter, statesForDefaultEntry );
			} else if( state.isTParallel() )
				for( s in state.childStates() )
					addStatesToEnter( s, statesToEnter, statesForDefaultEntry );
		}
	}
	
	/**
		<h5>procedure isInFinalState(s)</h5>
		
		<p>Return true if s is a compound <state> and one of its children is an active <final> 
		state (i.e. is a member of the current configuration), or if s is a <parallel> state and isInFinalState 
		is true of all its children.</p>
		
		<p>[
		function isInFinalState(s):
		    if isCompoundState(s):
		        return getChildStates(s).some(lambda s: isFinalState(s) and configuration.member(s))
		    elif isParallelState(s):
		        return getChildStates(s).every(isInFinalState)
		    else:
		        return false
		]</p>
	**/
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
		<h5>function findLCCA(stateList)</h5>
		
		<p>The Least Common Compound Ancestor is the <state> or <scxml> element s such that s is a proper 
		ancestor of all states on stateList and no descendant of s has this property. Note that there is guaranteed 
		to be such an element since the <scxml> wrapper element is a common ancestor of all states. Note also that 
		since we are speaking of proper ancestor (parent or parent of a parent, etc.) the LCCA is never a member of stateList.</p>
		
		<p>[
		function findLCCA(stateList):
		    for anc in getProperAncestors(stateList.head(),null).filter(isCompoundState):
		        if stateList.tail().every(lambda s: isDescendant(s,anc)):
		            return anc
		]</p>
	**/
	function findLCCA( stateList : List<Node> ) {
		for( ancestor in getProperAncestors(stateList.head(), null) )
			//if( stateList.filter(function(s:Node) return s != stateList.head()).every(function(s) return s.isDescendant(ancestor)) )
			if( stateList.filter( // cpp fix
				function(s:Node) {
					var head = stateList.head();
					if( s == head ) return false;
					return true;
				}
			).every(function(s) return s.isDescendant(ancestor)) )
				return ancestor;
		return null; // error
	}
	
	/**
		<h5>function getProperAncestors(state1, state2)</h5>
		
		<p>If state2 is null, returns the set of all ancestors of state1 in ancestry order 
		(state1's parent followed by the parent's parent, etc.). If state2 is non-null, returns in ancestry order 
		the set of all ancestors of state1, up to but not including state2.</p>
	**/
	function getProperAncestors( c : Node, limit : Null<Node> = null ) : List<Node> {
		var l = new List<Node>();
		while( c.parent != limit )
			l.add( c = c.parent );
		return l;
	}
	
	function sendDoneEvent( id : String ) {
		// FIXME
	}
	
	function cancelInvoke( inv : Node ) {
		// FIXME
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
			return eval( transition.get("cond") );
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
	
	function applyFinalize( inv : Node, evt : Event ) {
		// FIXME
	}
	
	function send( invokeid : String, evt : Event ) {
		// FIXME
	}
	
	function returnDoneEvent( doneData : Dynamic ) : Void {
		// FIXME
	}
	
	function executeContent( c : Node ) {
		switch( c.name ) {
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
			default:
		}
	}
	
	function executeInvoke( i : Node ) {
		return "??"; // FIXME
	}
	
	function invoke( inv : Node ) {
		return "??"; // FIXME
	}
	
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
			for( child in s.childStates() ) {
				var ss = getTargetState(child, id);
				if( ss != null )
					return ss;
			}
		}
		return null;
	}
	
}
