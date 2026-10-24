import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { parse } from '../lib/validate';
import { badRequest, forbidden, unauthorized } from '../lib/errors';
import { authenticate, signToken } from '../middleware/auth';
import { sessionPayload } from '../services/session.service';
import { logActivity } from '../lib/activity';

export const authRouter = Router();

authRouter.post('/login', async (req, res) => {
  const { email, password } = parse(
    z.object({ email: z.string().trim().toLowerCase().email('Please enter a valid email'), password: z.string().min(1, 'Please enter your password') }),
    req.body,
  );
  const u = await prisma.user.findUnique({ where: { email }, include: { shop: true } });
  if (!u) throw unauthorized('No account found with this email.');
  if (!(await bcrypt.compare(password, u.passwordHash))) throw unauthorized('Incorrect password. Please try again.');
  if (!u.isActive) throw forbidden('This account has been disabled');
  if (u.shop && !u.shop.isActive) throw forbidden('Your shop account is inactive. Contact support.');

  await prisma.user.update({ where: { id: u.id }, data: { lastLoginAt: new Date() } });
  if (u.shopId) await prisma.shop.update({ where: { id: u.shopId }, data: { lastLoginAt: new Date() } });
  const authUser = { id: u.id, name: u.name, email: u.email, role: u.role, shopId: u.shopId, branchId: u.branchId };
  await logActivity(authUser, 'login', `${u.name} signed in`);
  res.json({ token: signToken(authUser), ...(await sessionPayload(u)) });
});

authRouter.get('/me', authenticate, async (req, res) => {
  const u = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id } });
  res.json(await sessionPayload(u));
});

authRouter.post('/change-password', authenticate, async (req, res) => {
  const { currentPassword, newPassword } = parse(
    z.object({ currentPassword: z.string(), newPassword: z.string().min(6, 'Password must be at least 6 characters') }),
    req.body,
  );
  const u = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id } });
  if (!(await bcrypt.compare(currentPassword, u.passwordHash))) throw badRequest('Current password is incorrect');
  await prisma.user.update({ where: { id: u.id }, data: { passwordHash: await bcrypt.hash(newPassword, 10) } });
  res.json({ ok: true });
});
