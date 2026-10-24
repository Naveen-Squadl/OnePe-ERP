import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { parse, optStr } from '../lib/validate';

export const publicRouter = Router();

/** "Contact us" lead form on the login screen. */
publicRouter.post('/enquiries', async (req, res) => {
  const body = parse(
    z.object({ name: z.string().trim().min(1), businessType: optStr, contactNo: z.string().trim().min(6), location: optStr }),
    req.body,
  );
  res.status(201).json(await prisma.enquiry.create({ data: body }));
});

publicRouter.get('/legal', (_req, res) => {
  res.json({
    version: '1.0',
    terms: 'By using OnePe POS you agree to keep your login credentials confidential and to use the software for lawful business purposes.',
    privacy: 'Your business data is stored securely and is never shared with third parties without your consent.',
  });
});
