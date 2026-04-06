//
//  VoiceAssistTextField.m
//  cocoaModem 2.0
//
//  Created by Kok Chen on 4/13/12.
//  Copyright 2012 Kok Chen, W7AY. All rights reserved.
//

#import "VoiceAssistTextField.h"
#import "Application.h"
#import "AppDelegate.h"

static NSColor *fieldBackgroundColor( void )
{
	return [ NSColor textBackgroundColor ] ;
}

static NSColor *fieldTextColor( void )
{
	return [ NSColor textColor ] ;
}

static void setVoiceAssistEditorColors( NSText *editor )
{
	NSDictionary *attributes ;

	if ( editor == nil ) return ;
	if ( [ editor respondsToSelector:@selector(setTextColor:) ] ) [ (id)editor setTextColor:fieldTextColor() ] ;
	if ( [ editor respondsToSelector:@selector(setInsertionPointColor:) ] ) [ (id)editor setInsertionPointColor:fieldTextColor() ] ;
	attributes = @{
		NSForegroundColorAttributeName:fieldTextColor(),
		NSBackgroundColorAttributeName:[ NSColor selectedTextBackgroundColor ]
	} ;
	if ( [ editor respondsToSelector:@selector(setSelectedTextAttributes:) ] ) [ (id)editor setSelectedTextAttributes:attributes ] ;
}

static void setVoiceAssistFieldColors( NSTextField *field )
{
	if ( field == nil ) return ;
	[ field setDrawsBackground:YES ] ;
	[ field setBackgroundColor:fieldBackgroundColor() ] ;
	[ field setTextColor:fieldTextColor() ] ;
	if ( [ field currentEditor ] ) setVoiceAssistEditorColors( [ field currentEditor ] ) ;
}

@implementation VoiceAssistTextField

- (void)awakeFromNib
{
	setVoiceAssistFieldColors( self ) ;
	[ [ NSNotificationCenter defaultCenter ] addObserver:self selector:@selector(textDidBeginEditing:) name:NSTextDidBeginEditingNotification object:self ] ;
}

- (BOOL)becomeFirstResponder
{
	if ( [ super becomeFirstResponder ] ) {
		setVoiceAssistFieldColors( self ) ;
		return YES ;
	}
	return NO ;
}

- (void)viewDidMoveToWindow
{
	[ super viewDidMoveToWindow ] ;
	setVoiceAssistFieldColors( self ) ;
}

- (void)textDidBeginEditing:(NSNotification*)notification
{
	if ( [ notification object ] == self ) setVoiceAssistFieldColors( self ) ;
}

- (void)dealloc
{
	[ [ NSNotificationCenter defaultCenter ] removeObserver:self ] ;
	[ super dealloc ] ;
}


//  voice character
- (void)keyUp:(NSEvent*)event
{
	int ch ;
	
	ch = [ [ event characters ] characterAtIndex:0 ] ;
	switch ( ch ) {
	case 127:
		[ [ [ NSApp delegate ] application ] speakAssist:@"back spaced" ] ;
		break ;
	case '.':
		[ [ [ NSApp delegate ] application ] speakAssist:@" period " ] ;
		break ;
	default:
		[ [ [ NSApp delegate ] application ] speakAssist:[ NSString stringWithFormat:@" %c ", ch ] ] ;
		break ;
	}
	[ super keyUp:event ] ;
}

@end
