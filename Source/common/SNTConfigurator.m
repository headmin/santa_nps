/// Copyright 2015 Google Inc. All rights reserved.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///    http://www.apache.org/licenses/LICENSE-2.0
///
///    Unless required by applicable law or agreed to in writing, software
///    distributed under the License is distributed on an "AS IS" BASIS,
///    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///    See the License for the specific language governing permissions and
///    limitations under the License.

#import "SNTConfigurator.h"

#import "SNTLogging.h"
#import "SNTSystemInfo.h"

@interface SNTConfigurator ()
@property NSString *configFilePath;
@property NSMutableDictionary *configData;

/// Creating NSRegularExpression objects is not fast, so cache it.
@property NSRegularExpression *cachedWhitelistDirRegex;

/// Array of keys that cannot be changed while santad is running if santad didn't make the change.
@property(readonly) NSArray *protectedKeys;
@end

@implementation SNTConfigurator

/// The hard-coded path to the config file
NSString * const kDefaultConfigFilePath = @"/var/db/santa/config.plist";

/// The keys in the config file
static NSString * const kClientModeKey = @"ClientMode";
static NSString * const kWhitelistRegexKey = @"WhitelistRegex";
static NSString * const kLogFileChangesKey = @"LogFileChanges";

static NSString * const kMoreInfoURLKey = @"MoreInfoURL";
static NSString * const kEventDetailURLKey = @"EventDetailURL";
static NSString * const kEventDetailTextKey = @"EventDetailText";
static NSString * const kDefaultBlockMessage = @"DefaultBlockMessage";

static NSString * const kSyncBaseURLKey = @"SyncBaseURL";
static NSString * const kClientAuthCertificateFileKey = @"ClientAuthCertificateFile";
static NSString * const kClientAuthCertificatePasswordKey = @"ClientAuthCertificatePassword";
static NSString * const kClientAuthCertificateCNKey = @"ClientAuthCertificateCN";
static NSString * const kClientAuthCertificateIssuerKey = @"ClientAuthCertificateIssuerCN";
static NSString * const kServerAuthRootsDataKey = @"ServerAuthRootsData";
static NSString * const kServerAuthRootsFileKey = @"ServerAuthRootsFile";

static NSString * const kMachineOwnerKey = @"MachineOwner";
static NSString * const kMachineIDKey = @"MachineID";

static NSString * const kMachineOwnerPlistFileKey = @"MachineOwnerPlist";
static NSString * const kMachineOwnerPlistKeyKey = @"MachineOwnerKey";

static NSString * const kMachineIDPlistFileKey = @"MachineIDPlist";
static NSString * const kMachineIDPlistKeyKey = @"MachineIDKey";

- (instancetype)initWithFilePath:(NSString *)filePath {
  self = [super init];
  if (self) {
    _configFilePath = filePath;
    [self reloadConfigData];
  }
  return self;
}

#pragma mark Singleton retriever

+ (instancetype)configurator {
  static SNTConfigurator *sharedConfigurator = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
      sharedConfigurator = [[SNTConfigurator alloc] initWithFilePath:kDefaultConfigFilePath];
  });
  return sharedConfigurator;
}

#pragma mark Protected Keys

- (NSArray *)protectedKeys {
  return @[ kClientModeKey, kWhitelistRegexKey, kLogFileChangesKey ];
}

#pragma mark Public Interface

- (santa_clientmode_t)clientMode {
  int cm = [self.configData[kClientModeKey] intValue];
  if (cm > CLIENTMODE_UNKNOWN && cm < CLIENTMODE_MAX) {
    return (santa_clientmode_t)cm;
  } else {
    self.configData[kClientModeKey] = @(CLIENTMODE_MONITOR);
    return CLIENTMODE_MONITOR;
  }
}

- (void)setClientMode:(santa_clientmode_t)newMode {
  if (newMode > CLIENTMODE_UNKNOWN && newMode < CLIENTMODE_MAX) {
    self.configData[kClientModeKey] = @(newMode);
    [self saveConfigToDisk];
  }
}

- (NSRegularExpression *)whitelistPathRegex {
  if (!self.cachedWhitelistDirRegex && self.configData[kWhitelistRegexKey]) {
    NSString *re = self.configData[kWhitelistRegexKey];
    if (![re hasPrefix:@"^"]) re = [@"^" stringByAppendingString:re];
    self.cachedWhitelistDirRegex = [NSRegularExpression regularExpressionWithPattern:re
                                                                             options:0
                                                                               error:nil];
  }
  return self.cachedWhitelistDirRegex;
}

