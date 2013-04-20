package hsm.scxml.tools;

class ListTools {
	public static inline function head<T>( l : List<T> ) return l.first()
	public static inline function tail<T>( l : List<T> ) return l.last()
	public static inline function append<T>( l : List<T>, itemList : List<T> ) {
		for( i in itemList ) l.add( i ); return l;
	}
	public static inline function some<T>( l : List<T>, f : T -> Bool ) return l.filter( f ).length > 0
	public static inline function every<T>( l : List<T>, f : T -> Bool ) return l.filter( f ).length == l.length
	public static inline function clone<T>( l : List <T> ) {
		var l2 = new List<T>();
		for( i in l ) l2.add( i );
		return l2;
	}
	public static function sort<T>( l : List<T>, f : T -> T -> Int ) {
		var arr = Lambda.array(l);
		arr.sort(f); l.clear();
		for( i in arr ) l.add(i);
		return l;
	}
	public static inline function add2<T>( l : List<T>, item : T ) {
		l.add( item ); return l;
	}
}
