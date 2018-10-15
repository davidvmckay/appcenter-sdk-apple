#import "AppCenter+Internal.h"
#import "MSAnalyticsInternal.h"
#import "MSBooleanTypedProperty.h"
#import "MSConstants+Internal.h"
#import "MSCSData.h"
#import "MSCSModelConstants.h"
#import "MSDateTimeTypedProperty.h"
#import "MSDoubleTypedProperty.h"
#import "MSEventLogPrivate.h"
#import "MSEventPropertiesInternal.h"
#import "MSMetadataExtension.h"
#import "MSLongTypedProperty.h"
#import "MSStringTypedProperty.h"
#import "MSUtility+Date.h"
#import "MSCSExtensions.h"

static NSString *const kMSTypeEvent = @"event";

static NSString *const kMSId = @"id";

static NSString *const kMSTypedProperties = @"typedProperties";

@implementation MSEventLog

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSTypeEvent;
    _metadataTypeIdMapping = @{@"long" : @1 };
  }
  return self;
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];
  if (self.eventId) {
    dict[kMSId] = self.eventId;
  }
  if (self.typedProperties) {
    dict[kMSTypedProperties] = [self.typedProperties serializeToArray];
  }
  return dict;
}

- (BOOL)isValid {
  return [super isValid] && self.eventId;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSEventLog class]] || ![super isEqual:object]) {
    return NO;
  }
  MSEventLog *eventLog = (MSEventLog *)object;
  return ((!self.eventId && !eventLog.eventId) || [self.eventId isEqualToString:eventLog.eventId]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _eventId = [coder decodeObjectForKey:kMSId];
    _typedProperties = [coder decodeObjectForKey:kMSTypedProperties];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.eventId forKey:kMSId];
  [coder encodeObject:self.typedProperties forKey:kMSTypedProperties];
}

#pragma mark - MSAbstractLog

- (MSCommonSchemaLog *)toCommonSchemaLogForTargetToken:(NSString *)token {
  MSCommonSchemaLog *csLog = [super toCommonSchemaLogForTargetToken:token];

  // Event name goes to part A.
  csLog.name = self.name;

  // Metadata extension must accompany data.
  // Event properties goes to part C.
  MSCSData *data = [MSCSData new];
  csLog.data = data;
  csLog.data.properties = [self convertTypedPropertiesToCSProperties];
  return csLog;
}

#pragma mark - Helper

- (NSDictionary<NSString *, NSObject *> *)convertTypedPropertiesToCSProperties {

  //TODO clean up bools and strings from metadata.
  //TODO use the generated metadata
  NSMutableDictionary *csProperties;
  NSMutableDictionary *metadata;
  MSEventProperties *eventProperties = self.typedProperties;
  if (eventProperties) {
    csProperties = [NSMutableDictionary new];
    metadata = [NSMutableDictionary new];
    for (NSString *acKey in eventProperties.properties) {

      // Properties keys are mixed up with other keys from Data, make sure they don't conflict.
      if ([acKey isEqualToString:kMSDataBaseData] || [acKey isEqualToString:kMSDataBaseDataType]) {
        MSLogWarning(MSAnalytics.logTag, @"Cannot use %@ in properties, skipping that property.", acKey);
        continue;
      }

      // If the key contains a '.' then it's nested objects (i.e: "a.b":"value" => {"a":{"b":"value"}}).
      NSArray *csKeys = [acKey componentsSeparatedByString:@"."];
      NSMutableDictionary *propertyTree = csProperties;
      NSMutableDictionary *metadataTree = metadata;
      for (NSUInteger i = 0; i < csKeys.count - 1; i++) {
        NSMutableDictionary *propertySubtree = nil;
        NSMutableDictionary *metadataSubtree = nil;

        // If there is no field delimiter for this level in the metadata tree, create one.
        if (!metadataTree[kMSFieldDelimiter]) {
          metadataTree[kMSFieldDelimiter] = [NSMutableDictionary new];
        }
        if ([(NSObject *) propertyTree[csKeys[i]] isKindOfClass:[NSMutableDictionary class]]) {
          propertySubtree = propertyTree[csKeys[i]];
          metadataSubtree = metadataTree[kMSFieldDelimiter][csKeys[i]];
        }
        if (!propertySubtree) {
          if (propertyTree[csKeys[i]]) {
            propertyTree = nil;
            MSLogWarning(MSAnalytics.logTag, @"Property key '%@' already has a value, choosing one.", csKeys[i]);
            break;
          }
          propertySubtree = [NSMutableDictionary new];
          metadataSubtree = [NSMutableDictionary new];
          metadataTree[kMSFieldDelimiter][csKeys[i]] = metadataSubtree;
          propertyTree[csKeys[i]] = propertySubtree;
        }
        propertyTree = propertySubtree;
        metadataTree = metadataSubtree;
      }
      id lastKey = csKeys.lastObject;
      if (!propertyTree || propertyTree[lastKey]) {
        MSLogWarning(MSAnalytics.logTag, @"Property key '%@' already has a value, choosing one.", lastKey);
        continue;
      }
      id typedProperty = eventProperties.properties[acKey];
      if ([typedProperty isKindOfClass:[MSStringTypedProperty class]]) {
        MSStringTypedProperty *stringProperty = (MSStringTypedProperty *)typedProperty;
        propertyTree[lastKey] = stringProperty.value;
      } else if ([typedProperty isKindOfClass:[MSBooleanTypedProperty class]]) {
        MSBooleanTypedProperty *boolProperty = (MSBooleanTypedProperty *)typedProperty;
        propertyTree[lastKey] = @(boolProperty.value);
      } else if ([typedProperty isKindOfClass:[MSLongTypedProperty class]]) {
        MSLongTypedProperty *longProperty = (MSLongTypedProperty *)typedProperty;
        metadataTree[lastKey] = self.metadataTypeIdMapping[longProperty.type];
        propertyTree[lastKey] = @(longProperty.value);
      } else if ([typedProperty isKindOfClass:[MSDoubleTypedProperty class]]) {
        MSDoubleTypedProperty *doubleProperty = (MSDoubleTypedProperty *)typedProperty;
        metadataTree[lastKey] = self.metadataTypeIdMapping[doubleProperty.type];
        propertyTree[lastKey] = @(doubleProperty.value);
      } else if ([typedProperty isKindOfClass:[MSDateTimeTypedProperty class]]) {
        MSDateTimeTypedProperty *dateProperty = (MSDateTimeTypedProperty *)typedProperty;
        metadataTree[lastKey] = self.metadataTypeIdMapping[dateProperty.type];
        propertyTree[lastKey] = [MSUtility dateToISO8601:dateProperty.value];
      }
    }
  }
  return csProperties;
}

@end
