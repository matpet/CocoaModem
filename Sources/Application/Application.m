//
//  Application.m
//  cocoaModem
//
//  Created by Kok Chen on Sun May 16 2004.
	#include "Copyright.h"
//

#import "Application.h"
#import "About.h"
#import "AppDelegate.h"
#import "AudioInterfaceTypes.h"
#import "AudioManager.h"
#import "AuralMonitor.h"
#import "Config.h"
#import "Contest.h"
#import "ContestInterface.h"
#import "DigitalInterfaces.h"
#import "FSKHub.h"
#import "LiteRTTY.h"
#import "MacroInterface.h"
#import "MacroScripts.h"
#import "Messages.h"
#import "modemTypes.h"
#import "Modem.h"
#import "ModemSleepManager.h"
#import "Plist.h"
#import "Preferences.h"
#import "QSO.h"
#import "splash.h"
#import "StdManager.h"
#import "TextEncoding.h"
#import "Transceiver.h"
#import "Module.h"
#import "UserInfo.h"
#import "UTC.h"
#import <math.h>
#import <unistd.h>
#import "CoreModem.h"
#import "cocoaModemDebug.h"
#import "NetReceive.h"
#import "NetSend.h"
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/types.h>
#import "audioutils.h"

#define kXMLRPCPort 7362

@interface CMXMLRPCRequest : NSObject <NSXMLParserDelegate> {
	NSString *methodName ;
	NSMutableArray *params ;
}

- (id)initWithData:(NSData*)data ;
- (NSString*)methodName ;
- (NSArray*)params ;

@end

@interface CMXMLRPCServer : NSObject {
	Application *application ;
	int listenSocket ;
	Boolean running ;
}

- (id)initWithApplication:(Application*)app ;
- (void)start ;
- (void)stop ;

@end

@implementation CMXMLRPCRequest

static NSString *CMXMLRPCUnescape( NSString *string )
{
	NSMutableString *unescaped ;

	if ( string == nil ) return @"" ;
	unescaped = [ NSMutableString stringWithString:string ] ;
	[ unescaped replaceOccurrencesOfString:@"&lt;" withString:@"<" options:0 range:NSMakeRange( 0, [ unescaped length ] ) ] ;
	[ unescaped replaceOccurrencesOfString:@"&gt;" withString:@">" options:0 range:NSMakeRange( 0, [ unescaped length ] ) ] ;
	[ unescaped replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:0 range:NSMakeRange( 0, [ unescaped length ] ) ] ;
	[ unescaped replaceOccurrencesOfString:@"&apos;" withString:@"'" options:0 range:NSMakeRange( 0, [ unescaped length ] ) ] ;
	[ unescaped replaceOccurrencesOfString:@"&amp;" withString:@"&" options:0 range:NSMakeRange( 0, [ unescaped length ] ) ] ;
	return unescaped ;
}

static NSString *CMXMLRPCInnerTagValue( NSString *source, NSString *tag )
{
	NSString *startTag, *endTag ;
	NSRange start, end ;
	NSUInteger location ;

	startTag = [ NSString stringWithFormat:@"<%@>", tag ] ;
	endTag = [ NSString stringWithFormat:@"</%@>", tag ] ;
	start = [ source rangeOfString:startTag options:NSCaseInsensitiveSearch ] ;
	if ( start.location == NSNotFound ) return nil ;
	location = start.location + start.length ;
	end = [ source rangeOfString:endTag options:NSCaseInsensitiveSearch range:NSMakeRange( location, [ source length ]-location ) ] ;
	if ( end.location == NSNotFound ) return nil ;
	return [ source substringWithRange:NSMakeRange( location, end.location-location ) ] ;
}

static NSArray *CMXMLRPCParamBlocks( NSString *xml )
{
	NSMutableArray *blocks ;
	NSRange searchRange, start, end ;
	NSUInteger location ;

	blocks = [ NSMutableArray array ] ;
	searchRange = NSMakeRange( 0, [ xml length ] ) ;
	while ( 1 ) {
		start = [ xml rangeOfString:@"<param>" options:NSCaseInsensitiveSearch range:searchRange ] ;
		if ( start.location == NSNotFound ) break ;
		location = start.location + start.length ;
		end = [ xml rangeOfString:@"</param>" options:NSCaseInsensitiveSearch range:NSMakeRange( location, [ xml length ]-location ) ] ;
		if ( end.location == NSNotFound ) break ;
		[ blocks addObject:[ xml substringWithRange:NSMakeRange( location, end.location-location ) ] ] ;
		location = end.location + end.length ;
		searchRange = NSMakeRange( location, [ xml length ]-location ) ;
	}
	return blocks ;
}

- (id)initWithData:(NSData*)data
{
	NSString *xml, *paramString, *value ;
	NSArray *blocks ;
	NSEnumerator *enumerator ;
	id block ;
	NSData *decodedData ;

	self = [ super init ] ;
	if ( self ) {
		params = [ [ NSMutableArray alloc ] init ] ;
		xml = [ [ NSString alloc ] initWithData:data encoding:NSUTF8StringEncoding ] ;
		if ( xml == nil ) xml = [ [ NSString alloc ] initWithData:data encoding:NSISOLatin1StringEncoding ] ;
		if ( xml ) {
			value = CMXMLRPCInnerTagValue( xml, @"methodName" ) ;
			if ( value ) methodName = [ CMXMLRPCUnescape( value ) copy ] ;
			blocks = CMXMLRPCParamBlocks( xml ) ;
			enumerator = [ blocks objectEnumerator ] ;
			while ( ( block = [ enumerator nextObject ] ) != nil ) {
				paramString = CMXMLRPCInnerTagValue( block, @"string" ) ;
				if ( paramString ) {
					[ params addObject:CMXMLRPCUnescape( paramString ) ] ;
					continue ;
				}
				paramString = CMXMLRPCInnerTagValue( block, @"base64" ) ;
				if ( paramString ) {
					decodedData = [ [ NSData alloc ] initWithBase64EncodedString:paramString options:0 ] ;
					if ( decodedData ) [ params addObject:decodedData ] ;
					[ decodedData release ] ;
					continue ;
				}
				paramString = CMXMLRPCInnerTagValue( block, @"boolean" ) ;
				if ( paramString ) {
					[ params addObject:[ NSNumber numberWithBool:( [ paramString intValue ] != 0 ) ] ] ;
					continue ;
				}
				paramString = CMXMLRPCInnerTagValue( block, @"int" ) ;
				if ( paramString == nil ) paramString = CMXMLRPCInnerTagValue( block, @"i4" ) ;
				if ( paramString ) {
					[ params addObject:paramString ] ;
					continue ;
				}
				paramString = CMXMLRPCInnerTagValue( block, @"value" ) ;
				if ( paramString ) [ params addObject:CMXMLRPCUnescape( paramString ) ] ;
			}
			[ xml release ] ;
		}
	}
	return self ;
}

- (void)dealloc
{
	[ methodName release ] ;
	[ params release ] ;
	[ super dealloc ] ;
}

- (NSString*)methodName
{
	return methodName ;
}

- (NSArray*)params
{
	return params ;
}

@end

@implementation CMXMLRPCServer

- (id)initWithApplication:(Application*)app
{
	self = [ super init ] ;
	if ( self ) {
		application = app ;
		listenSocket = -1 ;
		running = NO ;
	}
	return self ;
}

- (NSString*)escape:(NSString*)string
{
	NSMutableString *escaped ;
	
	if ( string == nil ) return @"" ;
	escaped = [ NSMutableString stringWithString:string ] ;
	[ escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange( 0, [ escaped length ] ) ] ;
	[ escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange( 0, [ escaped length ] ) ] ;
	[ escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange( 0, [ escaped length ] ) ] ;
	return escaped ;
}

- (NSString*)xmlValueForObject:(id)object type:(NSString*)type
{
	NSString *string ;
	NSMutableString *xml ;
	NSEnumerator *enumerator ;
	id item ;

	if ( type == nil || [ type isEqualToString:@"nil" ] ) return @"<nil/>" ;
	if ( [ type isEqualToString:@"string" ] ) return [ NSString stringWithFormat:@"<string>%@</string>", [ self escape:object ] ] ;
	if ( [ type isEqualToString:@"boolean" ] ) return [ NSString stringWithFormat:@"<boolean>%d</boolean>", [ object boolValue ] ? 1 : 0 ] ;
	if ( [ type isEqualToString:@"base64" ] ) {
		string = [ object base64EncodedStringWithOptions:0 ] ;
		return [ NSString stringWithFormat:@"<base64>%@</base64>", string ] ;
	}
	if ( [ type isEqualToString:@"array" ] ) {
		xml = [ NSMutableString stringWithString:@"<array><data>" ] ;
		enumerator = [ object objectEnumerator ] ;
		while ( ( item = [ enumerator nextObject ] ) != nil ) {
			[ xml appendFormat:@"<value><string>%@</string></value>", [ self escape:item ] ] ;
		}
		[ xml appendString:@"</data></array>" ] ;
		return xml ;
	}
	return [ NSString stringWithFormat:@"<string>%@</string>", [ self escape:[ object description ] ] ] ;
}

