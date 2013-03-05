//
//  zkKeychain.m
//  AppExplorer
//
//  Created by Simon Fell on 11/26/06.
//  Copyright 2006 Simon Fell. All rights reserved.
//

#import "zkKeychain.h"
#include <Security/Security.h>

@interface zkKeychain (Private)
-(id)initWithServer:(NSString *)server andUsername:(NSString *)username;
- (void)deallocKeychainInfo;
- (void)loadCredentialsFromKeyChain:(NSString *)username;
- (void)saveCredentialToKeychain;
@end

@implementation zkKeychain

// server should be the serverName, without any protocol or path info (e.g. www.salesforce.com)
+ (id)KeychainItemForServer:(NSString *)server {
	return [self KeychainItemForServer:server andUsername:nil];
}

// note that if we don't find or get denied access to the specified users keychain entry, the username property becomes nil
+ (id)KeychainItemForServer:(NSString *)server andUsername:(NSString *)username {
	return [[[zkKeychain alloc] initWithServer:server andUsername:username] autorelease];
}

- (void)dealloc {
	[server release];
	[self deallocKeychainInfo];
	[super dealloc];
}

- (id)initWithServer:(NSString *)aServer andUsername:(NSString *)usernameToFind {
	self = [super init];
	keychainItem = NULL;
	promptOnSave = YES;
	server = [aServer copy];
	[self loadCredentialsFromKeyChain:usernameToFind];
	return self;
}

- (BOOL)promptOnSave {
	return promptOnSave;
}

- (void)setPromptOnSave:(BOOL)newPromptOnSave {
	promptOnSave = newPromptOnSave;
}

- (void)updateKeychainWithUsername:(NSString *)newUsername password:(NSString *)newPassword {
	if (username != newUsername) {
		[username release];
		username = [newUsername copy];
	}
	if (password != newPassword) {
		[password release];
		password = [newPassword copy];
	}
	[self saveCredentialToKeychain];
}

- (NSString *)server {
	return server;
}

- (NSString *)username {
	return username;
}

- (NSString *)password {
	return password;
}

- (void)deallocKeychainInfo {
	if (keychainItem != NULL) {
		CFRelease(keychainItem);
		keychainItem = NULL;
	}
	[username release];
	[password release];
	username = nil;
	password = nil;
}


- (void)loadCredentialsFromKeyChain:(NSString *)usernameToFind
{
	[self deallocKeychainInfo];
	UInt32 pwdLen;
	void * pwd;
	OSStatus status = SecKeychainFindInternetPassword (
		NULL,
		[server cStringLength], [server cString],
		0, NULL,
		[usernameToFind cStringLength], [usernameToFind cString], 
		0, NULL,
		0,
		kSecProtocolTypeHTTPS, 
		kSecAuthenticationTypeDefault,
		&pwdLen, &pwd, &keychainItem);
	if (noErr == status) {
		SecKeychainAttribute a[] = { { kSecAccountItemAttr, 0, NULL } };
		SecKeychainAttributeList al = { 1, a };
		if (noErr == SecKeychainItemCopyContent(keychainItem, NULL, &al, 0, NULL)) {
			username = [NSString stringWithCString:a[0].data length:a[0].length];
			password = [NSString stringWithCString:pwd length:pwdLen];
			[username retain];
			[password retain];
		}
		SecKeychainItemFreeContent(&al, pwd);
	}
}

- (BOOL)promptToStoreCredentialsInKeyChain {
	if (!promptOnSave) return YES;
	NSAlert *alert = [[NSAlert alloc] init];
	[alert addButtonWithTitle:@"Yes"];
	[alert addButtonWithTitle:@"No"];
	[alert setMessageText:@"Update keychain with information?"];
	[alert setInformativeText:@"Update your keychain with this username and password?"];
	[alert setAlertStyle:NSInformationalAlertStyle];
	BOOL ok = ([alert runModal] == NSAlertFirstButtonReturn);
	[alert release];
	return ok;
}

- (void)saveCredentialToKeychain {
	if ([self promptToStoreCredentialsInKeyChain]) {
		if (keychainItem == NULL) {
			// store in keychain
			OSStatus status = SecKeychainAddInternetPassword (
									NULL,
									[server cStringLength], [server cString],
									0, NULL,
									[username lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
									[username cStringUsingEncoding:NSUTF8StringEncoding],
									0, NULL,
									0,
									kSecProtocolTypeHTTPS,
									kSecAuthenticationTypeDefault,
									[password lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
									[password cStringUsingEncoding:NSUTF8StringEncoding],
									NULL);
		} else {
			// update it
			// Set up attribute vector (each attribute consists of {tag, length, pointer}):
			SecKeychainAttribute attrs[] = {
				{ kSecAccountItemAttr, [username lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [username cStringUsingEncoding:NSUTF8StringEncoding] } };
			const SecKeychainAttributeList attributes = { sizeof(attrs) / sizeof(attrs[0]),  attrs };
			OSStatus status = SecKeychainItemModifyAttributesAndData (
									keychainItem,   // the item reference
									&attributes,    // no change to attributes
									[password lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
									[password cStringUsingEncoding:NSUTF8StringEncoding] );
		}
	}
	[self deallocKeychainInfo];
}

@end
