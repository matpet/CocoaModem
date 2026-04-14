//
//  SerialLineKeyer.m
//  cocoaModem 2.0
//

	#include "Copyright.h"

#import "SerialLineKeyer.h"
#include <IOKit/IOBSD.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/serial/IOSerialKeys.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

static int serialFlagForLine( int line )
{
	return ( line == 0 ) ? TIOCM_DTR : TIOCM_RTS ;
}

@implementation SerialLineKeyer

- (void)timedKeyThread:(id)obj
{
	Boolean state ;
	int duration ;

	while ( 1 ) {
		[ timedQueueLock lockWhenCondition:1 ] ;
		if ( timedQueueClosed ) {
			[ timedQueueLock unlockWithCondition:0 ] ;
			break ;
		}
		state = timedQueue[timedQueueConsumer].state ;
		duration = timedQueue[timedQueueConsumer].microseconds ;
		timedQueueConsumer = ( timedQueueConsumer+1 ) & 0xfff ;
		[ timedQueueLock unlockWithCondition:( timedQueueProducer != timedQueueConsumer ) ? 1 : 0 ] ;
		[ self setKeyState:state ] ;
		if ( duration > 0 ) usleep( duration ) ;
	}
	[ self setKeyState:NO ] ;
	timedQueueRunning = NO ;
}

+ (int)findSerialPorts:(NSString**)pathArray stream:(NSString**)streamArray maxPorts:(int)maxPorts
{
	kern_return_t kernResult ;
	mach_port_t masterPort ;
	io_iterator_t serialPortIterator ;
	io_object_t modemService ;
	CFMutableDictionaryRef classesToMatch ;
	CFTypeRef cfString ;
	int count ;

	kernResult = IOMasterPort( MACH_PORT_NULL, &masterPort ) ;
	if ( kernResult != KERN_SUCCESS ) return 0 ;

	classesToMatch = IOServiceMatching( kIOSerialBSDServiceValue ) ;
	if ( classesToMatch == NULL ) return 0 ;

	CFDictionarySetValue( classesToMatch, CFSTR( kIOSerialBSDTypeKey ), CFSTR( kIOSerialBSDAllTypes ) ) ;
	kernResult = IOServiceGetMatchingServices( masterPort, classesToMatch, &serialPortIterator ) ;
	if ( kernResult != KERN_SUCCESS ) return 0 ;

	count = 0 ;
	while ( ( modemService = IOIteratorNext( serialPortIterator ) ) && count < maxPorts ) {
		cfString = IORegistryEntryCreateCFProperty( modemService, CFSTR( kIOTTYDeviceKey ), kCFAllocatorDefault, 0 ) ;
		if ( cfString ) {
			streamArray[count] = [ (NSString*)cfString retain ] ;
			CFRelease( cfString ) ;
			cfString = IORegistryEntryCreateCFProperty( modemService, CFSTR( kIOCalloutDeviceKey ), kCFAllocatorDefault, 0 ) ;
			if ( cfString ) {
				pathArray[count] = [ (NSString*)cfString retain ] ;
				CFRelease( cfString ) ;
				count++ ;
			}
		}
		IOObjectRelease( modemService ) ;
	}
	IOObjectRelease( serialPortIterator ) ;
	return count ;
}

- (id)initWithPath:(NSString*)devicePath line:(int)serialLine name:(NSString*)deviceName token:(int)serialToken
{
	self = [ super init ] ;
	if ( self ) {
		path = [ devicePath retain ] ;
		name = [ deviceName retain ] ;
		line = serialLine ;
		token = serialToken ;
		fileDescriptor = -1 ;
		hasOriginalTTYAttrs = NO ;
		invert = NO ;
		timedQueueLock = [ [ NSConditionLock alloc ] initWithCondition:0 ] ;
		timedQueueRunning = NO ;
		timedQueueClosed = NO ;
		timedQueueProducer = timedQueueConsumer = 0 ;
	}
	return self ;
}

- (void)dealloc
{
	[ self close ] ;
	[ timedQueueLock release ] ;
	[ path release ] ;
	[ name release ] ;
	[ super dealloc ] ;
}

- (Boolean)matchesPath:(NSString*)devicePath line:(int)serialLine
{
	return ( devicePath && path && [ path isEqualToString:devicePath ] && line == serialLine ) ;
}

