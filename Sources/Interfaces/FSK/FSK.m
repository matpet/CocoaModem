//
//  FSK.m
//  cocoaModem 2.0
//
//  Created by Kok Chen on 2/12/08.
//  Copyright 2008 Kok Chen, W7AY. All rights reserved.
//

#import "FSK.h"
#import "Application.h"
#import "FSKHub.h"
#import "FSKMenu.h"
#import "RTTY.h"
#import "SerialLineKeyer.h"

#define kSerialRTSMenuPrefix @"External FSK (RTS): "
#define kSerialDTRMenuPrefix @"External FSK (DTR): "

@implementation FSK

- (id)initWithHub:(FSKHub*)fskHub menu:(NSPopUpButton*)fskMenu modem:(RTTY*)client
{
	DigitalInterfaces *digitalInterfaces ;
	NSArray *keyers ;
	MicroKeyer *keyer ;
	Application *application ;
	NSString *path[32], *stream[32], *title ;
	int i, n, digiKeyers, microKeyers, menuItems, serialPorts ;

	self = [ super init ] ;
	if ( self ) {
		modem = client ;
		menu = fskMenu ;
		hub = fskHub ;
		selectedPort = 0 ;
		
		application = [ NSApp delegate ] ;	
		digitalInterfaces = [ application digitalInterfaces ] ;
		[ menu removeAllItems ] ;
		
		[ menu addItemWithTitle:kAFSKMenuTitle ] ;
		interfaces[0].type = kAFSKType ;
		interfaces[0].keyer = nil ;
		interfaces[0].path = nil ;
		interfaces[0].serialLine = 0 ;
		interfaces[0].enabled = YES ;
		
		[ [ menu menu ] addItem:[ NSMenuItem separatorItem ] ] ;
		interfaces[1].type = kSeparatorType ;
		interfaces[1].keyer = nil ;
		interfaces[1].path = nil ;
		interfaces[1].serialLine = 0 ;
		interfaces[1].enabled = NO ;
		
		digiKeyers = [ digitalInterfaces numberOfDigiKeyers ] ;
		microKeyers = [ digitalInterfaces numberOfMicroKeyers ] ;
		
		if ( digiKeyers <= 1 && microKeyers <= 1 ) {
			[ menu addItemWithTitle:kDigiKeyerMenuTitle ] ;
			keyer = [ digitalInterfaces digiKeyer ] ;
			if ( keyer == nil ) {
				interfaces[2].type = kBadType ;
				interfaces[2].keyer = nil ;
				interfaces[2].path = nil ;
				interfaces[2].serialLine = 0 ;
				interfaces[2].enabled = NO ;
			}
			else {
				interfaces[2].type = kFSKType ;
				interfaces[2].keyer = keyer ;
				interfaces[2].path = nil ;
				interfaces[2].serialLine = 0 ;
				interfaces[2].enabled = YES ;
			}
			
			[ menu addItemWithTitle:kMicroKeyerMenuTitle ] ;	
			keyer = [ digitalInterfaces microKeyer ] ;
			if ( keyer == nil ) {
				interfaces[3].type = kBadType ;
				interfaces[3].keyer = nil ;
				interfaces[3].path = nil ;
				interfaces[3].serialLine = 0 ;
				interfaces[3].enabled = NO ;
			}
			else {
				interfaces[3].type = kFSKType ;
				interfaces[3].keyer = keyer ;
				interfaces[3].path = nil ;
				interfaces[3].serialLine = 0 ;
				interfaces[3].enabled = YES ;
			}
			menuItems = 4 ;
		}
		else {
			menuItems = 2 ;
			keyers = [ digitalInterfaces microHAMKeyers ] ;
			n = [ keyers count ] ;
			for ( i = 0; i < n; i++ ) {
				//  list each keyer that is FSK capable
				keyer = keyers[i] ;
				if ( [ keyer isMicroKeyer ] || [ keyer isDigiKeyer ] ) {
					[ menu addItemWithTitle:[ NSString stringWithFormat:@"%@ %s", kFSKShortMenuTitle, [ keyer keyerID ] ] ] ;
					interfaces[menuItems].type = kFSKType ;
					interfaces[menuItems].keyer = keyer ;
					interfaces[menuItems].path = nil ;
					interfaces[menuItems].serialLine = 0 ;
					interfaces[menuItems].enabled = YES ;
					menuItems++ ;
				}
			}
		}

		serialPorts = [ SerialLineKeyer findSerialPorts:&path[0] stream:&stream[0] maxPorts:32 ] ;
		if ( serialPorts > 0 ) {
			[ [ menu menu ] addItem:[ NSMenuItem separatorItem ] ] ;
			interfaces[menuItems].type = kSeparatorType ;
			interfaces[menuItems].keyer = nil ;
			interfaces[menuItems].path = nil ;
			interfaces[menuItems].serialLine = 0 ;
			interfaces[menuItems].enabled = NO ;
			menuItems++ ;

			[ menu addItemWithTitle:kExternalFSKMenuTitle ] ;
			interfaces[menuItems].type = kSeparatorType ;
			interfaces[menuItems].keyer = nil ;
			interfaces[menuItems].path = nil ;
			interfaces[menuItems].serialLine = 0 ;
			interfaces[menuItems].enabled = NO ;
			menuItems++ ;

			for ( i = 0; i < serialPorts && menuItems < 30; i++ ) {
				title = [ kSerialRTSMenuPrefix stringByAppendingString:stream[i] ] ;
				[ menu addItemWithTitle:title ] ;
				interfaces[menuItems].type = kSerialFSKType ;
				interfaces[menuItems].keyer = nil ;
				interfaces[menuItems].path = [ path[i] retain ] ;
				interfaces[menuItems].serialLine = 1 ;
				interfaces[menuItems].enabled = YES ;
				menuItems++ ;

				if ( menuItems >= 31 ) break ;

				title = [ kSerialDTRMenuPrefix stringByAppendingString:stream[i] ] ;
				[ menu addItemWithTitle:title ] ;
				interfaces[menuItems].type = kSerialFSKType ;
				interfaces[menuItems].keyer = nil ;
				interfaces[menuItems].path = [ path[i] retain ] ;
				interfaces[menuItems].serialLine = 0 ;
				interfaces[menuItems].enabled = YES ;
				menuItems++ ;
			}
			for ( i = 0; i < serialPorts; i++ ) {
				[ path[i] release ] ;
				[ stream[i] release ] ;
			}
		}
		[ [ menu menu ] addItem:[ NSMenuItem separatorItem ] ] ;
		interfaces[menuItems].type = kSeparatorType ;
		interfaces[menuItems].keyer = nil ;
		interfaces[menuItems].path = nil ;
		interfaces[menuItems].serialLine = 0 ;
		interfaces[menuItems].enabled = NO ;
		menuItems++ ;
		
		[ menu addItemWithTitle:kDigiKeyerOOKMenuTitle ] ;
		interfaces[menuItems].type = kPFSKType ;
		interfaces[menuItems].keyer = nil ;
		interfaces[menuItems].path = nil ;
		interfaces[menuItems].serialLine = 0 ;
		interfaces[menuItems].enabled = YES ;
		menuItems++ ;
		
		[ menu addItemWithTitle:kOOKMenuTitle ] ;
		interfaces[menuItems].type = kOOKType ;
		interfaces[menuItems].keyer = nil ;
		interfaces[menuItems].path = nil ;
		interfaces[menuItems].serialLine = 0 ;
		interfaces[menuItems].enabled = YES ;
	}
	return self ;
}

