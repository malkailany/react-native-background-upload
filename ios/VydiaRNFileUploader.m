#import <Foundation/Foundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTBridgeModule.h>
#import <Photos/Photos.h>

@interface VydiaRNFileUploader : RCTEventEmitter <RCTBridgeModule, NSURLSessionTaskDelegate>
{
  NSMutableDictionary *_responsesData;
  NSMutableDictionary<NSString*, NSURL*> *_filesMap;
}
@end

@implementation VydiaRNFileUploader

RCT_EXPORT_MODULE();

@synthesize bridge = _bridge;
static int uploadId = 0;
static RCTEventEmitter* staticEventEmitter = nil;
static NSString *BACKGROUND_SESSION_ID = @"ReactNativeBackgroundUpload";
NSURLSession *_urlSession = nil;

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

-(id) init {
  self = [super init];
  if (self) {
    staticEventEmitter = self;
    _responsesData = [NSMutableDictionary dictionary];
    _filesMap = @{}.mutableCopy;
  }
  return self;
}

- (void)_sendEventWithName:(NSString *)eventName body:(id)body {
  if (staticEventEmitter == nil)
    return;
  [staticEventEmitter sendEventWithName:eventName body:body];
}

- (NSArray<NSString *> *)supportedEvents {
    return @[
        @"RNFileUploader-progress",
        @"RNFileUploader-error",
        @"RNFileUploader-cancelled",
        @"RNFileUploader-completed"
    ];
}

/*
 Gets file information for the path specified.  Example valid path is: file:///var/mobile/Containers/Data/Application/3C8A0EFB-A316-45C0-A30A-761BF8CCF2F8/tmp/trim.A5F76017-14E9-4890-907E-36A045AF9436.MOV
 Returns an object such as: {mimeType: "video/quicktime", size: 2569900, exists: true, name: "trim.AF9A9225-FC37-416B-A25B-4EDB8275A625.MOV", extension: "MOV"}
 */
RCT_EXPORT_METHOD(getFileInfo:(NSString *)path resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    @try {
        // Escape non latin characters in filename
        NSString *escapedPath = [path stringByAddingPercentEncodingWithAllowedCharacters: NSCharacterSet.URLQueryAllowedCharacterSet];
       
        NSURL *fileUri = [NSURL URLWithString:escapedPath];
        NSString *pathWithoutProtocol = [fileUri path];
        NSString *name = [fileUri lastPathComponent];
        NSString *extension = [name pathExtension];
        bool exists = [[NSFileManager defaultManager] fileExistsAtPath:pathWithoutProtocol];
        NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys: name, @"name", nil];
        [params setObject:extension forKey:@"extension"];
        [params setObject:[NSNumber numberWithBool:exists] forKey:@"exists"];

        if (exists)
        {
            [params setObject:[self guessMIMETypeFromFileName:name] forKey:@"mimeType"];
            NSError* error;
            NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:pathWithoutProtocol error:&error];
            if (error == nil)
            {
                unsigned long long fileSize = [attributes fileSize];
                [params setObject:[NSNumber numberWithLongLong:fileSize] forKey:@"size"];
            }
        }
        resolve(params);
    }
    @catch (NSException *exception) {
        reject(@"RN Uploader", exception.name, nil);
    }
}

/*
 Borrowed from http://stackoverflow.com/questions/2439020/wheres-the-iphone-mime-type-database
*/
- (NSString *)guessMIMETypeFromFileName: (NSString *)fileName {
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[fileName pathExtension], NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    
    if (UTI) {
        CFRelease(UTI);
    }
  
    if (!MIMEType) {
        return @"application/octet-stream";
    }
    return (__bridge NSString *)(MIMEType);
}

/*
 Utility method to copy a PHAsset file into a local temp file, which can then be uploaded.
 */
