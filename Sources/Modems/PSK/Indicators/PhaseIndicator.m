//
//  PhaseIndicator.m
//  cocoaModem
//
//  Created by Kok Chen on Tue Sep 07 2004.
	#include "Copyright.h"
//

#import "PhaseIndicator.h"
#include "DisplayColor.h"


@implementation PhaseIndicator

- (void)updateGeometry
{
	NSSize bsize ;

	bounds = [ self bounds ] ;
	bsize = bounds.size ;
	width = bsize.width ;
	height = bsize.height ;
}

- (BOOL)isOpaque
{
	return YES ;
}

- (void)awakeFromNib
{
	[ self updateGeometry ] ;
	xpos = -1 ; 
	yellow = [ [ NSColor colorWithDeviceRed:0.95 green:0.95 blue:0.0 alpha:1.0 ] retain ] ;
	black = [ [ NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.1 alpha:1.0 ] retain ] ;
}

- (void)drawRect:(NSRect)rect 
{
	NSBezierPath *path ;

	[ self updateGeometry ] ;
	[ black set ] ;
	path = [ NSBezierPath bezierPathWithRect:bounds ] ;
	[ path fill ] ;

	if ( xpos >= 0 ) {
		[ yellow set ] ;
		path = [ NSBezierPath bezierPath ] ;
		[ path setLineWidth:1.5 ] ;
		[ path moveToPoint:NSMakePoint( xpos, 0 ) ] ;
		[ path lineToPoint:NSMakePoint( xpos, height ) ] ;
		[ path stroke ] ;
	}
	[ super drawRect:rect ] ;
}

- (void)displayInMainThread
{
	[ self setNeedsDisplay:YES ] ;
}

- (void)newPhaseInMainThread:(NSNumber*)phaseNumber
{
	float radian ;
	int previous ;

	radian = [ phaseNumber floatValue ] ;
	if ( radian < -1.5708 || radian > 1.5708 ) return ;

	[ self updateGeometry ] ;
	previous = xpos ;
	xpos = ( radian + 1.5708 )/3.14145926*width + 0.5 ;
	if ( xpos != previous ) [ self displayInMainThread ] ;
}

//  radian is angle between -pi/2 to +pi/2
- (void)newPhase:(float)radian
{
	if ( [ NSThread isMainThread ] ) {
		[ self newPhaseInMainThread:[ NSNumber numberWithFloat:radian ] ] ;
	}
	else {
		[ self performSelectorOnMainThread:@selector(newPhaseInMainThread:) withObject:[ NSNumber numberWithFloat:radian ] waitUntilDone:NO ] ;
	}
}

- (void)clearInMainThread
{
	xpos = -1 ;
	[ self displayInMainThread ] ;
}

- (void)clear
{
	if ( [ NSThread isMainThread ] ) {
		[ self clearInMainThread ] ;
	}
	else {
		[ self performSelectorOnMainThread:@selector(clearInMainThread) withObject:nil waitUntilDone:NO ] ;
	}
}
@end
