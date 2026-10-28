//
//  IndicatorCompat.h
//  cocoaModem
//

#ifndef _INDICATORCOMPAT_H_
#define _INDICATORCOMPAT_H_

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

static inline void CMSetIndicatorColor( id indicator, NSColor *color )
{
	NSColor *rgbColor ;
	CALayer *layer ;

	if ( indicator == nil || color == nil ) return ;

	if ( [ indicator respondsToSelector:@selector(setDrawsBackground:) ] ) [ (id)indicator setDrawsBackground:YES ] ;
	if ( [ indicator respondsToSelector:@selector(setBackgroundColor:) ] ) [ (id)indicator setBackgroundColor:color ] ;

	if ( [ indicator respondsToSelector:@selector(setWantsLayer:) ] && [ indicator respondsToSelector:@selector(layer) ] ) {
		[ (NSView*)indicator setWantsLayer:YES ] ;
		layer = [ (NSView*)indicator layer ] ;
		if ( layer ) {
			rgbColor = [ color colorUsingColorSpace:[ NSColorSpace deviceRGBColorSpace ] ] ;
			if ( rgbColor == nil ) rgbColor = color ;
			[ layer setBackgroundColor:[ rgbColor CGColor ] ] ;
			[ layer setBorderWidth:1.0 ] ;
			[ layer setBorderColor:[ [ NSColor colorWithCalibratedWhite:0.2 alpha:1.0 ] CGColor ] ] ;
		}
	}

	if ( [ indicator respondsToSelector:@selector(setNeedsDisplay:) ] ) [ (id)indicator setNeedsDisplay:YES ] ;
}

#endif