- (void)copyAssetToFile: (NSString *)assetUrl completionHandler: (void(^)(NSString *__nullable tempFileUrl, NSError *__nullable error))completionHandler {
    NSURL *url = [NSURL URLWithString:assetUrl];
    PHAsset *asset = [PHAsset fetchAssetsWithALAssetURLs:@[url] options:nil].lastObject;
    if (!asset) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:@"Asset could not be fetched.  Are you missing permissions?" forKey:NSLocalizedDescriptionKey];
        completionHandler(nil,  [NSError errorWithDomain:@"RNUploader" code:5 userInfo:details]);
        return;
    }
    PHAssetResource *assetResource = [[PHAssetResource assetResourcesForAsset:asset] firstObject];
    NSString *pathToWrite = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSURL *pathUrl = [NSURL fileURLWithPath:pathToWrite];
    NSString *fileURI = pathUrl.absoluteString;

    PHAssetResourceRequestOptions *options = [PHAssetResourceRequestOptions new];
    options.networkAccessAllowed = YES;

    [[PHAssetResourceManager defaultManager] writeDataForAssetResource:assetResource toFile:pathUrl options:options completionHandler:^(NSError * _Nullable e) {
        if (e == nil) {
            completionHandler(fileURI, nil);
        }
        else {
            completionHandler(nil, e);
        }
    }];
}

- (NSURL *)saveMultipartUploadDataToDisk:(NSString *)uploadId data:(NSData *)data {
  NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
  NSString *cacheDirectory = [paths objectAtIndex:0];
  NSString *path = [NSString stringWithFormat:@"%@.multipart", uploadId];

  NSString *uploaderDirectory = [cacheDirectory stringByAppendingPathComponent:@"/uploader"];

  NSString *filePath = [uploaderDirectory stringByAppendingPathComponent:path];
  NSLog(@"Path to save: %@", filePath);

  NSFileManager *manager = [NSFileManager defaultManager];
  NSError *error;

  //Remove file if needed
  if ([manager fileExistsAtPath:filePath]) {
    [manager removeItemAtPath:filePath error:&error];
    if (error) {
      NSLog(@"Cannot delete file at path: %@. Error: %@", filePath, error.localizedDescription);
      return nil;
    }
  }
  //Create directory if needed
  if (![manager fileExistsAtPath:uploaderDirectory] && [manager createDirectoryAtPath:uploaderDirectory withIntermediateDirectories:NO attributes:nil error:&error]) {
    NSLog(@"Cannot save data at path %@. Error: %@", filePath, error.localizedDescription);
    return nil;
  }
  //Save NSData to file
  if (![data writeToFile:filePath options:NSDataWritingAtomic error:&error]) {
    NSLog(@"Cannot save data at path %@. Error: %@", filePath, error.localizedDescription);
    return nil;
  }

  return [NSURL fileURLWithPath:filePath];
}

- (void)removeFilesForUpload:(NSString *)uploadId {
  NSFileManager *manager = [NSFileManager defaultManager];
  NSError *error;

  NSURL *fileUrl = _filesMap[uploadId];

  if (!fileUrl) {
    return;
  }

  if (![manager removeItemAtURL:fileUrl error:&error]) {
    NSLog(@"Cannot delete file at path %@. Error: %@", fileUrl.absoluteString, error.localizedDescription);
  }

  [_filesMap removeObjectForKey:uploadId];
}

/*
 * Starts a file upload.
 * Options are passed in as the first argument as a js hash:
 * {
 *   url: string.  url to post to.
 *   path: string.  path to the file on the device
 *   headers: hash of name/value header pairs
 * }
 *
 * Returns a promise with the string ID of the upload.
 */