// NSMenuValidation for FSK menus; called by RTTYConfig to validate its menus
- (BOOL)validateAfskMenuItem:(NSMenuItem*)item
{
	int i, n ;
	
	n = [ menu numberOfItems ] ;	
	for ( i = 0; i < n; i++ ) {
		if ( item == [ menu itemAtIndex:i ] ) {
			return interfaces[i].enabled ;
		}
	}
	return YES ;
}

- (int)fskPortForName:(NSString*)title
{
	NSMenu *items ;
	int n ;
	MicroKeyer *keyer ;
	
	items = [ menu menu ] ;
	n = [ items indexOfItemWithTitle:title ] ;
	if ( n < 0 ) return 0 ;
	
	keyer = interfaces[n].keyer ;
	if ( keyer == nil ) return 0 ;

	return [ keyer fskWriteDescriptor ] ;
}

//  v0.89
- (int)controlPortForName:(NSString*)title
{
	NSMenu *items ;
	int n ;
	MicroKeyer *keyer ;
	
	items = [ menu menu ] ;
	n = [ items indexOfItemWithTitle:title ] ;
	if ( n < 0 ) return 0 ;
	
	keyer = interfaces[n].keyer ;
	if ( keyer == nil ) return 0 ;

	return [ keyer controlWriteDescriptor ] ;
}

//	v0.90
- (Boolean)checkAvailability:(NSString*)title
{
	NSMenu *items ;
	int n ;
	
	items = [ menu menu ] ;
	n = [ items indexOfItemWithTitle:title ] ;
	if ( n < 0 ) return NO ;
	
	return interfaces[n].enabled ;
}

- (int)selectedFSKPort
{
	NSString *title ;
	NSMenu *items ;
	int n ;

	title = [ menu titleOfSelectedItem ] ;
	items = [ menu menu ] ;
	n = [ items indexOfItemWithTitle:title ] ;
	if ( n < 0 ) return 0 ;

	if ( interfaces[n].type == kSerialFSKType ) {
		return [ hub serialPortTokenForPath:interfaces[n].path line:interfaces[n].serialLine name:title ] ;
	}
	return [ self fskPortForName:title ] ;
}

//  set fd to port selected by menu (or 0 if error)
- (int)useSelectedPort 
{
	selectedPort = [ self selectedFSKPort ] ;
	return selectedPort ;
}

//  v0.87
- (void)setKeyerMode:(int)mode controlPort:(int)port
{
	if ( port ) [ hub setKeyerMode:mode controlPort:port ] ; 
}

//  streams

- (void)startSampling:(float)baudrate invert:(Boolean)invertTx stopBits:(int)stopIndex
{
	if ( selectedPort > 0 ) {
		[ hub startSampling:selectedPort baudRate:baudrate invert:invertTx stopBits:stopIndex modem:modem ] ;
	}
}

- (void)stopSampling
{
	if ( selectedPort > 0 ) [ hub stopSampling ] ;
}

- (void)clearOutput
{
	[ hub clearOutput ] ;
}

- (void)appendASCII:(int)ascii
{
	[ hub appendASCII:ascii ] ;
}

- (void)setUSOS:(Boolean)state
{
	[ hub setUSOS:state ] ;
}

@end
