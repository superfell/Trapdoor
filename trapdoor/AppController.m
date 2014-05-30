/**
 * Copyright (c) 2007, salesforce.com, inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, are permitted provided
 * that the following conditions are met:
 *
 *    Redistributions of source code must retain the above copyright notice, this list of conditions and the
 *    following disclaimer.
 *
 *    Redistributions in binary form must reproduce the above copyright notice, this list of conditions and
 *    the following disclaimer in the documentation and/or other materials provided with the distribution.
 *
 *    Neither the name of salesforce.com, inc. nor the names of its contributors may be used to endorse or
 *    promote products derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 * PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#import "AppController.h"
#import "Credential.h"
#import "zkSforceClient.h"
#import "zkDescribeSObject.h"
#import "zkSoapException.h"
#import "NewPasswordController.h"
#import "Browser.h"
#import "BrowserSetting.h"
#import "zkLoginResult.h"
#import "zkUserInfo.h"
#import "zkParser.h"

NSString *prodUrl = @"https://www.salesforce.com";
NSString *testUrl = @"https://test.salesforce.com";

@interface AppController (Private)
- (void)updateCredentialList;
- (void)buildContextMenu;
@end

@implementation AppController

+ (void)initialize {
	NSMutableDictionary * defaults = [NSMutableDictionary dictionary];
	[defaults setObject:[NSArray arrayWithObjects:prodUrl, testUrl, nil] forKey:@"servers"];
	[defaults setObject:[NSNumber numberWithBool:YES] forKey:@"SUCheckAtStartup"];
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
}

OSStatus keychainCallback (SecKeychainEvent keychainEvent, SecKeychainCallbackInfo *info, void *context) {
	AppController *ac = (AppController*)context;
	[ac updateCredentialList];
	return noErr; 
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	SecKeychainRemoveCallback(keychainCallback);
	[currentCredentials release];
	[dockMenu release];
	[super dealloc];
}

- (void)awakeFromNib {
	[self updateCredentialList];
	[NSApp setDelegate:self];
	if (![[NSUserDefaults standardUserDefaults] boolForKey:@"HideWelcome"]) 
		[welcomeWindow makeKeyAndOrderFront:self];
	OSStatus s = SecKeychainAddCallback(keychainCallback, kSecAddEventMask | kSecDeleteEventMask | kSecUpdateEventMask, self);
	if (s != noErr)
		NSLog(@"Trapdoor - unable to register for keychain changes, got error %ld", (long)s);
	
	// this is needed because if you add TD to the dock, sparkle won't update its icon if the app icon changes.
	NSImage *currentIcon = [NSImage imageNamed:@"td"];
	if (currentIcon != nil)
		[NSApp setApplicationIconImage:currentIcon];
		
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(defaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
}

-(void)defaultsChanged:(NSNotification *)notification {
	[self updateCredentialList];
}

- (void)updateCredentialList {
	NSMutableArray *all = [NSMutableArray array];
	for (NSString *server in [[NSUserDefaults standardUserDefaults] objectForKey:@"servers"]) {
		NSArray *credentials = [Credential sortedCredentialsForServer:server];
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"SortByAlias"]) {
			NSSortDescriptor *alias = [[[NSSortDescriptor alloc] initWithKey:@"comment" ascending:YES] autorelease];
			NSSortDescriptor *usern = [[[NSSortDescriptor alloc] initWithKey:@"username" ascending:YES] autorelease];
			credentials = [credentials sortedArrayUsingDescriptors:[NSArray arrayWithObjects:alias, usern, nil]];
		}
		[all addObjectsFromArray:credentials];
	}
	[currentCredentials autorelease];
	currentCredentials = [all retain];
	[self buildContextMenu];
}

- (NSString *)clientId {
	static NSString *cid;
	if (cid != nil) return cid;
	NSDictionary *plist = [[NSBundle mainBundle] infoDictionary];
	cid = [[NSMutableString stringWithFormat:@"MacTrapdoor/%@", [plist objectForKey:@"CFBundleVersion"]] retain];
	return cid;
}

- (ZKDescribeSObject *)describeSomethingWithUrls:(ZKSforceClient *)sforce {
	NSArray *types = [sforce describeGlobal];
	// try a custom object first
	ZKDescribeGlobalSObject *type;
	ZKDescribeSObject *desc;
	desc = [sforce describeSObject:[[types lastObject] name]];
	if ([[desc urlNew] length] > 0) return desc;
	
	NSMutableArray *typeNames = [NSMutableArray array];
	for (type in types)
		[typeNames addObject:[type name]];
	
	// try some major entities we know should have urls
	NSArray *toTry = [NSArray arrayWithObjects:@"Event", @"Task", @"Product2", @"Contact", @"OpportunityLineItem", @"Opportunity", @"Lead", @"Account", nil];
	for (NSString *typeToTry in toTry) {
		if ([typeNames containsObject:typeToTry]) {
			desc = [sforce describeSObject:typeToTry];
			if ([[desc urlNew] length] > 0) return desc;
		}
	}
	// what, still no luck? grrh, brute force that sucker
	for (type in types) {
		desc = [sforce describeSObject:[type name]];
		if ([[desc urlNew] length] > 0) return desc;
	}
	return nil;
}

- (ZKSforceClient *)clientForServer:(NSString *)server {
	ZKSforceClient *sforce = [[[ZKSforceClient alloc] init] autorelease];
	[sforce setLoginProtocolAndHost:server andVersion:17];
	[sforce setClientId:[self clientId]];
	return sforce;
}

- (IBAction)launchHelp:(id)sender {
	NSString *help = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"ZKHelpUrl"];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:help]];
}

- (void)launchSalesforceForClient:(ZKSforceClient *)sforce andCredential:(Credential *)credential {
	[sforce setCacheDescribes:YES];
	ZKDescribeSObject *desc = [self describeSomethingWithUrls:sforce];
	NSString *sUrl = desc != nil ? [desc urlNew] : [sforce serverUrl];
	NSURL *url = [NSURL URLWithString:sUrl];
	NSURL *fd  = [NSURL URLWithString:[NSString stringWithFormat:@"/secur/frontdoor.jsp?sid=%@", [sforce sessionId]] relativeToURL:url];
    NSLog(@"final url: %@",url);
	NSString *bundleIdentifier = [[credential browser] bundleIdentifier];
	if (bundleIdentifier == nil)
		[[NSWorkspace sharedWorkspace] openURL:fd];
	else
		[[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:fd] withAppBundleIdentifier:bundleIdentifier 
			options:NSWorkspaceLaunchAsync additionalEventParamDescriptor:nil launchIdentifiers:nil];
}

- (IBAction)performLogin:(id)sender {
	Credential *c = [sender representedObject];
    [self completeLogin:c];
}

- (void)completeLogin:(Credential *)c {
	ZKSforceClient *sforce = [self clientForServer:[c server]];
	@try {
		ZKLoginResult *lr = [sforce login:[c username] password:[c password]];
		if ([lr passwordExpired]) {
			[newpassController showChangePasswordWindow:c withError:@"Your password has expired, please enter a new password" client:sforce];
		} else {
			[self launchSalesforceForClient:sforce andCredential:c];
		}
	}
	@catch (ZKSoapException *ex) {
		NSBeep();
		[newpassController showNewPasswordWindow:c withError:[ex reason]];
	}
}

- (void)addItemsToMenu:(NSMenu *)newMenu {
	Credential *c = nil;
	NSString *lastServer = nil;
	NSEnumerator *e = [currentCredentials objectEnumerator];
	int keyShortCut = 1;
	while (c = [e nextObject]) {
		if (![[c server] isEqualToString:lastServer]) {
			if (lastServer != nil) 
				[newMenu addItem:[NSMenuItem separatorItem]];
		    NSMenuItem *newItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:[c server] action:NULL keyEquivalent:@""];
		    [newMenu addItem:newItem];
		    [newItem release];
			lastServer = [c server];
		}
		NSString *itemTitle = [c username];
		if ([[c comment] length] > 0)
			itemTitle = [NSString stringWithFormat:@"%@ - %@", [c comment], [c username]];
		NSString *shortcut = keyShortCut < 10 ? [NSString stringWithFormat:@"%d", keyShortCut++] : @"";
        NSAssert(itemTitle != nil, @"ItemTitle shouldn't be nil");
	    NSMenuItem *newItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:itemTitle action:NULL keyEquivalent:shortcut];
		[newItem setRepresentedObject:c];
	    [newItem setTarget:self];
	    [newItem setAction:@selector(performLogin:)];
	    [newMenu addItem:newItem];
	    [newItem release];
	}
}

- (void)buildContextMenu {
	NSMenu *newMenu = [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:@"Login"];
	[self addItemsToMenu:newMenu];
	while ([loginMenu numberOfItems] >0)
		[loginMenu removeItemAtIndex:0];
	[self addItemsToMenu:loginMenu];
	[dockMenu release];
	dockMenu = newMenu;	
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
	return dockMenu;
}

- (BOOL)hasSomeCredentials {
	return [currentCredentials count] > 0;
}

- (Credential *)createCredential:(NSString *)newUsername password:(NSString *)newPassword server:(NSString *)newServer {
	ZKSforceClient *sforce = [self clientForServer:newServer];
	@try {
		[sforce login:newUsername password:newPassword];
		Credential *c = [Credential createCredentialForServer:newServer username:newUsername password:newPassword];
		if (c != nil)
			[self updateCredentialList];
		return c;
	}
	@catch (ZKSoapException *ex) {
		NSAlert * a = [NSAlert alertWithMessageText:[ex reason] defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Login failed"];
		[a runModal];
	}
	return nil;
}

@end
