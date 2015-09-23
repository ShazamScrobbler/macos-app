//
//  ShazamConstants.m
//  ShazamScrobbler
//
//  Created by Stéphane Bruckert on 09/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ShazamConstants.h"

@implementation ShazamConstants : NSObject

NSString* const PATH = @"~/Library/Group Containers/4GWDBCF5A4.group.com.shazam/com.shazam.mac.Shazam/";
NSString* const FILENAME = @"ShazamDataModel";
NSString* const EXTENSION = @"sqlite";
NSString* const EXTENSIONWAL = @"sqlite-wal";
NSString* const JOURNAL = @"Journal";

+ (NSString*)getSqlitePath {
    return [[[[PATH stringByExpandingTildeInPath] stringByAppendingString:@"/"] stringByAppendingString:FILENAME] stringByAppendingPathExtension:EXTENSION];
}

+ (NSString*)getSqliteWalPath {
    return [[[[PATH stringByExpandingTildeInPath] stringByAppendingString:@"/"] stringByAppendingString:FILENAME] stringByAppendingPathExtension:EXTENSIONWAL];
}

+ (NSString*)getJournalPath {
    return [[[PATH stringByExpandingTildeInPath] stringByAppendingString:@"/"] stringByAppendingString:JOURNAL];
}


@end