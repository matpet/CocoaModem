//
//  FrequencyIndicator.m
//  cocoaModem
//
//  Created by Kok Chen on Thu Sep 02 2004.
	#include "Copyright.h"
//

#import "FrequencyIndicator.h"
#include "DisplayColor.h"


@implementation FrequencyIndicator

- (void)drawWaterfallInRect:(NSRect)rect
{
	CGColorSpaceRef colorSpace ;
	CGContextRef context ;
	CGDataProviderRef provider ;
	CGImageRef imageRef ;

	if ( bitmaps[0] == nil || width <= 0 || height <= 0 ) return ;

	colorSpace = CGColorSpaceCreateDeviceRGB() ;
	if ( colorSpace == nil ) return ;

	provider = CGDataProviderCreateWithData( nil, bitmaps[0], rowBytes*height, nil ) ;
	if ( provider == nil ) {
		CGColorSpaceRelease( colorSpace ) ;
		return ;
	}

	imageRef = CGImageCreate( width, height, 8, 32, rowBytes, colorSpace, kCGBitmapByteOrder32Big | kCGImageAlphaLast, provider, nil, NO, kCGRenderingIntentDefault ) ;
	if ( imageRef ) {
		context = [ [ NSGraphicsContext currentContext ] CGContext ] ;
		CGContextSaveGState( context ) ;
		CGContextTranslateCTM( context, rect.origin.x, rect.origin.y + rect.size.height ) ;
		CGContextScaleCTM( context, rect.size.width/width, -rect.size.height/height ) ;
		CGContextDrawImage( context, CGRectMake( 0, 0, width, height ), imageRef ) ;
		CGContextRestoreGState( context ) ;
		CGImageRelease( imageRef ) ;
	}
	CGDataProviderRelease( provider ) ;
	CGColorSpaceRelease( colorSpace ) ;
}

- (void)awakeFromNib
{
	NSSize bsize ;
	int i, lsize ;
	UInt32 bg ;
		
	//  check window depth
	depth = NSBitsPerPixelFromDepth( [ NSWindow defaultDepthLimit ] ) ;  //  m = 24, t = 12, 256 = 8
	if ( depth < 24 ) depth = 32 ;

	sideband = NO ;

	bsize = [ self bounds ].size ;
	width = bsize.width ;  
	height = bsize.height ;  
	if ( width > 256 ) width = 256 ;	// local spectrum buffer limit
	
	pendingMainThreadDraw = NO ;
	bitmaps[0] = bitmaps[1] = bitmaps[2] = bitmaps[3] = bitmaps[4] = nil ;

	thread = [ NSThread currentThread ] ;
	[ self setRange:60.0 ] ;
	
	if ( depth >= 24 ) {
		bg = intensity[0] ;
		//  Uses 32 bit/pixel for millions of colors mode, all components of a pixel can then be written with a single int write.
		rowBytes = width*4 ;
		lsize = size = rowBytes*height/4 ;
		bitmaps[0] = ( unsigned char* )malloc( rowBytes*height ) ;
		bitmap = ( NSBitmapImageRep* )[ [ NSBitmapImageRep alloc ] initWithBitmapDataPlanes:bitmaps 
					pixelsWide:width pixelsHigh:height
					bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
					colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:rowBytes bitsPerPixel:32 ] ;
	}
	else {
		bg = ( intensity[0] << 16 ) | intensity[0] ;
		rowBytes = ( ( width*2 + 3 )/4 ) * 4 ;
		lsize = ( size = rowBytes*height/2 )/2 ;
		//  Uses 16 bit/pixel for thousands of colors mode, all components of a pixel can then be written with a single short write.
		bitmaps[0] = ( unsigned char* )malloc( rowBytes*height ) ;
		bitmap = ( NSBitmapImageRep* )[ [ NSBitmapImageRep alloc ] initWithBitmapDataPlanes:bitmaps 
					pixelsWide:width pixelsHigh:height
					bitsPerSample:4 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
					colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:rowBytes bitsPerPixel:16 ] ;
		
	}
	
	if ( bitmap && bitmaps[0] ) {
		[ bitmap retain ] ;
		pixel = ( UInt32* )bitmaps[0] ;
		for ( i = 0; i < lsize; i++ ) pixel[i] = bg ;
		image = [ [ NSImage alloc ] init ] ;
		[ image addRepresentation:bitmap ] ;
		[ self setImageScaling:NSScaleNone ] ;
		[ self setImage:image ] ;
	}
}

