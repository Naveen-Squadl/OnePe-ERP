import express, { NextFunction, Request, Response } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { Prisma } from '@prisma/client';
import { ApiError } from './lib/errors';
import { routes } from './routes';
import { thumbnails, UPLOAD_DIR } from './routes/upload.routes';

export function createApp() {
  const app = express();
  // Images are loaded cross-origin by the Flutter web client.
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(cors());
  app.use(express.json({ limit: '5mb' }));
  if (process.env.NODE_ENV !== 'test') app.use(morgan('dev'));

  // Serialize Prisma Decimals as JSON numbers.
  app.set('json replacer', function (this: any, key: string, value: unknown) {
    const raw = this?.[key];
    if (raw instanceof Prisma.Decimal) return raw.toNumber();
    return value;
  });

  app.get('/health', (_req, res) => {
    res.json({ ok: true });
  });
  app.use('/uploads', thumbnails, express.static(UPLOAD_DIR, { maxAge: '30d', immutable: true }));
  app.use('/api', routes);

  app.use((_req, res) => {
    res.status(404).json({ error: 'Not found' });
  });
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof ApiError) {
      res.status(err.status).json({ error: err.message, code: err.code });
      return;
    }
    if (err instanceof Prisma.PrismaClientKnownRequestError) {
      if (err.code === 'P2002') {
        res.status(409).json({ error: `Duplicate value for ${(err.meta?.target as string[] | undefined)?.join(', ') ?? 'field'}`, code: 'conflict' });
        return;
      }
      if (err.code === 'P2025') {
        res.status(404).json({ error: 'Record not found', code: 'not_found' });
        return;
      }
    }
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  });
  return app;
}