- (Boolean)openForWrite
{
	struct termios options ;
	int bits ;

	if ( fileDescriptor > 0 ) return YES ;
	if ( path == nil ) return NO ;
	fileDescriptor = open( [ path UTF8String ], O_RDWR | O_NOCTTY | O_NDELAY ) ;
	if ( fileDescriptor < 0 ) return NO ;
	if ( fcntl( fileDescriptor, F_SETFL, 0 ) < 0 ) {
		close( fileDescriptor ) ;
		fileDescriptor = -1 ;
		return NO ;
	}
	if ( tcgetattr( fileDescriptor, &originalTTYAttrs ) >= 0 ) {
		hasOriginalTTYAttrs = YES ;
		options = originalTTYAttrs ;
		options.c_cflag |= ( CLOCAL | CREAD ) ;
#ifdef CRTSCTS
		options.c_cflag &= ~CRTSCTS ;
#endif
#ifdef CCTS_OFLOW
		options.c_cflag &= ~CCTS_OFLOW ;
#endif
#ifdef CRTS_IFLOW
		options.c_cflag &= ~CRTS_IFLOW ;
#endif
#ifdef CDTR_IFLOW
		options.c_cflag &= ~CDTR_IFLOW ;
#endif
#ifdef CDSR_OFLOW
		options.c_cflag &= ~CDSR_OFLOW ;
#endif
#ifdef CCAR_OFLOW
		options.c_cflag &= ~CCAR_OFLOW ;
#endif
#ifdef MDMBUF
		options.c_cflag &= ~MDMBUF ;
#endif
		options.c_iflag &= ~( IXON | IXOFF | IXANY ) ;
		options.c_lflag &= ~( ICANON | ECHO | ECHOE | ISIG ) ;
		options.c_oflag &= ~OPOST ;
		options.c_cc[ VMIN ] = 0 ;
		options.c_cc[ VTIME ] = 10 ;
		tcsetattr( fileDescriptor, TCSANOW, &options ) ;
	}
	if ( ioctl( fileDescriptor, TIOCMGET, &bits ) < 0 ) {
		if ( hasOriginalTTYAttrs ) tcsetattr( fileDescriptor, TCSANOW, &originalTTYAttrs ) ;
		close( fileDescriptor ) ;
		fileDescriptor = -1 ;
		hasOriginalTTYAttrs = NO ;
		return NO ;
	}
	return YES ;
}

- (void)close
{
	if ( timedQueueRunning ) {
		[ timedQueueLock lock ] ;
		timedQueueClosed = YES ;
		[ timedQueueLock unlockWithCondition:1 ] ;
		while ( timedQueueRunning ) [ NSThread sleepUntilDate:[ NSDate dateWithTimeIntervalSinceNow:0.01 ] ] ;
	}
	if ( fileDescriptor > 0 ) {
		if ( hasOriginalTTYAttrs ) tcsetattr( fileDescriptor, TCSANOW, &originalTTYAttrs ) ;
		close( fileDescriptor ) ;
		fileDescriptor = -1 ;
	}
	hasOriginalTTYAttrs = NO ;
}

- (Boolean)setKeyState:(Boolean)state
{
	int bits, flag ;
	Boolean asserted ;

	if ( fileDescriptor <= 0 ) return NO ;
	flag = serialFlagForLine( line ) ;
	asserted = ( state ^ invert ) ;
	if ( ioctl( fileDescriptor, TIOCMGET, &bits ) < 0 ) return NO ;
	if ( asserted ) bits |= flag ; else bits &= ~flag ;
	return ( ioctl( fileDescriptor, TIOCMSET, &bits ) >= 0 ) ;
}

- (void)queueKeyState:(Boolean)state microseconds:(int)microseconds
{
	int next ;

	if ( fileDescriptor <= 0 ) return ;
	[ timedQueueLock lock ] ;
	next = ( timedQueueProducer+1 ) & 0xfff ;
	if ( next == timedQueueConsumer ) {
		[ timedQueueLock unlockWithCondition:1 ] ;
		return ;
	}
	timedQueue[timedQueueProducer].state = state ;
	timedQueue[timedQueueProducer].microseconds = microseconds ;
	timedQueueProducer = next ;
	if ( !timedQueueRunning ) {
		timedQueueClosed = NO ;
		timedQueueRunning = YES ;
		[ NSThread detachNewThreadSelector:@selector(timedKeyThread:) toTarget:self withObject:self ] ;
	}
	[ timedQueueLock unlockWithCondition:1 ] ;
}

- (void)clearQueuedKeyStates
{
	[ timedQueueLock lock ] ;
	timedQueueProducer = timedQueueConsumer = 0 ;
	[ timedQueueLock unlockWithCondition:0 ] ;
	[ self setKeyState:NO ] ;
}

- (void)setInvert:(Boolean)state
{
	invert = state ;
}

- (NSString*)path
{
	return path ;
}

- (NSString*)name
{
	return name ;
}

- (int)line
{
	return line ;
}

- (int)token
{
	return token ;
}

- (int)fileDescriptor
{
	return fileDescriptor ;
}

@end
