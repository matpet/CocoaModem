//
//  EA RTTY.m
//  cocoaModem
//

	#include "Copyright.h"
//

#import "EA RTTY.h"
#import "Messages.h"
#import "ContestManager.h"
#import "TextEncoding.h"
#import "TransparentTextField.h"
#import "UserInfo.h"


@implementation EARTTY

typedef struct {
	char *abbrev ;
	char area ;
	unsigned char worked[5] ;
} EAProvinceList ;

//  DX-side minimum support: accept common Spanish province abbreviations
//  and serial numbers from non-EA stations.
static EAProvinceList rawProvinceList[] = {
	{ "A", 1, { 0, 0, 0, 0, 0 } },	{ "AB", 1, { 0, 0, 0, 0, 0 } },	{ "AL", 1, { 0, 0, 0, 0, 0 } },	{ "AV", 1, { 0, 0, 0, 0, 0 } },
	{ "B", 1, { 0, 0, 0, 0, 0 } },	{ "BA", 1, { 0, 0, 0, 0, 0 } },	{ "BI", 1, { 0, 0, 0, 0, 0 } },	{ "BU", 1, { 0, 0, 0, 0, 0 } },
	{ "C", 1, { 0, 0, 0, 0, 0 } },	{ "CA", 1, { 0, 0, 0, 0, 0 } },	{ "CC", 1, { 0, 0, 0, 0, 0 } },	{ "CE", 1, { 0, 0, 0, 0, 0 } },	{ "CO", 1, { 0, 0, 0, 0, 0 } },	{ "CR", 1, { 0, 0, 0, 0, 0 } },	{ "CS", 1, { 0, 0, 0, 0, 0 } },	{ "CU", 1, { 0, 0, 0, 0, 0 } },
	{ "GC", 1, { 0, 0, 0, 0, 0 } },	{ "GI", 1, { 0, 0, 0, 0, 0 } },	{ "GR", 1, { 0, 0, 0, 0, 0 } },	{ "GU", 1, { 0, 0, 0, 0, 0 } },
	{ "H", 1, { 0, 0, 0, 0, 0 } },	{ "HU", 1, { 0, 0, 0, 0, 0 } },
	{ "J", 1, { 0, 0, 0, 0, 0 } },
	{ "L", 1, { 0, 0, 0, 0, 0 } },	{ "LE", 1, { 0, 0, 0, 0, 0 } },	{ "LO", 1, { 0, 0, 0, 0, 0 } },	{ "LU", 1, { 0, 0, 0, 0, 0 } },
	{ "M", 1, { 0, 0, 0, 0, 0 } },	{ "MA", 1, { 0, 0, 0, 0, 0 } },	{ "ML", 1, { 0, 0, 0, 0, 0 } },	{ "MU", 1, { 0, 0, 0, 0, 0 } },
	{ "NA", 1, { 0, 0, 0, 0, 0 } },
	{ "O", 1, { 0, 0, 0, 0, 0 } },	{ "OU", 1, { 0, 0, 0, 0, 0 } },
	{ "P", 1, { 0, 0, 0, 0, 0 } },	{ "PM", 1, { 0, 0, 0, 0, 0 } },	{ "PO", 1, { 0, 0, 0, 0, 0 } },
	{ "S", 1, { 0, 0, 0, 0, 0 } },	{ "SA", 1, { 0, 0, 0, 0, 0 } },	{ "SE", 1, { 0, 0, 0, 0, 0 } },	{ "SG", 1, { 0, 0, 0, 0, 0 } },	{ "SO", 1, { 0, 0, 0, 0, 0 } },	{ "SS", 1, { 0, 0, 0, 0, 0 } },
	{ "T", 1, { 0, 0, 0, 0, 0 } },	{ "TE", 1, { 0, 0, 0, 0, 0 } },	{ "TF", 1, { 0, 0, 0, 0, 0 } },	{ "TO", 1, { 0, 0, 0, 0, 0 } },
	{ "V", 1, { 0, 0, 0, 0, 0 } },	{ "VA", 1, { 0, 0, 0, 0, 0 } },	{ "VI", 1, { 0, 0, 0, 0, 0 } },
	{ "Z", 1, { 0, 0, 0, 0, 0 } },	{ "ZA", 1, { 0, 0, 0, 0, 0 } },
	{ "**", 40, { 0, 0, 0, 0, 0 } }
} ;

static int provinceBandIndex( int qsoBand )
{
	switch ( qsoBand ) {
	case 80:
		return 0 ;
	case 40:
		return 1 ;
	case 20:
		return 2 ;
	case 15:
		return 3 ;
	case 10:
		return 4 ;
	}
	return -1 ;
}

- (id)initContestName:(NSString*)name prototype:(NSString*)prototype parser:(NSXMLParser*)inParser manager:(ContestManager*)inManager
{
	int i, j ;

	for ( i = 0; rawProvinceList[i].area < 40; i++ ) {
		for ( j = 0; j < 5; j++ ) rawProvinceList[i].worked[j] = 0 ;
	}
	return [ super initContestName:name prototype:prototype parser:inParser manager:inManager ] ;
}

- (void)createMult:(ContestQSO*)p
{
	EAProvinceList *province ;
	int bandIndex ;

	if ( master ) {
		[ (EARTTY*)master createMult:p ] ;
		return ;
	}
	if ( p == nil || p->exchange == nil ) return ;

	bandIndex = provinceBandIndex( band( p->frequency ) ) ;
	if ( bandIndex < 0 ) return ;

	province = &rawProvinceList[0] ;
	while ( province->area < 40 ) {
		if ( strcmp( province->abbrev, p->exchange ) == 0 ) {
			province->worked[bandIndex] = 1 ;
			return ;
		}
		province++ ;
	}
}

