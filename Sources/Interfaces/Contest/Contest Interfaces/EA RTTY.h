//
//  EA RTTY.h
//  cocoaModem
//

#ifndef _EA_RTTY_H_
	#define _EA_RTTY_H_

	#import <Cocoa/Cocoa.h>
	#include "RSTExchange.h"


	@interface EARTTY : RSTExchange {
		char exchSent[12] ;
	}

	@end

#endif