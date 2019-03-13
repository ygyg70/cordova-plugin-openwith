#import <UIKit/UIKit.h>
#import <Social/Social.h>
#import "ShareViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>

/*
 * Add base64 export to NSData
 */
@interface NSData (Base64)
- (NSString*) convertToBase64;
@end

@implementation NSData (Base64)
- (NSString*) convertToBase64 {
  const uint8_t* input = (const uint8_t*)[self bytes];
  NSInteger length = [self length];

  static char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

  NSMutableData* data = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
  uint8_t* output = (uint8_t*)data.mutableBytes;

  NSInteger i;
  for (i=0; i < length; i += 3) {
    NSInteger value = 0;
    NSInteger j;

    for (j = i; j < (i + 3); j++) {
      value <<= 8;

      if (j < length) {
        value |= (0xFF & input[j]);
      }
    }

    NSInteger theIndex = (i / 3) * 4;
    output[theIndex + 0] =                    table[(value >> 18) & 0x3F];
    output[theIndex + 1] =                    table[(value >> 12) & 0x3F];
    output[theIndex + 2] = (i + 1) < length ? table[(value >> 6)  & 0x3F] : '=';
    output[theIndex + 3] = (i + 2) < length ? table[(value >> 0)  & 0x3F] : '=';
  }

  NSString *ret = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
#if ARC_DISABLED
  [ret autorelease];
#endif
  return ret;
}
@end

@interface ShareViewController : SLComposeServiceViewController <UIAlertViewDelegate> {
  int _verbosityLevel;
  NSUserDefaults *_userDefaults;
}
@property (nonatomic) int verbosityLevel;
@property (nonatomic,retain) NSUserDefaults *userDefaults;
@end

/*
 * Constants
 */

#define VERBOSITY_DEBUG  0
#define VERBOSITY_INFO  10
#define VERBOSITY_WARN  20
#define VERBOSITY_ERROR 30

@implementation ShareViewController

@synthesize verbosityLevel = _verbosityLevel;
@synthesize userDefaults = _userDefaults;

- (void) log:(int)level message:(NSString*)message {
  if (level >= self.verbosityLevel) {
    NSLog(@"[ShareViewController.m]%@", message);
  }
}

- (void) debug:(NSString*)message { [self log:VERBOSITY_DEBUG message:message]; }
- (void) info:(NSString*)message { [self log:VERBOSITY_INFO message:message]; }
- (void) warn:(NSString*)message { [self log:VERBOSITY_WARN message:message]; }
- (void) error:(NSString*)message { [self log:VERBOSITY_ERROR message:message]; }

- (void) setup {
  [self debug:@"[setup]"];

  self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:SHAREEXT_GROUP_IDENTIFIER];
  self.verbosityLevel = [self.userDefaults integerForKey:@"verbosityLevel"];
}

- (BOOL) isContentValid {
  return YES;
}

- (void) openURL:(nonnull NSURL *)url {
  SEL selector = NSSelectorFromString(@"openURL:options:completionHandler:");

  UIResponder* responder = self;
  while ((responder = [responder nextResponder]) != nil) {

    if([responder respondsToSelector:selector] == true) {
      NSMethodSignature *methodSignature = [responder methodSignatureForSelector:selector];
      NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];

      // Arguments
      NSDictionary<NSString *, id> *options = [NSDictionary dictionary];
      void (^completion)(BOOL success) = ^void(BOOL success) {};

      [invocation setTarget: responder];
      [invocation setSelector: selector];
      [invocation setArgument: &url atIndex: 2];
      [invocation setArgument: &options atIndex:3];
      [invocation setArgument: &completion atIndex: 4];
      [invocation invoke];
      break;
    }
  }
}