- (NSData*)httpResponseForBody:(NSString*)body status:(NSString*)status
{
	NSString *header ;
	NSData *bodyData ;
	NSMutableData *response ;

	bodyData = [ body dataUsingEncoding:NSUTF8StringEncoding ] ;
	header = [ NSString stringWithFormat:@"HTTP/1.1 %@\r\nContent-Type: text/xml\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", status, (unsigned long)[ bodyData length ] ] ;
	response = [ NSMutableData data ] ;
	[ response appendData:[ header dataUsingEncoding:NSUTF8StringEncoding ] ] ;
	[ response appendData:bodyData ] ;
	return response ;
}

- (NSData*)faultResponse:(int)code string:(NSString*)message
{
	NSString *body ;
	body = [ NSString stringWithFormat:@"<?xml version=\"1.0\"?><methodResponse><fault><value><struct><member><name>faultCode</name><value><int>%d</int></value></member><member><name>faultString</name><value><string>%@</string></value></member></struct></value></fault></methodResponse>", code, [ self escape:message ] ] ;
	return [ self httpResponseForBody:body status:@"200 OK" ] ;
}

- (NSData*)invokeMethod:(NSString*)method params:(NSArray*)params
{
	NSMutableDictionary *request ;
	NSString *type, *body ;
	id result ;

	request = [ NSMutableDictionary dictionary ] ;
	[ request setObject:( method ) ? method : @"" forKey:@"method" ] ;
	[ request setObject:( params ) ? params : [ NSArray array ] forKey:@"params" ] ;
	[ application performSelectorOnMainThread:@selector(handleXMLRPCRequest:) withObject:request waitUntilDone:YES ] ;
	result = [ request objectForKey:@"result" ] ;
	type = [ request objectForKey:@"type" ] ;
	if ( [ type isEqualToString:@"fault" ] ) {
		return [ self faultResponse:[ [ request objectForKey:@"faultCode" ] intValue ] string:[ request objectForKey:@"faultString" ] ] ;
	}
	body = [ NSString stringWithFormat:@"<?xml version=\"1.0\"?><methodResponse><params><param><value>%@</value></param></params></methodResponse>", [ self xmlValueForObject:result type:type ] ] ;
	return [ self httpResponseForBody:body status:@"200 OK" ] ;
}

- (NSData*)responseForRequestData:(NSData*)requestData
{
	NSString *requestString, *bodyString ;
	NSRange separator ;
	CMXMLRPCRequest *request ;
	NSData *bodyData ;
	NSData *response ;

	requestString = [ [ NSString alloc ] initWithData:requestData encoding:NSUTF8StringEncoding ] ;
	if ( requestString == nil ) requestString = [ [ NSString alloc ] initWithData:requestData encoding:NSISOLatin1StringEncoding ] ;
	if ( requestString == nil ) return [ self faultResponse:-32700 string:@"Malformed HTTP request" ] ;
	separator = [ requestString rangeOfString:@"\r\n\r\n" ] ;
	if ( separator.location == NSNotFound ) separator = [ requestString rangeOfString:@"\n\n" ] ;
	if ( separator.location == NSNotFound ) {
		[ requestString release ] ;
		return [ self faultResponse:-32700 string:@"HTTP body not found" ] ;
	}
	bodyString = [ requestString substringFromIndex:separator.location+separator.length ] ;
	bodyData = [ bodyString dataUsingEncoding:NSUTF8StringEncoding ] ;
	request = [ [ CMXMLRPCRequest alloc ] initWithData:bodyData ] ;
	if ( [ [ request methodName ] length ] == 0 ) {
		response = [ self faultResponse:-32600 string:@"Missing methodName" ] ;
	}
	else {
		response = [ self invokeMethod:[ request methodName ] params:[ request params ] ] ;
	}
	[ request release ] ;
	[ requestString release ] ;
	return response ;
}

- (NSData*)readRequestFromSocket:(int)fd
{
	NSMutableData *request ;
	char buffer[2048] ;
	ssize_t count ;
	NSRange range ;
	NSString *headers ;
	NSUInteger contentLength, offset, expectedLength ;

	request = [ NSMutableData data ] ;
	contentLength = 0 ;
	offset = 0 ;
	expectedLength = 0 ;
	while ( ( count = recv( fd, buffer, sizeof( buffer ), 0 ) ) > 0 ) {
		[ request appendBytes:buffer length:count ] ;
		if ( expectedLength == 0 ) {
			headers = [ [ NSString alloc ] initWithData:request encoding:NSUTF8StringEncoding ] ;
			if ( headers == nil ) headers = [ [ NSString alloc ] initWithData:request encoding:NSISOLatin1StringEncoding ] ;
			if ( headers ) {
				range = [ headers rangeOfString:@"\r\n\r\n" ] ;
				if ( range.location == NSNotFound ) range = [ headers rangeOfString:@"\n\n" ] ;
				if ( range.location != NSNotFound ) {
					offset = range.location + range.length ;
					NSRange lengthRange = [ headers rangeOfString:@"Content-Length:" options:NSCaseInsensitiveSearch ] ;
					if ( lengthRange.location != NSNotFound ) {
						NSUInteger index = lengthRange.location + lengthRange.length ;
						while ( index < [ headers length ] && [ headers characterAtIndex:index ] == ' ' ) index++ ;
						contentLength = [ [ headers substringFromIndex:index ] intValue ] ;
					}
					expectedLength = offset + contentLength ;
				}
				[ headers release ] ;
			}
		}
		if ( expectedLength > 0 && [ request length ] >= expectedLength ) break ;
	}
	return request ;
}

- (void)serverThread:(id)unused
{
	NSAutoreleasePool *pool ;
	struct sockaddr_in address ;
	int client, on ;
	socklen_t length ;
	NSData *requestData, *responseData ;

	pool = [ [ NSAutoreleasePool alloc ] init ] ;
	listenSocket = socket( AF_INET, SOCK_STREAM, 0 ) ;
	if ( listenSocket < 0 ) {
		[ pool release ] ;
		return ;
	}
	on = 1 ;
	setsockopt( listenSocket, SOL_SOCKET, SO_REUSEADDR, &on, sizeof( on ) ) ;
	bzero( &address, sizeof( address ) ) ;
	address.sin_len = sizeof( address ) ;
	address.sin_family = AF_INET ;
	address.sin_addr.s_addr = htonl( INADDR_LOOPBACK ) ;
	address.sin_port = htons( kXMLRPCPort ) ;
	if ( bind( listenSocket, (struct sockaddr*)&address, sizeof( address ) ) < 0 ) {
		close( listenSocket ) ;
		listenSocket = -1 ;
		[ pool release ] ;
		return ;
	}
	if ( listen( listenSocket, 4 ) < 0 ) {
		close( listenSocket ) ;
		listenSocket = -1 ;
		[ pool release ] ;
		return ;
	}
	while ( running ) {
		length = sizeof( address ) ;
		client = accept( listenSocket, (struct sockaddr*)&address, &length ) ;
		if ( client < 0 ) {
			if ( running == NO ) break ;
			continue ;
		}
		requestData = [ self readRequestFromSocket:client ] ;
		responseData = [ self responseForRequestData:requestData ] ;
		if ( responseData ) send( client, [ responseData bytes ], [ responseData length ], 0 ) ;
		close( client ) ;
	}
	if ( listenSocket >= 0 ) {
		close( listenSocket ) ;
		listenSocket = -1 ;
	}
	[ pool release ] ;
}

- (void)start
{
	if ( running ) return ;
	running = YES ;
	[ NSThread detachNewThreadSelector:@selector(serverThread:) toTarget:self withObject:self ] ;
}

- (void)stop
{
	running = NO ;
	if ( listenSocket >= 0 ) shutdown( listenSocket, SHUT_RDWR ) ;
}

@end


@implementation Application

- (void)installAppearanceMenuItem
{
	NSMenu *appMenu ;
	int i, index ;

	if ( darkModeMenuItem != nil ) return ;
	if ( [ NSApp mainMenu ] == nil ) return ;
	appMenu = [ [ [ NSApp mainMenu ] itemAtIndex:0 ] submenu ] ;
	if ( appMenu == nil ) return ;
	index = [ appMenu numberOfItems ] ;
	for ( i = 0; i < [ appMenu numberOfItems ]; i++ ) {
		NSMenuItem *item = [ appMenu itemAtIndex:i ] ;
		if ( [ item action ] == @selector(showPreferences:) ) {
			index = i+1 ;
			break ;
		}
	}
	if ( index < [ appMenu numberOfItems ] && ![ [ appMenu itemAtIndex:index ] isSeparatorItem ] ) {
		[ appMenu insertItem:[ NSMenuItem separatorItem ] atIndex:index ] ;
		index++ ;
	}
	darkModeMenuItem = [ [ NSMenuItem alloc ] initWithTitle:@"Use Dark Mode" action:@selector(toggleDarkMode:) keyEquivalent:@"" ] ;
	[ darkModeMenuItem setTarget:self ] ;
	[ darkModeMenuItem setState:( appDarkMode ) ? NSOnState : NSOffState ] ;
	[ appMenu insertItem:darkModeMenuItem atIndex:index ] ;
}