RCT_EXPORT_METHOD(startUpload:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    int thisUploadId;
    @synchronized(self.class)
    {
        thisUploadId = uploadId++;
    }

    NSString *uploadUrl = options[@"url"];
    __block NSString *fileURI = options[@"path"];
    NSString *method = options[@"method"] ?: @"POST";
    NSString *uploadType = options[@"type"] ?: @"raw";
    NSString *fieldName = options[@"field"];
    NSString *customUploadId = options[@"customUploadId"];
    NSString *appGroup = options[@"appGroup"];
    NSDictionary *headers = options[@"headers"];
    NSDictionary *parameters = options[@"parameters"];

    @try {
        NSURL *requestUrl = [NSURL URLWithString: uploadUrl];
        if (requestUrl == nil) {
            return reject(@"RN Uploader", @"URL not compliant with RFC 2396", nil);
        }

        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl];
        [request setHTTPMethod: method];

        [headers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull val, BOOL * _Nonnull stop) {
            if ([val respondsToSelector:@selector(stringValue)]) {
                val = [val stringValue];
            }
            if ([val isKindOfClass:[NSString class]]) {
                [request setValue:val forHTTPHeaderField:key];
            }
        }];


        // asset library files have to be copied over to a temp file.  they can't be uploaded directly
        if ([fileURI hasPrefix:@"assets-library"]) {
            dispatch_group_t group = dispatch_group_create();
            dispatch_group_enter(group);
            [self copyAssetToFile:fileURI completionHandler:^(NSString * _Nullable tempFileUrl, NSError * _Nullable error) {
                if (error) {
                    dispatch_group_leave(group);
                    reject(@"RN Uploader", @"Asset could not be copied to temp file.", nil);
                    return;
                }
                fileURI = tempFileUrl;
                dispatch_group_leave(group);
            }];
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        }

        NSURLSessionUploadTask *uploadTask;
        NSString *taskDescription = customUploadId ? customUploadId : [NSString stringWithFormat:@"%i", thisUploadId];

        if ([uploadType isEqualToString:@"multipart"]) {
            NSString *uuidStr = [[NSUUID UUID] UUIDString];
            [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", uuidStr] forHTTPHeaderField:@"Content-Type"];

            NSData *httpBody = [self createBodyWithBoundary:uuidStr path:fileURI parameters: parameters fieldName:fieldName];
            [request setHTTPBodyStream: [NSInputStream inputStreamWithData:httpBody]];
            [request setValue:[NSString stringWithFormat:@"%zd", httpBody.length] forHTTPHeaderField:@"Content-Length"];

            NSURL *fileUrlOnDisk = [self saveMultipartUploadDataToDisk:taskDescription data:httpBody];
            if (fileUrlOnDisk) {
              _filesMap[taskDescription] = fileUrlOnDisk;
              uploadTask = [[self urlSession: appGroup] uploadTaskWithRequest:request fromFile:fileUrlOnDisk];
            } else {
              NSLog(@"Cannot save multipart data file to disk, Fallback to old method wtih stream");
              [request setHTTPBodyStream: [NSInputStream inputStreamWithData:httpBody]];
              uploadTask = [[self urlSession: appGroup] uploadTaskWithStreamedRequest:request];
            }
        } else {
            if (parameters.count > 0) {
                reject(@"RN Uploader", @"Parameters supported only in multipart type", nil);
                return;
            }

            uploadTask = [[self urlSession: appGroup] uploadTaskWithRequest:request fromFile:[NSURL URLWithString: fileURI]];
        }

        uploadTask.taskDescription = taskDescription;

        [uploadTask resume];
        resolve(uploadTask.taskDescription);
    }
    @catch (NSException *exception) {
        reject(@"RN Uploader", exception.name, nil);
    }
}

/*
 * Cancels file upload
 * Accepts upload ID as a first argument, this upload will be cancelled
 * Event "cancelled" will be fired when upload is cancelled.
 */
RCT_EXPORT_METHOD(cancelUpload: (NSString *)cancelUploadId resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
  __weak typeof(self) weakSelf = self;

    [_urlSession getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
      __strong typeof(self) strongSelf = weakSelf;

        for (NSURLSessionTask *uploadTask in uploadTasks) {
            if ([uploadTask.taskDescription isEqualToString:cancelUploadId]){
                // == checks if references are equal, while isEqualToString checks the string value
                [uploadTask cancel];
                [strongSelf removeFilesForUpload:cancelUploadId];
            }
        }
    }];
    resolve([NSNumber numberWithBool:YES]);
}

/*
 * Cancels all uploads associated with a parent ID, including individual chunks
 */
RCT_EXPORT_METHOD(cancelUploadWithParentId:(NSString *)parentUploadId resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject) {
    if (!parentUploadId) {
        reject(@"RN Uploader", @"Parent Upload ID is required", nil);
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSMutableArray *canceledTasks = [NSMutableArray array];

    [_urlSession getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        __strong typeof(self) strongSelf = weakSelf;
        
        for (NSURLSessionTask *task in uploadTasks) {
            NSString *taskDescription = task.taskDescription;
            
            // Check if this task is related to the parent ID (either exact match or chunk)
            if ([taskDescription isEqualToString:parentUploadId] || 
                [taskDescription hasPrefix:[NSString stringWithFormat:@"%@_chunk", parentUploadId]]) {
                [task cancel];
                [canceledTasks addObject:taskDescription];
                [strongSelf removeFilesForUpload:taskDescription];
                
                // Send cancelled event for each canceled task
                [strongSelf _sendEventWithName:@"RNFileUploader-cancelled" 
                    body:@{ 
                        @"id": taskDescription,
                        @"parentId": parentUploadId
                    }
                ];
            }
        }
        
        if (canceledTasks.count > 0) {
            resolve(@YES);
        } else {
            // If no tasks were found to cancel, still return success
            resolve(@YES);
        }
    }];
}

