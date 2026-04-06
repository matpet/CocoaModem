//
//  QSO.m
//  cocoaModem
//
//  Created by Kok Chen on Thu Jul 08 2004.
	#include "Copyright.h"
//

#import "QSO.h"
#include "Application.h"
#include "Messages.h"
#include "Modem.h"
#import "TextEncoding.h"


@implementation QSO

static void setLegacyAquaAppearance( id object )
{
	if ( object && [ object respondsToSelector:@selector(setAppearance:) ] ) {
		[ object setAppearance:[ NSAppearance appearanceNamed:NSAppearanceNameAqua ] ] ;
	}
}

- (void)applyReadableFieldColors:(id)field
{
	if ( field == nil ) return ;
	setLegacyAquaAppearance( field ) ;
	if ( [ field respondsToSelector:@selector(setDrawsBackground:) ] ) [ field setDrawsBackground:YES ] ;
	if ( [ field respondsToSelector:@selector(setBackgroundColor:) ] ) [ field setBackgroundColor:[ NSColor whiteColor ] ] ;
	if ( [ field respondsToSelector:@selector(setTextColor:) ] ) [ field setTextColor:[ NSColor blackColor ] ] ;
	if ( [ field currentEditor ] ) {
		NSText *editor = [ field currentEditor ] ;
		setLegacyAquaAppearance( editor ) ;
		if ( [ editor respondsToSelector:@selector(setBackgroundColor:) ] ) [ (id)editor setBackgroundColor:[ NSColor whiteColor ] ] ;
		if ( [ editor respondsToSelector:@selector(setTextColor:) ] ) [ (id)editor setTextColor:[ NSColor blackColor ] ] ;
		if ( [ editor respondsToSelector:@selector(setInsertionPointColor:) ] ) [ (id)editor setInsertionPointColor:[ NSColor blackColor ] ] ;
	}
}

- (void)controlTextDidBeginEditing:(NSNotification*)notification
{
	id field ;

	field = [ notification object ] ;
	if ( field == callsignField || field == nameField ) [ self applyReadableFieldColors:field ] ;
}

- (void)controlTextDidEndEditing:(NSNotification*)notification
{
	id field ;

	field = [ notification object ] ;
	if ( field == callsignField || field == nameField ) [ self applyReadableFieldColors:field ] ;
}

- (void)refreshEditableFieldColors:(id)field
{
	[ self applyReadableFieldColors:field ] ;
}

//  (Private API)
- (void)setInterface:(NSControl*)object to:(SEL)selector
{
	[ object setAction:selector ] ;
	[ object setTarget:self ] ;
}

//  called from Application (delegate of NSApplication)
- (BOOL)application:(NSApplication*)sender delegateHandlesKey:(NSString*)key 
{
	//printf( "delegateHandlesKey in QSO call with %s\n", [ key cStringUsingEncoding:kTextEncoding ] ) ;
	return YES ;
}

/* local */
static void convertToUpper( char *string )
{
	int v ;
	
	while ( *string ) {
		v = *string & 0xff ;
		if ( v == 216 || v == 175 ) /* slashed zero */ v = '0' ;
		if ( v >= 'a' && v <= 'z' ) v += 'A' - 'a' ;
		*string++ = v ;
	}
}

- (void)newCallsign:(NSNotification*)notify
{
	NSString *str, *capturedString ;
	Modem *src ;
	int length ;
	
	src = [ notify object ] ;
	
	capturedString = [ self asciiCString:[ src capturedString ] ] ;
	length = [ capturedString length ] ;
	if ( length > 15 ) length = 15 ;
	str = [ capturedString substringWithRange:NSMakeRange(0,length) ] ;
	[ capturedString release ] ;
	if ( callsignField ) [ callsignField setStringValue:str ] ;
}

- (void)newName:(NSNotification*)notify
{
	NSString *str, *capturedString ;
	Modem *src ;
	int length ;
	
	src = [ notify object ] ;
	
	capturedString = [ self asciiCString:[ src capturedString ] ] ;
	length = [ capturedString length ] ;
	if ( length > 20 ) length = 20 ;
	str = [ capturedString substringWithRange:NSMakeRange(0,length) ] ;
	if ( nameField ) [ nameField setStringValue:str ] ;
}

