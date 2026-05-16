/*
 *  TextEncoding.h
 *  cocoaModem 2.0
 *
 *  Created by Kok Chen on 11/3/07.
 */

#import <Foundation/Foundation.h>

#define kTextEncoding NSISOLatin1StringEncoding

static inline NSString* CMStringBySanitizingForTextEncoding( NSString *string )
{
	int i, length ;
	unichar ch ;
	NSString *character ;
	NSMutableString *result ;
	
	if ( string == nil || [ string canBeConvertedToEncoding:kTextEncoding ] ) return string ;
	
	result = [ NSMutableString stringWithCapacity:[ string length ] ] ;
	length = (int)[ string length ] ;
	for ( i = 0; i < length; i++ ) {
		ch = [ string characterAtIndex:i ] ;
		switch ( ch ) {
		case 0x2018:
		case 0x2019:
			[ result appendString:@"'" ] ;
			break ;
		case 0x201c:
		case 0x201d:
			[ result appendString:@"\"" ] ;
			break ;
		case 0x2013:
		case 0x2014:
			[ result appendString:@"-" ] ;
			break ;
		case 0x2026:
			[ result appendString:@"..." ] ;
			break ;
		default:
			character = [ NSString stringWithCharacters:&ch length:1 ] ;
			if ( [ character canBeConvertedToEncoding:kTextEncoding ] ) {
				[ result appendString:character ] ;
			}
			else {
				[ result appendString:@"." ] ;
			}
			break ;
		}
	}
	return result ;
}
