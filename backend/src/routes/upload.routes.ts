import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import multer from 'multer';
import { shopIdOf } from '../middleware/auth';
import { badRequest } from '../lib/errors';

export const UPLOAD_DIR = path.resolve(__dirname, '../../uploads');

const EXT: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 3 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => cb(null, file.mimetype in EXT),
});

export const uploadRouter = Router();

/** Upload a product photo / shop logo. Returns a URL path served from /uploads. */
uploadRouter.post('/', upload.single('file'), async (req, res) => {
  if (!req.file) throw badRequest('Upload a JPG, PNG or WEBP image (max 3 MB)');
  const shopId = shopIdOf(req);
  const dir = path.join(UPLOAD_DIR, shopId);
  await fs.promises.mkdir(dir, { recursive: true });
  const name = `${randomUUID()}.${EXT[req.file.mimetype]}`;
  await fs.promises.writeFile(path.join(dir, name), req.file.buffer);
  res.status(201).json({ url: `/uploads/${shopId}/${name}` });
});
