// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FirebaseMessagingPlugin.h"

#import "Firebase/Firebase.h"
#import <UserNotifications/UserNotifications.h>

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
@interface FLTFirebaseMessagingPlugin ()<FIRMessagingDelegate>
@end
#endif

@implementation FLTFirebaseMessagingPlugin {
  FlutterMethodChannel *_channel;
  NSDictionary *_launchNotification;
  BOOL _resumingFromBackground;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"plugins.flutter.io/firebase_messaging"
                                  binaryMessenger:[registrar messenger]];
  FLTFirebaseMessagingPlugin *instance =
      [[FLTFirebaseMessagingPlugin alloc] initWithChannel:channel];
  [registrar addApplicationDelegate:instance];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithChannel:(FlutterMethodChannel *)channel {
  self = [super init];

  if (self) {
    _channel = channel;
    _resumingFromBackground = NO;
    if (![FIRApp defaultApp]) {
      [FIRApp configure];
    }
    [FIRMessaging messaging].delegate = self;
  }
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSString *method = call.method;
  if ([@"requestNotificationPermissions" isEqualToString:method]) {
    UIUserNotificationType notificationTypes = 0;
    NSDictionary *arguments = call.arguments;
    if (arguments[@"sound"]) {
      notificationTypes |= UIUserNotificationTypeSound;
    }
    if (arguments[@"alert"]) {
      notificationTypes |= UIUserNotificationTypeAlert;
    }
    if (arguments[@"badge"]) {
      notificationTypes |= UIUserNotificationTypeBadge;
    }
    UIUserNotificationSettings *settings =
        [UIUserNotificationSettings settingsForTypes:notificationTypes categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];

    result(nil);
  } else if ([@"configure" isEqualToString:method]) {
    [[UIApplication sharedApplication] registerForRemoteNotifications];
    if (_launchNotification != nil) {
      [_channel invokeMethod:@"onLaunch" arguments:_launchNotification];
    }
    result(nil);
  } else if ([@"subscribeToTopic" isEqualToString:method]) {
    NSString *topic = call.arguments;
    [[FIRMessaging messaging] subscribeToTopic:topic];
    result(nil);
  } else if ([@"unsubscribeFromTopic" isEqualToString:method]) {
    NSString *topic = call.arguments;
    [[FIRMessaging messaging] unsubscribeFromTopic:topic];
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
// Receive data message on iOS 10 devices while app is in the foreground.
- (void)applicationReceivedRemoteMessage:(FIRMessagingRemoteMessage *)remoteMessage {
  [self didReceiveRemoteNotification:remoteMessage.appData];
}
#endif

- (void)didReceiveRemoteNotification:(NSDictionary *)userInfo {
  if (_resumingFromBackground) {
    [_channel invokeMethod:@"onResume" arguments:userInfo];
  } else {
    [_channel invokeMethod:@"onMessage" arguments:userInfo];
  }
}

#pragma mark - AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  if (launchOptions != nil) {
    _launchNotification = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
  }
  return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
  _resumingFromBackground = YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
  _resumingFromBackground = NO;
  // Clears push notifications from the notification center, with the
  // side effect of resetting the badge count. We need to clear notifications
  // because otherwise the user could tap notifications in the notification
  // center while the app is in the foreground, and we wouldn't be able to
  // distinguish that case from the case where a message came in and the
  // user dismissed the notification center without tapping anything.
  // TODO(goderbauer): Revisit this behavior once we provide an API for managing
  // the badge number, or if we add support for running Dart in the background.
  // Setting badgeNumber to 0 is a no-op (= notifications will not be cleared)
  // if it is already 0,
  // therefore the next line is setting it to 1 first before clearing it again
  // to remove all
  // notifications.
  application.applicationIconBadgeNumber = 1;
  application.applicationIconBadgeNumber = 0;
}

- (bool)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler {
  [self didReceiveRemoteNotification:userInfo];
    //这里做内容的处理需要的内容有 类型， title， body， imageUrl
    NSDictionary *data = userInfo;
    if (data && [data objectForKey:@"cate"]) {
        int64_t cate = [[data objectForKey:@"cate"] longLongValue];
        if (cate == 103) {
#ifdef DEBUG
            NSLog(@"我收到了article 通知");
#endif
            NSString *title = [data objectForKey:@"title"];
            NSString *body = [data objectForKey:@"brief"];
            NSString *imageUrl = [data objectForKey:@"image"];
            if (imageUrl) {
                [self loadAttachmentForUrlString:imageUrl title:title body:body userInfo:data fetchCompletionHandler:completionHandler];
            }
        }
    } else {
        completionHandler(UIBackgroundFetchResultNoData);
    }
  return YES;
}

