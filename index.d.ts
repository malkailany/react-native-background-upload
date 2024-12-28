declare module 'react-native-background-upload' {
  import type { EventSubscription } from 'react-native'

  export interface EventData {
    id: string
  }

  export interface ProgressData extends EventData {
    progress: number
  }

  export interface ErrorData extends EventData {
    error: string
  }

  export interface CompletedData extends EventData {
    responseCode: number
    responseBody: string
    responseHeaders: {
      [key: string]: string
    }
  }

  export interface S3MultipartOptions {
    url: string;
    path: string;
    headers?: {
      [index: string]: string;
    };
    partSize?: number; // Size in bytes for each part
    maxConcurrentUploads?: number;
    appGroup?: string;
  }

  export interface S3PartData {
    ETag: string;
    PartNumber: number;
  }

  export interface S3CompletedData extends EventData {
    parts: S3PartData[];
    bucket: string;
    key: string;
    location: string;
  }
  
  export interface ChunkUploadOptions {
    url: string;
    path: string;
    offset: number;
    chunkSize: number;
    customUploadId?: string;
    headers?: {
      [index: string]: string;
    };
    appGroup?: string;
  }

  export interface FileInfo extends Record<string, any> {
    name: string;
    exists: boolean;
    size?: number;
    extension?: string;
    mimeType?: string;
  }

  export type NotificationOptions = {
    /**
     * Enable or diasable notifications. Works only on Android version < 8.0 Oreo. On Android versions >= 8.0 Oreo is required by Google's policy to display a notification when a background service run  { enabled: true }
     */
    enabled: boolean
    /**
     * Autoclear notification on complete  { autoclear: true }
     */
    autoClear: boolean
    /**
     * Sets android notificaion channel  { notificationChannel: "My-Upload-Service" }
     */
    notificationChannel: string
    /**
     * Sets whether or not to enable the notification sound when the upload gets completed with success or error   { enableRingTone: true }
     */
    enableRingTone: boolean
    /**
     * Sets notification progress title  { onProgressTitle: "Uploading" }
     */
    onProgressTitle: string
    /**
     * Sets notification progress message  { onProgressMessage: "Uploading new video" }
     */
    onProgressMessage: string
    /**
     * Sets notification complete title  { onCompleteTitle: "Upload finished" }
     */
    onCompleteTitle: string
    /**
     * Sets notification complete message  { onCompleteMessage: "Your video has been uploaded" }
     */
    onCompleteMessage: string
    /**
     * Sets notification error title   { onErrorTitle: "Upload error" }
     */
    onErrorTitle: string
    /**
     * Sets notification error message   { onErrorMessage: "An error occured while uploading a video" }
     */
    onErrorMessage: string
    /**
     * Sets notification cancelled title   { onCancelledTitle: "Upload cancelled" }
     */
    onCancelledTitle: string
    /**
     * Sets notification cancelled message   { onCancelledMessage: "Video upload was cancelled" }
     */
    onCancelledMessage: string
  }

  export interface UploadOptions {
    url: string
    path: string
    type?: 'raw' | 'multipart'
    method?: 'POST' | 'GET' | 'PUT' | 'PATCH' | 'DELETE'
    customUploadId?: string
    headers?: {
      [index: string]: string
    }
    // Android notification settings
    notification?: Partial<NotificationOptions>
    /**
     * AppGroup defined in XCode for extensions. Necessary when trying to upload things via this library
     * in the context of ShareExtension.
     */
    appGroup?: string
    // Necessary only for multipart type upload
    field?: string
  }

  export interface MultipartUploadOptions extends UploadOptions {
    type: 'multipart'
    field: string
    parameters?: {
      [index: string]: string
    }
  }

  type uploadId = string

  export type UploadListenerEvent =
    | 'progress'
    | 'error'
    | 'completed'
    | 'cancelled'

  export default class Upload {
    static startUpload(
      options: UploadOptions | MultipartUploadOptions,
    ): Promise<uploadId>
    static addListener(
      event: 'progress',
      uploadId: uploadId | null,
      callback: (data: ProgressData) => void,
    ): EventSubscription
    static addListener(
      event: 'error',
      uploadId: uploadId | null,
      callback: (data: ErrorData) => void,
    ): EventSubscription
    static addListener(
      event: 'completed',
      uploadId: uploadId | null,
      callback: (data: CompletedData) => void,
    ): EventSubscription
    static addListener(
      event: 'cancelled',
      uploadId: uploadId | null,
      callback: (data: EventData) => void,
    ): EventSubscription
    static getFileInfo(path: string): Promise<FileInfo>
    static cancelUpload(uploadId: uploadId): Promise<boolean>
    static initiateS3MultipartUpload(
      options: S3MultipartOptions
    ): Promise<{ uploadId: string }>;
    static uploadS3Part(
      options: S3MultipartOptions & {
        uploadId: string;
        partNumber: number;
      }
    ): Promise<S3PartData>;
    static completeS3MultipartUpload(
      options: S3MultipartOptions & {
        uploadId: string;
        parts: S3PartData[];
      }
    ): Promise<S3CompletedData>;
    static abortS3MultipartUpload(
      options: S3MultipartOptions & {
        uploadId: string;
      }
    ): Promise<boolean>;
    static uploadChunk(
      options: ChunkUploadOptions
    ): Promise<string>;
  }
}
