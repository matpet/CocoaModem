//
//  FSKHub.m
//  cocoaModem 2.0
//
//  Created by Kok Chen on 2/11/08.
//  Copyright 2008 Kok Chen, W7AY. All rights reserved.
//

#import "FSKHub.h"
#import "Application.h"
#import "RouterCommands.h"
#import "TextEncoding.h"
#include <IOKit/serial/IOSerialKeys.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>


static char CMLtrs[] = {  '*',  'E', '*', 'A', ' ', 'S', 'I', 'U', 
						'*',  'D', 'R',  'J', 'N', 'F', 'C', 'K', 
						'T',  'Z', 'L',  'W', 'H', 'Y', 'P', 'Q', 
						'O',  'B', 'G',  '*', 'M', 'X', 'V', '*',
					} ;

static char CMFigs[] = {  '*',  '3',  '\n', '-',  ' ', '*', '8', '7', 
						'*',  '$',  '4',  '*',  ',', '!', ':', '(', 
						'5',  '\"', ')',  '2',  '#', '6', '0', '1', 
						'9',  '?',  '&',  '*',  '.', '/', ';', '*',
					} ;

#define CMFIGSCODE			0x1b
#define CMLTRSCODE			0x1f

#define kRobustThreshold	16

static int stopMask[4] = { /* 1 stop */ 0x0, /* 1.5 stops */ 0x8, /* 2 stops */ 0x4, /* default */ 0x8 } ;
static int stopBitsCount[4] = { 2, 3, 4, 3 } ;

static uint64_t absoluteTimeUnitsForNanoseconds( uint64_t nanoseconds )
{
	static mach_timebase_info_data_t timebase = { 0, 0 } ;
	long double scaled ;

	if ( timebase.denom == 0 ) mach_timebase_info( &timebase ) ;
	scaled = ( (long double)nanoseconds * (long double)timebase.denom ) / (long double)timebase.numer ;
	if ( scaled < 1.0 ) return 1 ;
	return (uint64_t)( scaled + 0.5 ) ;
}

static void sleepUntilAbsoluteTime( uint64_t deadline )
{
	uint64_t now ;

	now = mach_absolute_time() ;
	if ( deadline > now ) mach_wait_until( deadline ) ;
}

@implementation FSKHub

//	(Private API)
//  set up FSK ports to the Router
- (void)setupMicrohamRouter
{
	int i, n, fskFd, flagsFd ;
	NSArray *keyers ;
	MicroKeyer *keyer ;
	MicroHamKeyerCache *keyerCache ;
		
	router = [ [ [ NSApp delegate ] digitalInterfaces ] router ] ;
	if ( router == nil ) return ;

	keyers = [ router connectedKeyers ] ;
	n = [ keyers count ] ;
	
	//  set up listener for read ports
	selectCount = activeKeyers = 0 ;
	for ( i = 0; i < n; i++ ) {
		keyer = keyers[i] ;
		fskFd = [ keyer fskWriteDescriptor ] ;
		if ( fskFd > 0 ) {
			keyerCache = &microKeyerCache[activeKeyers++] ;
			keyerCache->keyer = keyer ;
			keyerCache->fskPort = fskFd ;
			keyerCache->controlPort = [ keyer controlWriteDescriptor ] ;
			flagsFd = [ keyer flagsReadDescriptor ] ;
			if ( flagsFd > 0 ) {
				FD_SET( flagsFd, &selectSet ) ;
				keyerCache->flagsPort = flagsFd ;
				if ( flagsFd > selectCount ) selectCount = flagsFd ;
			}
		}
	}
	if ( selectCount > 0 ) {
		//  create thread to listen to flags
		[ NSThread detachNewThreadSelector:@selector(pollThread) toTarget:self withObject:nil ] ;
	}
}

