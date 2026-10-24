import { Prisma } from '@prisma/client';

/** Convert Prisma.Decimal | number | null to a JS number. */
export const num = (v: Prisma.Decimal | number | string | null | undefined): number =>
  v == null ? 0 : typeof v === 'number' ? v : Number(v);

export const round2 = (v: number) => Math.round((v + Number.EPSILON) * 100) / 100;
export const round3 = (v: number) => Math.round((v + Number.EPSILON) * 1000) / 1000;
