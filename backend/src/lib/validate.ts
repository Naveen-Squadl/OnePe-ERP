import { z, ZodTypeAny } from 'zod';
import { badRequest } from './errors';

export function parse<T extends ZodTypeAny>(schema: T, data: unknown): z.infer<T> {
  const r = schema.safeParse(data);
  if (!r.success) {
    const msg = r.error.issues.map((i) => `${i.path.join('.') || 'body'}: ${i.message}`).join('; ');
    throw badRequest(msg);
  }
  return r.data;
}

export const optStr = z.string().trim().optional().nullable();
export const money = z.coerce.number().finite();

/** History panels: `?from=&to=` (ISO dates) → a Prisma DateTime filter, or undefined when neither is given. */
export function dateRange(query: Record<string, unknown>): { gte?: Date; lte?: Date } | undefined {
  const from = query.from ? new Date(String(query.from)) : undefined;
  const to = query.to ? new Date(String(query.to)) : undefined;
  return from || to ? { gte: from, lte: to } : undefined;
}