- (NSData *)createBodyWithBoundary:(NSString *)boundary
                         path:(NSString *)path
                         parameters:(NSDictionary *)parameters
                         fieldName:(NSString *)fieldName {

    NSMutableData *httpBody = [NSMutableData data];

    // Escape non latin characters in filename
    NSString *escapedPath = [path stringByAddingPercentEncodingWithAllowedCharacters: NSCharacterSet.URLQueryAllowedCharacterSet];

    // resolve path
    NSURL *fileUri = [NSURL URLWithString: escapedPath];
    
    NSError* error = nil;
    NSData *data = [NSData dataWithContentsOfURL:fileUri options:NSDataReadingMappedAlways error: &error];

    if (data == nil) {
        NSLog(@"Failed to read file %@", error);
    }

    NSString *filename  = [path lastPathComponent];
    NSString *mimetype  = [self guessMIMETypeFromFileName:path];

    [parameters enumerateKeysAndObjectsUsingBlock:^(NSString *parameterKey, NSString *parameterValue, BOOL *stop) {
        [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", parameterKey] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"%@\r\n", parameterValue] dataUsingEncoding:NSUTF8StringEncoding]];
    }];

    [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", fieldName, filename] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", mimetype] dataUsingEncoding:NSUTF8StringEncoding]];
    [httpBody appendData:data];
    [httpBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];

    [httpBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    return httpBody;
}

- (NSURLSession *)urlSession: (NSString *) groupId {
    if (_urlSession == nil) {
        NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:BACKGROUND_SESSION_ID];
        if (groupId != nil && ![groupId isEqualToString:@""]) {
            sessionConfiguration.sharedContainerIdentifier = groupId;
        }
        _urlSession = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:self delegateQueue:nil];
    }

    return _urlSession;
}

#pragma NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithObjectsAndKeys:task.taskDescription, @"id", nil];
    NSURLSessionDataTask *uploadTask = (NSURLSessionDataTask *)task;
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)uploadTask.response;
    if (response != nil)
    {
        [data setObject:[NSNumber numberWithInteger:response.statusCode] forKey:@"responseCode"];
        // Add response headers to the data dictionary
        NSDictionary *headers = [response allHeaderFields];
        if (headers) {
            NSLog(@"[RNFileUploader] Response headers: %@", headers);
            
            // Convert all header keys to lowercase for case-insensitive comparison
            NSMutableDictionary *normalizedHeaders = [NSMutableDictionary dictionary];
            [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
                normalizedHeaders[[key lowercaseString]] = obj;
            }];
            
            [data setObject:normalizedHeaders forKey:@"responseHeaders"];
            
            // Log the complete data object to verify structure
            NSLog(@"[RNFileUploader] Complete response data: %@", data);
        } else {
            NSLog(@"[RNFileUploader] No headers found in response");
        }
    } else {
        NSLog(@"[RNFileUploader] No response object available");
    }
    
    //Add data that was collected earlier by the didReceiveData method
    NSMutableData *responseData = _responsesData[@(task.taskIdentifier)];
    if (responseData) {
        [_responsesData removeObjectForKey:@(task.taskIdentifier)];
        
        NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        [data setObject:response forKey:@"responseBody"];
    } else {
        [data setObject:[NSNull null] forKey:@"responseBody"];
    }
    
    [self removeFilesForUpload:task.taskDescription];
    
    if (error == nil)
    {
        // Check if we have the ETag in the response headers
        NSDictionary *responseHeaders = data[@"responseHeaders"];
        NSString *etag = responseHeaders[@"etag"];
        if (!etag) {
            etag = responseHeaders[@"Etag"];  // Try with capital E
        }
        if (!etag) {
            etag = responseHeaders[@"ETag"];  // Try with capital T
        }
        
        if (etag) {
            [self _sendEventWithName:@"RNFileUploader-completed" body:data];
        } else {
            [data setObject:@"No ETag in response" forKey:@"error"];
            [self _sendEventWithName:@"RNFileUploader-error" body:data];
        }
    }
    else
    {
        [data setObject:error.localizedDescription forKey:@"error"];
        if (error.code == NSURLErrorCancelled) {
            [self _sendEventWithName:@"RNFileUploader-cancelled" body:data];
        } else {
            [self _sendEventWithName:@"RNFileUploader-error" body:data];
        }
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
    float progress = -1;
    if (totalBytesExpectedToSend > 0) //see documentation.  For unknown size it's -1 (NSURLSessionTransferSizeUnknown)
    {
        progress = 100.0 * (float)totalBytesSent / (float)totalBytesExpectedToSend;
    }
    [self _sendEventWithName:@"RNFileUploader-progress" body:@{ @"id": task.taskDescription, @"progress": [NSNumber numberWithFloat:progress] }];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (!data.length) {
        return;
    }
    //Hold returned data so it can be picked up by the didCompleteWithError method later
    NSMutableData *responseData = _responsesData[@(dataTask.taskIdentifier)];
    if (!responseData) {
        responseData = [NSMutableData dataWithData:data];
        _responsesData[@(dataTask.taskIdentifier)] = responseData;
    } else {
        [responseData appendData:data];
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream *bodyStream))completionHandler {

    NSInputStream *inputStream = task.originalRequest.HTTPBodyStream;

    if (completionHandler) {
        completionHandler(inputStream);
    }
}