- (void)applyAppAppearance
{
	NSAppearance *appearance ;
	NSArray *windows ;
	int i ;

	appearance = [ NSAppearance appearanceNamed:( appDarkMode ) ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua ] ;
	if ( [ NSApp respondsToSelector:@selector(setAppearance:) ] ) [ NSApp setAppearance:appearance ] ;
	windows = [ NSApp windows ] ;
	for ( i = 0; i < [ windows count ]; i++ ) {
		NSWindow *window = [ windows objectAtIndex:i ] ;
		if ( [ window respondsToSelector:@selector(setAppearance:) ] ) [ window setAppearance:appearance ] ;
		CMApplyAppearanceRecursively( [ window contentView ], appearance ) ;
		[ [ window contentView ] setNeedsDisplay:YES ] ;
	}
	if ( darkModeMenuItem ) [ darkModeMenuItem setState:( appDarkMode ) ? NSOnState : NSOffState ] ;
}

- (void)setDarkModeState:(Boolean)state save:(Boolean)savePreference
{
	appDarkMode = state ;
	[ self applyAppAppearance ] ;
	if ( savePreference && config ) {
		[ config setInt:( appDarkMode ) ? 1 : 0 forKey:kAppDarkMode ] ;
		[ config savePlist ] ;
	}
}

// global
Boolean gFinishedInitialization = NO ;
Boolean gSplashShowing = NO ;
NSThread *mainThread ;

static void CMApplyAppearanceRecursively( id object, NSAppearance *appearance )
{
	NSArray *subviews ;
	int i ;

	if ( object == nil || appearance == nil ) return ;
	if ( [ object respondsToSelector:@selector(setAppearance:) ] ) [ object setAppearance:appearance ] ;
	if ( [ object respondsToSelector:@selector(subviews) ] ) {
		subviews = [ object subviews ] ;
		for ( i = 0; i < [ subviews count ]; i++ ) CMApplyAppearanceRecursively( [ subviews objectAtIndex:i ], appearance ) ;
	}
}

static NSString *CMXMLRPCRawReceiveStream( Modem *modem )
{
	NSMutableString *result ;
	NSString *chunk ;
	Transceiver *transceiver ;
	Module *receiver ;
	int i, count ;

	if ( modem == nil ) return @"" ;
	result = [ NSMutableString string ] ;
	count = [ modem selectedTransceiver ] ;
	if ( count < 1 ) count = 1 ;
	if ( count > 2 ) count = 2 ;
	for ( i = 0; i < count; i++ ) {
		transceiver = ( i == 0 ) ? [ modem transceiver1 ] : [ modem transceiver2 ] ;
		if ( transceiver == nil ) continue ;
		receiver = [ transceiver receiver ] ;
		if ( receiver == nil ) continue ;
		chunk = [ receiver stream ] ;
		if ( [ chunk length ] > 0 ) [ result appendString:chunk ] ;
	}
	return result ;
}

static Boolean CMXMLRPCIsReceiveCommand( NSString *text )
{
	NSString *trimmed ;

	if ( text == nil ) return NO ;
	trimmed = [ text stringByTrimmingCharactersInSet:[ NSCharacterSet whitespaceAndNewlineCharacterSet ] ] ;
	if ( [ trimmed length ] == 0 ) return NO ;
	if ( [ trimmed isEqualToString:@"^r" ] || [ trimmed isEqualToString:@"^R" ] ) return YES ;
	if ( [ trimmed length ] == 1 ) {
		unichar ch = [ trimmed characterAtIndex:0 ] ;
		if ( ch == 0x12 || ch == 0x05 ) return YES ;
	}
	return NO ;
}

- (void)handleXMLRPCRequest:(NSMutableDictionary*)request
{
	NSString *method, *version, *text ;
	NSArray *params, *methods ;
	Modem *modem ;
	NSData *bytes ;
	id param ;

	method = [ request objectForKey:@"method" ] ;
	params = [ request objectForKey:@"params" ] ;
	modem = [ stdManager currentModem ] ;
	if ( [ method isEqualToString:@"fldigi.name" ] ) {
		[ request setObject:@"cocoaModem 2.1rc4" forKey:@"result" ] ;
		[ request setObject:@"string" forKey:@"type" ] ;
		return ;
	}
	if ( [ method isEqualToString:@"fldigi.version" ] ) {
		version = [ [ NSBundle mainBundle ] objectForInfoDictionaryKey:@"CFBundleVersion" ] ;
		[ request setObject:( version ) ? version : @"unknown" forKey:@"result" ] ;
		[ request setObject:@"string" forKey:@"type" ] ;
		return ;
	}
	if ( [ method isEqualToString:@"fldigi.list" ] ) {
		methods = [ NSArray arrayWithObjects:@"fldigi.list", @"fldigi.name", @"fldigi.version", @"main.abort", @"main.get_trx_state", @"main.get_trx_status", @"main.rx", @"main.tx", @"rx.get_data", @"rxtx.get_data", @"text.add_tx", @"text.add_tx_bytes", nil ] ;
		[ request setObject:methods forKey:@"result" ] ;
		[ request setObject:@"array" forKey:@"type" ] ;
		return ;
	}
	if ( modem == nil ) {
		[ request setObject:@"fault" forKey:@"type" ] ;
		[ request setObject:[ NSNumber numberWithInt:-32000 ] forKey:@"faultCode" ] ;
		[ request setObject:@"No active modem" forKey:@"faultString" ] ;
		return ;
	}
	if ( [ method isEqualToString:@"main.tx" ] ) {
		[ stdManager switchCurrentModemToTransmit:YES ] ;
		[ request setObject:@"type" forKey:@"type" ] ;
		[ request setObject:@"nil" forKey:@"type" ] ;
		return ;
	}
	if ( [ method isEqualToString:@"main.rx" ] ) {
		[ stdManager flushCurrentModem ] ;
		[ request setObject:@"nil" forKey:@"type" ] ;
		return ;
	}
	if ( [ method isEqualToString:@"main.abort" ] ) {
		[ stdManager flushCurrentModem ] ;
		[ request setObject:@"nil" forKey:@"type" ] ;
		return ;
	}
	if ( [ method isEqualToString:@"main.get_trx_state" ] || [ method isEqualToString:@"main.get_trx_status" ] ) {
		[ request setObject:( [ modem currentTransmitState ] ) ? @"tx" : @"rx" forKey:@"result" ] ;
		[ request setObject:@"string" forKey:@"type" ] ;
		return ;
	}
	if ( [ method isEqualToString:@"text.add_tx" ] || [ method isEqualToString:@"text.add_tx_bytes" ] ) {
		text = @"" ;
		if ( [ params count ] > 0 ) {
			param = [ params objectAtIndex:0 ] ;
			if ( [ param isKindOfClass:[ NSData class ] ] ) {
				text = [ [ NSString alloc ] initWithData:param encoding:kTextEncoding ] ;
				if ( text == nil ) text = [ [ NSString alloc ] initWithData:param encoding:NSISOLatin1StringEncoding ] ;
				if ( text == nil ) text = [ [ NSString alloc ] initWithString:@"" ] ;
				[ text autorelease ] ;
			}
			else {
				text = param ;
			}
		}
		if ( CMXMLRPCIsReceiveCommand( text ) ) {
			[ modem setStream:[ NSString stringWithFormat:@"%c", 5 /* %[rx] */ ] ] ;
			[ request setObject:@"nil" forKey:@"type" ] ;
			return ;
		}
		[ modem setStream:text ] ;
		[ modem externalTransmitTextAppended ] ;
		[ request setObject:@"nil" forKey:@"type" ] ;
		return ;
	}
	if ( [ method isEqualToString:@"rx.get_data" ] || [ method isEqualToString:@"rxtx.get_data" ] ) {
		text = CMXMLRPCRawReceiveStream( modem ) ;
		if ( text == nil ) text = @"" ;
		bytes = [ text dataUsingEncoding:kTextEncoding allowLossyConversion:YES ] ;
		[ request setObject:( bytes ) ? bytes : [ NSData data ] forKey:@"result" ] ;
		[ request setObject:@"base64" forKey:@"type" ] ;
		return ;
	}
	if ( [ method isEqualToString:@"tx.get_data" ] ) {
		text = CMXMLRPCRawReceiveStream( modem ) ;
		bytes = [ NSData data ] ;
		[ request setObject:( bytes ) ? bytes : [ NSData data ] forKey:@"result" ] ;
		[ request setObject:@"base64" forKey:@"type" ] ;
		return ;
	}
	[ request setObject:@"fault" forKey:@"type" ] ;
	[ request setObject:[ NSNumber numberWithInt:-32601 ] forKey:@"faultCode" ] ;
	[ request setObject:[ NSString stringWithFormat:@"Unsupported XML-RPC method %@", method ] forKey:@"faultString" ] ;
}

- (int)appLevel
{
	return 0 ;
}

