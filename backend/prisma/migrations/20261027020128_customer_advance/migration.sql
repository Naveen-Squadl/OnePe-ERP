-- AlterEnum
ALTER TYPE "PaymentMethod" ADD VALUE 'ADVANCE';

-- AlterTable
ALTER TABLE "Bill" ADD COLUMN     "advanceUsed" DECIMAL(12,2) NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "CustomerPayment" ADD COLUMN     "isRefund" BOOLEAN NOT NULL DEFAULT false;