- (id)init
{
	int i, ch, encoded ;
	
	self = [ super init ] ;
	if ( self ) {			
		usos = YES ;							//  v0.84
		fskBusy = NO ;
		currentFd = 0 ;
		currentPortToken = 0 ;
		currentSerialLine = kSerialRTSLine ;
		currentSerialPort = nil ;
		currentBitPeriod = 1.0/45.45 ;
		currentStopBits = 1 ;
		serialInvert = NO ;
		serialMode = NO ;
		selectCount = 0 ;
		shift = kLTRSshift ;
		closed = running = NO ;
		producer = consumer = 0 ;
		currentBaudotCharacter = CMLTRSCODE ;	//  v0.88 feedback to aural monitor
		robust = NO ;							//  v0.88 USOS "compatibility mode"
		spaceFollowedFIGS = NO ;
		pendingASCII = 0 ;
		robustCount = 0 ;
		serialPortCount = 0 ;
		
		modem = nil ;
		
		//  initialize Baudot table with spaces
		for ( i = 0; i < 256; i++ ) baudot[i] = 0x04 + LTRSMASK + FIGSMASK ;
		
		for ( i = 0; i < 32; i++ ) {
			ch = CMLtrs[i] & 0x7f ;
			switch ( ch ) {
			case '*':
			case '\n':
			case '\r':
				encoded = 0 ;
				break ;
			default:
				encoded = ch ;
			}
			if ( encoded > 0 ) {
				baudot[ encoded ] = ( i & 0x1f ) + LTRSMASK ;
				if ( encoded >= 'A' && encoded <= 'Z' ) baudot[ encoded-'A'+'a' ] = ( i & 0x1f ) + LTRSMASK ;
			}
		}
		for ( i = 0; i < 32; i++ ) {
			ch = CMFigs[i] & 0x7f ;
			switch ( ch ) {
			case '*':
			case '\n':
			case '\r':
				encoded = 0 ;
				break ;
			default:
				encoded = ch ;
			}
			if ( encoded > 0 ) baudot[ encoded ] = ( i & 0x1f ) + FIGSMASK ;
		}
		baudot[ ' ' ] = 0x04 + LTRSMASK + FIGSMASK ;
		baudot[ 0x0a ] = 0x02 + LTRSMASK + FIGSMASK ;
		baudot[ 0x0d ] = 0x08 + LTRSMASK + FIGSMASK ;
		baudot[ '\'' ] = 0x05 + FIGSMASK ;
		
		
		FD_ZERO( &selectSet ) ;
		[ self setupMicrohamRouter ] ;
		
		//  make cocoaModem active even when other helper apps are launched
		[ NSApp activateIgnoringOtherApps:YES ] ;
	}
	return self ;
}

- (void)dealloc
{
	int i ;

	[ self closeFSKConnections ] ;
	for ( i = 0; i < serialPortCount; i++ ) [ serialPorts[i] release ] ;
	[ super dealloc ] ;
}

- (int)serialPortTokenForPath:(NSString*)path line:(int)line name:(NSString*)name
{
	int i ;

	if ( path == nil ) return 0 ;
	for ( i = 0; i < serialPortCount; i++ ) {
		if ( [ serialPorts[i] matchesPath:path line:line ] ) return [ serialPorts[i] token ] ;
	}
	if ( serialPortCount >= 64 ) return 0 ;

	serialPorts[serialPortCount] = [ [ SerialLineKeyer alloc ] initWithPath:path line:line name:name token:( 0x10000 + serialPortCount ) ] ;
	serialPortCount++ ;
	return [ serialPorts[serialPortCount-1] token ] ;
}

//  v0.84
- (void)setUSOS:(Boolean)state
{
	usos = state ;
}