//  check if option/control/shift keys have changed
//  send to current active modem
- (void)modifierKeyCheck:(NSNotification*)notify
{
	unsigned int flags ;
	
	flags = [ [ notify object ] modifierFlags ] & ( NSAlternateKeyMask | NSShiftKeyMask | NSControlKeyMask ) ;
	
	if ( flags != lastModifierFlags ) {
		// notify others of control key change (for callsign capture, etc)
		lastModifierFlags = flags ;
		[ [ NSNotificationCenter defaultCenter ] postNotificationName:@"ModifierFlagsChanged" object:self ] ;
	}
}

- (unsigned int)keyboardModifierFlags
{
	return lastModifierFlags ;
}

//  Note: for Tiger, ( floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_3 )
//  Tiger 10.4.8 appears to be 824.41.
- (float)OSVersion
{
	return NSAppKitVersionNumber ;
}

//  command key equivalents for macro keys 
//  send to current active modem
- (void)macroKeyCheck:(NSNotification*)notify
{
	NSEvent *event ;
	int key, index, sheet ;
	unsigned int flags ;
	Boolean option, shift ;
	ContestInterface *modem ;

	event = [ notify object ] ;
	if ( [ [ event characters ] length ] <= 0 ) return ;		// v0.35
	
	key = [ [ event charactersIgnoringModifiers ] characterAtIndex:0 ] ;
	
	if ( key >= '1' && key <= '9' ) index = key-'1' ;
	else if ( key == '0' ) index = 9 ;
	else if ( key == '-' ) index = 10 ;
	else if ( key == '=' ) index = 11 ;
	else return ;
	
	flags = [ event modifierFlags ] ;
	option = ( ( flags & NSAlternateKeyMask ) != 0 ) ;
	shift = ( ( flags & NSShiftKeyMask ) != 0 ) ;
	
	sheet = 0 ;
	if ( option ) {
		if ( shift ) sheet = 2 ; else sheet = 1 ;
	}
	
	modem = (ContestInterface*)[ stdManager currentModem ] ;		
	if ( modem ) {
		if ( contestMode ) {
			//  ask contestManager to execute (common) contest macro
			[ stdManager executeContestMacroFromShortcut:index sheet:sheet modem:modem ] ;
		}
		else {
			// ask modem to execute macro
			[ modem executeMacro:index sheetNumber:sheet ] ;
		}
	}
}

- (void)sysBeep:(NSNotification*)notify
{
}

- (UTC*)clock
{
	return utc ;
}

//  insternal UTC clock server
- (void)tick:(NSTimer*)timer
{
	struct tm *time ;
	
	time = [ utc setTime ] ;
	[ [ NSNotificationCenter defaultCenter ] postNotificationName:@"SecondTick" object:utc ] ;
	
	if ( minute != time->tm_min ) {
		minute = time->tm_min ;
		[ [ NSNotificationCenter defaultCenter ] postNotificationName:@"MinuteTick" object:utc ] ;
	}
}

/* local */
- (void)getLocalHostIP
{
	NSEnumerator *addresses ; 
	NSString *address ;
	NSHost *currentHost ;
	const char *ipAddr, *s ;
	
	currentHost = [ NSHost currentHost ] ;

	addresses = [ [ currentHost addresses ] objectEnumerator ] ;
			
	strcpy( localHostIP, "127.0.0.1" ) ;
	while ( ( address = [ addresses nextObject ] ) != nil ) {
		ipAddr = [ address cStringUsingEncoding:kTextEncoding ] ;
		s = ipAddr ;
		while ( *s ) {
			if ( *s++ == '.' ) {
				strcpy( localHostIP, ipAddr ) ;
				return ;
			}
		}
	}
}

/* local */
- (NSArray*)createNetInputPorts:(Preferences*)pref
{
	NSArray *serviceArray, *ipArray, *portArray, *passwordArray ;
	NSMutableArray *array ;
	NetReceive *netAudio ;
	NSString *service, *ip, *portNum, *password ;
	const char *ipAddr ;
	int i, port ;
	
	array = [ [ NSMutableArray alloc ] initWithCapacity:4 ] ;
	serviceArray = [ pref arrayForKey:kNetInputServices ] ;
	ipArray = [ pref arrayForKey:kNetInputAddresses ] ;
	portArray = [ pref arrayForKey:kNetInputPorts ] ;
	passwordArray = [ pref arrayForKey:kNetInputPasswords ] ;
	
	//  v0.64d use NetAudio only if in Preferences
	if ( [ pref hasKey:kEnableNetAudio ] == NO ) return array ;
	if ( [ pref intValueForKey:kEnableNetAudio ] == 0 ) return array ;
	
	//  sanity check
	if ( !serviceArray || [ serviceArray count ] < 4 ) return array ;
	if ( !ipArray || [ ipArray count ] <= 0 ) return array ;
	if ( !portArray || [ portArray count ] <= 0 ) return array ;

	for ( i = 0; i < 4; i++ ) {
		netAudio = nil ;
		service = serviceArray[i] ;
		
		//  check if service name, IP address or port number is specified
		if ( service && [ service length ] > 0 ) {
			netAudio = [ [ NetReceive alloc ] initWithService:service delegate:nil samplesPerBuffer:512 ] ;
		}
		else {
			ip = ipArray[i] ;
			portNum = portArray[i] ;
			if ( ( ip && [ ip length ] ) || ( portNum && [ portNum length ] ) ) {
			
				if ( ip && [ ip length ] > 0 ) {
					ipAddr = [ ip cStringUsingEncoding:kTextEncoding ] ;
				}
				else {
					if ( localHostIP[0] == 0 ) [ self getLocalHostIP ] ;
					ipAddr = localHostIP ;
				}
				port = ( portNum && [ portNum length ] ) ? [ portNum intValue ] : 52800 ;
				netAudio = [ [ NetReceive alloc ] initWithAddress:ipAddr port:port delegate:nil samplesPerBuffer:512 ] ;
			}
		}
		if ( netAudio ) {
			password = passwordArray[i] ;
			if ( password && [ password length ] > 0 ) [ netAudio setPassword:password ] ;
			[ array addObject:netAudio ] ;
		}
	}
	return array ;
}

- (NSArray*)createNetPorts:(Preferences*)pref isInput:(Boolean)isInput
{
	NSArray *prefArray ;
	NSMutableArray *array ;
	NetAudio *netAudio ;
	NSString *str ;
	char cstr[64] ;
	int count, i, j, ip1, ip2, ip3, ip4, port ;
	
	array = [ [ NSMutableArray alloc ] initWithCapacity:4 ] ;
	prefArray = [ pref arrayForKey:( isInput ) ? kNetInputServices : kNetOutputServices ] ;
	
	if ( prefArray != nil ) {
	
		count = [ prefArray count ] ;
		for ( j = 0; j < count; j++ ) {

			netAudio = nil ;
			str = prefArray[j] ;
			
			if ( str && [ str length ] > 0 ) {
			
				ip1 = ip2 = ip3 = ip4 = port = -1 ;
				if ( isInput ) {
					//  NetReceive
					sscanf( [ str cString ], "%d.%d.%d.%d:%d", &ip1, &ip2, &ip3, &ip4, &port ) ;
					if ( ip1 < 0 || ip2 < 0 || ip3 < 0 || ip4 < 0 || port < 0 ) {
						//  get NetReceive using service name
						netAudio = [ [ NetReceive alloc ] initWithService:str delegate:nil samplesPerBuffer:512 ] ;
					}
					else {
						// get NetReceive with ip:port
						strcpy( cstr, [ str cString ] ) ;
						for ( i = 0; i < 64; i++ ) {
							if ( cstr[i] == ':' ) {
								cstr[i] = 0 ;
								break ;
							}
						}
						netAudio = [ [ NetReceive alloc ] initWithAddress:cstr port:port delegate:nil samplesPerBuffer:512 ] ;
					}
				}
				else {
					//  NetSend, either service name, or servicename:port
					strcpy( cstr, [ str cString ] ) ;
					for ( i = 0; i < 64; i++ ) {
						//  look for port number
						if ( cstr[i] == ':' || cstr[i] <= 0 ) break ;
					}
					if ( cstr[i] ) {
						//  terminate string before port number
						sscanf( &cstr[i+1], "%d", &port ) ;
						if ( port >= 0 ) cstr[i] = 0 ;
					}
					str = [ NSString stringWithCString:cstr encoding:kTextEncoding ] ; 
					netAudio = [ [ NetSend alloc ] initWithService:str delegate:nil samplesPerBuffer:512 ] ;
					if ( port >= 0 && netAudio != nil ) {
						//  try setting the port number
						if ( [ (NetSend*)netAudio setPortNumber:port ] == NO ) netAudio = nil ;
					}
				}
			}
			if ( netAudio ) [ array addObject:netAudio ] ;
		}
	}
	return array ;
}

- (const char*)localHostIP 
{
	if ( localHostIP[0] == 0 ) [ self getLocalHostIP ] ;			// v0.53b deferred getLocalIP (uses 2.2 seconds)
	return localHostIP ;
}