- (void)application:(UIApplication *)application
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
#ifdef DEBUG
  [[FIRMessaging messaging] setAPNSToken:deviceToken type:FIRMessagingAPNSTokenTypeSandbox];
#else
  [[FIRMessaging messaging] setAPNSToken:deviceToken type:FIRMessagingAPNSTokenTypeProd];
#endif

  [_channel invokeMethod:@"onToken" arguments:[[FIRInstanceID instanceID] token]];
}

- (void)application:(UIApplication *)application
    didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings {
  NSDictionary *settingsDictionary = @{
    @"sound" : [NSNumber numberWithBool:notificationSettings.types & UIUserNotificationTypeSound],
    @"badge" : [NSNumber numberWithBool:notificationSettings.types & UIUserNotificationTypeBadge],
    @"alert" : [NSNumber numberWithBool:notificationSettings.types & UIUserNotificationTypeAlert],
  };
  [_channel invokeMethod:@"onIosSettingsRegistered" arguments:settingsDictionary];
}

- (void)messaging:(nonnull FIRMessaging *)messaging
    didReceiveRegistrationToken:(nonnull NSString *)fcmToken {
  [_channel invokeMethod:@"onToken" arguments:fcmToken];
}

#pragma 私有方法
- (void)loadAttachmentForUrlString:(NSString *)urlStr
                             title:(NSString *)title
                              body:(NSString *)body
                          userInfo:(NSDictionary *)userInfo
            fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
#ifdef DEBUG
    NSLog(@"下载的图片地址%@", urlStr);
#endif
    NSString *fileExt = urlStr.pathExtension;
    NSURL *attachmentURL = [NSURL URLWithString:urlStr];
    __block UNMutableNotificationContent *content = nil;
    __block UNNotificationAttachment *img_attachment = nil;
    __block UNTimeIntervalNotificationTrigger *time_trigger = nil;
    __block UNNotificationRequest *request = nil;
    __block UNUserNotificationCenter *notificationCenter = nil;
    __block NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    [[session downloadTaskWithURL:attachmentURL
                completionHandler:^(NSURL *temporaryFileLocation, NSURLResponse *response, NSError *error) {
                    if (error != nil) {
#ifdef DEBUG
                        NSLog(@"error %@", error.localizedDescription);
#endif
                        completionHandler(UIBackgroundFetchResultFailed);
                    } else {
#ifdef DEBUG
                        NSLog(@"下载的图片完成了%@", temporaryFileLocation.path);
#endif
                        NSFileManager *fileManager = [NSFileManager defaultManager];
                        NSURL *localURL = [NSURL fileURLWithPath:[temporaryFileLocation.path
                                                                  stringByAppendingString:[@"." stringByAppendingString:fileExt]]];
                        [fileManager moveItemAtURL:temporaryFileLocation toURL:localURL error:&error];
                        
                        content = [[UNMutableNotificationContent alloc] init];
                        content.title = title;
                        content.body = body;
                        content.badge = @0;
                        NSError *attachmentError = nil;
                        //将本地图片的路径形成一个图片附件，加入到content中
                        img_attachment = [UNNotificationAttachment attachmentWithIdentifier:@"aricaleImage" URL:localURL options:nil error:&attachmentError];
                        if (attachmentError) {
#ifdef DEBUG
                            NSLog(@"%@", attachmentError);
#endif
                            
                        } else {
                            content.attachments = @[img_attachment];
                        }
                        content.sound =  [UNNotificationSound defaultSound];
                        content.userInfo = userInfo;
                        //设置时间间隔的触发器
                        time_trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];
                        NSString *requestIdentifer = @"aircleIndentifer";
                        request = [UNNotificationRequest requestWithIdentifier:requestIdentifer content:content trigger:time_trigger];
                        notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
                        [notificationCenter addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
                            if (error){
#ifdef DEBUG
                                NSLog(@"error %@",error);
#endif
                                completionHandler(UIBackgroundFetchResultFailed);
                            } else {
                                completionHandler(UIBackgroundFetchResultNewData);
                            }
                        }];
                    }
                    
                }
      ] resume];
}

@end
