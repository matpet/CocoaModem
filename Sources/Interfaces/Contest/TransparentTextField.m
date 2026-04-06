//
//  TransparentTextField.m
//  cocoaModem
//
//  Created by Kok Chen on 11/23/04.
	#include "Copyright.h"
//

#import "TransparentTextField.h"
#import <QuartzCore/QuartzCore.h>


static void setEditorColors( NSText* editor )
{
	NSDictionary *attributes ;

	if ( editor == nil ) return ;
	if ( [ editor respondsToSelector:@selector(setTextColor:) ] ) [ (id)editor setTextColor:[ NSColor blackColor ] ] ;
	if ( [ editor respondsToSelector:@selector(setInsertionPointColor:) ] ) [ (id)editor setInsertionPointColor:[ NSColor blackColor ] ] ;
	attributes = @{
		NSForegroundColorAttributeName:[ NSColor blackColor ],
		NSBackgroundColorAttributeName:[ NSColor selectedTextBackgroundColor ]
	} ;
	if ( [ editor respondsToSelector:@selector(setSelectedTextAttributes:) ] ) [ (id)editor setSelectedTextAttributes:attributes ] ;
}

static void setFieldHighlightState( NSView *view, Boolean state )
{
	CALayer *layer ;

	if ( view == nil ) return ;
	[ view setWantsLayer:YES ] ;
	layer = [ view layer ] ;
	if ( layer == nil ) return ;
	[ layer setCornerRadius:3.0 ] ;
	[ layer setBorderWidth:( state ) ? 2.0 : 1.0 ] ;
	[ layer setBorderColor:( state ) ? [ [ NSColor redColor ] CGColor ] : [ [ NSColor lightGrayColor ] CGColor ] ] ;
}


@implementation TransparentTextField


//  transparent text field for use over a watermark (e.g., DUPE warning)
- (void)awakeFromNib
{
	//  accepts fontChanges messages here
	[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(setContestFont:) name:@"ContestFont" object:nil ] ;
	
	fieldType = 0 ;
	savedString = @"" ;
	ignore = NO ;
	[ self setBezeled:YES ] ;
	[ self setBordered:YES ] ;
	[ self setDrawsBackground:YES ] ;
	[ self setBackgroundColor:[ NSColor whiteColor ] ] ;
	[ self setTextColor:[ NSColor blackColor ] ] ;
	[ self setEditable:YES ] ;
	[ self setSelectable:YES ] ;
	[ self setEnabled:YES ] ;
	setEditorColors( [ self currentEditor ] ) ;
}

//  kCallsignTextField, kExchangeTextField
- (void)setFieldType:(int)type
{
	fieldType = type ;
}

- (int)fieldType
{
	return fieldType ;
}

- (void)markAsSelected:(Boolean)state
{
	[ self setBordered:YES ] ;
	setFieldHighlightState( self, state ) ;
}

- (void)notifyFieldSelected
{
	[ [ NSNotificationCenter defaultCenter ] postNotificationName:@"SelectNewField" object:self ] ;
}

- (NSString*)clickedString
{
	return savedString ;
}

- (void)setIgnoreFirstResponder:(Boolean)state
{
	ignore = state ;
}

//  clear savedString if the field is manually edited
- (BOOL)textShouldEndEditing:(NSText *)textObject
{
	savedString = @"" ;
	return [ super textShouldEndEditing:textObject ] ;
}

- (BOOL)acceptsFirstResponder
{
	return !ignore ;
}

//  save string in clicked string
//  any non zero length string here would cause a click/control click to cause an IBAction
- (BOOL)becomeFirstResponder
{
	savedString = [ self stringValue ] ;
	if ( ignore ) {
		ignore = NO ;
		return YES ;
	}
	if ( [ super becomeFirstResponder ] ) {
		setEditorColors( [ self currentEditor ] ) ;
		[ self notifyFieldSelected ] ;
		return YES ;
	}
	return NO ;
}

- (void)mouseDown:(NSEvent*)event
{
	savedString = [ self stringValue ] ;
	if ( !ignore ) [ self notifyFieldSelected ] ;
	[ super mouseDown:event ] ;
}

- (void)moveAbove
{
	NSView *view ;
	
	view = [ self superview ] ;
	[ self retain ] ;
	[ self removeFromSuperview ] ;
	[ view addSubview:self positioned:NSWindowAbove relativeTo:nil ] ;
	[ self release ] ;  // addSubview should do one retain
}

//  NSNotification with name "ContestFont" is sent when font changes
- (void)setContestFont:(NSNotification*)notify
{
	NSFont *font ;
	
	font = [ notify object ] ;
	if ( font ) [ self setFont:font ] ;
	[ self setBackgroundColor:[ NSColor whiteColor ] ] ;
	[ self setTextColor:[ NSColor blackColor ] ] ;
	setEditorColors( [ self currentEditor ] ) ;

	//  redraw
	[ self setStringValue:[ self stringValue ] ] ;
}

@end