//  (Private API)
- (void)setInterface:(NSControl*)object to:(SEL)selector
{
	[ object setAction:selector ] ;
	[ object setTarget:self ] ;
}

//  v0.71
- (void)setAllowShiftJISForPSK:(Boolean)state
{
	int n ;
	
	allowShiftJIS = state ;
	if ( state == NO ) {
		//  if preference is not set, check if we are Japanese Mac OS X, if not, disable Command-j.
		n = [ NSLocalizedString( @"Use Shift-JIS", nil ) characterAtIndex:0 ] ;
		if ( n != '1' ) {
			[ psk31UnicodeInterfaceItem setKeyEquivalent:@"" ] ;
			return ;
		}
	}
	//  preference sets allow shift-JIS
	[ psk31UnicodeInterfaceItem setKeyEquivalent:@"j" ] ;
}

//	v1.02c
- (void)updateDirectAccessFrequency
{
	float freq ;
	
	freq = [ stdManager selectedFrequency ] ; 
	[ directFrequencyAccessField setFloatValue:freq ] ;
}

//  v1.02e
- (void)setSpeakAssistInfo:(NSString*)string
{
	if ( speakAssistInfo ) [ speakAssistInfo autorelease ] ;
	speakAssistInfo = [ [ NSString alloc ] initWithString:string ] ;
}

- (IBAction)speakAlertInfo:(id)sender
{
	if ( speakAssistInfo == nil ) {
		[ self speakAssist:@"No alert info." ] ;
		return ;
	}
	[ self speakAssist:speakAssistInfo ] ;
}
	
- (void)awakeFromNib
{
	NSWindow *window ;
	Preferences *tempPref ;
	Boolean isBrushedMetal ;
	Boolean isLite ;
	NSArray *netInputs, *netOutputs ;
	NSBundle *bundle ;
	NSData *jisdata ;
	NSString *path ;
	const char *str ;
	int i ;

	if ( [ NSApp respondsToSelector:@selector(setAppearance:) ] ) {
		[ NSApp setAppearance:[ NSAppearance appearanceNamed:NSAppearanceNameAqua ] ] ;
	}
	
	//	v1.01b
	voiceAssist = NO ;
	//	v1.02d
	assistVoice = [ [ Speech alloc ] initWithVoice:nil ] ;
	[ assistVoice setVerbatim:YES ] ;
	[ assistVoice setMute:NO ] ;
	[ assistVoice setSpell:NO ] ;
	//	v1.02e
	speakAssistInfo = nil ;
	
	//  v0.96d
	mainReceiverVoice = [ [ Speech alloc ] initWithVoice:nil ] ;
	subReceiverVoice = [ [ Speech alloc ] initWithVoice:nil ] ;
	transmitterVoice = [ [ Speech alloc ] initWithVoice:nil ] ;
	
	//  v0.78
	auralMonitor = nil ;
	audioManager = nil ;
	initAudioUtils() ;
		
	//  set up local IP defer until needed
	//  [ self getLocalHostIP ] ;
	localHostIP[0] = 0 ;
	
	mainThread = [ NSThread currentThread ] ;
	
	splashScreen = [ [ splash alloc ] init ] ;
	[ self showSplash:@"Welcome" ] ;
	
	//  v0.70 read Shift-JIS Tables from resource
	allowShiftJIS = NO ;
	for ( i = 0; i < 65536; i++ ) jisToUnicode[i] = unicodeToJis[i] = 0 ;
	bundle = [ NSBundle mainBundle ];
	path = [ [ bundle bundlePath ] stringByAppendingString:@"/Contents/Resources/jisToUni.dat" ] ;
	if ( path ) {
		jisdata = [ NSData dataWithContentsOfFile:path ] ;
		if ( jisdata ) memcpy( jisToUnicode, [ jisdata bytes ], 65536*2 ) ;
	}
	path = [ [ bundle bundlePath ] stringByAppendingString:@"/Contents/Resources/uniToJis.dat" ] ;
	if ( path ) {
		jisdata = [ NSData dataWithContentsOfFile:path ] ;
		if ( jisdata ) memcpy( unicodeToJis, [ jisdata bytes ], 65536*2 ) ;
		//  v0.81 Shift-JIS slashed zero
		unicodeToJis[216*2] = 0 ;
		unicodeToJis[216*2+1] = 216 ;
	}
	
	// initialize CoreModem framework
	[ [ CoreModem alloc ] init ] ;
	
	contestMode = NO ;
	
	//	v1.02b
	[ self setInterface:directFrequencyAccessField to:@selector(directFrequencyAccessed:) ] ;
	
	//  v0.70
	[ self setInterface:psk31UnicodeInterfaceItem to:@selector(useUnicodeForPSKChanged:) ] ;
	[ self setInterface:psk31RawInterfaceItem to:@selector(useRawForPSKChanged:) ] ;
	
	//  accepts SysBeep messages here
	[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(sysBeep:) name:@"SysBeep" object:nil ] ;
	//  create sleep manager
	sleepManager = [ [ ModemSleepManager alloc ] initWithApplication:self ] ;
	
	selectedString[0] = 0 ;
	selectedTextView = nil ;
	[ splashScreen positionWindow ] ;
	gSplashShowing = YES ;
	
	//  check Plist (temporary copy) to see if which UI and if we should search for NetAudio devices
	
	tempPref = [ [ Preferences alloc ] init ] ;
	[ tempPref fetchPlist:NO ] ;
	appDarkMode = ( [ tempPref intValueForKey:kAppDarkMode ] != 0 ) ;
	[ self installAppearanceMenuItem ] ;
	[ self applyAppAppearance ] ;
	
	Boolean dontOpenRouter = [ tempPref intValueForKey:kNoOpenRouter ] ;
	
	//	v0.89  Digital Interfaces (cocoaPTT, MacLoggerDX, microHAM devices, etc
	if ( dontOpenRouter ) {
		digitalInterfaces = [ [ DigitalInterfaces alloc ] initWithoutRouter ] ;
	}
	else {
		digitalInterfaces = [ [ DigitalInterfaces alloc ] init ] ;
	}
	macroScripts = [ [ MacroScripts alloc ] init ] ;				//  v0.89
	
	isBrushedMetal = isLite = NO ;
	
	NSString *prefString = [ tempPref stringValueForKey:kAppearancePrefs ] ;
	if ( prefString != nil ) {												// v0.42 Leopard returning nil cString
		str = [ prefString cStringUsingEncoding:kTextEncoding ] ;
		if ( str != nil ) {
			if ( strlen( str ) >= 9 && str[8] == '1' ) isLite = YES ;
			else {
				isBrushedMetal = ( str == nil || strlen( str ) < 6 || str[5] == '1' ) ;	
			}
		}
	}
	//  v0.64d
	Boolean useNetAudio = NO ;
	if ( [ tempPref hasKey:kEnableNetAudio ] ) {
		if ( [ tempPref intValueForKey:kEnableNetAudio ] != 0 ) useNetAudio = YES ;
	}
	if ( useNetAudio ) {
		//  v0.47
		netInputs = [ self createNetInputPorts:tempPref ] ;
		netOutputs = [ self createNetPorts:tempPref isInput:NO ] ;	
	}
	else {
		netInputs = [ [ NSMutableArray alloc ] initWithCapacity:0 ] ;
		netOutputs = [ [ NSMutableArray alloc ] initWithCapacity:0 ] ;
	}
	
	//  v0.76s release thread for 60 ms to allow other things to run
	[ NSThread sleepUntilDate:[ NSDate dateWithTimeIntervalSinceNow:0.06 ] ] ;

	//  v0.50 shared FSKHub
	fskHub = [ [ FSKHub alloc ] init ] ;
	//  create UserInfo (must be before StdManager setupWindow)
	userInfo = [ [ UserInfo alloc ] init ] ;
	
	//  v0.78 aural monitor and AudioManager
	audioManager = [ [ AudioManager alloc ] init ] ;
	auralMonitor = [ [ AuralMonitor alloc ] init ] ;

	//  select UI (must be set up before modems, see createModems futher down)
	[ stdManager setupWindow:isBrushedMetal lite:isLite ] ;	

	[ stdManager updateQSOWindow ] ;
	
	//  don't allocate About panel until needed
	about = nil ; 
	[ self showSplash: @"Discover Audio Devices" ] ;

	//  configure from Preference
	[ self showSplash: @"Creating User Configuration" ] ;
	
	config = [ [ Config alloc ] initWithApp:self ] ;
	[ config awakeFromApplication ] ;
	
	//  create the modems based on what is asked for in the Preference panel
	
	// 0.54 use config as prefs
	[ stdManager createModems:config startModemsFromPlist:tempPref ] ;
	[ tempPref release ] ;
	
	//  v0.53b 
	//  updateDeviceWithActualSamplingRate in ExtendedAudioChannel is initially inhibited by finishedInitializing in the app delegate
	//  we set setFinishedInitializing from here and after all modems have finished initialized	
	gFinishedInitialization = YES ;
	
	//  AppleScript support
	appleScript = [ [ AppDelegate alloc ] initFromApplication:self ] ;
	xmlrpcServer = [ [ CMXMLRPCServer alloc ] initWithApplication:self ] ;
	[ xmlrpcServer start ] ;
	if ( [ self mainWindow ] ) [ [ self mainWindow ] setTitle:@"cocoaModem 2.1rc4" ] ;
	
	[ [ NSApp delegate ] setIsLite:isLite ] ;

	//  set up default preferences in case Plist does not exist or is messed up  moved here 0.54
	[ self showSplash:@"Reading preferences" ] ;
	[ config setupDefaultPreferences ] ; 	
	
	//  now update preferences from the Plist file, if file exists
	[ config fetchPlist:YES ] ;
	
	//  then, update preferences from Plist file
	[ self showSplash:@"Updating preferences" ] ;
	[ config updatePreferences ] ;
	
	//  update sources for modems in the interfaces  v0.53d
	//  [ stdManager updateModemSources ] ;
	
	//  now make window visible and set us as delegate
	window = [ stdManager windowObject ] ;
	if ( isLite ) {
		//  check if we want to keep a Lite window hidden anyway
		if ( [ config intValueForKey:kHideWindow ] == 0 ) {
			[ window orderFront:self ] ;
			[ (LiteRTTY*)[ stdManager wfRTTYModem ] showControlWindow:YES ] ;
			[ [ NSApp delegate ] setWindowIsVisible:YES ] ;
		}
		else {
			[ (LiteRTTY*)[ stdManager wfRTTYModem ] showControlWindow:NO ] ;
			[ [ NSApp delegate ] setWindowIsVisible:NO ] ;
		}
	}
	else {
		[ window orderFront:self ] ;
		[ [ NSApp delegate ] setWindowIsVisible:YES ] ;
	}
	
	[ window makeFirstResponder:self ] ;
	
	//  add notification observer for option key
	lastModifierFlags = 0 ;
	[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(modifierKeyCheck:) name:@"OptionKey" object:nil ] ;
	[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(macroKeyCheck:) name:@"MacroKeyboardShortcut" object:nil ] ;

	//  set up cocoaModem timer
	utc = [ [ UTC alloc ] init ] ;
	minute = -1 ;
	[ NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick:) userInfo:self repeats:YES ] ;
	
	//  start off by selecting the interfactive interface
	[ self switchInterfaceMode:0 ] ;
	
	//  close splashscreen from a timer - Leopard bug? v0.37
	//[ NSTimer scheduledTimerWithTimeInterval:0.25 target:splashScreen selector:@selector(close) userInfo:self repeats:NO ] ;
	[ splashScreen remove ] ;
	gSplashShowing = NO ;
	
	if ( [ config booleanValueForKey:kVoiceAssist ] ) {
		[ self toggleVoiceAssist:voiceAssistMenuItem ] ;			//  v1.01b
		[ stdManager speakModemSelection ] ;						//  v1.02c
		[ self speakAssist:@" , " ] ;
		[ self updateDirectAccessFrequency ] ;						//  v1.02c
	}
}

