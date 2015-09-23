//
//  ShazamConstants.h
//  ShazamScrobbler
//
//  Created by Stéphane Bruckert on 09/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#ifndef ShazamScrobbler_ShazamConstants_h
#define ShazamScrobbler_ShazamConstants_h

@interface ShazamConstants : NSObject

extern NSString* const PATH;
extern NSString* const FILENAME;
extern NSString* const EXTENSION;
extern NSString* const JOURNAL;

+ (NSString*)getSqlitePath;
+ (NSString*)getSqliteWalPath;
+ (NSString*)getJournalPath;

@end

#endif