- (void) viewDidAppear:(BOOL)animated {
  [self.view endEditing:YES];

  [self setup];
  [self debug:@"[viewDidAppear]"];

  __block int remainingAttachments = ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments.count;
  __block NSMutableArray *items = [[NSMutableArray alloc] init];
  __block NSDictionary *results = @{
    @"text" : self.contentText,
    @"items": items,
  };

  for (NSItemProvider* itemProvider in ((NSExtensionItem*)self.extensionContext.inputItems[0]).attachments) {
    [self debug:[NSString stringWithFormat:@"item provider registered indentifiers = %@", itemProvider.registeredTypeIdentifiers]];

    // IMAGE
    if ([itemProvider hasItemConformingToTypeIdentifier:@"public.image"]) {
      [self debug:[NSString stringWithFormat:@"item provider = %@", itemProvider]];

      [itemProvider loadItemForTypeIdentifier:@"public.image" options:nil completionHandler: ^(NSURL* item, NSError *error) {
        NSData *data = [NSData dataWithContentsOfURL:(NSURL*)item];
        NSString *base64 = [data convertToBase64];
        NSString *suggestedName = item.lastPathComponent;

        NSString *uti = @"public.image";
        NSString *registeredType = nil;

        if ([itemProvider.registeredTypeIdentifiers count] > 0) {
          registeredType = itemProvider.registeredTypeIdentifiers[0];
        } else {
          registeredType = uti;
        }

        NSString *mimeType =  [self mimeTypeFromUti:registeredType];
        NSDictionary *dict = @{
          @"text" : self.contentText,
          @"data" : base64,
          @"uti"  : uti,
          @"utis" : itemProvider.registeredTypeIdentifiers,
          @"name" : suggestedName,
          @"type" : mimeType
        };

        [items addObject:dict];

        --remainingAttachments;
        if (remainingAttachments == 0) {
          [self sendResults:results];
        }
      }];
    }

    // URL
    else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.url"]) {
      [itemProvider loadItemForTypeIdentifier:@"public.url" options:nil completionHandler: ^(NSURL* item, NSError *error) {
        [self debug:[NSString stringWithFormat:@"public.url = %@", item]];

        NSString *uti = @"public.url";
        NSDictionary *dict = @{
          @"data" : item.absoluteString,
          @"uti": uti,
          @"utis": itemProvider.registeredTypeIdentifiers,
          @"name": @"",
          @"type": [self mimeTypeFromUti:uti],
        };

        [items addObject:dict];

        --remainingAttachments;
        if (remainingAttachments == 0) {
          [self sendResults:results];
        }
      }];
    }

    // TEXT
    else if ([itemProvider hasItemConformingToTypeIdentifier:@"public.text"]) {
      [itemProvider loadItemForTypeIdentifier:@"public.text" options:nil completionHandler: ^(NSString* item, NSError *error) {
        [self debug:[NSString stringWithFormat:@"public.text = %@", item]];

        NSString *uti = @"public.text";
        NSDictionary *dict = @{
          @"text" : self.contentText,
          @"data" : item,
          @"uti": uti,
          @"utis": itemProvider.registeredTypeIdentifiers,
          @"name": @"",
          @"type": [self mimeTypeFromUti:uti],
       };

        [items addObject:dict];

        --remainingAttachments;
        if (remainingAttachments == 0) {
          [self sendResults:results];
        }
      }];
    }

    // Unhandled data type
    else {
      --remainingAttachments;
      if (remainingAttachments == 0) {
        [self sendResults:results];
      }
    }
  }
}

- (void) sendResults: (NSDictionary*)results {
  [self.userDefaults setObject:results forKey:@"shared"];
  [self.userDefaults synchronize];

  // Emit a URL that opens the cordova app
  NSString *url = [NSString stringWithFormat:@"%@://shared", SHAREEXT_URL_SCHEME];
  [self openURL:[NSURL URLWithString:url]];

  // Shut down the extension
  [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

 - (void) didSelectPost {
   [self debug:@"[didSelectPost]"];
 }

- (NSArray*) configurationItems {
  // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
  return @[];
}

- (NSString *) mimeTypeFromUti: (NSString*)uti {
  if (uti == nil) { return nil; }

  CFStringRef cret = UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)uti, kUTTagClassMIMEType);
  NSString *ret = (__bridge_transfer NSString *)cret;

  return ret == nil ? uti : ret;
}

@end
