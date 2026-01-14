const express = require('express');
const cors = require('cors');
const { S3Client, CreateMultipartUploadCommand, UploadPartCommand, CompleteMultipartUploadCommand, AbortMultipartUploadCommand, ListPartsCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const { STSClient, AssumeRoleCommand, GetSessionTokenCommand } = require('@aws-sdk/client-sts');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Initialize S3 client
const s3Client = new S3Client({
  region: process.env.AWS_REGION || 'us-east-1',
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
});

// Initialize STS client for temporary credentials
const stsClient = new STSClient({
  region: process.env.AWS_REGION || 'us-east-1',
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
});

const BUCKET_NAME = process.env.S3_BUCKET;

if (!BUCKET_NAME) {
  console.error('ERROR: S3_BUCKET environment variable is required');
  process.exit(1);
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', bucket: BUCKET_NAME });
});

// Get temporary credentials for client-side signing
app.get('/sts-credentials', async (req, res) => {
  try {
    // Use GetSessionToken to get temporary credentials
    // This is simpler than AssumeRole and works with the same credentials
    const command = new GetSessionTokenCommand({
      DurationSeconds: 3600, // 1 hour
    });

    const result = await stsClient.send(command);

    if (!result.Credentials) {
      throw new Error('No credentials returned from STS');
    }

    res.json({
      credentials: {
        AccessKeyId: result.Credentials.AccessKeyId,
        SecretAccessKey: result.Credentials.SecretAccessKey,
        SessionToken: result.Credentials.SessionToken,
        Expiration: result.Credentials.Expiration?.toISOString(),
      },
      bucket: BUCKET_NAME,
      region: process.env.AWS_REGION || 'us-east-1',
    });
  } catch (error) {
    console.error('Error getting temporary credentials:', error);
    res.status(500).json({ error: error.message });
  }
});

// Single-part upload: Get presigned PUT URL
app.post('/presign-upload', async (req, res) => {
  try {
    const { filename, contentType } = req.body;

    if (!filename) {
      return res.status(400).json({ error: 'filename is required' });
    }

    const key = `uploads/${Date.now()}-${filename}`;

    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      ContentType: contentType || 'application/octet-stream',
    });

    const url = await getSignedUrl(s3Client, command, { expiresIn: 3600 });

    res.json({ url, key });
  } catch (error) {
    console.error('Error creating presigned URL:', error);
    res.status(500).json({ error: error.message });
  }
});

// Multipart: Create multipart upload
app.post('/multipart/create', async (req, res) => {
  try {
    const { filename, contentType } = req.body;

    if (!filename) {
      return res.status(400).json({ error: 'filename is required' });
    }

    const key = `uploads/${Date.now()}-${filename}`;

    const command = new CreateMultipartUploadCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      ContentType: contentType || 'application/octet-stream',
    });

    const result = await s3Client.send(command);

    res.json({
      uploadId: result.UploadId,
      key: key,
    });
  } catch (error) {
    console.error('Error creating multipart upload:', error);
    res.status(500).json({ error: error.message });
  }
});

// Multipart: Sign part upload
app.post('/multipart/sign-part', async (req, res) => {
  try {
    const { key, uploadId, partNumber } = req.body;

    if (!key || !uploadId || !partNumber) {
      return res.status(400).json({ error: 'key, uploadId, and partNumber are required' });
    }

    const command = new UploadPartCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      UploadId: uploadId,
      PartNumber: parseInt(partNumber),
    });

    const url = await getSignedUrl(s3Client, command, { expiresIn: 3600 });

    res.json({ url });
  } catch (error) {
    console.error('Error signing part:', error);
    res.status(500).json({ error: error.message });
  }
});

// Multipart: List uploaded parts
app.post('/multipart/list-parts', async (req, res) => {
  try {
    const { key, uploadId } = req.body;

    if (!key || !uploadId) {
      return res.status(400).json({ error: 'key and uploadId are required' });
    }

    const command = new ListPartsCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      UploadId: uploadId,
    });

    const result = await s3Client.send(command);

    const parts = (result.Parts || []).map(p => ({
      partNumber: p.PartNumber,
      size: p.Size,
      eTag: p.ETag,
    }));

    res.json({ parts });
  } catch (error) {
    console.error('Error listing parts:', error);
    res.status(500).json({ error: error.message });
  }
});

// Multipart: Complete multipart upload
app.post('/multipart/complete', async (req, res) => {
  try {
    const { key, uploadId, parts } = req.body;

    if (!key || !uploadId || !parts) {
      return res.status(400).json({ error: 'key, uploadId, and parts are required' });
    }

    const command = new CompleteMultipartUploadCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      UploadId: uploadId,
      MultipartUpload: {
        Parts: parts.map(p => ({
          PartNumber: p.PartNumber || p.partNumber,
          ETag: p.ETag || p.eTag,
        })),
      },
    });

    const result = await s3Client.send(command);

    res.json({
      location: result.Location || `https://${BUCKET_NAME}.s3.amazonaws.com/${key}`,
      eTag: result.ETag,
      bucket: result.Bucket,
      key: result.Key,
    });
  } catch (error) {
    console.error('Error completing multipart upload:', error);
    res.status(500).json({ error: error.message });
  }
});

// Multipart: Abort multipart upload
app.post('/multipart/abort', async (req, res) => {
  try {
    const { key, uploadId } = req.body;

    if (!key || !uploadId) {
      return res.status(400).json({ error: 'key and uploadId are required' });
    }

    const command = new AbortMultipartUploadCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      UploadId: uploadId,
    });

    await s3Client.send(command);

    res.json({ success: true });
  } catch (error) {
    console.error('Error aborting multipart upload:', error);
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`🚀 Fluppy S3 Backend Server running on port ${PORT}`);
  console.log(`📦 S3 Bucket: ${BUCKET_NAME}`);
  console.log(`🌍 Region: ${process.env.AWS_REGION || 'us-east-1'}`);
  console.log(`\n✅ Health check: http://localhost:${PORT}/health`);
});