- (NSWindow*)mainWindow
{
	return [ stdManager windowObject ] ;
}

//  v0.50
- (FSKHub*)fskHub
{
	return fskHub ;
}

- (StdManager*)stdManagerObject
{
	return stdManager ;
}

- (UserInfo*)userInfoObject
{
	return userInfo ;
}

- (AuralMonitor*)auralMonitor
{
	return auralMonitor ;
}

- (AudioManager*)audioManager
{
	return audioManager ;
}

- (NSMenuItem*)qsoEnableItem
{
	return qsoInterfaceEnableItem ;
}

//  display message on splash screen
- (void)showSplash:(NSString*)msg
{
	[ splashScreen showMessage:NSLocalizedString( msg, nil ) ] ;		// v0.39, v0.70  translate localization here
}

- (Boolean)speakAssist:(NSString*)assist 
{
	if ( [ self voiceAssist ] ) {
		[ assistVoice queuedSpeak:assist ] ;
		return YES ;
	}
	return NO ;
}

- (void)flushSpeakAssist
{
	[ assistVoice clearVoice ] ;
}

- (IBAction)showPreferences:(id)sender
{
	[ config showPreferencePanel:self ] ;
}

- (IBAction)showQSO:(id)sender
{
	[ stdManager toggleQSOShowing ] ;
}

//  v1.01a
- (IBAction)selectQSOCall:(id)sender
{
	[ stdManager selectQSOCall ] ;
	[ self speakAssist:@"call sign" ] ;
}

//  v1.01a		
- (IBAction)selectQSOName:(id)sender
{
	[ stdManager selectQSOName ] ;
	[ self speakAssist:@"name" ] ;
}

//  v1.01b		
- (IBAction)toggleVoiceAssist:(id)sender
{
	voiceAssist = ( [ sender state ] == NSOffState ) ;
	[ sender setState:( voiceAssist ) ? NSOnState : NSOffState ] ;
	if ( voiceAssist ) {
		[ assistVoice setVoiceEnable:YES ] ;
		[ assistVoice speak:@"Voice Assist On." ] ;

	}
	else {
		[ assistVoice speak:@"Voice Assist Offff." ] ;
		[ assistVoice setVoiceEnable:NO ] ;
	}
}

- (IBAction)toggleDarkMode:(id)sender
{
	[ self setDarkModeState:( [ sender state ] == NSOffState ) save:YES ] ;
}

//  update appearance from "General" preferences
- (void)setAppearancePrefs:(NSMatrix*)appearancePrefs
{
	int i, count, state ;
	NSButton *b ;
	
	count = [ appearancePrefs numberOfRows ] ;
	for ( i = 0; i < count; i++ ) {
		b = [ appearancePrefs cellAtRow:i column:0 ] ;
		state = [ b state ] ;
		if ( state == NSOnState ) {
			switch ( i ) {
			case 0:
				//  enable command Q
				[ quitMenu setKeyEquivalent:@"q" ] ;
				break ;
			}
		}
		else {
			switch ( i ) {
			case 0:
				//  disable command Q
				[ quitMenu setKeyEquivalent:@"" ] ;
				break ;
			}
		}
	}
}

/* local */
- (void)enableContestMenus:(Boolean)state
{
	[ resumeMenuItem setEnabled:state ] ;
	[ newMenuItem setEnabled:state ] ;
	[ recentMenuItem setEnabled:state ] ;
}

//  mode 0 - QSO mode, 1 = Contest mode
- (void)switchInterfaceMode:(int)mode
{
	[ contestInterfaceItem setState:(mode==1) ] ;
	[ qsoInterfaceItem setState:(mode==0) ] ;

	[ stdManager activateModems:YES ] ;
	[ self enableContestMenus:YES ] ;
	
	[ stdManager useContestMode:(mode==1) ] ;
			
	contestMode = (mode==1) ;
	[ stdManager updateQSOWindow ] ;

	//  close any open config if interface changed
	[ self closeConfigPanels ] ;
}

- (Boolean)contestModeState
{
	return contestMode ;
}

//  v0.70
- (void)saveSelectedString:(NSString*)string view:(NSTextView*)view
{
	int length, i ;
	unichar u ;
	char *s ;
	
	selectedTextView = view ;
	length = [ string length ] ;
	if ( length > 32 ) length = 32 ;
	s = selectedString ;
	for ( i = 0; i < length; i++ ) {
		u = [ string characterAtIndex:i ] ;
		*s++ = ( ( int )u ) & 0xff ;				//  only allow ASCII
	}
	*s = 0 ;
}

//  ask all interfaces to close their config panels
//  this is typically used when interface or modem changes
- (void)closeConfigPanels
{
	[ stdManager closeConfigPanels ] ;
}

//  show config window of current mode of current interface
- (IBAction)showConfig:(id)sender
{
	[ stdManager showConfigPanel ] ;
}

- (IBAction)showSoftRock:(id)sender
{
	[ stdManager showSoftRock ] ;
}

//  show About panel, allocate and load Nib file if needed
- (IBAction)showAboutPanel:(id)sender
{
	if ( !about ) about = [ [ About alloc ] initFromNib ] ;
	[ about showPanel ] ;
}

//	v1.02b
- (IBAction)showDirectFrequencyAccess:(id)sender
{
	[ [ directFrequencyAccessField window ] makeKeyAndOrderFront:self ] ;
}

//	v1.02b
- (IBAction)directFrequencyAccess:(id)sender
{
	[ self updateDirectAccessFrequency ] ;
	[ [ directFrequencyAccessField window ] makeKeyAndOrderFront:self ] ;
	[ directFrequencyAccessField selectText:self ] ;
	[ self speakAssist:@" Enter frequency - ending with a carriage return. " ] ;
}

- (void)speakContentsOfCurrentFrequency
{
	int ifreq ;
	float freq ;
	
	freq = [ directFrequencyAccessField floatValue ] ;
	
	if ( freq < 1 ) {
		[ self speakAssist:@" Modem turned off. " ] ;
		return ;
	}
	ifreq = freq ;
	if ( fabs( ifreq-freq ) < .05 ) {
		[ self flushSpeakAssist ] ;
		[ self speakAssist:[ NSString stringWithFormat:@"Tuned to %d Hertz ", ifreq ] ] ;
	}
	else {
		[ self flushSpeakAssist ] ;
		[ self speakAssist:[ NSString stringWithFormat:@"Tuned to %.1f Hertz ", freq ] ] ;
	}
}

