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

NSString* const PATH = @"~/Library/Containers/com.shazam.mac.Shazam/Data/Documents";
NSString* const FILENAME = @"ShazamDataModel";
NSString* const EXTENSION = @"sqlite";
NSString* const EXTENSIONWAL = @"sqlite-wal";

+ (NSString*)getSqlitePath {
    return [[[[PATH stringByExpandingTildeInPath] stringByAppendingString:@"/"] stringByAppendingString:FILENAME] stringByAppendingPathExtension:EXTENSION];
}

+ (NSString*)getSqliteWalPath {
    return [[[[PATH stringByExpandingTildeInPath] stringByAppendingString:@"/"] stringByAppendingString:FILENAME] stringByAppendingPathExtension:EXTENSIONWAL];
}


@end