- (void)closeFSKConnections
{
	int i ;
	char dummy[2] ;
	MicroHamKeyerCache *keyerCache ;
	
	closed = YES ;
	running = NO ;
	
	//  close µH Router ports	
	if ( router != nil ) {	
		for ( i = 0; i < activeKeyers; i++ ) {
			keyerCache = &microKeyerCache[i] ;
			keyerCache->fskPort = keyerCache->controlPort = 0 ;
			if ( keyerCache->flagsPort > 0 ) {
				//  send a character to the flags FIFO to kill the thread
				dummy[0] = 0 ;
				write( keyerCache->flagsPort, dummy, 1 ) ;
				keyerCache->flagsPort = 0 ;
			}
		}
		[ NSThread sleepUntilDate:[ NSDate dateWithTimeIntervalSinceNow:0.1 ] ] ;
	}
	if ( currentFd > 0 ) {
		[ currentSerialPort close ] ;
		currentFd = 0 ;
	}
	currentSerialPort = nil ;
}

- (int)digiKeyerFSKPort
{
	MicroKeyer *keyer ;
	int i ;
	
	for ( i = 0; i < activeKeyers; i++ ) {
		keyer = microKeyerCache[i].keyer ;
		if ( [ keyer isDigiKeyer ] == YES ) return microKeyerCache[i].fskPort ;
	}
	return 0 ;
}

- (int)microKeyerFSKPort
{
	MicroKeyer *keyer ;
	int i ;
	
	for ( i = 0; i < activeKeyers; i++ ) {
		keyer = microKeyerCache[i].keyer ;
		if ( [ keyer isMicroKeyer ] == YES ) return microKeyerCache[i].fskPort ;
	}
	return 0 ;
}

//	v0.87
- (int)digiKeyerControlPort
{
	MicroKeyer *keyer ;
	int i ;
	
	for ( i = 0; i < activeKeyers; i++ ) {
		keyer = microKeyerCache[i].keyer ;
		if ( [ keyer isDigiKeyer ] == YES ) return microKeyerCache[i].controlPort ;
	}
	return 0 ;
}

//	v0.87
- (int)microKeyerControlPort
{
	MicroKeyer *keyer ;
	int i ;
	
	for ( i = 0; i < activeKeyers; i++ ) {
		keyer = microKeyerCache[i].keyer ;
		if ( [ keyer isMicroKeyer ] == YES ) return microKeyerCache[i].controlPort ;
	}
	return 0 ;
}

//  streams

- (Boolean)setSerialMark:(Boolean)mark
{
	if ( currentSerialPort == nil ) return NO ;
	return [ currentSerialPort setKeyState:mark ] ;
}

- (void)transmitBaudotCode:(int)code
{
	unsigned char buf[2] ;
	int bit, stopCount ;
	uint64_t deadline, bitInterval, halfBitInterval ;

	[ self setCurrentBaudotCharacter:code ] ;
	if ( serialMode ) {
		//  Use an absolute schedule for each edge so raw RTS/DTR FSK stays close
		//  to 45.45 baud framing even when the thread wakes up a little late.
		bitInterval = absoluteTimeUnitsForNanoseconds( currentBitPeriod*1000000000.0 + 0.5 ) ;
		halfBitInterval = absoluteTimeUnitsForNanoseconds( currentBitPeriod*500000000.0 + 0.5 ) ;
		deadline = mach_absolute_time() ;
		[ self setSerialMark:NO ] ;
		deadline += bitInterval ;
		sleepUntilAbsoluteTime( deadline ) ;
		for ( bit = 0; bit < 5; bit++ ) {
			[ self setSerialMark:( ( code >> bit ) & 0x1 ) != 0 ] ;
			deadline += bitInterval ;
			sleepUntilAbsoluteTime( deadline ) ;
		}
		stopCount = stopBitsCount[ currentStopBits & 0x3 ] ;
		for ( bit = 0; bit < stopCount; bit++ ) {
			[ self setSerialMark:YES ] ;
			deadline += halfBitInterval ;
			sleepUntilAbsoluteTime( deadline ) ;
		}
		return ;
	}
	buf[0] = code ;
	write( currentFd, buf, 1 ) ;
}

- (void)sendLTRS
{
	[ self transmitBaudotCode:CMLTRSCODE ] ;
	shift = kLTRSshift ;
	robustCount = 0 ;
}