- (void)dealloc
{
	if ( image && bitmap ) [ image removeRepresentation:bitmap ] ;
	if ( bitmap ) [ bitmap release ] ;
	if ( image ) [ image release ] ;
	if ( bitmaps[0] ) free( bitmaps[0] ) ;
	[ super dealloc ] ;
}

- (BOOL)isOpaque
{
	return YES ;
}

//  0 = LSB
- (void)setSideband:(int)state
{
	sideband = ( state == 1 ) ;
}

- (void)drawRect:(NSRect)rect 
{
	NSBezierPath *line ;
	float p ;
	
	if ( bitmap ) {
		[ self drawWaterfallInRect:[ self bounds ] ] ;
	}
	else {
		[ [ NSColor blackColor ] set ] ;
		NSRectFill( [ self bounds ] ) ;
	}
	line = [ NSBezierPath bezierPath ] ;
	[ line setLineWidth:1 ] ;
	p = width/2 - 15.5 ;
	[ line moveToPoint:NSMakePoint( p, 0 ) ] ;
	[ line lineToPoint:NSMakePoint( p, 4 ) ] ;
	[ line moveToPoint:NSMakePoint( p, height ) ] ;
	[ line lineToPoint:NSMakePoint( p, height-4 ) ] ;
	p = width/2 + 0.5;
	[ line moveToPoint:NSMakePoint( p, 0 ) ] ;
	[ line lineToPoint:NSMakePoint( p, height ) ] ;
	p = width/2 + 16.5 ;
	[ line moveToPoint:NSMakePoint( p, 0 ) ] ;
	[ line lineToPoint:NSMakePoint( p, 4 ) ] ;
	[ line moveToPoint:NSMakePoint( p, height ) ] ;
	[ line lineToPoint:NSMakePoint( p, height-4 ) ] ;
	[ [ NSColor redColor ] set ] ;
	[ line stroke ] ;
}

- (void)setRange:(float)value
{
	NSColor *a, *b, *c, *d ;
	float v, map, inten, p ;
	CGFloat r0, g0, b0, a0, r1, g1, b1, a1 ;
	int i ;
	
	exponent = 0.25 ;
	range = value ;
	if ( range > 79 ) p = 1.0 ;
	else {
		if ( range > 59 ) p = 1.414 ;
		else {
			if ( range > 39 ) p = 2.0 ;
			else p = 2.818 ;
		}
	}
	//  create color scale, defined by 4 colors
	//  use a 20000 element table to achieve 85 dB of dynamic range
	a = [ NSColor colorWithCalibratedRed:0.0 green:0 blue:0.2 alpha:0 ] ;
	b = [ NSColor colorWithCalibratedRed:0 green:0.0 blue:0.8 alpha:0 ] ;
	c = [ NSColor colorWithCalibratedRed:0.0 green:0.5 blue:0.5 alpha:0 ] ;
	d = [ NSColor colorWithCalibratedRed:0.7 green:0.7 blue:0 alpha:0 ] ;
	
	for ( i = 0; i < 20000; i++ ) {
		map = pow( i/20000.0, p )*2 ;
		if ( map > 1 ) map = 1 ;
		inten = 1.0 ;
		if ( map < .3 ) {
			v = map/.3 ;
			[ a getRed:&r0 green:&g0 blue:&b0 alpha:&a0 ] ;
			[ b getRed:&r1 green:&g1 blue:&b1 alpha:&a1 ] ;
		}
		else {
			if ( map < 0.95 ) {
				v = ( map-.3 )/0.65 ;
				[ b getRed:&r0 green:&g0 blue:&b0 alpha:&a0 ] ;
				[ c getRed:&r1 green:&g1 blue:&b1 alpha:&a1 ] ;
			}
			else {
				v = ( map-0.95 )/0.05 ;
				[ c getRed:&r0 green:&g0 blue:&b0 alpha:&a0 ] ;
				[ d getRed:&r1 green:&g1 blue:&b1 alpha:&a1 ] ;
			}
		}
		r0 = inten*( ( 1.0-v )*r0 + v*r1 ) ;
		g0 = inten*( ( 1.0-v )*g0 + v*g1 ) ;
		b0 = inten*( ( 1.0-v )*b0 + v*b1 ) ;
		
		if ( depth >= 24 ) {
			intensity[i] = [ DisplayColor millionsOfColorsFromRed:r0 green:g0 blue:b0 ] ;
		}
		else {
			intensity[i] = [ DisplayColor thousandsOfColorsFromRed:r0 green:g0 blue:b0 ] ;
		}
	}
}