- (void)setUTC
{
	time_t t ;
	NSString *str ;
	
	t = time( nil ) ;
	gmt = *gmtime( &t ) ;
	
	if ( day != gmt.tm_mday ) {
		day = gmt.tm_mday ;
		str = [ NSString stringWithFormat:@"%02d/%02d/%02d", day, gmt.tm_mon+1, ( gmt.tm_year+1900 )%100 ] ;
		[ utcDateField setStringValue:str ] ;
	}
	str = [ NSString stringWithFormat:@"%02d:%02d", gmt.tm_hour, gmt.tm_min ] ;
	[ utcTimeField setStringValue:str ] ;
}

- (NSString*)callsign
{
	NSString *string ;
	
	string = [ callsignField stringValue ] ;
	if ( string == nil ) return @"" ;
	if ( strippedCallsign ) [ strippedCallsign release ] ;
	strippedCallsign = [ [ self asciiString:string ] retain ] ;
	return strippedCallsign ;
}

- (void)setCallsign:(NSString*)str
{
	if ( callsignField ) {
		[ callsignField setStringValue:str ] ;
	}
}

- (NSString*)opName
{
	NSString *string ;
	
	string = [ nameField stringValue ] ;
	if ( string == nil ) return @"" ;
	if ( strippedOp ) [ strippedOp release ] ;
	strippedOp = [ [ self asciiString:string ] retain ] ;
	return strippedOp ;
}

- (void)setOpName:(NSString*)str
{
	if ( nameField ) {
		[ nameField setStringValue:str ] ;
	}
}

- (void)setNumber:(NSString*)str
{
	if ( previousNumber ) [ previousNumber release ] ;
	previousNumber = qsoNumber ;
	qsoNumber = [ str retain ] ;
}

//  this field is used by the contest manager and used by macro sheets
- (void)setExchangeString:(NSString*)str
{
	[ myExchange release ] ;
	myExchange = [ str retain ] ;
}

//  this field is used by the contest manager and used by macro sheets
- (void)setDXExchange:(NSString*)str
{
	[ dxExchange release ] ;
	dxExchange = [ str retain ] ;
}

- (void)tick:(NSTimer*)timer
{
	[ self setUTC ] ;
}

- (id)initIntoTabView:(NSTabView*)tabview app:(Application*)app
{
	NSTabViewItem *tabItem ;
	
	self = [ super init ] ;
	if ( self ) {
		application = app ;
		qsoNumber = @"001" ;
		previousNumber = @"001" ;
		day = -1 ;
		myExchange = dxExchange = @"" ;
		appleScript = nil ;
		strippedCallsign = strippedOp = nil ;

		if ( [ NSBundle loadNibNamed:@"QSO" owner:self ] ) {
			// loadNib should have set up view
			if ( view ) {
				setLegacyAquaAppearance( view ) ;
				//  create a new TabViewItem for QSO
				tabItem = [ [ NSTabViewItem alloc ] init ] ;
				[ tabItem setLabel:NSLocalizedString( @"QSO", nil ) ] ;
				[ tabItem setView:view ] ;
				//  and insert as tabView item
				controllingTabView = tabview ;
				[ controllingTabView insertTabViewItem:tabItem atIndex:0 ] ;
				//  disable log script button first
				[ logButton setEnabled:NO ] ;

				//  create notification client for ExchangeView
				[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(newCallsign:) name:@"CapturedCallsign" object:nil ] ;
				[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(newName:) name:@"CapturedName" object:nil ] ;
				[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(registerTime) name:@"RegisterTime" object:nil ] ;
				[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(registerAndUpdateTime) name:@"RegisterAndUpdateTime" object:nil ] ;
				[ self setUTC ] ;
				[ self registerAndUpdateTime ] ;
				[ NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tick:) userInfo:self repeats:YES ] ;
				[ self applyReadableFieldColors:callsignField ] ;
				[ self applyReadableFieldColors:nameField ] ;
				[ self applyReadableFieldColors:utcDateField ] ;
				[ self applyReadableFieldColors:utcTimeField ] ;
				if ( [ callsignField respondsToSelector:@selector(setDelegate:) ] ) [ callsignField setDelegate:self ] ;
				if ( [ nameField respondsToSelector:@selector(setDelegate:) ] ) [ nameField setDelegate:self ] ;


				[ self setInterface:callButton to:@selector(transferCall) ] ;	
				[ self setInterface:nameButton to:@selector(transferName) ] ;	
				[ self setInterface:clearButton to:@selector(clearFields) ] ;	
				[ self setInterface:logButton to:@selector(logQSO) ] ;	

				return self ;
			}
		}
	}
	return nil ;
}