- (NSData *)readChunkFromFile:(NSString *)path offset:(NSUInteger)offset length:(NSUInteger)length {
    NSLog(@"[RNFileUploader] Starting readChunkFromFile with path: %@, offset: %lu, length: %lu", path, (unsigned long)offset, (unsigned long)length);
    
    // Escape non latin characters in filename
    NSString *escapedPath = [path stringByAddingPercentEncodingWithAllowedCharacters: NSCharacterSet.URLQueryAllowedCharacterSet];
    NSLog(@"[RNFileUploader] Escaped path: %@", escapedPath);
    
    NSURL *fileUri = [NSURL URLWithString:escapedPath];
    NSString *pathWithoutProtocol = [fileUri path];
    NSLog(@"[RNFileUploader] Path without protocol: %@", pathWithoutProtocol);
    
    NSError *error = nil;
    NSData *fileData = [NSData dataWithContentsOfFile:pathWithoutProtocol options:NSDataReadingMappedIfSafe error:&error];
    
    if (!fileData) {
        NSLog(@"[RNFileUploader] Failed to read file at path: %@, error: %@", pathWithoutProtocol, error);
        return nil;
    }
    
    NSLog(@"[RNFileUploader] Successfully read file, total size: %lu", (unsigned long)fileData.length);
    
    @try {
        NSRange range = NSMakeRange(offset, MIN(length, fileData.length - offset));
        NSLog(@"[RNFileUploader] Attempting to read range - location: %lu, length: %lu", (unsigned long)range.location, (unsigned long)range.length);
        
        if (range.location + range.length <= fileData.length) {
            NSData *chunk = [fileData subdataWithRange:range];
            NSLog(@"[RNFileUploader] Successfully read chunk of size: %lu", (unsigned long)chunk.length);
            return chunk;
        } else {
            NSLog(@"[RNFileUploader] Invalid range: offset=%lu length=%lu fileSize=%lu", 
                  (unsigned long)offset, 
                  (unsigned long)length, 
                  (unsigned long)fileData.length);
            return nil;
        }
    } @catch (NSException *exception) {
        NSLog(@"[RNFileUploader] Error reading chunk: %@", exception);
        return nil;
    }
}

