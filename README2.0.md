# react-native-background-upload

[![npm version](https://badge.fury.io/js/react-native-background-upload.svg)](https://badge.fury.io/js/react-native-background-upload) 
![GitHub Actions status](https://github.com/Vydia/react-native-background-upload/workflows/Test%20iOS%20Example%20App/badge.svg) 
![GitHub Actions status](https://github.com/Vydia/react-native-background-upload/workflows/Test%20Android%20Example%20App/badge.svg)

The most powerful React Native file uploader with background support for both iOS and Android. Perfect for large file uploads that need to continue even when the app is in the background.

## Features

- ✅ Background upload support
- ✅ Progress tracking
- ✅ Chunk upload support
- ✅ Cancellation support (both single uploads and chunk groups)
- ✅ S3 compatible
- ✅ Multipart form support
- ✅ Custom headers
- ✅ TypeScript support
- ✅ Customizable notifications (Android)

## Installation

```bash
npm install react-native-background-upload
# or
yarn add react-native-background-upload
```

### iOS Setup
```bash
cd ios && pod install
```

### Android Setup

Add to proguard-rules.pro:
```
-keep class net.gotev.uploadservice.** { *; }
```

## Basic Usage

```typescript
import Upload from 'react-native-background-upload'

const options = {
  url: 'https://your-server.com/upload',
  path: 'file://path/to/file/on/device',
  method: 'POST',
  type: 'raw',
  headers: {
    'content-type': 'application/octet-stream'
  }
}

try {
  const uploadId = await Upload.startUpload(options)
  
  // Add event listeners
  Upload.addListener('progress', uploadId, (data) => {
    console.log(`Progress: ${data.progress}%`)
  })
  
  Upload.addListener('completed', uploadId, (data) => {
    console.log('Upload completed!', data.responseBody)
  })
} catch (error) {
  console.error('Upload failed:', error)
}
```

## Chunk Upload Support

For large files, you can split the upload into chunks:

```typescript
const chunkOptions = {
  url: 'https://your-server.com/upload-chunk',
  path: 'file://path/to/large/file',
  method: 'POST',
  type: 'raw',
  parentUploadId: 'unique-parent-id', // Used to group chunks together
  chunkIndex: 1, // Chunk sequence number
  headers: {
    'content-type': 'application/octet-stream'
  }
}

// Start chunk upload
const chunkId = await Upload.startUpload(chunkOptions)

// Cancel all chunks for a parent upload
await Upload.cancelChunkUploads(parentUploadId)
```

## API Reference

### Upload Methods

#### `startUpload(options: UploadOptions): Promise<string>`
Starts a new upload task. Returns an upload ID.

#### `cancelUpload(uploadId: string): Promise<boolean>`
Cancels a specific upload.

#### `cancelChunkUploads(parentUploadId: string): Promise<boolean>`
Cancels all chunk uploads associated with a parent ID.

#### `addListener(event: UploadEvent, uploadId: string, callback: Function)`
Add event listeners for upload progress and status.

### Options

```typescript
interface UploadOptions {
  url: string;
  path: string;
  method?: 'POST' | 'PUT';
  type?: 'raw' | 'multipart';
  headers?: Record<string, string>;
  customUploadId?: string;
  parentUploadId?: string; // For chunk uploads
  chunkIndex?: number; // For chunk uploads
  // Android specific
  notification?: {
    enabled: boolean;
    autoClear?: boolean;
    notificationChannel?: string;
    onProgressTitle?: string;
    onProgressMessage?: string;
    onCompleteTitle?: string;
    onCompleteMessage?: string;
    onErrorTitle?: string;
    onErrorMessage?: string;
  };
}
```

### Events

- `progress`: Upload progress (0-100)
- `error`: Upload error details
- `completed`: Upload completion with response
- `cancelled`: Upload cancellation confirmation

## Platform Specific Features

### Android Notifications

```typescript
const options = {
  // ... other options
  notification: {
    enabled: true,
    autoClear: true,
    notificationChannel: "Uploads",
    onProgressTitle: "Uploading...",
    onCompleteTitle: "Upload finished",
    onErrorTitle: "Upload failed"
  }
}
```

### iOS Background Mode

Add the following to your Info.plist:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
</array>
```

## S3 Compatibility

This module is fully compatible with S3 uploads. For chunk uploads, it automatically:
- Generates unique ETags for each chunk
- Maintains parent-child relationships between uploads
- Supports cancellation of entire upload groups

## Example

Check out our [example app](https://github.com/Vydia/react-native-background-upload/tree/master/example) for a complete implementation.

## Contributing

See our [Contributing Guide](./CONTRIBUTING.md) for details.

## License

MIT 