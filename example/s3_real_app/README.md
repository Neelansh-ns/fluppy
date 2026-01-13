# Fluppy S3 Real Upload Example

This Flutter app demonstrates **real S3 uploads** using the Fluppy package with a Node.js backend that generates presigned URLs.

## Features Demonstrated

- ✅ Single-part uploads (files < 100MB)
- ✅ Multipart uploads (files > 100MB)
- ✅ Pause/Resume functionality
- ✅ Retry on failure
- ✅ Progress tracking
- ✅ Multiple concurrent uploads (max 3)
- ✅ Real-time event updates
- ✅ File picker integration
- ✅ AWS S3 integration

---

## Prerequisites

### 1. AWS Account & S3 Bucket

You need:
- An AWS account
- An S3 bucket created
- AWS credentials (Access Key ID and Secret Access Key)

### 2. Software Requirements

- **Flutter SDK**: 3.0.0 or higher
- **Node.js**: 18.x or higher
- **npm**: 8.x or higher

---

## Setup Instructions

### Step 1: AWS S3 Bucket Configuration

1. **Create an S3 bucket** (or use an existing one)

2. **Configure CORS** - Add this CORS policy to your bucket:

```json
[
  {
    "AllowedHeaders": ["*"],
    "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
    "AllowedOrigins": ["*"],
    "ExposeHeaders": ["ETag", "Location"],
    "MaxAgeSeconds": 3000
  }
]
```

To set CORS:
- Go to your S3 bucket in AWS Console
- Click "Permissions" tab
- Scroll to "Cross-origin resource sharing (CORS)"
- Click "Edit" and paste the JSON above