- (void)sendFIGS
{
	[ self transmitBaudotCode:CMFIGSCODE ] ;
	shift = kFIGSshift ;
	robustCount = 0 ;
}

//  unmap phi to zero
static int unmap( int d )
{
	if ( d == 216 || d == 175 ) return '0' ;
	d &= 0x7f ;
	return d ;
}

//  v0.88 -- an approximation of the most recent character that was sent
- (int)currentBaudotCharacter
{
	return currentBaudotCharacter ;
}

//  v0.88 feedback to aural monitor
- (void)setCurrentBaudotCharacter:(int)c
{
	currentBaudotCharacter = c ;
}

//  v0.88 USOS "compatibility mode"
- (void)setRobustMode:(Boolean)state
{
	robust = state ;
	robustCount = 0 ;
}

- (void)sendNextBaudotCharacter:(int)index
{
	unsigned char buf[2] ;
	int ascii, bchar ;

	if ( currentFd <= 0 || running == NO ) return ;
	
	if ( pendingASCII != 0 ) {
		ascii = pendingASCII ;
		pendingASCII = 0 ;
	}
	else {
		if ( producer == consumer ) {
			//  no new characters, send LTRS as diddle
			[ self sendLTRS ] ;
			return ;
		}

		ascii = fskBuffer[ consumer & 0x7ff ] ;
		consumer = ( consumer + 1 ) & 0x7ff ;
		if ( modem ) [ modem transmittedCharacter:ascii ] ;
	}
	
	if ( ascii == 0x5 || ascii == 0x1a ) return ;
	
	//  Keep ext-FSK compatible with the AFSK Baudot encoder, including explicit
	//  \l (LTRS) / \f (FIGS) macro insertions.
	if ( ascii == CMLTRSCODE || ascii == '=' ) {
		[ self sendLTRS ] ;
		return ;
	}
	if ( ascii == CMFIGSCODE ) {
		[ self sendFIGS ] ;
		return ;
	}

	if ( ascii == '\n' ) {
		//  match the AFSK encoder by transmitting a CR/LF pair for a text view newline.
		pendingASCII = '\n' ;
		ascii = '\r' ;
	}
	
	bchar = baudot[ unmap( ascii & 0xff ) & 0x7f ] ;
	
	if ( spaceFollowedFIGS ) {
		if ( robust == YES ) {
			//  check if we need to force a LTRS shift (for USOS) or FIGS shift (for non-USOS)
			if ( usos == YES ) {
				//  transmitting with USOS, check for the case "1<space>A"
				if ( ( bchar & FIGSMASK ) == 0 ) [ self sendLTRS ] ;  // current character is not FIGS, force a LTRS out in USOS
			}
			else {
				//  transmitting with non-USOS, check for the case "1<space>2"
				if ( ( bchar & LTRSMASK ) == 0 ) [ self sendFIGS ] ;  // current character is not LTRS, force a FIGS out in USOS
			}
		}
		spaceFollowedFIGS = NO ;
	}
	
	if ( shift == kLTRSshift ) {
		//  changing from LTRS to FIGS
		if ( ( bchar & LTRSMASK ) == 0 ) [ self sendFIGS ] ;
	}
	else {
		//  changing from FIGS to LTRS
		if ( ( bchar & FIGSMASK ) == 0 ) [ self sendLTRS ] ;
	}

	//	send character now
	buf[0] = bchar & 0x1f ;
	[ self transmitBaudotCode:buf[0] ] ;
	robustCount++ ;																//  v0.88 added robust mode to FSK
	
	spaceFollowedFIGS = NO ;
	//  v0.84 bug fix: change shift to LTRS if USOS is on
	if ( ascii == ' ' ) {
		if ( shift == kFIGSshift ) spaceFollowedFIGS = YES ;					//  v0.88 for USOS compatibility
		if ( usos == YES ) {
			//  note: no explicit LTRS character is sent
			shift = kLTRSshift ;
		}
	}
	if ( robustCount >= kRobustThreshold ) {										//  v0.88 robust mode
		if ( shift == kLTRSshift ) [ self sendLTRS ] ;							
		if ( shift == kFIGSshift ) [ self sendFIGS ] ;
	}
}