- (void)showOnlyDateAndTime:(Boolean)state
{
	[ callsignField setHidden:state ] ;
	[ callButton setHidden:state ] ;
	[ nameField setHidden:state ] ;
	[ nameButton setHidden:state ] ;
	[ clearButton setHidden:state ] ;
	[ logButton setHidden:state ] ;
}

- (void)registerTime
{
	registeredTime = gmt ;
}

- (void)registerAndUpdateTime
{
	[ self registerTime ] ;
	previousTime = registeredTime ;
}

- (NSString*)getRegisteredTime
{
	char format[16] ;

	sprintf( format, "%02d%02d", registeredTime.tm_hour, registeredTime.tm_min ) ;
	return [ NSString stringWithCString:format encoding:kTextEncoding ] ;
}

- (NSString*)cutFor:(NSString*)original
{
	char c[16] ;
	int i ;
	
	strcpy( c, [ original cStringUsingEncoding:kTextEncoding ] ) ;
	for ( i = 0; i < 5; i++ ) {
		if ( c[i] == 0 ) break ;
		if ( c[i] == '1' ) c[i] = 'A' ; else if ( c[i] == '9' ) c[i] = 'N' ;  else if ( c[i] == '0' ) c[i] = 'T' ;
	}
	return [ NSString stringWithCString:c encoding:kTextEncoding ] ;
}

- (NSString*)zeroCutFor:(NSString*)original
{
	char c[16] ;
	int i ;
	
	strcpy( c, [ original cStringUsingEncoding:kTextEncoding ] ) ;
	for ( i = 0; i < 5; i++ ) {
		if ( c[i] == 0 ) break ;
		if ( c[i] == '0' ) c[i] = 'T' ;
	}
	return [ NSString stringWithCString:c encoding:kTextEncoding ] ;
}

//  fetch macro
- (NSString*)macroFor:(int)c
{
	NSString *str ;
	char format[16] ;
	
	switch ( c ) {
	case 'C':
		str = [ callsignField stringValue ] ;
		break ;
	case 'H':
		//  name
		str = [ nameField stringValue ] ;
		break ;
	case 'n':
		//  number
	case 'N':
		//  cut (A=1,N=9,T=0) number
	case 'o':
		//  zero cut (T=0) number
		// str = qsoNumber ;
		str = [ self macroFor:c count:0 ] ;
		break ;
	case 'p':
		//  previous number
		str = ( [ [ callsignField stringValue ] length ] > 0 ) ? qsoNumber : previousNumber ;
		break ;
	case 't':
		sprintf( format, "%02d%02d", gmt.tm_hour, gmt.tm_min ) ;
		str = [ NSString stringWithCString:format encoding:kTextEncoding ] ;
		break ;
	case 'T':
		sprintf( format, "%02d%02d", registeredTime.tm_hour, registeredTime.tm_min ) ;
		str = [ NSString stringWithCString:format encoding:kTextEncoding ] ;
		break ;
	case 'P':
		sprintf( format, "%02d%02d", previousTime.tm_hour, previousTime.tm_min ) ;
		str = [ NSString stringWithCString:format encoding:kTextEncoding ] ;
		break ;		
	case 'x':
		//  contest exchange
		str = myExchange ;
		break ;
	case 'X':
		//  dx exchange
		str = dxExchange ;
		break ;
	default:
		str = @"----" ;
		break ;
	}
	return str ;
}

