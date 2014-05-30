//
//  NSObject+ScriptSupport.h
//  trapdoor
//
//  Created by Matt Welch on 5/28/14.
//
//

#import <Foundation/Foundation.h>
#import "AppController.h"
#import "credential.h"

@interface NSObject (ScriptSupport)
- (void) returnError:(int)n string:(NSString*)s;
@end

@interface Credential (ScriptSupport)
- (void)login:(NSScriptCommand *)cmd;
@end