//  thread to poll for flag changes
- (void)pollThread
{
	NSAutoreleasePool *pool = [ [ NSAutoreleasePool alloc ] init ] ;
	int fd, i, count, bytes ;

	//  Start polling.  select() blocks until one or more file descriptors has data
	while ( 1 ) {
		if ( closed ) break ;
		//  poll the full set
		FD_COPY( &selectSet, &readSet ) ;
		count = select( selectCount+1, &readSet, nil, nil, nil ) ;
		
		if ( count < 0 ) break ;		//  abort polling when an error is seen
		if ( count > 0 ) {
			for ( i = 0; i < activeKeyers; i++ ) {
				fd = microKeyerCache[i].flagsPort ;
				if ( fd > 0 ) {
					if ( FD_ISSET( fd, &readSet ) ) {
						bytes = read( fd, tempBuffer, 1 ) ;
						if ( bytes == 1 && ( tempBuffer[0] & 0x20 ) == 0 ) {
							[ self sendNextBaudotCharacter:i ] ;
						}						
						count-- ;
					}
				}
			}
			//  sanity check -- clear everything fd if count not zero
			if ( count > 0 ) {
				for ( fd = 0; fd < FD_SETSIZE; fd++ ) {
					if ( FD_ISSET( fd, &readSet ) ) {
						read( fd, tempBuffer, 64 ) ;
					}
				}
			}
		}
	}
	[ pool release ] ;
}

- (void)serialThread
{
	NSAutoreleasePool *pool = [ [ NSAutoreleasePool alloc ] init ] ;

	if ( running ) {
		[ self setSerialMark:YES ] ;
	}
	[NSThread sleepUntilDate:[ NSDate dateWithTimeIntervalSinceNow:0.18 ] ] ;
	if ( running ) {
		fskBusy = YES ;
		[ self setSerialMark:YES ] ;
	}
	while ( running && serialMode && currentFd > 0 ) {
		[ self sendNextBaudotCharacter:0 ] ;
	}
	[ self setSerialMark:YES ] ;
	[ pool release ] ;
}

//  start is delayed to allow a steady mark tone that is at least a character long after PTT is engaged
//  This makes sure the first character prints correctly.
- (void)delayedStart:(NSTimer*)timer
{
	running = YES ;
	[ self sendLTRS ] ;		//  fires off the stream
	fskBusy = YES ;
}

- (void)setupBaudRate:(int)rate invertFSK:(Boolean)invertFSK stopIndex:(int)stopIndex keyerCache:(MicroHamKeyerCache*)keyerCache
{
	int controlWrite ;
	unsigned char buf[32] ;

	if ( router != nil ) {
		controlWrite = [ keyerCache->keyer controlWriteDescriptor ] ;
		if ( controlWrite > 0 ) {
			//  baud rate
			buf[0] = 0x03 ;
			buf[1] = rate & 0xff ;
			buf[2] = ( rate / 256 ) & 0xff ;
			buf[3] = stopMask[ stopIndex & 0x3 ] ;	//  stop bits
			buf[4] = 0x83 ;
			write( controlWrite, buf, 5 ) ;
			[ NSThread sleepUntilDate:[ NSDate dateWithTimeIntervalSinceNow:0.01 ] ] ;
            // TEB - should be configurable!
			//  set digital keyer mode v0.68
			//buf[0] = 0x0a ;
			// buf[1] = 0x03 ;
			//buf[2] = 0x8a ;
			//write( controlWrite, buf, 3 ) ;
			[ NSThread sleepUntilDate:[ NSDate dateWithTimeIntervalSinceNow:0.01 ] ] ;
			//  invert FSK v0.68 (use the special 0f..8f backdoor in µH Router)
			buf[0] = 0x0f ;
			buf[1] = 0x01 ;
			buf[2] = ( invertFSK ) ? 1 : 0 ;
			buf[3] = 0x8f ;
			write( controlWrite, buf, 4 ) ;
			[ NSThread sleepUntilDate:[ NSDate dateWithTimeIntervalSinceNow:0.01 ] ] ;
		}
	}
}

