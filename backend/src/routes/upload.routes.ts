import { Router } from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import type { RequestHandler } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import { shopIdOf } from '../middleware/auth';
import { badRequest } from '../lib/errors';

export const UPLOAD_DIR = path.resolve(__dirname, '../../uploads');

const EXT: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
const FORMAT = { jpg: 'jpeg', png: 'png', webp: 'webp' } as const;

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
  const ext = EXT[req.file.mimetype];
  const name = `${randomUUID()}.${ext}`;
  // Cap at 1024 px (web uploads are not resized by the client); keep the format, apply EXIF rotation.
  const image = await sharp(req.file.buffer)
    .rotate()
    .resize(1024, 1024, { fit: 'inside', withoutEnlargement: true })
    .toFormat(FORMAT[ext as keyof typeof FORMAT], { quality: 82 })
    .toBuffer()
    .catch(() => {
      throw badRequest('Could not read the image');
    });
  await fs.promises.writeFile(path.join(dir, name), image);
  res.status(201).json({ url: `/uploads/${shopId}/${name}` });
});

export const THUMB_SUFFIX = '.thumb.webp';

/**
 * `/uploads/<shop>/<file>.thumb.webp` – 300 px WEBP thumbnail (≈10–20 KB) for product tiles, made on first
 * request (so older photos get one too) and then served as a static file.
 */
export const thumbnails: RequestHandler = async (req, _res, next) => {
  if (!req.path.endsWith(THUMB_SUFFIX)) return next();
  const thumb = path.join(UPLOAD_DIR, path.normalize(req.path));
  const original = thumb.slice(0, -THUMB_SUFFIX.length);
  if (!thumb.startsWith(UPLOAD_DIR + path.sep) || fs.existsSync(thumb) || !fs.existsSync(original)) return next();
  try {
    await sharp(original).rotate().resize(300, 300, { fit: 'inside', withoutEnlargement: true }).webp({ quality: 75 }).toFile(thumb);
  } catch {
    // Unreadable original – fall through to a 404.
  }
  next();
};
