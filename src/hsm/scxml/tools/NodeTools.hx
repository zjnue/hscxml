package hsm.scxml.tools;

import hsm.scxml.Node;

class NodeTools {
	// types
	public static inline function isTState( s : Node ) { return Std.is(s,State); }
	public static inline function isTParallel( s : Node ) { return Std.is(s,Parallel); }
	public static inline function isTFinal( s : Node ) { return Std.is(s,Final); }
	public static inline function isTScxml( s : Node ) { return Std.is(s,Scxml); }
	public static inline function isTInitial( s : Node ) { return Std.is(s,Initial); }
	public static inline function isTHistory( s : Node ) { return Std.is(s,History); }
	// defs
	public static inline function isState( s : Node ) { return isTState(s) || isTParallel(s) || isTFinal(s); }
	public static inline function isPseudoState( s : Node ) { return isTInitial(s) || isTHistory(s); }
	public static inline function isTransitionTarget( s : Node ) { return isState(s) || isTHistory(s); }
	public static inline function isAtomic( s : Node ) { return (isTState(s) && !hasChildStates(s)) || isTFinal(s); }
	public static inline function isCompound( s : Node ) { return isTState(s) && hasChildStates(s); }
	public static function isDescendant( s : Node , ancestor : Node ) : Bool {
		var node = s;
		while( node.parent != null ) {
			if ( node.parent == ancestor ) return true;
			node = node.parent;
		}
		return false;
	}
	public static function getChildStates( n : Node ) : List<Node> {
		var l = new List<Node>();
		for( e in n )
			if( isState(e) )
				l.add( e );
		return l;
	}
	public static function hasChildStates( n : Node ) : Bool {
		for( e in n )
			if( isState(e) )
				return true;
		return false;
	}
	// extra
	public static inline function isTTransition( s : Node ) { return Std.is(s, Transition); }
	public static inline function isTDataModel( s : Node ) { return Std.is(s, DataModel); }
	public static inline function isTScript( s : Node ) { return Std.is(s, Script); }
	public static inline function isTInvoke( s : Node ) { return Std.is(s, Invoke); }
	public static inline function isTOnEntry( s : Node ) { return Std.is(s, OnEntry); }
	public static inline function isTOnExit( s : Node ) { return Std.is(s, OnExit); }
	public static inline function isTData( s : Node ) { return Std.is(s, Data); }
	public static inline function isTParam( s : Node ) { return Std.is(s, Param); }
	public static inline function isTContent( s : Node ) { return Std.is(s, Content); }
	// filters
	public static inline function stateFilter( n : Node ) { return isTState(n); }
	public static inline function parallelFilter( n : Node ) { return isTParallel(n); }
	public static inline function transitionFilter( n : Node ) { return isTTransition(n); }
	public static inline function historyFilter( n : Node ) { return isTHistory(n); }
	public static inline function finalFilter( n : Node ) { return isTFinal(n); }
	public static inline function initialFilter( n : Node ) { return isTInitial(n); }
	public static inline function dataModelFilter( n : Node ) { return isTDataModel(n); }
	public static inline function scriptFilter( n : Node ) { return isTScript(n); }
	public static inline function invokeFilter( n : Node ) { return isTInitial(n); }
	public static inline function onEntryFilter( n : Node ) { return isTOnEntry(n); }
	public static inline function onExitFilter( n : Node ) { return isTOnExit(n); }
	// lists
	public static inline function state( n : Node ) { return Lambda.filter( n, stateFilter ).iterator(); }
	public static inline function parallel( n : Node ) { return Lambda.filter( n, parallelFilter ).iterator(); }
	public static inline function transition( n : Node ) { return Lambda.filter( n, transitionFilter ).iterator(); }
	public static inline function history( n : Node ) { return Lambda.filter( n, historyFilter ).iterator(); }
	public static inline function final( n : Node ) { return Lambda.filter( n, finalFilter ).iterator(); }
	public static inline function initial( n : Node ) { return Lambda.filter( n, initialFilter ).iterator(); }
	public static inline function datamodel( n : Node ) { return Lambda.filter( n, dataModelFilter ).iterator(); }
	public static inline function script( n : Node ) { return Lambda.filter( n, scriptFilter ).iterator(); }
	public static inline function invoke( n : Node ) { return Lambda.filter( n, invokeFilter ).iterator(); }
	public static inline function onentry( n : Node ) { return Lambda.filter( n, onEntryFilter ).iterator(); }
	public static inline function onexit( n : Node ) { return Lambda.filter( n, onExitFilter ).iterator(); }
}
