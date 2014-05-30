//
//  NSObject+ScriptSupport.m
//  trapdoor
//
//  Created by Matt Welch on 5/28/14.
//
//

#import "NSObject+ScriptSupport.h"
@implementation NSObject (ScriptSupport)

- (void) returnError:(int)n string:(NSString*)s {
	NSScriptCommand* c = [NSScriptCommand currentCommand];
	[c setScriptErrorNumber:n];
	if (s)
		[c setScriptErrorString:s];
}

@end

@implementation AppController (ScriptSupport)

- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key {
	if ([key isEqualToString: @"credentialsArray"])
		return YES;
	return NO;
}


- (unsigned int)countOfCredentialsArray {
	return [currentCredentials count];
}


- (Credential *)objectInCredentialsArrayAtIndex:(unsigned int)i {
	return [currentCredentials objectAtIndex: i];
}


- (Credential *)valueInCredentialsArrayAtIndex:(unsigned int)i {
	if (![[NSScriptCommand currentCommand] isKindOfClass:[NSExistsCommand class]])
		if (i >= [currentCredentials count]) {
			[self returnError:errAENoSuchObject string:@"No such credential."];
			return nil;
        }
	return [currentCredentials objectAtIndex: i];
}

- (Credential *) valueInCredentialsArrayWithName: (NSString*) name {
	int i, u = [currentCredentials count];
	for (i=0; i<u; i++)
		if ([[[currentCredentials objectAtIndex:i] username] caseInsensitiveCompare:name] == NSOrderedSame)
			return [currentCredentials objectAtIndex: i];
	return nil;
}

@end

@implementation Credential (ScriptSupport)


- (NSScriptObjectSpecifier *)objectSpecifier {
	NSScriptClassDescription* appDesc = (NSScriptClassDescription*)[NSApp classDescription];
    
    return [[[NSNameSpecifier alloc] initWithContainerClassDescription:appDesc containerSpecifier:nil key:@"credentialsArray" name:[self username]] autorelease];
}

- (NSString *)credentialUsername
{
	return username;
}


- (NSString *)credentialServer
{
	return server;
}

- (NSString *)credentialComment
{
	return [self comment];
}

-(void)login:(NSScriptCommand *)cmd {
	AppController *app = (AppController *)[NSApp delegate];
	[app completeLogin:self];
}


@end