- (IBAction)speakCurrentFrequency:(id)sender
{
	[ self speakContentsOfCurrentFrequency ] ;
}

//	v1.02c
- (IBAction)selectNextModem:(id)sender 
{
	[ stdManager selectNextModem ] ;
}

//	v1.02c
- (IBAction)selectPreviousModem:(id)sender 
{
	[ stdManager selectPreviousModem ] ;
}

- (IBAction)showRTTYScope:(id)sender
{
	[ stdManager displayRTTYScope ] ;
}

- (IBAction)showAuralMonitor:(id)sender
{
	[ auralMonitor showWindow ] ;
}

- (IBAction)showUserInfo:(id)sender
{
	[ userInfo showSheet:[ stdManager windowObject ] ] ;
}

//  open Cabrillo sheet in contest manager
- (IBAction)showContestInfo:(id)sender
{
	[ stdManager showCabrilloInfo ] ;
}

- (IBAction)switchToTransmit:(id)sender
{
	[ [ stdManager windowObject ] makeKeyWindow ] ;				// v0.33
	[ stdManager switchCurrentModemToTransmit:YES ] ;
}

- (IBAction)switchToReceive:(id)sender
{
	[ stdManager switchCurrentModemToTransmit:NO ] ;
}

- (IBAction)flushToReceive:(id)sender
{
	[ stdManager flushCurrentModem ] ;
}

//	v0.70  Added menu item to Interface Menu
- (void)useUnicodeForPSKChanged:(id)sender
{
	[ self setUseUnicodeForPSK:( [ psk31UnicodeInterfaceItem state ] == NSOffState ) ] ;
}

//  v0.70
- (Boolean)useUnicodeForPSK
{
	return ( [ psk31UnicodeInterfaceItem state ] == NSOnState ) ;
}

//  v0.70
- (void)setUseUnicodeForPSK:(Boolean)state
{
	Boolean useShiftJIS ;
	int n ;

	//  v0.71
	if ( allowShiftJIS == NO ) {
		//  if pref is not set, check if Japanese Mac OS X
		n = [ NSLocalizedString( @"Use Shift-JIS", nil ) characterAtIndex:0 ] ;
		if ( n != '1' ) {
			if ( state == YES ) {
				[ [ NSAlert alertWithMessageText:NSLocalizedString( @"Shift-JIS setting ignored.", nil ) defaultButton:NSLocalizedString( @"OK", nil ) alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString( @"Shift-JIS cannot be turned on", nil ) ] runModal ] ;
			}
			[ stdManager setUseShiftJIS:NO ] ;
			return ;
		}
	}
	[ psk31UnicodeInterfaceItem setState:( state == NO ) ? NSOffState : NSOnState ] ;
	useShiftJIS = ( [ psk31UnicodeInterfaceItem state ] == NSOnState ) ;
	[ stdManager setUseShiftJIS:useShiftJIS ] ;
}

//  v0.70
- (unsigned char*)jisToUnicodeTable
{
	return jisToUnicode ;
}

//  v0.70
- (unsigned char*)unicodeToJisTable ;
{
	return unicodeToJis ;
}

//	(Private API)
//  v0.70
- (void)setUseRawForPSK:(Boolean)state
{
	Boolean useRaw ;
	
	[ psk31RawInterfaceItem setState:( state == NO ) ? NSOffState : NSOnState ] ;
	useRaw = ( [ psk31RawInterfaceItem state ] == NSOnState ) ;
	[ stdManager setUseRawForPSK:useRaw ] ;
}

//	v0.70  Added menu item to Interface Menu
- (void)useRawForPSKChanged:(id)sender
{
	[ self setUseRawForPSK:( [ psk31RawInterfaceItem state ] == NSOffState ) ] ;
}

//	v1.02b
- (void)setDirectFrequencyFieldTo:(float)value
{
	int ivalue ;
	
	ivalue = value ;
	[ directFrequencyAccessField setStringValue:( fabs( ivalue-value ) < 0.05 ) ? [ NSString stringWithFormat:@"%d", ivalue ] : [ NSString stringWithFormat:@"%.1f", value ] ] ;
	[ NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(speakContentsOfCurrentFrequency) userInfo:nil repeats:NO ] ;
}

//	v1.02b  Direct frequency Access
- (void)directFrequencyAccessed:(id)sender
{
	float freq ;
	int ifreq ;
	
	freq = [ sender floatValue ] ;
	if ( freq > 0 ) {
		if ( freq < 400 || freq > 2400 ) {
			ifreq = [ stdManager selectedFrequency ] ;
			if ( ifreq > 0 ) {
				[ sender setStringValue:[ NSString stringWithFormat:@"%d", ifreq ] ] ;
				[ self speakAssist:[ NSString stringWithFormat:@"Frequency out of range, unchanged at %d Hertz.", ifreq ] ] ;
			}
			else [ self speakAssist:@"Frequency out of range " ] ;
		}
		else {
			if ( fabs( [ stdManager selectedFrequency ] - freq ) < 0.1 ) {
				ifreq = freq ;
				if ( fabs( ifreq-freq ) < 0.05 ) {
					[ self speakAssist:[ NSString stringWithFormat:@"Frequency unchanged. Already tuned to %d Hertz.", ifreq ] ] ;
				}
				else {
					[ self speakAssist:[ NSString stringWithFormat:@"Frequency unchanged. Already tuned to %.1f Hertz.", freq ] ] ;
				}
				return ;
			}
			[ stdManager directSetFrequency:freq ] ;
		}
	}
	else {
		[ stdManager directSetFrequency:0 ] ;
	}
}

- (IBAction)selectInterfaceMode:(id)sender
{
	int mode ;
	
	mode = [ sender tag ] ;
	
	//  check to see if any contest has been selected, if not, do nothing
	if ( mode == 1 && ![ stdManager currentContest ] ) return ;

	//  tag 0 - QSO mode, 1 = Contest mode
	[ self switchInterfaceMode:[ sender tag ] ] ;
}

- (IBAction)swapInterfaceMode:(id)sender
{
	//  check to see if any contest has been selected, if not, do nothing
	if ( ![ stdManager currentContest ] ) return ;

	[ self switchInterfaceMode:(contestMode)?0:1 ] ;
}

- (IBAction)qsoCommands:(id)sender
{
	NSString *string ;
	int t ;
	
	//  check if there is a selected string
	string = [ sender title ] ;	
	t = 0 ;
	if ( [ string isEqualToString:@"Copy Callsign" ] ) t = 'C' ;
	else if ( [ string isEqualToString:@"Copy Name" ] ) t = 'N' ;
	
	[ self transferToQSOField:t ] ;
}

- (void)transferToQSOField:(int)t
{
	NSRange range ;
	
	if ( selectedString[0] == 0 ) return ;
	if ( t != 0 ) {
		[ [ stdManager qsoObject ] copyString:selectedString into:t ] ;
		if ( selectedTextView ) {
			//  unselect the field
			[ selectedTextView lockFocus ] ;
			range = [ selectedTextView selectedRange ] ;
			range.length = 0 ;
			[ selectedTextView setSelectedRange:range ] ;
			[ selectedTextView unlockFocus ] ;
			selectedTextView = nil ;
		}
	}
}

- (void)enableContestMenuItems:(Boolean)state
{
	[ qsoInterfaceItem setEnabled:state ] ;
	[ contestInterfaceItem setEnabled:state ] ;
	[ resumeMenuItem setEnabled:state ] ;
	[ newMenuItem setEnabled:state ] ;
	[ recentMenuItem setEnabled:state ] ;
}

//  clean up and save Plist
- (NSApplicationTerminateReply)terminate
{
	int reply ;
	
	if ( ![ stdManager okToQuit ] ) {
		reply = [ [ NSAlert alertWithMessageText:NSLocalizedString( @"database not saved", nil ) defaultButton:NSLocalizedString( @"OK", nil ) alternateButton:nil otherButton:NSLocalizedString( @"Quit anyway", nil ) informativeTextWithFormat:NSLocalizedString( @"save contest", nil ) ] runModal ] ;
		if ( reply != -1 ) return NSTerminateCancel ;
	}
	[ stdManager applicationTerminating ] ;
	if ( xmlrpcServer ) {
		[ xmlrpcServer stop ] ;
		[ xmlrpcServer release ] ;
		xmlrpcServer = nil ;
	}
	
	// v0.50
	if ( fskHub ) {
		[ fskHub closeFSKConnections ] ;
		fskHub = nil ;
	}
	if ( digitalInterfaces ) [ digitalInterfaces terminate:config ] ;

	[ sleepManager release ] ;			// this should deallocate it
	
	[ config setBoolean:[ self voiceAssist ] forKey:kVoiceAssist ] ;
	[ config savePlist ] ;

	//  v0.78
	[ auralMonitor unconditionalStop ] ;
	[ audioManager release ] ;
	
	return NSTerminateNow ;
}