- (NSString*)macroFor:(int)c count:(int)n
{
	NSString *str, *format ;
	int p ;
	
	switch ( c ) {
	case 'n':
		//  number
		sscanf( [ qsoNumber cStringUsingEncoding:kTextEncoding ], "%d", &p ) ;
		switch ( n ) {
		case 0:
			format = @"%d" ;
			break ;
		case 3:
			format = ( p < 1000 ) ? @"%03d" : @"%d" ;
			break ;
		case 4:
			format = ( p < 1000 ) ? @"%04d" : @"%d" ;
			break ;
		default:
			format = @"%d" ;
		}
		str = [ [ NSString stringWithFormat:format, p ] retain ]  ;
		break ;
	case 'N':
		//  cut number
		sscanf( [ qsoNumber cStringUsingEncoding:kTextEncoding ], "%d", &p ) ;
		switch ( n ) {
		case 0:
			format = @"%d" ;
			break ;
		case 3:
			format = ( p < 1000 ) ? @"%03d" : @"%d" ;
			break ;
		case 4:
			format = ( p < 1000 ) ? @"%04d" : @"%d" ;
			break ;
		default:
			format = @"%d" ;
		}
		str = [ self cutFor:[ NSString stringWithFormat:format, p ] ]  ;
		break ;
	case 'o':
		//  zero cut number
		sscanf( [ qsoNumber cStringUsingEncoding:kTextEncoding ], "%d", &p ) ;
		switch ( n ) {
		case 0:
			format = @"%d" ;
			break ;
		case 3:
			format = ( p < 1000 ) ? @"%03d" : @"%d" ;
			break ;
		case 4:
			format = ( p < 1000 ) ? @"%04d" : @"%d" ;
			break ;
		default:
			format = @"%d" ;
		}
		str = [ self zeroCutFor:[ NSString stringWithFormat:format, p ] ]  ;
		break ;
	case 'p':
		//  previous number
		sscanf( [ str cStringUsingEncoding:kTextEncoding ], "%d", &p ) ;
		if ( n > 1 && [ [ callsignField stringValue ] length ] > 0 ) n-- ;
		switch ( n ) {
		case 3:
			format = ( p < 1000 ) ? @"%03d" : @"%d" ;
			break ;
		case 4:
			format = ( p < 1000 ) ? @"%04d" : @"%d" ;
			break ;
		default:
			format = @"%d" ;
		}
		str = [ [ NSString stringWithFormat:format, p ] retain ]  ;
		break ;		
	default:
		str = @"----" ;
		break ;
	}
	return str ;
}

//  copy string into text field
- (void)copyString:(char*)selectedString into:(int)field
{
	NSTextField *f ;
	
	f = nil ;
	switch ( field ) {
	case 'C':
		f = callsignField ;
		convertToUpper( selectedString ) ;
		break ;
	case 'N':
		f = nameField ;
		break ;
	}
	if ( f ) [ f setStringValue:[ NSString stringWithCString:selectedString encoding:kTextEncoding ] ] ;
}

- (void)logScriptChanged:(NSString*)fileName
{
	NSURL *url ;
	NSDictionary *dict ;
	
	dict = nil ;
	appleScript = nil ;
	[ logButton setEnabled:NO ] ;
	if ( [ fileName length ] > 0 ) {
		url = [ NSURL fileURLWithPath:[ fileName stringByExpandingTildeInPath ] ] ;
		appleScript = [ [ NSAppleScript alloc ] initWithContentsOfURL:url error:&dict ] ;
		if ( appleScript ) {
			if ( [ appleScript compileAndReturnError:&dict ] ) {
				[ logButton setEnabled:YES ] ;
				[ dict release ] ;
				return ;
			}
		}
		[ Messages appleScriptError:dict script:"Log button" ] ;
	}
}

- (void)logQSO
{
	NSDictionary *dict ;
	
	if ( appleScript ) {
		dict = [ [ NSDictionary alloc ] init ] ; ;
		if ( ![ appleScript executeAndReturnError:&dict ] ) {
			[ Messages appleScriptError:dict script:"Log" ] ;
			[ appleScript release ] ;
			[ logButton setEnabled:NO ] ;
			appleScript = nil ;
		}
		[ dict release ] ;
	}
}

- (void)transferCall
{
	[ application transferToQSOField:'C' ] ;
}

- (void)transferName
{
	[ application transferToQSOField:'N' ] ;
}

- (void)clearFields
{
	[ callsignField setStringValue:@"" ] ;
	[ nameField setStringValue:@"" ] ;
}

//  v1.01a
- (void)selectCall 
{
	[ callsignField becomeFirstResponder ] ;
	[ self performSelector:@selector(refreshEditableFieldColors:) withObject:callsignField afterDelay:0.0 ] ;
	[ callsignField setStringValue:@"" ] ;
}

//  v1.01a
- (void)selectName
{
	[ nameField becomeFirstResponder ] ;
	[ self performSelector:@selector(refreshEditableFieldColors:) withObject:nameField afterDelay:0.0 ] ;
	[ nameField setStringValue:@"" ] ;
}

	
@end