- (void)setWhitelistPathRegex:(NSRegularExpression *)re {
  if (!re) {
    [self.configData removeObjectForKey:kWhitelistRegexKey];
  } else {
    self.configData[kWhitelistRegexKey] = [re pattern];
  }
  self.cachedWhitelistDirRegex = nil;
  [self saveConfigToDisk];
}

- (BOOL)logFileChanges {
  return [self.configData[kLogFileChangesKey] boolValue];
}

- (void)setLogFileChanges:(BOOL)logFileChanges {
  self.configData[kLogFileChangesKey] = @(logFileChanges);
  [self saveConfigToDisk];
}

- (NSURL *)moreInfoURL {
  return [NSURL URLWithString:self.configData[kMoreInfoURLKey]];
}

- (NSString *)eventDetailURL {
  return self.configData[kEventDetailURLKey];
}

- (NSString *)eventDetailText {
  return self.configData[kEventDetailTextKey];
}

- (NSString *)defaultBlockMessage {
  return self.configData[kDefaultBlockMessage];
}

- (NSURL *)syncBaseURL {
  return [NSURL URLWithString:self.configData[kSyncBaseURLKey]];
}

- (NSString *)syncClientAuthCertificateFile {
  return self.configData[kClientAuthCertificateFileKey];
}

- (NSString *)syncClientAuthCertificatePassword {
  return self.configData[kClientAuthCertificatePasswordKey];
}

- (NSString *)syncClientAuthCertificateCn {
  return self.configData[kClientAuthCertificateCNKey];
}

- (NSString *)syncClientAuthCertificateIssuer {
  return self.configData[kClientAuthCertificateIssuerKey];
}

- (NSData *)syncServerAuthRootsData {
  return self.configData[kServerAuthRootsDataKey];
}

- (NSString *)syncServerAuthRootsFile {
  return self.configData[kServerAuthRootsFileKey];
}

- (NSString *)machineOwner {
  NSString *machineOwner;

  if (self.configData[kMachineOwnerPlistFileKey] && self.configData[kMachineOwnerPlistKeyKey]) {
    NSDictionary *plist =
        [NSDictionary dictionaryWithContentsOfFile:self.configData[kMachineOwnerPlistFileKey]];
    machineOwner = plist[self.configData[kMachineOwnerPlistKeyKey]];
  }

  if (self.configData[kMachineOwnerKey]) {
    machineOwner = self.configData[kMachineOwnerKey];
  }

  if (!machineOwner) machineOwner = @"";

  return machineOwner;
}

- (NSString *)machineID {
  NSString *machineId;

  if (self.configData[kMachineIDPlistFileKey] && self.configData[kMachineIDPlistKeyKey]) {
    NSDictionary *plist =
        [NSDictionary dictionaryWithContentsOfFile:self.configData[kMachineIDPlistFileKey]];
    machineId = plist[self.configData[kMachineIDPlistKeyKey]];
  }

  if (self.configData[kMachineIDKey]) {
    machineId = self.configData[kMachineIDKey];
  }

  if ([machineId length] == 0) {
    machineId = [SNTSystemInfo hardwareUUID];
  }

  return machineId;
}

- (void)reloadConfigData {
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:self.configFilePath]) return;

  NSError *error;
  NSData *readData = [NSData dataWithContentsOfFile:self.configFilePath
                                            options:NSDataReadingMappedIfSafe
                                              error:&error];
  if (error) {
    LOGE(@"Could not read configuration file: %@", [error localizedDescription]);
    return;
  }

  NSDictionary *configData =
      [NSPropertyListSerialization propertyListWithData:readData
                                                options:kCFPropertyListImmutable
                                                 format:NULL
                                                  error:&error];
  if (error) {
    LOGE(@"Could not parse configuration file: %@", [error localizedDescription]);
    return;
  }

  if (!self.configData) {
    self.configData = [configData mutableCopy];
  } else {
    // Ensure no-one is trying to change protected keys behind our back.
    NSMutableDictionary *configDataMutable = [configData mutableCopy];
    BOOL changed = NO;
    for (NSString *key in self.protectedKeys) {
      if (geteuid() == 0 &&
          ((self.configData[key] && !configData[key]) ||
           (!self.configData[key] && configData[key]) ||
           (self.configData[key] && ![self.configData[key] isEqual:configData[key]]))) {
        if (self.configData[key]) {
          configDataMutable[key] = self.configData[key];
        } else {
          [configDataMutable removeObjectForKey:key];
        }
        changed = YES;
        LOGI(@"Ignoring changed configuration key: %@", key);
      }
    }
    self.configData = configDataMutable;
    if (changed) [self saveConfigToDisk];
  }
}

#pragma mark Private

///
///  Saves the current @c self.configData to disk.
///
- (void)saveConfigToDisk {
  [self.configData writeToFile:self.configFilePath atomically:YES];
}

@end
