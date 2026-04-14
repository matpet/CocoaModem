//
//  SerialLineKeyer.h
//  cocoaModem 2.0
//

#ifndef _SERIALLINEKEYER_H_
	#define _SERIALLINEKEYER_H_

	#import <Cocoa/Cocoa.h>
	#include <termios.h>

	@interface SerialLineKeyer : NSObject {
		NSString *path ;
		NSString *name ;
		int line ;
		int token ;
		int fileDescriptor ;
		struct termios originalTTYAttrs ;
		Boolean hasOriginalTTYAttrs ;
		Boolean invert ;
		NSConditionLock *timedQueueLock ;
		Boolean timedQueueRunning ;
		Boolean timedQueueClosed ;
		int timedQueueProducer ;
		int timedQueueConsumer ;
		struct {
			Boolean state ;
			int microseconds ;
		} timedQueue[4096] ;
	}

	+ (int)findSerialPorts:(NSString**)path stream:(NSString**)stream maxPorts:(int)maxPorts ;

	- (id)initWithPath:(NSString*)devicePath line:(int)serialLine name:(NSString*)deviceName token:(int)serialToken ;
	- (Boolean)matchesPath:(NSString*)devicePath line:(int)serialLine ;
	- (Boolean)openForWrite ;
	- (void)close ;
	- (Boolean)setKeyState:(Boolean)state ;
	- (void)queueKeyState:(Boolean)state microseconds:(int)microseconds ;
	- (void)clearQueuedKeyStates ;
	- (void)setInvert:(Boolean)state ;

	- (NSString*)path ;
	- (NSString*)name ;
	- (int)line ;
	- (int)token ;
	- (int)fileDescriptor ;

	@end

#endif