- (int)plotValue:(float)sample
{
	return pow( sample, exponent ) * 20000.0 ;
}

- (void)displayInMainThread
{
	pendingMainThreadDraw = NO ;
	[ self setNeedsDisplay:YES ] ;
}

- (void)requestDisplayInMainThread
{
	if ( pendingMainThreadDraw ) return ;
	pendingMainThreadDraw = YES ;
	[ self performSelectorOnMainThread:@selector(displayInMainThread) withObject:nil waitUntilDone:NO ] ;
}

// v0.57 - n changed to 1024 for 1000s/sec sampling rate
- (void)newSpectrum:(DSPSplitComplex*)spec size:(int)n
{
	float g[256], p, q, power, *re, *im, min, max, norm ;
	char *src, *insert ;
	int i, m, index ;
	UInt32 *line ;
	UInt16 *sline ;
	
	if ( n != 1024 ) return ;
	if ( width < 4 || width > 256 ) return ;
	
	re = spec->realp ;
	im = spec->imagp ;
	m = width/2 ;			//  0.32 bug fix (was 192)
	g[0] = 0 ;
	for ( i = 0; i < m; i++ ) {
		p = re[i] ;
		q = im[i] ;
		power = p*p + q*q ;
		if ( power != power || power < 0 ) power = 0 ;
		g[width/2+i] = power ;
	}
	for ( i = 1; i <= m; i++ ) {
		p = re[1024-i] ;
		q = im[1024-i] ;
		power = p*p + q*q ;
		if ( power != power || power < 0 ) power = 0 ;
		g[width/2-i] = power ;
	}
	min = max = g[0] ;
	for ( i = 1; i < width; i++ ) {
		if ( g[i] > max ) max = g[i] ;
		else if ( g[i] < min ) min = g[i] ;
	}
	norm = 1.0/( max - min + .001 ) ;
	for ( i = 0; i < width; i++ ) {
		g[i] = ( g[i] - min )*norm ;
	}
	
	src = ( ( char* )pixel ) + rowBytes ;
	memcpy( pixel, src, rowBytes*( height-1 ) ) ;
	insert = ( ( char* )pixel ) + rowBytes*( height-1 ) ;
	
	if ( sideband ) {
		if ( depth >= 24 ) {
			line = (UInt32*)( insert ) ;
			for ( i = 0; i < width; i++ ) {
				index = [ self plotValue:g[i] ] ;
				if ( index > 19999 ) index = 19999 ;
				line[i] = intensity[index] ;
			}
		}
		else {
			sline = (UInt16*)( insert ) ;
			for ( i = 0; i < width; i++ ) {
				index = [ self plotValue:g[i] ] ;
				if ( index > 19999 ) index = 19999 ;
				sline[i] = intensity[index] ;
			}
		}
	}
	else {
		if ( depth >= 24 ) {
			line = (UInt32*)( insert ) ;
			for ( i = 0; i < width; i++ ) {
				index = [ self plotValue:g[width-i-1] ] ;
				if ( index > 19999 ) index = 19999 ;
				line[i] = intensity[index] ;
			}
		}
		else {
			sline = (UInt16*)( insert ) ;
			for ( i = 0; i < width; i++ ) {
				index = [ self plotValue:g[width-i-1] ] ;
				if ( index > 19999 ) index = 19999 ;
				sline[i] = intensity[index] ;
			}
		}
	}
	[ self requestDisplayInMainThread ] ;
}

- (void)clear
{
	char *s ;
	UInt32 *line, value ;
	UInt16 *sline ;
	int i ;
	
	value = intensity[0] ;
	if ( depth >= 24 ) {
		line = (UInt32*)( pixel ) ;
		for ( i = 0; i < width; i++ ) line[i] = value ;
	}
	else {
		sline = (UInt16*)( pixel ) ;
		for ( i = 0; i < width; i++ ) sline[i] = value ;
	}

	s = ( (char*)pixel ) + rowBytes ;
	for ( i = 1; i < height; i++ ) {
		memcpy( s, pixel, rowBytes ) ;
		s += rowBytes ;
	}
	[ self requestDisplayInMainThread ] ;
}


@end
