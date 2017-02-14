// Copyright (c) 2006-2008 Simon Fell
//
// Permission is hereby granted, free of charge, to any person obtaining a 
// copy of this software and associated documentation files (the "Software"), 
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense, 
// and/or sell copies of the Software, and to permit persons to whom the 
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included 
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS 
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN 
// THE SOFTWARE.
//

#import "zkBaseClient.h"
#import "zkSoapException.h"
#import "zkParser.h"

@interface ConnectionDelegate : NSObject<NSURLConnectionDataDelegate> {
    NSMutableData *data;
    NSConditionLock *lock;
    NSError *err;
}
-(NSError *)waitForResult;
-(NSData *)data;

@end

@implementation ZKBaseClient

static NSString *SOAP_NS = @"http://schemas.xmlsoap.org/soap/envelope/";

static NSOperationQueue *delegateQueue;

+(void)initialize {
    delegateQueue = [[NSOperationQueue alloc] init];
}

- (void)dealloc {
	[endpointUrl release];
	[super dealloc];
}

- (zkElement *)sendRequest:(NSString *)payload {
	return [self sendRequest:payload returnRoot:NO];
}

- (zkElement *)sendRequest:(NSString *)payload returnRoot:(BOOL)returnRoot {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpointUrl]];
	[request setHTTPMethod:@"POST"];
	[request addValue:@"text/xml; charset=UTF-8" forHTTPHeaderField:@"content-type"];	
	[request addValue:@"\"\"" forHTTPHeaderField:@"SOAPAction"];
    [request setHTTPShouldHandleCookies:NO];
    
	NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
	[request setHTTPBody:data];
	
	NSHTTPURLResponse *resp = nil;
	// NSError *err = nil;
	// todo, support request compression
	// todo, support response compression
    ConnectionDelegate *connDelegate = [[[ConnectionDelegate alloc] init] autorelease];
    NSURLConnection *c = [[NSURLConnection alloc] initWithRequest:request delegate:connDelegate startImmediately:NO];
    [c setDelegateQueue:delegateQueue];
    [c start];
    
    NSError *err = [connDelegate waitForResult];
    if (err != nil) {
        NSLog(@"request got an error response %@", err);
        @throw [NSException exceptionWithName:@"HTTP error" reason:@"Unable to make http request to server" userInfo:nil];
    }
    
    NSData *respPayload = [connDelegate data];
    //[NSURLConnection sendSynchronousRequest:request returningResponse:&resp error:&err];
	//NSLog(@"response \r\n%@", [NSString stringWithCString:[respPayload bytes] length:[respPayload length]]);
	zkElement *root = [zkParser parseData:respPayload];
    if (root == nil) {
        NSLog(@"request send to %@\n%@\n", request.URL, payload);
        NSLog(@"got unparsable response\n%@\n", [[[NSString alloc] initWithData:respPayload encoding:NSUTF8StringEncoding] autorelease]);
		@throw [NSException exceptionWithName:@"Xml error" reason:@"Unable to parse XML returned by server" userInfo:nil];
    }
    if (![[root name] isEqualToString:@"Envelope"]) {
        NSLog(@"request send to %@\n%@\n", request.URL, payload);
        NSLog(@"got unparsable response\n%@\n", [[[NSString alloc] initWithData:respPayload encoding:NSUTF8StringEncoding] autorelease]);
		@throw [NSException exceptionWithName:@"Xml error" reason:[NSString stringWithFormat:@"response XML not valid SOAP, root element should be Envelope, but was %@", [root name]] userInfo:nil];
    }
	if (![[root namespace] isEqualToString:SOAP_NS])
		@throw [NSException exceptionWithName:@"Xml error" reason:[NSString stringWithFormat:@"response XML not valid SOAP, root namespace should be %@ but was %@", SOAP_NS, [root namespace]] userInfo:nil];
	zkElement *body = [root childElement:@"Body" ns:SOAP_NS];
	if (500 == [resp statusCode]) {
		zkElement *fault = [body childElement:@"Fault" ns:SOAP_NS];
		if (fault == nil)
			@throw [NSException exceptionWithName:@"Xml error" reason:@"Fault status code returned, but unable to find soap:Fault element" userInfo:nil];
		NSString *fc = [[fault childElement:@"faultcode"] stringValue];
		NSString *fm = [[fault childElement:@"faultstring"] stringValue];
		@throw [ZKSoapException exceptionWithFaultCode:fc faultString:fm];
	}
	return returnRoot ? root : [[body childElements] objectAtIndex:0];
}

@end


@implementation ConnectionDelegate

-(id)init {
    self = [super init];
    data = [[NSMutableData dataWithCapacity:4096] retain];
    lock = [[NSConditionLock alloc] initWithCondition:0];
    return self;
}

-(void)dealloc {
    [data release];
    [lock release];
    [err release];
    [super dealloc];
}

-(NSError *)waitForResult {
    [lock lockWhenCondition:1];
    NSError *ret = [err autorelease];
    [lock unlock];
    return ret;
}

// only valid after you've called waitForResult
-(NSData *)data {
    return [data copy];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)d {
    [lock lock];
    [data appendData:d];
    [lock unlockWithCondition:0];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response {

    NSLog(@"NSURLConnection: willSendRequest %@ %@\n", [request HTTPMethod], [[request URL] absoluteString]);
    if (response != nil) {
        NSLog(@"redirect received from server %@\n", response);
        NSHTTPURLResponse *hr = (NSHTTPURLResponse *)response;
        NSLog(@"statusCode %ld headers %@\n",[hr statusCode], [hr allHeaderFields]);
    }
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSHTTPURLResponse *hr = (NSHTTPURLResponse *)response;
    NSLog(@"didRecvResponse statusCode %ld\nheaders %@\n",[hr statusCode], [hr allHeaderFields]);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)e {
    [lock lock];
    err = [e retain];
    [lock unlockWithCondition:1];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [lock lock];
    [lock unlockWithCondition:1];
}

@end