//  called from ModemSleepManager
- (void)putCodecsToSleep
{
	if ( audioManager != nil ) [ audioManager putCodecsToSleep ] ;
}

//  called from ModemSleepManager
- (void)wakeCodecsUp
{
	if ( audioManager != nil ) [ audioManager wakeCodecsUp ] ;
}

//   NSResponder - catches option and shift keys
- (void)flagsChanged:(NSEvent*)event
{
	[ [ NSNotificationCenter defaultCenter ] postNotificationName:@"OptionKey" object:event ] ;
	[ super flagsChanged:event ] ;
}

//   NSResponder - catches command 1 through = keys
//   this usually is caught in the Exhange and Send text views, but is trapped here if they don't see it
- (BOOL)performKeyEquivalent:(NSEvent*)event
{
	int n ;
		
	if ( [ [ event characters ] length ] > 0 ) {		// v0.35
		n = [ [ event charactersIgnoringModifiers ] characterAtIndex:0 ] ;
		if ( ( n >= '0' && n <= '9' ) || n == '-' || n == '=' ) {
			[ [ NSNotificationCenter defaultCenter ] postNotificationName:@"MacroKeyboardShortcut" object:event ] ;
			return YES ;
		}
	}
	return NO ;
}

//  AppleScript support

//  class references
- (ModemManager*)interface
{
	return stdManager ;
}

- (void)changeInterfaceTo:(ModemManager*)which alternate:(Boolean)state
{
	[ self switchInterfaceMode:(state)?1:0 ] ;
}

- (BOOL)windowShouldClose:(id)sender
{
	return NO ;	
}

//  v0.75
- (void)openURLDoc:(NSString*)url
{
	[ [ NSWorkspace sharedWorkspace ] openURL:[ NSURL URLWithString:url ] ] ;
}

//  v0.72
- (IBAction)checkForUpdate:(id)sender
{
	NSString *url, *version ;
	FILE *updateFile ;
	char line[129], *s, *app ;
	int i, len, alert ;
	float latest, current ;

	app = "cocoaModem 2.0" ;
	len = strlen( app ) ;
	url = @"curl -s -m10 -A \"Mozilla/4.0 (compatible; MSIE 5.5; Windows 98)\" " ;
	url = [ url stringByAppendingString:@"\"http://www.w7ay.net/site/Downloads/updates.txt\"" ] ;
	updateFile = popen( [ url cStringUsingEncoding:NSASCIIStringEncoding ], "r" ) ;

	if ( updateFile == nil ) {
		[ [ NSAlert alertWithMessageText:NSLocalizedString( @"Update information error", nil ) defaultButton:NSLocalizedString( @"OK", nil ) alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString( @"Update file not found", nil ) ] runModal ] ;
		return ;
	}
	for ( i = 0; i < 20; i++ ) {
		s = fgets( line, 128, updateFile ) ;
		if ( s == nil ) {
			[ [ NSAlert alertWithMessageText:NSLocalizedString( @"Update information error", nil ) defaultButton:NSLocalizedString( @"OK", nil ) alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedString( @"No update info", nil ) ] runModal ] ;
			break ;
		}
		if ( strncmp( s, app, len ) == 0 ) {
			sscanf( s+len, "%f", &latest ) ;
			version = [ [ NSBundle mainBundle ] objectForInfoDictionaryKey:@"CFBundleVersion" ] ;
			sscanf( [ version cStringUsingEncoding:kTextEncoding ], "%f", &current ) ;
			
			if ( ( latest - current ) > .0001 ) {
				alert = [ [ NSAlert alertWithMessageText:NSLocalizedString( @"New download available", nil ) defaultButton:NSLocalizedString( @"OK", nil ) alternateButton:nil otherButton:NSLocalizedString( @"What's New", nil ) informativeTextWithFormat:[ NSString stringWithFormat:NSLocalizedString( @"Update available info", nil ), latest ] ] runModal ] ;
				if ( alert == -1 || alert == NSAlertThirdButtonReturn ) {
					// v0.75
					[ self openURLDoc:@"http://www.w7ay.net/site/Applications/cocoaModem/Whats%20New/index.html" ] ;
				}
			}
			else {
				[ [ NSAlert alertWithMessageText:NSLocalizedString( @"Up to date", nil ) defaultButton:NSLocalizedString( @"OK", nil ) alternateButton:nil otherButton:nil informativeTextWithFormat:[ NSString stringWithFormat:NSLocalizedString( @"Up to date info", nil ), latest ] ] runModal ] ;
			}
			break ;
		}
	}
	pclose( updateFile ) ;
}

//	v0.96c
- (IBAction)selectMainView:(id)sender 
{
	[ stdManager selectView:1 ] ;
}

//	v0.96c
- (IBAction)selectSubView:(id)sender
{
	[ stdManager selectView:2 ] ;
}

//	v0.96c
- (IBAction)selectTransmitView:(id)sender
{
	[ stdManager selectView:0 ] ;
}

//	v0.96d
- (IBAction)muteSpeech:(id)sender
{
	Boolean state ;
	
	if ( [ sender state ] == NSOffState ) {
		[ sender setState:NSOnState ] ;
		state = YES ;
	}
	else {
		[ sender setState:NSOffState ] ;
		state = NO ;
		[ mainReceiverVoice speak:@"Text To Speech On." ] ;
	}
	[ transmitterVoice setMute:state ] ;
	[ mainReceiverVoice setMute:state ] ;
	[ subReceiverVoice setMute:state ] ;
}

//	v1.00
- (IBAction)spellSpeech:(id)sender
{
	Boolean state ;
	
	if ( [ sender state ] == NSOffState ) {
		[ sender setState:NSOnState ] ;
		state = YES ;
	}
	else {
		[ sender setState:NSOffState ] ;
		state = NO ;
	}
	[ transmitterVoice setSpell:state ] ;
	[ mainReceiverVoice setSpell:state ] ;
	[ subReceiverVoice setSpell:state ] ;
}

- (DigitalInterfaces*)digitalInterfaces
{
	return digitalInterfaces ;
}

- (MacroScripts*)macroScripts
{
	return macroScripts ;
}

//	v0.96d TextToSpeech
//	channel 0	transmit
//			1	main receiver
//			2	sub receiver
- (void)addToVoice:(int)ascii channel:(int)channel
{
	switch ( channel ) {
	case 0:
		[ transmitterVoice addToVoice:ascii ] ;
		break ;
	case 1:
		[ mainReceiverVoice addToVoice:ascii ] ;
		break ;
	case 2:
		[ subReceiverVoice addToVoice:ascii ] ;
		break ;
	case 3:
		[ assistVoice addToVoice:ascii ] ;
		break ;
	}
}

- (void)setVoice:(NSString*)name channel:(int)channel
{
	switch ( channel ) {
	case 0:
		[ transmitterVoice setVoice:name ] ;
		break ;
	case 1:
		[ mainReceiverVoice setVoice:name ] ;
		break ;
	case 2:
		[ subReceiverVoice setVoice:name ] ;
		break ;
	case 3:
		[ assistVoice setVoice:name ] ;
		//[ assistVoice setRate:800.0 ] ;
		[ self speakAssist:@"Welcome to cocoaModem." ] ;
		break ;
	}
}

- (void)setVoiceEnable:(Boolean)state channel:(int)channel
{
	switch ( channel ) {
	case 0:
		[ transmitterVoice setVoiceEnable:state ] ;
		break ;
	case 1:
		[ mainReceiverVoice setVoiceEnable:state ] ;
		break ;
	case 2:
		[ subReceiverVoice setVoiceEnable:state ] ;
		break ;
	}
}

- (void)setVerbatimSpeech:(Boolean)state channel:(int)channel
{
	switch ( channel ) {
	case 0:
		[ transmitterVoice setVerbatim:state ] ;
		break ;
	case 1:
		[ mainReceiverVoice setVerbatim:state ] ;
		break ;
	case 2:
		[ subReceiverVoice setVerbatim:state ] ;
		break ;
	}
}

- (void)clearVoiceChannel:(int)channel
{
	switch ( channel ) {
	case 0:
		[ transmitterVoice clearVoice ] ;
		break ;
	case 1:
		[ mainReceiverVoice clearVoice ] ;
		break ;
	case 2:
		[ subReceiverVoice clearVoice ] ;
		break ;
	}
}

- (void)clearAllVoices
{
	[ transmitterVoice clearVoice ] ;
	[ mainReceiverVoice clearVoice ] ;
	[ subReceiverVoice clearVoice ] ;
}

//	v1.01b
- (Boolean)voiceAssist
{
	return voiceAssist ;
}

- (void)dealloc
{
	[ darkModeMenuItem release ] ;
	[ mainReceiverVoice release ] ;
	[ subReceiverVoice release ] ;
	[ transmitterVoice release ] ;
	if ( speakAssistInfo ) [ speakAssistInfo release ] ;
	[ super dealloc ] ;
}

@end