- (Boolean)validateExchange:(NSString*)exchange
{
	const char *s, *t ;
	int c ;
	EAProvinceList *province ;

	s = t = [ exchange cStringUsingEncoding:kTextEncoding ] ;
	c = *t++ & 0xff ;

	if ( isAlpha[c] ) {
		province = &rawProvinceList[0] ;
		while ( 1 ) {
			if ( strcmp( province->abbrev, s ) == 0 ) return YES ;
			province++ ;
			if ( province->area > 39 ) {
				[ dxExchange markAsSelected:YES ] ;
				[ Messages alertWithMessageText:@"Error -- bad province abbreviation." informativeText:@"EA RTTY exchange should be a Spanish province abbreviation such as M, B, GC, TF, PM, CE or a QSO number for non-EA stations." ] ;
				[ dxExchange markAsSelected:NO ] ;
				return NO ;
			}
		}
	}
	if ( isNumeric[c] ) {
		while ( c > 0 ) {
			if ( !isNumeric[c] ) {
				[ dxExchange markAsSelected:YES ] ;
				[ Messages alertWithMessageText:@"Error -- bad exchange." informativeText:@"EA RTTY exchange should be a Spanish province abbreviation or a QSO number." ] ;
				[ dxExchange markAsSelected:NO ] ;
				return NO ;
			}
			c = *t++ & 0xff ;
		}
		return YES ;
	}
	[ dxExchange markAsSelected:YES ] ;
	[ Messages alertWithMessageText:@"Error -- bad exchange." informativeText:@"EA RTTY exchange should be a Spanish province abbreviation or a QSO number." ] ;
	[ dxExchange markAsSelected:NO ] ;
	return NO ;
}

- (void)setupFields
{
	[ super setupFields ] ;
	if ( master ) [ master setCabrilloContestName:"EA-RTTY" ] ;
}

- (void)writeCabrilloQSOs
{
	int i, count, frequency, year, month, day, utc, rst ;
	char *mode, callsign[32], myCall[32], exchange[13] ;
	Callsign *c ;
	DateTime *time ;
	ContestQSO *q ;

	myCall[0] = 0 ;
	if ( usedCallString ) {
		strncpy( myCall, [ usedCallString cStringUsingEncoding:kTextEncoding ], 16 ) ;
		myCall[13] = 0 ;
	}

	count = 0 ;
	for ( i = 0; i < MAXQ; i++ ) {
		q = sortedQSOList[i] ;
		if ( q ) {
			if ( q->callsign->callsign[0] == 0 || strcmp( q->callsign->callsign, "NIL" ) == 0 ) continue ;

			frequency = q->frequency*1000.0 + 0.1 ;
			mode = stringForMode( q->mode ) ;
			if ( strcmp( mode, "PK" ) == 0 ) mode = "RY" ;
			time = &q->time ;
			year = time->year ;
			if ( year < 2000 ) year += 2000 ;
			month = time->month ;
			day = time->day ;
			utc = time->hour*100 + time->minute ;

			c = q->callsign ;
			callsign[0] = 0 ;
			if ( c ) {
				strncpy( callsign, c->callsign, 16 ) ;
				callsign[13] = 0 ;
			}

			fprintf( cabrilloFile, "QSO: %5d %2s ", frequency%100000, mode ) ;
			fprintf( cabrilloFile, "%4d-%02d-%02d %04d ", year, month, day, utc ) ;
			fprintf( cabrilloFile, "%-13s", myCall ) ;
			fprintf( cabrilloFile, "599%7d ", q->qsoNumber ) ;
			fprintf( cabrilloFile, "%-13s", callsign ) ;

			rst = q->rst ;
			if ( rst > 599 ) rst = 599 ; else if ( rst < 111 ) rst = 111 ;

			strncpy( exchange, q->exchange, 8 ) ;
			exchange[7] = 0 ;
			fprintf( cabrilloFile, "%3d%7s", rst, exchange ) ;
			fprintf( cabrilloFile, "\n" ) ;

			if ( ++count >= numberOfQSO ) break ;
		}
	}
}

- (void)showMultsWindow
{
	EAProvinceList *province ;
	NSMutableString *info ;
	int total, bandTotals[5], i, j ;
	NSString *bandNames[5] ;

	if ( master != nil ) return ;

	bandNames[0] = @"80m" ;
	bandNames[1] = @"40m" ;
	bandNames[2] = @"20m" ;
	bandNames[3] = @"15m" ;
	bandNames[4] = @"10m" ;
	for ( j = 0; j < 5; j++ ) bandTotals[j] = 0 ;
	total = 0 ;
	province = &rawProvinceList[0] ;
	for ( i = 0; province->area < 40; i++ ) {
		for ( j = 0; j < 5; j++ ) {
			if ( province->worked[j] ) {
				bandTotals[j]++ ;
				total++ ;
			}
		}
		province++ ;
	}

	info = [ NSMutableString stringWithFormat:@"Province multipliers worked so far: %d\n\n", total ] ;
	for ( j = 0; j < 5; j++ ) {
		[ info appendFormat:@"%@: %d province mults\n", bandNames[j], bandTotals[j] ] ;
	}
	[ info appendString:@"\nCurrent EA RTTY implementation counts Spanish province multipliers per band. Full EADX-100 entity and W/VE/JA/VK call-area multiplier support is not implemented yet." ] ;
	[ Messages alertWithMessageText:@"EA RTTY Multipliers" informativeText:info ] ;
}

@end