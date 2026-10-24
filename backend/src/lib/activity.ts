import { prisma, Tx } from './prisma';
import { AuthUser } from '../middleware/auth';

export async function logActivity(
  user: AuthUser | null,
  action: string,
  description: string,
  metadata?: Record<string, unknown>,
  tx: Tx = prisma,
  shopId?: string | null,
) {
  await tx.activityLog.create({
    data: {
      shopId: shopId ?? user?.shopId ?? null,
      userId: user?.id,
      userName: user?.name,
      action,
      description,
      metadata: (metadata ?? undefined) as any,
    },
  });
}