- (NSURL *)saveChunkToTempFile:(NSData *)chunkData withId:(NSString *)uploadId {
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-chunk", uploadId]];
    NSURL *tempUrl = [NSURL fileURLWithPath:tempPath];
    
    NSError *error;
    if (![chunkData writeToURL:tempUrl options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[RNFileUploader] Failed to write chunk to temp file: %@", error);
        return nil;
    }
    
    return tempUrl;
}

RCT_EXPORT_METHOD(uploadChunk:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"[RNFileUploader] Starting uploadChunk with options: %@", options);
    
    int thisUploadId;
    @synchronized(self.class)
    {
        thisUploadId = uploadId++;
    }
    
    NSString *uploadUrl = options[@"url"];
    NSString *fileURI = options[@"path"];
    NSNumber *offset = options[@"offset"];
    NSNumber *chunkSize = options[@"chunkSize"];
    NSString *customUploadId = options[@"customUploadId"];
    NSString *parentUploadId = options[@"parentUploadId"];
    NSNumber *chunkIndex = options[@"chunkIndex"];
    NSString *appGroup = options[@"appGroup"];
    NSDictionary *headers = options[@"headers"];
    
    NSLog(@"[RNFileUploader] Parsed options - URL: %@, path: %@, offset: %@, chunkSize: %@", uploadUrl, fileURI, offset, chunkSize);
    
    if (!offset || !chunkSize) {
        NSLog(@"[RNFileUploader] Missing required parameters - offset: %@, chunkSize: %@", offset, chunkSize);
        reject(@"RN Uploader", @"Offset and chunkSize are required", nil);
        return;
    }
    
    @try {
        NSLog(@"[RNFileUploader] Attempting to read chunk");
        NSData *chunkData = [self readChunkFromFile:fileURI offset:[offset unsignedIntegerValue] length:[chunkSize unsignedIntegerValue]];
        if (!chunkData) {
            NSLog(@"[RNFileUploader] Failed to read chunk from file");
            reject(@"RN Uploader", @"Failed to read chunk from file", nil);
            return;
        }
        
        NSLog(@"[RNFileUploader] Successfully read chunk of size: %lu", (unsigned long)chunkData.length);
        
        // Generate a unique task description that includes parent ID and chunk information
        NSString *taskDescription;
        if (customUploadId) {
            taskDescription = customUploadId;
        } else if (parentUploadId && chunkIndex) {
            taskDescription = [NSString stringWithFormat:@"%@_chunk%@", parentUploadId, chunkIndex];
        } else {
            taskDescription = [NSString stringWithFormat:@"%i", thisUploadId];
        }
        
        // Save chunk to temp file
        NSURL *tempChunkUrl = [self saveChunkToTempFile:chunkData withId:taskDescription];
        if (!tempChunkUrl) {
            reject(@"RN Uploader", @"Failed to save chunk to temp file", nil);
            return;
        }
        
        _filesMap[taskDescription] = tempChunkUrl;
        
        NSURL *requestUrl = [NSURL URLWithString:uploadUrl];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl];
        [request setHTTPMethod:@"PUT"];
        
        NSLog(@"[RNFileUploader] Setting headers: %@", headers);
        [headers enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *stop) {
            if ([val respondsToSelector:@selector(stringValue)]) {
                val = [val stringValue];
            }
            if ([val isKindOfClass:[NSString class]]) {
                [request setValue:val forHTTPHeaderField:key];
            }
        }];
        
        // Add chunk-specific headers to help with ETag uniqueness
        [request setValue:[NSString stringWithFormat:@"%@", taskDescription] forHTTPHeaderField:@"X-Upload-Chunk-Id"];
        if (parentUploadId) {
            [request setValue:parentUploadId forHTTPHeaderField:@"X-Upload-Parent-Id"];
        }
        if (chunkIndex) {
            [request setValue:[chunkIndex stringValue] forHTTPHeaderField:@"X-Upload-Chunk-Index"];
        }
        
        [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)chunkData.length] forHTTPHeaderField:@"Content-Length"];
        
        NSLog(@"[RNFileUploader] Creating upload task with description: %@", taskDescription);
        
        NSURLSessionUploadTask *uploadTask = [[self urlSession:appGroup] uploadTaskWithRequest:request fromFile:tempChunkUrl];
        uploadTask.taskDescription = taskDescription;
        
        [uploadTask resume];
        NSLog(@"[RNFileUploader] Upload task started");
        resolve(uploadTask.taskDescription);
    }
    @catch (NSException *exception) {
        NSLog(@"[RNFileUploader] Exception in uploadChunk: %@", exception);
        reject(@"RN Uploader", exception.name, nil);
    }
}

@end
