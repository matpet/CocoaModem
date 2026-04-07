
//  HellschreiberFont.c
//  cocoaModem 2.0
//
//  Created by Kok Chen on 1/31/06.
	#include "Copyright.h"
	
#include "HellschreiberFont.h"
#include <stdio.h>
#include <stdlib.h>
#include <netinet/in.h>

typedef struct {
	unsigned short version ;
	unsigned short size ;
	char name[32] ;
	unsigned short index[128] ;
	unsigned int fontData ;
} HellschreiberDiskHeader ;

HellschreiberFontHeader* MakeHellFont(const char *filename )
{
	FILE *f ;
	HellschreiberFontHeader *header ;
	HellschreiberDiskHeader diskHeader ;
	unsigned char *fontData ;
	int i ;

	f = fopen( filename, "rb" ) ;
	if ( !f ) return (HellschreiberFontHeader*)0 ;
	
	header = ( HellschreiberFontHeader* )malloc( sizeof( HellschreiberFontHeader ) ) ;
	if ( header == NULL ) {
		fclose( f ) ;
		return (HellschreiberFontHeader*)0 ;
	}

	if ( fread( &diskHeader, sizeof( HellschreiberDiskHeader ), 1, f ) != 1 ) {
		fclose( f ) ;
		free( header ) ;
		return (HellschreiberFontHeader*)0 ;
	}

	header->version = ntohs( diskHeader.version ) ;
	header->size = ntohs( diskHeader.size ) ;
	for ( i = 0; i < 128; i++ ) header->index[i] = ntohs( diskHeader.index[i] ) ;
	for ( i = 0; i < 32; i++ ) header->name[i] = diskHeader.name[i] ;
	
	fontData = (unsigned char*)malloc( header->size ) ;
	if ( fontData == NULL ) {
		fclose( f ) ;
		free( header ) ;
		return (HellschreiberFontHeader*)0 ;
	}
	if ( fread( fontData, 1, header->size, f ) != header->size ) {
		fclose( f ) ;
		free( fontData ) ;
		free( header ) ;
		return (HellschreiberFontHeader*)0 ;
	}
	fclose( f ) ;
	
	header->fontData = fontData ;
	return header ;
}
