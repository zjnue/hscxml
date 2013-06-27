package hsm.scxml;

class Const {
	
	public static inline var IOPROC_SCXML = "http://www.w3.org/TR/scxml/#SCXMLEventProcessor";
	public static inline var IOPROC_SCXML_SHORT = "scxml";
	public static inline var IOPROC_BASICHTTP = "http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor";
	public static inline var IOPROC_BASICHTTP_SHORT = "basichttp";
	public static inline var IOPROC_DOM = "http://www.w3.org/TR/scxml/#DOMEventProcessor";
	public static inline var IOPROC_DOM_SHORT = "dom";
	
	public static inline function isIoProcScxml( type : String ) {
		return type == IOPROC_SCXML || type == IOPROC_SCXML_SHORT;
	}
	public static inline function isIoProcBasicHttp( type : String ) {
		return type == IOPROC_BASICHTTP || type == IOPROC_BASICHTTP_SHORT;
	}
	public static inline function isIoProcDom( type : String ) {
		return type == IOPROC_DOM || type == IOPROC_DOM_SHORT;
	}
	
	public static inline var INV_TYPE_SCXML = "http://www.w3.org/TR/scxml";
	public static inline var INV_TYPE_SCXML_SHORT = "scxml";
	public static inline var INV_TYPE_CCXML = "http://www.w3.org/TR/ccxml/";
	public static inline var INV_TYPE_CCXML_SHORT = "ccxml";
	public static inline var INV_TYPE_VOICEXML30 = "http://www.w3.org/TR/voicexml30/";
	public static inline var INV_TYPE_VOICEXML30_SHORT = "voicexml30";
	public static inline var INV_TYPE_VOICEXML21 = "http://www.w3.org/TR/voicexml21/";
	public static inline var INV_TYPE_VOICEXML21_SHORT = "voicexml21";
	
	public static var acceptedInvokeTyoes = [
		INV_TYPE_SCXML, INV_TYPE_SCXML_SHORT,
//		INV_TYPE_CCXML, INV_TYPE_CCXML_SHORT,
//		INV_TYPE_VOICEXML30, INV_TYPE_VOICEXML30_SHORT,
//		INV_TYPE_VOICEXML21, INV_TYPE_VOICEXML21_SHORT,
	];
	
	public static inline function isAcceptedInvokeType( type : String ) {
		return Lambda.has( acceptedInvokeTyoes, type );
	}
	public static inline function isScxmlInvokeType( type : String ) {
		return type == INV_TYPE_SCXML || type == INV_TYPE_SCXML_SHORT;
	}
}