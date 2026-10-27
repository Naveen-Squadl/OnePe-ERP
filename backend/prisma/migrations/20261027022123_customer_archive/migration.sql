-- DropForeignKey
ALTER TABLE "CustomerPayment" DROP CONSTRAINT "CustomerPayment_customerId_fkey";

-- AlterTable
ALTER TABLE "Customer" ADD COLUMN     "archivedAt" TIMESTAMP(3),
ADD COLUMN     "isArchived" BOOLEAN NOT NULL DEFAULT false;

-- AddForeignKey
ALTER TABLE "CustomerPayment" ADD CONSTRAINT "CustomerPayment_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE NO ACTION ON UPDATE CASCADE;