- (void)startSampling:(int)fd baudRate:(float)baudRate invert:(Boolean)invertTx stopBits:(int)stopIndex modem:(RTTY*)inModem
{
	int i, rate ;
	MicroHamKeyerCache *keyerCache ;
		
	if ( fskBusy ) [ self stopSampling ] ;
	
	currentFd = 0 ;
	currentPortToken = fd ;
	serialMode = NO ;
	currentSerialPort = nil ;
	if ( fd >= 0x10000 ) {
		for ( i = 0; i < serialPortCount; i++ ) {
			if ( [ serialPorts[i] token ] == fd ) {
				currentSerialPort = serialPorts[i] ;
				[ currentSerialPort setInvert:invertTx ] ;
				if ( ![ currentSerialPort openForWrite ] ) {
					currentSerialPort = nil ;
					return ;
				}
				currentFd = [ currentSerialPort fileDescriptor ] ;
				currentSerialLine = [ currentSerialPort line ] ;
				currentBitPeriod = 1.0 / ( ( baudRate < 10.0 ) ? 10.0 : baudRate ) ;
				currentStopBits = stopIndex ;
				serialInvert = invertTx ;
				modem = inModem ;
				producer = consumer = 0 ;
				shift = kLTRSshift ;
				spaceFollowedFIGS = NO ;
				pendingASCII = 0 ;
				robustCount = 0 ;
				serialMode = YES ;
				running = YES ;
				[ self setSerialMark:YES ] ;
				[ NSThread detachNewThreadSelector:@selector(serialThread) toTarget:self withObject:nil ] ;
				return ;
			}
		}
		return ;
	}
	currentFd = fd ;
	if ( fd > 0 ) {
		for ( i = 0; i < activeKeyers; i++ ) {
			keyerCache = &microKeyerCache[i] ;
			if ( fd == keyerCache->fskPort ) break ; 
		}
		if ( i >= activeKeyers ) return ;		//  fd not found
		
		//  check and set baud rate
		if ( baudRate < 10 ) baudRate = 10 ;
		rate = 2700.0/baudRate + 0.5 ;
		
		modem = inModem ;
		
		if ( rate != keyerCache->currentBaudConstant || invertTx != keyerCache->currentTxInvert || stopIndex != keyerCache->currentStopIndex ) {
			[ self setupBaudRate:rate invertFSK:invertTx stopIndex:stopIndex keyerCache:keyerCache ] ;
		}
		keyerCache->currentBaudConstant = rate ;
		keyerCache->currentTxInvert = invertTx ;
		keyerCache->currentStopIndex = stopIndex ;

		producer = consumer = 0 ;
		pendingASCII = 0 ;
		[ NSTimer scheduledTimerWithTimeInterval:0.18 target:self selector:@selector(delayedStart:) userInfo:self repeats:NO ] ;
	}
}

- (void)stopSampling
{
	running = fskBusy = NO ;
	modem = nil ;
	if ( serialMode && currentFd > 0 ) {
		[ self setSerialMark:YES ] ;
		if ( currentSerialPort ) [ currentSerialPort close ] ; else close( currentFd ) ;
		currentFd = 0 ;
	}
	serialMode = NO ;
}

- (void)clearOutput
{
	producer = consumer = 0 ;
	pendingASCII = 0 ;
}

- (Boolean)outputEmpty
{
	return ( producer == consumer && pendingASCII == 0 ) ;
}

- (void)appendASCII:(int)ascii
{
	int next ;
	
	next = ( producer+1 ) & 0x7ff ;
	if ( next == consumer ) return ;
	
	fskBuffer[ producer & 0x7ff ] = ascii ;
	producer = next ;
}

@end
