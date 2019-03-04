#import "MSCosmosDb.h"
#import "MSCosmosDbIngestion.h"
#import "MSTokenResult.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Document DB base endpoint
 */
static NSString *const kMSDocumentDbEndpoint = @"https://%@.documents.azure.com";

/**
 * Document DB database URL suffix
 */
static NSString *const kMSDocumentDbDatabaseUrlSuffix = @ "dbs/%@";

/**
 * Document DB collection URL suffix
 */
static NSString *const kMSDocumentDbCollectionUrlSuffix = @"colls/%@";

/**
 * Document DB document URL suffix
 */
static NSString *const kMSDocumentDbDocumentUrlPrefix = @"docs";

/**
 * Document DB document URL suffix
 */
static NSString *const kMSDocumentDbDocumentUrlSuffix = @"docs/%@";

/**
 * Document DB authorization header format
 * TODO : Change the "type" to be "resource" instead of "master"
 */
static NSString *const kMSDocumentDbAuthorizationHeaderFormat = @"type=master&ver=1.0&sig=%@";
;

static NSString *const kMSHeaderDocumentDbPartitionKey = @"x-ms-documentdb-partitionkey";

static NSString *const kMSHeaderMsVesionValue = @"2018-06-18";
static NSString *const kMSHeaderMsVesion = @"x-ms-version";
static NSString *const kMSHeaderMsDate = @"x-ms-documentdb-partitionkey";
static NSString *const kMSHeaderAuthorization = @"Authorization";

@implementation MSCosmosDb : NSObject

+ (NSString *)rfc1123String:(NSDate *)date {
  static NSDateFormatter *df = nil;
  if (!df) {
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
      df = [[NSDateFormatter alloc] init];
      df.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
      df.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
      df.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    });
  }
  return [df stringFromDate:date];
}

+ (NSDictionary *)defaultHeaderWithPartition:(NSString *)partition dbToken:(NSString *)dbToken {
  return @{
    kMSHeaderDocumentDbPartitionKey : partition,
    kMSHeaderMsVesion : kMSHeaderMsVesionValue,
    kMSHeaderMsDate : [MSCosmosDb rfc1123String:[NSDate date]],
    kMSHeaderContentTypeKey : kMSHeaderContentTypeKey,
    kMSHeaderAuthorization : dbToken
  };
}

+ (NSString *)documentDbEndpointWithDbAccount:(NSString *)dbAccount documentResourceId:(NSString *)documentResourceId {
  NSString *documentEndpoint = [NSString stringWithFormat:kMSDocumentDbEndpoint, dbAccount];
  return [NSString stringWithFormat:@"%@/%@", documentEndpoint, documentResourceId];
}

+ (NSString *)documentBaseUrlWithDatabaseName:(NSString *)databaseName
                               collectionName:(NSString *)collectionName
                                   documentId:(NSString *)documentId {
  NSString *dbUrlSuffix = [NSString stringWithFormat:kMSDocumentDbDatabaseUrlSuffix, databaseName];
  NSString *dbCollectionUrlSuffix = [NSString stringWithFormat:kMSDocumentDbCollectionUrlSuffix, collectionName];
  NSString *dbDocumentId = documentId ? [NSString stringWithFormat:@"/%@", documentId] : @"";

  return [NSString stringWithFormat:@"%@/%@/%@%@", dbUrlSuffix, dbCollectionUrlSuffix, kMSDocumentDbDocumentUrlPrefix, dbDocumentId];
}

+ (NSString *)documentUrlWithTokenResult:(MSTokenResult *)tokenResult documentId:(NSString *)documentId {
  NSString *documentResourceIdPrefix = [MSCosmosDb documentBaseUrlWithDatabaseName:tokenResult.dbName
                                                                    collectionName:tokenResult.dbCollectionName
                                                                        documentId:documentId];
  return [MSCosmosDb documentDbEndpointWithDbAccount:tokenResult.dbCollectionName documentResourceId:documentResourceIdPrefix];
}

+ (void)cosmosDbAsync:(MSCosmosDbIngestion *)httpIngestion
          tokenResult:(MSTokenResult *)tokenResult
           documentId:(NSString *)documentId
             httpVerb:(NSString *)httpVerb
                 body:(NSString *)body
    completionHandler:(MSCosmosDbCompletionHandler)completion {
  httpIngestion.httpVerb = httpVerb;
  httpIngestion.httpHeaders = [MSCosmosDb defaultHeaderWithPartition:tokenResult.partition dbToken:tokenResult.token];
  httpIngestion.sendURL = (NSURL *)[NSURL URLWithString:[MSCosmosDb documentUrlWithTokenResult:tokenResult documentId:documentId]];

  // Payload.
  NSData *payloadData = [body dataUsingEncoding:NSUTF8StringEncoding];
  [httpIngestion sendAsync:payloadData
         completionHandler:^(NSString __unused *callId, NSHTTPURLResponse __unused *response, NSData *data, NSError *error) {
           completion(data, error);
         }];
}

@end

NS_ASSUME_NONNULL_END
