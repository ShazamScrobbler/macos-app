//
//  Shazam.h
//  ShazamScrobbler
//
//  Created by Stéphane Bruckert on 09/10/14.
//  Copyright (c) 2014 Stéphane Bruckert. All rights reserved.
//

#ifndef ShazamScrobbler_Shazam_h
#define ShazamScrobbler_Shazam_h

@interface ShazamController : NSObject

+ (void)init;
+ (void)watch:(NSString*)path;
+ (void)findNewTags:(bool)scrobblingWasDisabled;

@end

#endif
