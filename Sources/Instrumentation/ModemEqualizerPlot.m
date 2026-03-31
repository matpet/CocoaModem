//
//  ModemEqualizerPlot.m
//  cocoaModem 2.0
//
//  Created by Kok Chen on 11/30/06.
	#include "Copyright.h"
	
	
#import "ModemEqualizerPlot.h"
#include <math.h>


@implementation ModemEqualizerPlot

- (id)initWithFrame:(NSRect)frame 
{
	NSSize size ;
	int i,n ;
	CGFloat dash[2] = { 2.0, 1.0 } ;
	float x, xp[81] ;
	
    self = [ super initWithFrame:frame ] ;
    if ( self ) {
		bounds = [ self bounds ] ;
		size = bounds.size ;
		width = size.width ;
		height = size.height ;
		if ( !isfinite( width ) || width <= 0.0 ) width = ( isfinite( frame.size.width ) && frame.size.width > 0.0 ) ? frame.size.width : 1.0 ;
		if ( !isfinite( height ) || height <= 0.0 ) height = ( isfinite( frame.size.height ) && frame.size.height > 0.0 ) ? frame.size.height : 1.0 ;

		plotColor = [ [ NSColor colorWithCalibratedRed:0.9 green:0.9 blue:0 alpha:1 ] retain ] ;
		plot = nil ;
		
		//  background
		backgroundColor = [ [ NSColor colorWithDeviceRed:0 green:0.1 blue:0 alpha:1 ] retain ] ;
		background = [ [ NSBezierPath alloc ] init ] ;
		[ background appendBezierPathWithRect:NSMakeRect( 0, 0, width, height ) ] ;
		//  scale
		scaleColor = [ [ NSColor colorWithCalibratedRed:0 green:1 blue:0.1 alpha:1 ] retain ] ;
		scale = [ [ NSBezierPath alloc ] init ] ;
		[ scale setLineDash:dash count:2 phase:0 ] ;
		for ( i = 0; i < 4; i++ ) {
			n = ( 0.1 + i*0.24 )*width ;
			x = n + 0.5 ;
			[ scale moveToPoint:NSMakePoint( x, 0 ) ] ;
			[ scale lineToPoint:NSMakePoint( x, height ) ] ;
		}
		for ( i = 0; i < 81; i++ ) xp[i] = 0.0 ;	//  flat 0 dB response
		[ self setResponse:xp ] ;
	}
	return self ;
}

//  accepts a response curve (dB) from 400 Hz to 2400 Hz inclusive (81 samples) at 25 Hz resolution
- (void)setResponse:(float*)array
{
	int i ;
	float x, y, response ;
	
	if ( plot ) [ plot release ] ;
	plot = [ [ NSBezierPath alloc ] init ] ;
	for ( i = 0; i < 81; i++ ) {
		response = array[i] ;
		if ( !isfinite( response ) ) response = 0.0 ;
		x = ( 0.1 + response*0.24 )*width ;
		y = height*( 1.0 - i/82.0 ) - 8.0 ;
		if ( !isfinite( x ) ) x = 0.0 ;
		if ( !isfinite( y ) ) y = 0.0 ;
		if ( i == 0 ) [ plot moveToPoint:NSMakePoint( x, y ) ] ; else [ plot lineToPoint:NSMakePoint( x, y ) ] ;
	}
}

- (void)drawRect:(NSRect)frame
{
	[ backgroundColor set ] ;
	[ background fill ] ;
	//  insert scale
	[ scaleColor set ] ;
	[ scale stroke ] ;
	if ( plot ) {
		//  insert plot
		[ plotColor set ] ;
		[ plot stroke ] ;
	}
}

@end