3. **Set Bucket Policy** (if needed for public uploads):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPresignedUploads",
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/*"
    }
  ]
}
```

Replace `YOUR_BUCKET_NAME` with your actual bucket name.

---

### Step 2: Backend Server Setup

The backend server generates presigned URLs for secure S3 uploads.

#### 2.1 Install Dependencies

```bash
cd server
npm install
```

#### 2.2 Configure Environment Variables

Create a `.env` file in the `server/` directory:

```bash
cp .env.example .env
```

Edit `.env` with your AWS credentials:

```env
# AWS Configuration
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
AWS_REGION=us-east-1
AWS_S3_BUCKET=your-bucket-name

# Server Configuration
PORT=3000
```

**Important**:
- Replace `your_access_key_here` with your AWS Access Key ID
- Replace `your_secret_key_here` with your AWS Secret Access Key
- Replace `your-bucket-name` with your S3 bucket name
- Adjust `AWS_REGION` if your bucket is in a different region

#### 2.3 Start the Backend Server

```bash
cd server
npm start
```

You should see:
```
🚀 Server running on http://localhost:3000
```

**Backend Endpoints**:
- `POST /presign-upload` - Get presigned URL for single-part upload
- `POST /multipart/create` - Create multipart upload
- `POST /multipart/sign-part` - Sign a multipart upload part
- `POST /multipart/list-parts` - List uploaded parts
- `POST /multipart/complete` - Complete multipart upload
- `POST /multipart/abort` - Abort multipart upload

---

### Step 3: Flutter App Setup

#### 3.1 Install Flutter Dependencies

```bash
cd ..  # Back to s3_real_app root
flutter pub get
```

#### 3.2 Update Backend URL (if needed)

If your backend is not running on `http://localhost:3000`, edit [lib/main.dart:36](lib/main.dart#L36):

```dart
String backendUrl = 'http://localhost:3000';  // Change if needed
```

#### 3.3 Run the Flutter App

**macOS**:
```bash
flutter run -d macos
```

**Linux**:
```bash
flutter run -d linux
```

**Windows**:
```bash
flutter run -d windows
```

**Android**:
```bash
flutter run -d <device_id>
```

**iOS**:
```bash
flutter run -d <device_id>
```

**Important for Mobile**: If running on Android/iOS, you'll need to:
1. Use your computer's local IP instead of `localhost`
2. Update `backendUrl` in `lib/main.dart`:
   ```dart
   String backendUrl = 'http://192.168.1.x:3000';  // Your computer's IP
   ```

---

## Usage

### 1. Pick Files

Click **"Pick Files"** button to select one or more files from your device.

### 2. Upload Files

Click **"Upload All"** to start uploading all added files to S3.

### 3. Monitor Progress

Each file card shows:
- File name and size
- Upload progress (percentage)
- Current status
- Action buttons (Pause/Resume/Retry)

### 4. Pause/Resume

For multipart uploads (files > 100MB):
- Click **"Pause"** to pause the upload
- Click **"Resume"** to continue from where you left off

### 5. Retry on Failure

If an upload fails:
- The file card will show "Error" status
- Click **"Retry"** to attempt the upload again

### 6. View Uploaded Files

Successful uploads show the S3 location URL in the status.

---

## Testing Scenarios

### Test 1: Small File Upload (Single-part)
1. Pick a file < 100MB (e.g., 10MB image)
2. Click "Upload All"
3. Verify progress updates smoothly
4. Verify upload completes successfully
5. Check S3 bucket for the uploaded file

### Test 2: Large File Upload (Multipart)
1. Pick a file > 100MB (e.g., 500MB video)
2. Click "Upload All"
3. Verify multipart upload starts
4. Verify multiple parts upload concurrently
5. Verify upload completes successfully

### Test 3: Pause/Resume
1. Pick a large file > 100MB
2. Start upload
3. Click "Pause" after a few parts upload
4. Wait a few seconds
5. Click "Resume"
6. Verify upload continues from where it stopped

### Test 4: Multiple Concurrent Uploads
1. Pick 5+ files of various sizes
2. Click "Upload All"
3. Verify max 3 files upload at once
4. Verify remaining files queue properly
5. Verify all files complete successfully

### Test 5: Retry on Failure
1. Stop the backend server
2. Start an upload (it will fail)
3. Restart the backend server
4. Click "Retry" on the failed file
5. Verify upload succeeds

### Test 6: Network Interruption
1. Start a large file upload
2. Disconnect your network
3. Wait for upload to fail
4. Reconnect network
5. Click "Retry"
6. Verify upload succeeds

---

## Troubleshooting

### Backend Issues

**Error: `AWS_ACCESS_KEY_ID is not defined`**
- Make sure you created `.env` file in `server/` directory
- Verify all environment variables are set correctly

**Error: `EADDRINUSE: address already in use`**
- Port 3000 is already in use
- Change `PORT` in `.env` to a different port (e.g., 3001)
- Update `backendUrl` in Flutter app accordingly

**Error: `The security token included in the request is invalid`**
- Your AWS credentials are invalid
- Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in `.env`
- Make sure the IAM user has S3 permissions

### Flutter App Issues

**Error: `Connection refused`**
- Backend server is not running
- Start the server: `cd server && npm start`
- Verify `backendUrl` is correct in `lib/main.dart`

**Error: `SocketException: Failed host lookup`**
- Backend URL is incorrect
- If on mobile, use your computer's local IP (not `localhost`)
- Verify backend is accessible from the device

**Upload hangs at 0%**
- Check S3 bucket CORS configuration
- Verify presigned URLs are being generated correctly
- Check browser/app console for errors

**Multipart upload fails to resume**
- Verify `listParts` endpoint is working correctly
- Check S3 console for incomplete multipart uploads
- May need to abort and restart the upload

### AWS S3 Issues

**Error: `403 Forbidden`**
- Presigned URL may have expired
- Check URL expiration time (default: 1 hour)
- Verify S3 bucket policy allows uploads
- Verify IAM user has `s3:PutObject` permission

**Error: `NoSuchBucket`**
- S3 bucket name is incorrect in `.env`
- Verify `AWS_S3_BUCKET` matches your actual bucket name

**CORS Error in Browser**
- CORS policy not set correctly on S3 bucket
- Follow Step 1 instructions to set CORS

---

## Architecture Overview

```
┌─────────────────────────────────────────┐
│      Flutter App (s3_real_app)          │
│  - File picker                           │
│  - Fluppy integration                    │
│  - UI for upload management              │
└───────────────┬─────────────────────────┘
                │
                │ HTTP requests for presigned URLs
                ▼
┌─────────────────────────────────────────┐
│   Node.js Backend (Express Server)      │
│  - Generates presigned URLs              │
│  - AWS SDK v3 integration                │
│  - Endpoints for single/multipart        │
└───────────────┬─────────────────────────┘
                │
                │ AWS SDK calls
                ▼
┌─────────────────────────────────────────┐
│         AWS S3 (Storage Bucket)          │
│  - Stores uploaded files                 │
│  - CORS configured                       │
│  - Bucket policy set                     │
└─────────────────────────────────────────┘
                ▲
                │
                │ Direct HTTP PUT (presigned URL)
                │
┌───────────────┴─────────────────────────┐
│      Flutter App via Fluppy              │
│  - Uses presigned URLs                   │
│  - Uploads directly to S3                │
│  - No credentials in client              │
└─────────────────────────────────────────┘
```

### Why Presigned URLs?

1. **Security**: AWS credentials never leave the backend
2. **Direct Upload**: Files upload directly to S3 (not through backend)
3. **Scalability**: Backend doesn't handle file data
4. **Flexibility**: Backend controls upload permissions per file

---

## Security Notes

### Production Considerations

1. **Never commit `.env` file**
   - The `.gitignore` already excludes it
   - Never commit AWS credentials to version control

2. **Use IAM Roles in Production**
   - Don't use long-term access keys in production
   - Use IAM roles for EC2/ECS/Lambda
   - Rotate credentials regularly

3. **Limit S3 Bucket Permissions**
   - Don't use overly permissive bucket policies
   - Restrict to specific actions and principals
   - Use IAM policies for fine-grained control

4. **Set Expiration on Presigned URLs**
   - Current default: 1 hour (3600 seconds)
   - Adjust based on expected upload time
   - Shorter is more secure

5. **Add Backend Authentication**
   - Current example has no authentication
   - Add JWT/session-based auth in production
   - Verify user permissions before generating URLs

6. **Rate Limiting**
   - Add rate limiting to backend endpoints
   - Prevent abuse of presigned URL generation
   - Use tools like `express-rate-limit`

7. **HTTPS in Production**
   - Always use HTTPS for backend API
   - Presigned URLs will also use HTTPS
   - Prevent MITM attacks

---

## File Size Limits

- **Single-part Upload**: < 100MB (configurable in `shouldUseMultipart`)
- **Multipart Upload**: > 100MB (up to 5TB maximum)
- **Part Size**: 10MB per part (configurable in `getChunkSize`)
- **S3 Limits**:
  - Max object size: 5TB
  - Max parts: 10,000
  - Part size: 5MB - 5GB

---

## Next Steps

### Enhancements You Could Add

1. **Upload History**: Store upload history in local database
2. **File Preview**: Show image/video previews before upload
3. **Custom Metadata**: Add custom metadata to uploaded files
4. **Folder Organization**: Upload files to specific S3 prefixes/folders
5. **Access Control**: Add ACL settings for uploaded files
6. **Upload Queue Management**: Better queue visualization and control
7. **Server-Side Validation**: Validate file types/sizes on backend
8. **Webhooks**: Notify other services when uploads complete
9. **CDN Integration**: Serve uploaded files via CloudFront
10. **Thumbnail Generation**: Auto-generate thumbnails for images

---

## Resources

- [Fluppy Documentation](../../README.md)
- [AWS S3 Presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html)
- [AWS S3 Multipart Upload](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html)
- [Uppy.io Documentation](https://uppy.io/docs/)

---

## License

This example is part of the Fluppy package and is licensed under the MIT License.

---

## Support

If you encounter issues:
1. Check the Troubleshooting section above
2. Verify AWS credentials and S3 configuration
3. Check backend server logs for errors
4. Open an issue on the [Fluppy GitHub repository](https://github.com/Neelansh-ns/fluppy/issues)
