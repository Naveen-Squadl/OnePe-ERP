-- DropForeignKey
ALTER TABLE "SupplierPayment" DROP CONSTRAINT "SupplierPayment_supplierId_fkey";

-- AlterTable
ALTER TABLE "Supplier" ADD COLUMN     "archivedAt" TIMESTAMP(3),
ADD COLUMN     "isArchived" BOOLEAN NOT NULL DEFAULT false;

-- AddForeignKey
ALTER TABLE "SupplierPayment" ADD CONSTRAINT "SupplierPayment_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "Supplier"("id") ON DELETE NO ACTION ON UPDATE CASCADE;
